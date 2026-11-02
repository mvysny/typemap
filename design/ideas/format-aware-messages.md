# Hints for the file's classic mistakes, in no format's words

Asked by pikuri-tui, whose config moved onto Typemap. A TOML file with `[server]` where
`[[server]]` belongs now says:

```
server: expected Array[Shared::Config::Server], got {"id"=>"a"}
```

Every word of it is exact. The old hand-written check said `` `server` must be an array of
tables (use [[server]], not [server]) ``: it named the fix. `[x]` for `[[x]]` is probably the
most common TOML mistake there is: the two headers differ by one bracket pair, and both parse.

## What's wrong with today's message

`error.rb` says who reads a `DataError`: *the file's author fixes it*. Two things stand in their
way:

- **The fix is missing**, though for this mistake it's mechanical.
- **The namespace**: `Shared::Config::Server` is the app's code layout, nothing the file shows.
  `Server` alone usually matches the key it sits under.

The RBS spelling itself stays: `Array[Server]`, `Integer`, `bool`, `String?` read plainly to
anyone who writes a config file, and one spelling serves every message.

## The mistakes are the Hash's, not the format's

Read the classic mistakes by what they leave in the Hash, and each one is the same in all three
formats, with a fix that can be said without naming any of them:

| What the Hash holds | TOML | YAML | JSON | Hint |
|---|---|---|---|---|
| one entry where an array belongs | `[x]` for `[[x]]` | a missing `- ` | missing `[ ]` | `got a single Server; wrap it in an array` |
| an array of one where one entry belongs | `[[x]]` for `[x]` | a stray `- ` | stray `[ ]` | `got an array of one Server; unwrap it` |
| a key one level too deep, which an ancestor has | a key below `[ui]`, meant for above the header | wrong indentation | a misplaced `}` | `ui.sandbox: unknown key; sandbox belongs to the top level, not to ui` |
| a non-string scalar where a String belongs | a date-time; `1.10` | `no`, `off` (the Norway problem); `1.10`; `2024-01-01` | `1.10` | `got false; quote it to make it a string` |
| a String that reads as the Integer / Float / bool expected | `"70"` | `"70"` | `"70"` | `got "70"; remove the quotes` |

A hint is a clause after today's message, never a replacement for it. Why no format's words:

- **"One thing: the mapping" holds.** The hints come from Typemap's own types and shapes; it
  still never knows which format the Hash came from, so no `format:` option is needed.
- **No parser knowledge creeps in.** A TOML- or YAML-worded catalogue depends on the parser, not
  the format: Tomlrb's `Time` for a date-time, Psych reading YAML 1.1 so that `no` is `false`.
  An app that switches parsers would get wrong hints, and Typemap would be maintaining a matrix.
- **It holds inside arrays.** At `llm[0].params`, a TOML `[llm.params]` header attaches to the
  last `[[llm]]` entry, not to `llm[0]`, so a hint quoting the header could point the wrong
  way. "Got a single X; wrap it in an array" is true wherever it sits.

The misplaced key matters most: it's the only mistake where today's message points the wrong
way. `ui.sandbox: unknown key` sends the reader to look at `[ui]`'s keys, while the fix is to
move a line up.

**The bet**: "wrap it in an array" is close enough to `[[server]]` for a TOML user. pikuri-tui
is the test. If it isn't enough, the format's own syntax comes back as the deferred part below.

## How each is detected

All of them run only on a value that has already failed, so a good load costs nothing extra.

- **A single entry / an array of one**: `ArrayOf#load` meeting a non-Array test-loads it as the
  element; a class meeting a one-element Array test-loads the entry. If that load succeeds, the
  hint is added. Any `DataError` from the test-load means no hint and today's message. This
  covers scalars too: `tags = "a"` for `Array[String]`. Loading builds a new object and never
  changes a default, so the test-load is safe.
- **A key one level too deep**: `reject_unknown` sees only its own plan today. The session
  carries the chain of ancestors' plans and paths down, and an unknown key that the nearest
  ancestor has exactly gets the hint. An exact ancestor match beats `DidYouMean`'s guesses;
  without one, the spell-checker's message stays as it is. Ancestors only, never siblings or the
  rest of the tree: the chain is one path and either has the key or doesn't, while a search
  across the tree guesses and misses. For a key in the wrong sibling (`sandbox` under `[ui]`,
  meant for `[code]`), today's `unknown key; Ui has theme, font` already tells the reader it's
  not `ui`'s, and they know where it goes.
- **Quote it**: a String scalar, a `String?`, or a literal union of Strings (`"yes" | "no"`,
  where YAML's `no` hurts most) meeting an Integer, Float, `true`/`false`, `Time` or `Date`.
  The message shows the parser's value, `got 1.1` where the file says `1.10`: Typemap never
  sees the file's text, and the path finds the line.
- **No hint**: a found value stays its `inspect`, cut at 60 characters, a container too. A
  Hash that loads neither as the array nor as one entry shows as `{"id"=>"a"}`: that already
  shows the keys, plus the values, and every found value follows the same rule. Revisit if
  that backfires.
- **Remove the quotes**: an Integer, Float or bool meeting a String that reads as one exactly:
  `/\A[+-]?\d+\z/` for an Integer, the same with a fraction for a Float, `"true"`/`"false"` for
  a bool. Not `Integer()`, which also takes `"0x1A"` and `"1_000"`, forms the file's format
  may not have meant as numbers. Strict, never coerced: the value still raises; the hint only
  says what to change in the file.

**The hint lives in `detail`**, after a `; `, with no field of its own. An app that wants to
replace the hint with its format's syntax needs to know *which* mistake it is, and a hint string
doesn't say that without parsing English. What it needs is the structured error below, so a
`hint` field would be an extension point that nothing can use yet. `detail` already carries
through the `entry_name` rename (`server[1] "grok".url`), so the hint does too.

## Load errors drop the namespace

A load error names a class by its last segment: `expected Array[Server]`, and
`unknown key; Server has id, url`. `dump` and `DefinitionError` keep the full name: their
reader is the programmer, and the exact class is what they need. `Type#to_s` serves every
message today, so load messages need a second spelling beside it (or `Type.mismatch` told
which). An anonymous class keeps its `inspect`.

## What stays

- **Strict, never coerced.** A hint says what to change in the file; Typemap never acts on it.
- **The path stays as it is**, `code.mcp[0].env`: dotted paths read the same in all three
  formats, and TOML's own dotted keys look like them.
- **No format's word for a Hash**, as `error.rb` already says. "Table" and "object" stay out.

## Deferred: the format's own syntax

To reopen if "wrap it in an array" proves not enough:

- **A structured `DataError`**: besides `path`, the kind of mistake (mismatch, unknown key,
  required, limit, `validate`, and which hint), the expected type and the found value, so the
  app writes `write [[server]], not [server]` itself (`D_functions_over_rules`). The catch:
  `Type` is `@api private`, so exposing the expected type makes the type model public API. It
  should also carry the entry's name from `entry_name`.
- **`load(..., format: :toml)`** with built-in wordings on top of that: rejected for now for
  the parser-knowledge reason above. The name would also collide with `constrain format:`.

## When it graduates

- `DataError`'s doc comment: the message gains the hint clause and the short class name.
- `design/decisions.md`: a `D_` entry along the lines of *why hints in no format's words,
  rather than TOML's `[[x]]`?*, covering the Hash's-not-the-format's argument, parser
  knowledge, the bet, and why the hint is in `detail` and not a field.
- CHANGELOG: load messages change wording; `detail`'s text is not an API, so no `**Breaking:**`.
