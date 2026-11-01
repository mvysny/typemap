# Required keys: "the file must give this"

Today no key is required: every class builds with a bare `new`, its default instance, so a
missing key keeps the default (`D_accessor_properties`). That is right for state and for an
optional config file. pikuri has keys with no sensible default, such as an API key or a model
name, so required keys come with pikuri.

Depends on `validation-phase.md`: an accessor class's `required:` is checked in the validation
phase, over the whole result.

## Requiredness belongs to the shape

Whether a key is required is decided by its default, not by its type: a property with no
default must be given. Nilability is a separate question. In Ruby, `Data.define(:a)` won't
build without `a` whatever its type. In Kotlin, `val a: String?` with no default is required
too. The two class forms differ in whether they can say "no default":

- **A `Data` class can.** A keyword without a default is required, and Ruby already enforces
  it. Typemap reads that off the class, just as it reads `members`.
- **An accessor class can't.** A bare `new` gives every property a value, so `required: true` on
  a `T?` property is the only way it can say a key must be given.

So each shape has one way to say it, and the shape answers "which properties are required"
the way it already answers "which properties are there". The mapper still never branches on the
kind of class anywhere else (architecture.md).

- Rejected: deciding from the type, so that `String` means required and `String?` optional. A
  `Data` keyword `String` with the default `"x"` is optional, and a `String?` keyword with no
  default is required. Deciding from the type would contradict the class.
- Rejected: `required:` defaulting to `true` on an accessor class. That would break the partial
  config file, which is the main use. `required: true` on a non-nilable type is a mistake (see
  below), so every type would have to become `T?`. And under `RBSTypes`, every optional property
  would need a `constrain` line, which `D_accessor_properties` refuses to require.

## Data classes: a keyword without a default

```ruby
Llm = Data.define(:api_key, :model) do
  def initialize(api_key:, model: "gpt-5") = super
end
```

- **The type is non-nil.** `api_key` is a `String`, and the app never handles a `nil` that the
  class cannot hold. This is the payoff: the `T?` that accessor classes pay for isn't
  necessary here.
- **Read from `instance_method(:initialize).parameters`.** `:keyreq` is required and `:key`
  is optional. A plain `Data.define` with no override reports `[[:rest]]` (the method's owner is
  `Data`), so every member is required. Any other signature, `**opts` say, can't be read and
  is a `DefinitionError` when the class is first read. So is a mapped member that isn't a
  keyword, and an `ignore`d member that is required, since the file can't give it.
- **`required:` on a `Data` class is a `DefinitionError`**, raised when the mapper first reads
  the class, like `constrain names X, not a property`. To make a key required, drop its
  default.
- **Missing from the Hash → `DataError`** `llm.api_key: required`, raised before `new`, so
  Ruby's `ArgumentError` text never reaches the user. Unlike `required:`, this is checked on
  the Hash: a `Data` instance can't exist without the key, so there is no result to check.
- **The type decides `null`.** A `String?` keyword with no default must be given, and JSON
  `null` is a valid value for it, as in Kotlin. A `String` keyword rejects `null` through the
  type check, as now.
- **Required spreads upward.** A parent can't default a nested `llm:` whose class has a required
  keyword, so the parent's `llm` is required too, or `Llm?` with `nil`. If the file leaves out
  `[llm]`, that raises `llm: required`.

### No default instance

A class with a required keyword has no bare `new`, and with it go two things that the default
instance gives today:

- **The defaults are checked on each load, not when the class is first read.** `Plan.build` has
  no instance to read the optional keywords' defaults from, which bends the invariant "a class
  is fully checked the first time the mapper reads it" for such classes. The validation phase
  checks every result, defaults included, so a bad default still raises, just later. The rest of
  the plan is still checked up front: the types, the limits fitting their types, the
  initializer's signature.
- **The base is built from the required keys.** Load the required keys first (type check,
  recursion), then `klass.new(**required)` is the base. The flow continues as it does today:
  every other key loads onto the base's value, so a partial `[llm]` table still merges onto the
  parent's default `llm`, and the shape builds a new object from the base plus the loaded values.
  A required keyword that is itself a nested class has no default to merge onto, so it builds
  from its own class's defaults.

## Accessor classes: `required:` on a `T?`

- `constrain :api_key, type: "String?", required: true`. The default is `nil`, so the bare
  `new` still works, but a result that still holds `nil` there raises `DataError`,
  `api_key: required`.
- **The type is `T?`, always.** The class is a Ruby class first, and its signature describes
  every instance, the bare `new` included. A property whose default is `nil` holds `nil`, so its
  type says so: `String?`, not `String`. Kotlin works the same way: a mutable class's field with
  no default must be `String?`. Ruby has no `lateinit`, so the app still handles the `nil` in
  its own code (`config.api_key or raise`, or Steep's narrowing). A class that wants the
  non-nil type is a `Data` class.
  - Rejected: a bare `String` with a `nil` default meaning "required". That would treat "the
    default fails the type" as "the key must be given", so a forgotten default would quietly
    become a required key instead of a `DefinitionError`, and the signature would lie about the
    bare instance.
  - So `required: true` on a non-nilable type is a `DefinitionError` when the class is first
    read: such a property can never be missing, so `required:` there is a mistake.
- **Checked on the result, not the Hash.** A required key inside a nested table that the file
  leaves out still raises, with its full path: `llm.api_key: required`. So does an explicit
  JSON `null`, since `nil` is the placeholder here.
- **Checked on dump too.** A required property still `nil` at dump time raises, because the
  file written would not load back. A `Data` class needs no such check: its type already
  rules out the `nil`.

## Not `not_nil:`

TOML has no null, so a TOML file can only leave a key out, which means the default. In JSON,
`not_nil:` would forbid an explicit `null` on a property whose type and default both allow it.
There's no known use case for that. On an accessor class, "must be given" is `required:`, and an
explicit `null` fails it just like a missing key. On a `Data` class, the non-nil type
rejects `null`.

## On graduation

- `D_accessor_properties`: drop "so there are no required keys yet". A new `D_` entry: why
  requiredness belongs to the shape (a `Data` keyword without a default, `required:` on an
  accessor class's `T?`), and why it is never read off the type.
- `design/architecture.md`, "Reading a class" step 1 and "Loading a file" step 2: a `Data` class
  with required keywords has no default instance, and its base is built from the required keys.
- AGENTS.md invariant "A class is fully checked the first time the mapper reads it": its
  exception for a `Data` class's defaults.
- `Constrain#constrain` doc comment: the `required:` parameter, accessor classes and nilable
  types only.
- `DataShape` doc comment: required keywords read from `initialize`.
- README: a required key in the config example, in both class forms.
