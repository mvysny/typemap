# Required keys: "the file must give this"

Today no key is required: every class builds with a bare `new`, its default instance, so a
missing key keeps the default (`D_accessor_properties`). That is right for state and for an
optional config file. pikuri has keys with no sensible default, such as an API key or a model
name, so `required:` comes with pikuri.

Depends on `validation-phase.md`: `required:` is checked in the validation phase, over the whole
result.

## The shape of it

- `constrain :api_key, type: "String?", required: true`. The default is `nil`, so the bare
  `new` still works, but a result that still holds `nil` there raises `DataError`,
  `api_key: required`.
- **The type is `T?`, always.** The class is a Ruby class first and its signature describes every
  instance, the bare `new` included. A property whose default is `nil` holds `nil`, so its type
  says so: `String?`, not `String`. That's like Kotlin, where a mutable class's field with no
  default must be `String?`. Ruby has no `lateinit`, so the app still handles the `nil` in its
  own code (`config.api_key or raise`, or Steep's narrowing). This is the price of Ruby's type
  system, and Typemap doesn't paper over it.
  - Rejected: a bare `String` with a `nil` default meaning "required". That would read "the
    default fails the type" as "the key must be given", so a forgotten default would quietly
    become a required key instead of a `DefinitionError`, and the signature would lie about the
    bare instance.
  - So `required: true` on a non-nilable type is a `DefinitionError` when the class is first
    read: such a property can never be missing, so `required:` there is a mistake.
- **Checked on the result, not the Hash.** A required key inside a nested table the file leaves
  out still raises, with its full path: `llm.api_key: required`.
- **Checked on dump too.** A required property still `nil` at dump time raises, because the
  file written would not load back.
- **Not a `Data` keyword without a default.** That class could not build bare, and the bare `new`
  is how the mapper learns every default. A data class spells it
  `def initialize(api_key: nil) = super`.

## Not `not_nil:`

TOML has no null, so a TOML file can only leave a key out, which means the default. In JSON,
`not_nil:` would forbid an explicit `null` on a property whose type and default both allow it.
There's no known use case for that. "Must be given" is `required:`, and since it checks the
result, an explicit `null` in JSON fails it just like a missing key.

## On graduation

- `D_accessor_properties`: drop "so there are no required keys yet"; a `D_` entry on why
  `required:` and not a non-nilable type with a `nil` default.
- `Constrain#constrain` doc comment: the `required:` parameter, nilable types only.
- README: a required key in the config example.
