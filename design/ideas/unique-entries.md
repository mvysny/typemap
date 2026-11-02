# Unique array entries: `constrain :server, unique_by: :id`

Every config with named entries checks they are unique. Both pikuri shells do it in the root
class's `validate`, three lists at once:

```ruby
def validate
  { 'server id' => server.map(&:id), 'llm name' => llm.map(&:name), 'code.mcp id' => code.mcp.map(&:id) }
    .each do |label, values|
      dups = values.tally.select { |_, n| n > 1 }.keys
      raise "duplicate #{label}(s): #{dups.join(', ')}" unless dups.empty?
    end
end
```

The message is `duplicate server id(s): local` — no path, no index, so the user hunts through
the `[[server]]` headers for both. That hunt is exactly what `D_entry_name` set out to end.

**This reverses part of `D_entry_name`**, which says "uniqueness is the app's check". That was
said about why the index stays in a named path (two entries may share a name), not as a ruling
on uniqueness itself; but it needs revisiting on the record if this goes ahead.

## The sketch

```ruby
constrain :server, unique_by: :id
constrain :llm, unique_by: :name
constrain :tags, unique: true          # Array of scalars: the values themselves
```

```
server[2] "local".id: duplicate of server[0]
```

- A limit on an `Array[T]`, checked in the validation phase (`D_validation_phase`) after every
  entry passed its own — so `id` is known to be a non-nil String by then.
- `unique_by:` names a property of `T`; `check_against` raises a `DefinitionError` when `T` has
  no such property, or is no class.
- The path is the *second* occurrence, named through `entry_name` like any entry error, and the
  detail names the first by index.

## Open questions

- `Q_function_or_name` — a property name, or a function (`unique_by: ->(s) { s.url.downcase }`)?
  `D_functions_over_rules` leans function once it must say *how*; a property name only says
  *what*. Start with a Symbol, allow a Proc later if a consumer asks?
- `Q_across_arrays` — pikuri's `[[server]] id` and `[[llm]] name` are separate namespaces, so
  per-array is enough here. A key unique across two arrays is the app's `validate`, still.
