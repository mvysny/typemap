# Validation as its own phase, after load and before dump

Today one pass does everything per object: `Session#load_object` type-checks each key present,
checks its `constrain` limits, builds the object and calls its `validate`. Two gaps follow:

- **An object the file never mentions is never checked.** A missing `[llm]` table keeps the
  default's nested object, and `load_object` never runs for it. That's harmless only because a
  default must pass its type and limits when the class is first read, and it stops being harmless
  once `required:` exists (`required-keys.md`).
- **`dump` checks types, not limits nor `validate`.** An app that changes its state in code can
  write a file that the next load rejects.

## The split

1. **Conversion**: Hash → objects on load, objects → Hash on dump. This is everything needed to
   build: the strict type check, unknown keys, recursion into nested tables. Types can't move
   out of this phase, because there is nothing to build from `"70"` when the type is `Integer`.
2. **Validation**: reads the finished object tree, walking it through the plans and changing nothing.
   Per object, nested objects first:
   1. the `in:` / `format:` limits,
   2. `required:` (`required-keys.md`),
   3. the class's own `validate`. It runs last, so it can assume the limits passed: a
      `min <= max` check compares two Integers already known to be in range.

The first problem raises a `DataError` with its path, as now.

- **`load`** = conversion, then validation of the whole result, so an object the file left
  out is checked too.
- **`dump`** = conversion, then validation, and the Hash comes back only if both pass. Validation
  doesn't run first because it assumes the types hold, and `in: 1..100` on a String the app put
  there is nonsense. The conversion's type check settles that. Nothing is written that a
  later `load` would reject.

## Walking the tree

Validation has to reach every object, including those inside `Array[Foo]` and
`Hash[String, Foo]`. So each `Type` gets a third hook next to `load` and `dump`, one that yields
the class-typed objects inside a value along with their paths. `ClassRef` yields the value itself,
the collections yield what their element types yield, and scalars yield nothing. The second
walk costs nothing at config size.

## Checking the default when the class is first read

`plan.rb` checks each default against its type and limits on its own. That becomes conversion's
type check plus validation steps 1–2 run on the bare `new`, with `required:` skipped (a required
property's `nil` default is the point). The result is one rulebook instead of two. A `Data` class
with a required keyword has no bare `new` (`required-keys.md`), so its defaults are checked only
through each load's result.

- `Q_default_validate`: should reading the class also run the class's own `validate` on the
  default? It would catch a default that breaks its own invariant before any file is read, but
  a class with a required key can't pass it on its `nil` default, and a `validate` written for
  loaded objects may crash on `nil`. Leaning no: limits only.

## Not now

- **A public `mapper.validate(object)`**: validation stays private to `load` and `dump` until an
  app needs it on its own.
- **Layered loads** (a system file, then a user file onto it): not supported. `required:` is
  checked on each load's result.
- **Reporting every violation at once**: validation could collect them instead of raising at the
  first. Nothing asks for it yet.

## On graduation

- `design/architecture.md`, "Loading a file" and "Dumping": the two phases.
- `D_` entry: why validation runs over the whole result and on dump, and why types stay in
  conversion.
- `Mapper#load` / `#dump` doc comments: what runs in which order; `dump` gains a `@raise`
  for limits and `validate`.
- CHANGELOG: `dump` now raises on an out-of-range value or a failing `validate` (**Breaking:**).
