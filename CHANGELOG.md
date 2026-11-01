<!-- An entry is one sentence — `Add` / `Fix` / `**Breaking:**`, the symbol, what changed, ≈40
     words; a breaking entry earns a second sentence for the migration only. -->

## [Unreleased]

- Add `Typemap::Mapper#load` and `#dump` — a Hash onto a data class or an accessor class and back, strict types, the first problem raised as a `Typemap::DataError` carrying the value's path, the class's own `validate` called nested objects first.
- Add `Typemap::Constrain` — `constrain :name, type: "Integer", in: 1..100, format: /…/` and `ignore :name`, metadata the mapper reads, defining nothing on the class.
- Add `Typemap::Mapper::BasicTypes`, the default type strategy (types from `constrain type:`), and `Typemap::Mapper::RBSTypes` (types from `sig/*.rbs`, with the app's `rbs` gem).
- Add `Typemap::DefinitionError`, raised the first time the mapper reads a class it cannot map — no type, a default the type rejects, a limit the type cannot take.
