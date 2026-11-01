# Required keys: "the file must give this"

Today no key is required: every class builds with a bare `new`, its default instance, so a
missing key keeps the default (`D_accessor_properties`). That is right for state and for an
optional config file. pikuri has keys with no sensible default — an API key, a model name — so
`required:` comes with pikuri.

## The shape of it

- `constrain :api_key, type: "String?", required: true`: the default may be `nil` — the bare
  `new` still works — but a file without the key raises `DataError`, `api_key: required`.
- **Not a `Data` keyword without a default**: that class could not build bare, and the bare `new`
  is how the mapper learns every default.

## Not `not_nil:`

TOML has no null, so a TOML file can only leave a key out, which means the default. In JSON,
`not_nil:` would forbid an explicit `null` on a property whose type and default both allow it —
no known use case. "Must be given" is `required:`.

## Open questions

- `Q_required_type` — must a required property's type be `T?`, so its `nil` default passes, or
  may the default fail the type as long as the key is required? The first keeps "the default
  must pass the type" without an exception.
