# Custom types: a scalar in the file, an object in Ruby

A type tells the mapper what a property is, not how a scalar in the file becomes that object:
`min_actual = "8 GiB"` is a String in the file and virtui's `Size` in Ruby; `veto = "60s"` would be
a `Duration`. That needs a conversion both ways, which the mapper does not have: today a class
that is not a data class or an accessor class raises "has no properties", so nothing is converted
quietly.

## Why it is not built yet

Nothing needs it while settings carry their unit in the key — `min_actual_gib = 8`,
`veto_seconds = 60` — plain integers that cannot be misread. It waits on virtui's `Q_units`
(its `design/ideas/config-file.md`): unit in the key, or unit in the value.

## The two designs

- **A protocol class**: any class with `.load(raw)` and `#dump` is a custom type; the mapper
  calls `Size.load("8 GiB")`, which raises on garbage, and `size.dump` → `"8 GiB"`. No
  registration; the class says it.
- **A registry**: `Confect::Mapper.type("Size") { |raw| … }` that type names resolve through — for
  a class the app does not own and cannot add `.load` to.

## Open questions

- `Q_custom_protocol` — protocol, registry, or the protocol first and a registry when a foreign
  class needs one?
- `Q_custom_limits` — may `in:` limit a custom type (`in: Size.gib(1)..Size.gib(64)`)? Only if
  the type is `Comparable`.
