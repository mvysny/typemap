# Hints worded for the data's source: `load(..., source: :toml)`

Reopens `D_format_neutral_hints`. A hint that names no format serves none of them well:

- **A Hash built in Ruby has no quotes.** `expected String, got 70; quote it to make it a
  string` tells a Ruby caller to edit text that doesn't exist. What it needs is the plain
  mismatch: an Integer came, a String was expected.
- **`wrap it in an array` is far from `[[server]]`.** A TOML user reads it and may try
  `[server]` with something else, or a `server = [...]` they'd never write by hand. `[x]` for
  `[[x]]` is the most common TOML mistake there is; its fix should be spelled in TOML.

## Why the old arguments don't hold

The code already splits **detection** from **wording**. Detection reads the Hash and is the same
whatever the format: a single entry where an array belongs, a String that reads as a number, a
key that an enclosing object has. Only the wording depends on the format, and wording needs
the format's spec, not its parser.

- **"Parser knowledge creeps in."** Tomlrb's `Time` and Psych's `no` → `false` decide which
  values reach Typemap, which is detection, and that stays on the Hash. `[[server]]` is the TOML
  spec, not a Tomlrb quirk. YAML's booleans are Psych's YAML 1.1, and Psych is effectively the
  only YAML parser Ruby has.
- **"Inside arrays a header names the wrong entry."** Overstated: a TOML header has no indices.
  Someone who wrote `[llm.servers]` under the first `[[llm]]` fixes it with `[[llm.servers]]` in
  the same spot, and the error path already names `llm[0]`. The header is the path with its
  indices stripped.

## The proposal

```ruby
mapper.load(Config, hash, source: :toml)   # :ruby (the default), :toml, :json, :yaml
```

- **A `load` keyword, not a `Mapper.new` one.** A Mapper holds the class side: the type
  strategy and the cached plans. The source is a property of the data, and one mapper may load a
  TOML file and a JSON payload. Dump errors go to the programmer, so dump always words for Ruby.
- **`:ruby` is the default.** Hints that assume a text file show only when the app says there is
  one. An app that forgets `source:` gets correct messages with fewer hints, never wrong ones.
- **`format:` was not picked** because it collides with `constrain format:`.
- **No format's word for a Hash** still holds in every wording: no "table", no "object". The
  type stays RBS-spelled, `expected Array[Server]`. Only the hint speaks the format.
- **Strict, never coerced**, unchanged: a hint says what to change in the file.

## The wordings

| Mistake | `:ruby` | `:toml` | `:json` | `:yaml` |
|---|---|---|---|---|
| a single entry where an array of objects belongs | wrap it in an array | write `[[server]]`, not `[server]`, or `server = [{…}]` | wrap it in `[ ]` | start the entry with `- ` |
| a single scalar where an array belongs, `tags = "a"` | wrap it in an array | wrap it in `[ ]` | wrap it in `[ ]` | make it a list: start it with `- ` |
| an array of one where one object belongs | unwrap it | write `[server]`, not `[[server]]`, or `server = {…}` | remove the `[ ]` | remove the `- ` |
| a non-String where a String belongs | — | quote it | quote it | quote it; for a bool: YAML reads `yes`, `no`, `on`, `off` as booleans |
| a String reading as the Integer / Float / bool expected | — | remove the quotes | remove the quotes | remove the quotes |
| a key that the top level has, under `ui` | belongs to the top level | move it above the `[ui]` header | move it out of `ui`'s `{ }` | dedent it to the top level |
| a key that `code` has, under `code.ui` | belongs to code | move it under `[code]`, above `[code.ui]` | move it out of `ui`'s `{ }`, into `code`'s | dedent it to code |

A `—` means no hint: the mismatch itself says it all to a Ruby caller.

**`:ruby` names the found value's class**: `expected String, got Integer 70`. A Ruby source
means a Ruby programmer reads the message, and they know what `Integer` is. `inspect` alone
blurs some cases: a `Time` prints like unquoted text, and `70` vs `70.0` is easy to misread.
`nil`, `true` and `false` stay bare, since `got NilClass nil` and `got TrueClass true` add only
noise. This is a sixth wording method, `found(value)`. The text sources keep today's `inspect`.

