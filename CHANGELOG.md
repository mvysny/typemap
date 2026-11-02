<!-- An entry is one sentence — `Add` / `Fix` / `**Breaking:**`, the symbol, what changed, ≈40
     words; a breaking entry earns a second sentence for the migration only. -->

## [Unreleased]

## [0.1.0] - 2026-11-02

- Add `Typemap::Mapper#load` and `#dump`: a Hash onto a data class or an accessor class and back, strictly typed, then validated — limits, required keys, the class's own `validate` — the first problem raised as a `Typemap::DataError` with the value's path.
- Add frozen data-class results: after `load`, every Array, Hash and String a data object holds is frozen in place, defaults and the caller's Strings included, so `config.engines << "x"` raises; an accessor class's values stay mutable.
- Add a suggestion for a misspelled key, `rasie_at_percent: unknown key, did you mean raise_at_percent?`, and limits in words, `must be at least 1, got 0` rather than `0 is not in 1..`.
- Add a hint at the fix for a classic mistake, worded for `load`'s `source:` — `:toml`'s `write [[server]], not [server]`, `:json`'s `wrap it in [ ]`, `:yaml`, or the default `:ruby`'s `got Integer 70` — and a class named without its namespace, `expected Array[Server]`.
- Add an array entry's name to an error path: a class method `entry_name(raw)`, given the entry as a Hash with String keys, turns `server[1].url: required` into `server[1] "grok".url: required`; a blank result leaves the bare index.
- Add required keys: a data class's keyword without a default, or an accessor class's `constrain :name, type: "T?", required: true`; one missing raises `name: required`, nested ones with their full path.
- Add the `Object` type: plain data — String, Integer, Float, bool, Array, Hash with String keys, `nil` nested inside — passed through on load and checked on dump, so `Hash[String, Object]` holds keys sent somewhere verbatim.
- Add whole-number loading: an `Integer` property takes `70.0` as `70`, a `Float` property takes `1` as `1.0`; `70.5`, NaN and an Integer a Float would round still raise.
- Add the `unique: true` and `unique_by:` limits for an Array — `unique_by: :id` names a property of the entries, `unique_by: ->(m) { m.url.downcase }` a function — reported at the second entry, `server[2] "local".id: duplicate of server[0], both "local"`.
- Add the `not_blank: true` limit for a String, which refuses `""` and `"  "`, and `not_empty: true` for an Array or a Hash; a miss reads `url: must not be blank`, the path down to the key.
- Add `Typemap::Constrain` — `constrain :name, type: "Integer", in: 1..100, format: /…/` and `ignore :name`, metadata the mapper reads, defining nothing on the class.
- Add a class's own unknown-key policy, `unknown :ignore` or `unknown :raise`, which wins over `load`'s `unknown:` for that class's keys wherever it appears — a table another program owns stays lenient in an otherwise strict file.
- Add `Typemap::Mapper::BasicTypes`, the default type strategy (types from `constrain type:`), and `Typemap::Mapper::RBSTypes` (types from `sig/*.rbs`, with the app's `rbs` gem).
- Add `Typemap::DefinitionError`, like `DataError` a `Typemap::Error`, raised the first time the mapper reads a class it cannot map — no type, a default the type rejects, a limit the type cannot take.
