# `Object`: a value passed through as the file holds it

Asked by pikuri-tui, whose `Shared::Config` would move onto Typemap. Two of its keys hold data
whose meaning belongs to someone else:

- `[[llm]] params = { chat_template_kwargs = { enable_thinking = false } }`: extra
  chat-completion keys sent to the server verbatim. Each server spells them differently, so
  the app checks only that `params` is a table.
- `[titler]`, `[web]`: tables another program reads from the same shared file. The app checks
  they're tables and nothing more, so the other program adding a key can't stop this one
  booting.

In YARD both are `Hash{String => Object}`; sord writes `attr_reader params: ::Hash[String, Object]`.
Typemap rejects that today:

```
Typemap::DefinitionError: Object has no properties: neither a data class nor an accessor class
```

The message is misleading as well: `Object` isn't a class someone forgot to give properties to.
The README's Types table doesn't list `Object`, so the README doesn't claim it works. But the
table doesn't say it is the complete list either; a line saying "anything else raises
unsupported type" would answer the question before anyone tries.

## The sketch

`Object` as a type, bare or nested (`Hash[String, Object]`, `Array[Object]`, `Object?`):

- **load**: takes any value the parser produced and passes it through unchanged: a String,
  Integer, Float, `true`/`false`, an Array, a Hash, nested any way. A `Hash[String, Object]`
  still checks the outer level, so `params = 7` fails with `params: expected Hash, got 7`.
- **dump**: checks that the value is something a file can hold, so a bug that put a `Proc` or
  a `Tuile::Size` into `params` is caught before it is written, the same promise `dump` makes
  for every other type.
- **Types table**: `Object` | any value the file holds, as parsed | on `dump`, a Ruby object no
  file can hold.

## `untyped` stays rejected

sord writes `untyped` when it gives up: a duck type (`[#call]`), or a name it couldn't resolve
with `--replace-unresolved-with-untyped`. Accepting `untyped` as a synonym would let sord's
gaps become unchecked properties. `Object` is something the author wrote down on purpose;
`untyped` usually isn't. The `unsupported type` error for `untyped` could point at `Object`.

## Open questions

- `Q_object_scalars`: which values are "a file can hold"? JSON gives String, Integer, Float,
  bool, nil, Array, Hash. Tomlrb also gives `Time` / `Date` for TOML date-times, and
  `YAML.safe_load` can, given `permitted_classes`. Are those passed through on load and
  accepted on dump, or is the set exactly JSON's?
- `Q_object_nil`: does bare `Object` take `nil` (RBS `Object` does), or must it be written
  `Object?`, like every other type here? Typemap's types never take `nil` unless written with
  `?`, and keeping that rule seems right; a JSON `null` nested *inside* the value is just data.
- `Q_object_keys`: `JSON.load_file(path, symbolize_names: true)` gives Symbol keys inside
  the opaque value too. Pass them through, or convert them to Strings so `dump` writes
  the file the way it was read?
- `Q_object_freeze`: deep-freeze what passes through? pikuri-tui freezes `params` itself today;
  a `Data` object holding a Hash the caller can still mutate is only half immutable.