**TOML headers come from the path**: the error's own path with indices stripped, `llm[0].servers`
→ `[[llm.servers]]`. An enclosing array entry is named by its array header: a key misplaced
under `llm[0].params` that `llm[0]` has reads `move it under [[llm]], above [llm.params]`. A key
that isn't a bare TOML key (a dot, a space) is quoted, `["a.b"]`. The path used is the one
Typemap built, before `entry_name` decorates it, so `server[1] "grok"` never ends up in a
header.

## The shape: one wording object per source

Each hint site today builds its own text (`Type.quote_hint`, `"remove the quotes"` in `Scalar`
and `Bool`, `"wrap it in an array"` in `ArrayOf#single`, `"unwrap it"` in `Session#not_a_hash`,
`Session#unknown_detail`). Four sources × six sites as `case source` would scatter each format
across `type.rb` and `mapper.rb`.

Instead, a private object per source, one method per mistake, each returning the hint or `nil`:

```ruby
wording.single(path:, element:)        # element: the short RBS name; plus whether it's an object
wording.array_of_one(path:)
wording.not_a_string(value)
wording.quoted(value)
wording.misplaced(path:, key:, owner:) # owner: the enclosing object's path, "" for the top level
```

- **`Session` carries it**: `Session.new(mapper:, unknown:, parents:, wording:)`. Every hint site
  already gets the session (`Scalar#load`'s `_session` today), so nothing new is threaded.
- **Detection stays where it is.** The wording only turns facts into text and never decides
  whether a mistake happened.
- **Private** (`@api private`). The public API is the symbol. Accepting an app's own object later
  doesn't break anything; until a real app needs it, the method signatures stay free to change.
- **Composition for the shared parts.** TOML, JSON and YAML share "quote it" and "remove the
  quotes" through a helper, not a base class.
- `Mapper#load` maps the symbol to its object and raises `ArgumentError` on an unknown one, like
  `unknown:` does.

## Costs

- **TOML inline tables.** The array hints name both spellings, the header and the inline
  `server = [{…}]`, since Typemap can't tell which one the file used. That makes them longer,
  but they're never wrong, and erring toward helpful is the point. A key misplaced inside an
  inline table, or set as a dotted key, is still told about a header that isn't there.
- **YAML flow style.** Someone who wrote `{id: a}` or `[a]` is told about `- ` and indentation.
  Block style is the common case.
- **The promise changes.** "Finding config files, file formats, env-var overrides … stay the
  app's" becomes something like *parsing stays the app's; Typemap words its errors in the
  format's syntax when told which.*
- **The parser's value in `got`**, `got 1.1` where the file says `1.10`, is unchanged.

## Open questions

- `Q_wording_object`: one object per source (above) or a `case source` at each site? The owner's
  hunch is that the objects read clearer. I agree: each format's voice sits in one file, and the
  sites stay one call each. A table of five mistakes × four sources is the case where a `case`
  repeats itself most. Settle it when writing the code.
- `Q_found_syntax`: spell a found container in the format's syntax, `got {id = "a"}` rather than
  `{"id"=>"a"}`? Not part of this idea; it only goes here so it isn't lost.

## When it graduates

- `design/decisions.md`: `D_format_neutral_hints` is replaced by an entry along the lines of
  *why hints worded for the source the app names, and why `:ruby` is the default*. It should
  cover the detection/wording split, why the parser-knowledge and inside-arrays arguments fell,
  and why a `load` keyword and not a constructor one.
- `AGENTS.md`: the "One thing: the mapping" promise is reworded as above.
- `DataError`'s doc comment and the README: the examples show a source's hint.
- `design/architecture.md`: the wording object in the load flow.
- CHANGELOG: `load` gains `source:`. Without it, quote hints no longer show, so an app loading a
  file should pass its format. The `detail` text is not an API, so no `**Breaking:**` line.
