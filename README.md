# Confect

Confect loads a config file into a Ruby class you already wrote, and checks every value on the
way: `"70"` is never 70, and the file never names a class. Your class stays yours — a
`Data.define` or a plain class with `attr_accessor`s, typed by `constrain` lines or by your RBS
signatures. TOML, JSON and YAML parsing stays with their own gems; Confect owns the mapping, the
checking, and optionally where an app's config and state files live.

To confect is to prepare something from raw ingredients: a raw file in, a checked Ruby object
served out.

Pre-release: the mapper below works; the layer that finds an app's files in `~/.config` and
`/etc` is still [an idea](design/ideas/locations.md). Requires Ruby 3.3+; no runtime dependencies.

## A quick look

```ruby
require "confect"
require "tomlrb"

class Ballooning < Data.define(:raise_at_percent, :shrink_at_percent, :pinned_vms)
  extend Confect::Constrain

  constrain :raise_at_percent, :shrink_at_percent, type: "Integer", in: 1..100
  constrain :pinned_vms, type: "Array[String]"

  def initialize(raise_at_percent: 65, shrink_at_percent: 55, pinned_vms: []) = super

  def validate
    raise "raise_at_percent must be above shrink_at_percent" unless raise_at_percent > shrink_at_percent
  end
end

mapper = Confect::Mapper.new
ballooning = mapper.load(Ballooning, Tomlrb.load_file("ballooning.toml"))
```

A file that does not fit raises `Confect::DataError`, with the path of the offending value:

```
raise_at_percent: expected Integer, got "70"
raise_at_percent: 170 is not in 1..100
pinned_vms[1]: expected String, got 7
rasie: unknown key; Ballooning has raise_at_percent, shrink_at_percent, pinned_vms
raise_at_percent must be above shrink_at_percent
```

## Loading and saving

```ruby
mapper = Confect::Mapper.new

config = mapper.load(Config, Tomlrb.load_file(path))                  # Tomlrb, JSON, YAML.safe_load: any Hash
state  = mapper.load(State, JSON.load_file(path), unknown: :ignore)   # drop keys a newer version wrote
File.write(path, JSON.pretty_generate(mapper.dump(state)))            # String keys, nested objects as Hashes
```

- **A key present replaces the default; a key absent keeps it.** A nested table loads onto the
  default's nested object, so a file that sets one nested key keeps the other nested defaults.
- **An unknown key raises**, unless `unknown: :ignore`.
- **Keys may be Strings or Symbols** (`JSON.load_file(path, symbolize_names: true)` works).
- **`dump` writes properties in declaration order** and checks every value against its type, so
  a bug that put a wrong value in an object is caught before it reaches the file.
- **The first problem raises.** Confect does not collect every error.
- **A mapper is safe to share between threads**; it works out each class once and remembers it.

## Your class

Two shapes of class map, and either must build with a bare `new` — that instance is the default:

- **A data class**, `Data.define`: its properties are its members. Give every member a default
  with `def initialize(a: 1, b: "x") = super`.
- **An accessor class**, mutable: its properties are its **public reader + writer pairs** —
  `attr_accessor`s, or a hand-written `def foo` / `def foo=(value)`, inherited ones included.
  It is built with a bare `new`, then a setter per property.

```ruby
class State
  extend Confect::Constrain

  attr_accessor :system_pane_visible, :log_pane_visible
  attr_accessor :on_change                  # a listener, not a setting
  attr_reader :path                         # a reader alone is not a property

  constrain :system_pane_visible, :log_pane_visible, type: "bool"
  ignore :on_change

  def initialize
    @system_pane_visible = true
    @log_pane_visible = true
  end
end
```

An accessor that is not a setting goes `private`, or stays public under `ignore`. Left public, it
has no type, and Confect raises when it first reads the class — it never serializes it quietly.

**Validation across properties** goes in the class's own `validate`, which Confect calls after
building the object, nested objects first; whatever it raises becomes a `Confect::DataError`
carrying the object's path.

## Types

Every property needs a declared type: from `constrain type:`, or from your RBS signatures (below).
The default never supplies one — a default of `65` would otherwise reject `65.5` from the file.

| Type | Takes | Rejects |
|---|---|---|
| `Integer` | `70` | `"70"`, `70.0` |
| `Float` | `0.5` | `1` (an Integer is not a Float) |
| `String` | `"a"` | `:a` |
| `bool` | `true`, `false` | `0`, `"yes"` |
| `T?` | `nil`, or a `T` | |
| `"short" \| "verbose"` | one of the literals | anything else; `1 \| 2` rejects `1.0` |
| `Array[T]` | an Array of `T` | |
| `Hash[String, T]` | a table of `T` | |
| `Ballooning` | a table, loaded into your class | |

Types are RBS strings, never Ruby classes: `"Integer"` does not take `nil`, `"Integer?"` does. A
name resolves the way Ruby resolves it in the code beside it — `"Size"` inside `module App` finds
`App::Size` first; `"::Size"` or `"Other::Size"` says exactly which.

**Limits** narrow a type:

```ruby
constrain :raise_at_percent, type: "Integer", in: 1..100   # a range, for a number
constrain :min_gib, type: "Integer", in: (1..)              # an endless range: parenthesize it
constrain :mode, type: "String", in: %w[short verbose]      # a list of values
constrain :name, type: "String", format: /\A[a-z]+\z/       # a pattern, for a String
```

Parenthesize an endless range at the end of a line: `in: 1..` followed by a newline makes Ruby
read the next line as the range's end.

## Problems in the class itself

A class Confect cannot map raises `Confect::DefinitionError` the first time the mapper reads it —
before it looks at any file, so a gap never waits for a user to set that key:

```
Config#name: no type: give it `constrain :name, type: "…"` (…)
Config#port: its default nil does not fit Integer
Config#port: format: /x/ limits only a String, not Integer
Config#ratio: unsupported type: Set[…]
Config: constrain names prot, not a property
Config: must build with a bare new, its default instance (missing keyword: :port)
```

Both `Confect::DataError` and `Confect::DefinitionError` are `Confect::Error`s.

## Types from RBS signatures

A project that keeps `sig/*.rbs` can take its types from there instead of `constrain type:`:

```ruby
mapper = Confect::Mapper.new(types: Confect::Mapper::RBSTypes.new)
```

- A property's type is its reader's: `attr_reader` / `attr_accessor name: T`, or
  `def name: () -> T`, along the class's ancestors.
- `RBSTypes` finds the `sig/` directory beside the class's own source, walking up from its file;
  `RBSTypes.new(sig: ["sig/app.rbs"])` names the files instead.
- `constrain` still gives limits; a `constrain type:` for a property the signatures already type
  raises, since a type declared twice drifts.
- It needs the `rbs` gem — add `gem "rbs"` to your Gemfile. Confect itself never depends on it.

[sord](https://github.com/AaronC81/sord) writes `sig/*.rbs` from YARD tags
(`sord gen sig/app.rbs --rbs`). A data class is typed with YARD's `@!attribute` directive, in the
`class X < Data.define(…)` form:

```ruby
# @!attribute [r] raise_at_percent
#   @return [Integer] grow the guest above this share of its memory
class Ballooning < Data.define(:raise_at_percent)
```

## Design

Why Confect is shaped this way — and why not dry-struct, ActiveModel or `T::Struct` — is in
[design/decisions.md](design/decisions.md).

## License

MIT; see [LICENSE.txt](LICENSE.txt).
