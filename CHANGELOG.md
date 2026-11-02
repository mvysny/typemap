<!-- An entry is one sentence — `Add` / `Fix` / `**Breaking:**`, the symbol, what changed, ≈40
     words; a breaking entry earns a second sentence for the migration only. -->

## [Unreleased]

- Add `Typemap::Mapper#load` and `#dump` — a Hash onto a data class or an accessor class and back, strict types, then the whole result validated — limits, required keys, the class's own `validate`, nested objects first — the first problem raised as a `Typemap::DataError` carrying the value's path.
- Add a suggestion for a misspelled key, `rasie_at_percent: unknown key, did you mean raise_at_percent?`, and limits in words, `must be at least 1, got 0` rather than `0 is not in 1..`.
- Add required keys: a data class's keyword without a default, or an accessor class's `constrain :name, type: "T?", required: true`; one missing raises `name: required`, nested ones with their full path.
- Add whole-number loading: an `Integer` property takes `70.0` as `70`, a `Float` property takes `1` as `1.0`; `70.5`, NaN and an Integer a Float would round still raise.
- Add `Typemap::Constrain` — `constrain :name, type: "Integer", in: 1..100, format: /…/` and `ignore :name`, metadata the mapper reads, defining nothing on the class.
- Add `Typemap::Mapper::BasicTypes`, the default type strategy (types from `constrain type:`), and `Typemap::Mapper::RBSTypes` (types from `sig/*.rbs`, with the app's `rbs` gem).
- Add `Typemap::DefinitionError`, raised the first time the mapper reads a class it cannot map — no type, a default the type rejects, a limit the type cannot take.
