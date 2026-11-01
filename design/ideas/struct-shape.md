# `Struct` as a third shape

Confect maps two shapes (`design/architecture.md`, `D_accessor_properties`): a data class (`Data.define`,
built with `new(**values)`) and an accessor class (public reader + writer pairs, built with a
bare `new` and then setters). A `Struct` is neither quite, and an app may well use one for its
config or state.

## What a `Struct` already gives

- **Readers and writers for every member**, so the accessor rule would find them as they are.
- **A bare `new` works**: `Point = Struct.new(:x, :y); Point.new` gives `x = nil, y = nil`.
- **`keyword_init: true`** (or, since Ruby 3.2, keywords by default when all arguments are
  keywords) builds it like a data class: `Point.new(x: 1, y: 2)`.
- **Its members have no source location**: `instance_method(:x).source_location` is `nil`
  (`R_ruby_reflection`), so the accessor shape's declaration order — sorted by source line —
  does not work. The order must come from `members`.

So the third shape is small: properties from `members` (in order), read through the getter,
built with a bare `new` and the setters — the accessor shape with `members` as its list.

## Why it is not built yet

No app uses a `Struct` for its settings: virtui's are a data class (`Ballooning`) and an
accessor class (`State`). Today a `Struct` already maps — it is not a `Data`, so it is read as an
accessor class — but its members have no source line, so it dumps them by name: `Struct.new(:y,
:x)` dumps `x` first (verified 2026-11-01). Shapes are internal, with no option to add one;
adding `Struct` is a `StructShape` beside `DataShape` and `AccessorShape` in
`lib/confect/mapper/`, picked by `klass < Struct` in `Plan.build`, its order from `members`.

## Open questions

- `Q_struct_defaults` — a bare `Struct#new` sets every member to `nil`, so with non-nil types
  every default fails the type check (`Integer` with default `nil`). A config `Struct` must then
  override `initialize` with real defaults, or type every member `T?`. Is the override the
  documented way, or does Confect read defaults some other way? The override keeps the rule
  "the bare `new` is the default instance" intact.
- `Q_struct_order` — `members` order is declaration order; is `to_h` the dump, or the shape's
  own walk through the getters? The walk keeps nested objects and `ignore` working the same as
  for the other shapes.
- `Q_who_asks` — which app wants it first; until one does, it stays here.
