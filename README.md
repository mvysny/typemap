# Typemap

Typemap maps a Hash onto a Ruby class you already wrote, and back, checking every value on the
way: `"70"` is never 70, and the data never names a class. Your class stays yours — a
`Data.define` or a plain class with `attr_accessor`s, typed by `constrain` lines or by your RBS
signatures. Reading and writing TOML, JSON or YAML, and finding the file, stay with the app;
Typemap owns the mapping and the checking, and does that one thing well.

Pre-release. Requires Ruby 3.3+; no runtime dependencies.

## A quick look

```ruby
require "typemap"
require "tomlrb"

class Ballooning < Data.define(:raise_at_percent, :shrink_at_percent, :pinned_vms)
  extend Typemap::Constrain

  constrain :raise_at_percent, :shrink_at_percent, type: "Integer", in: 1..100
  constrain :pinned_vms, type: "Array[String]"

  def initialize(raise_at_percent: 65, shrink_at_percent: 55, pinned_vms: []) = super

  def validate
    raise "raise_at_percent must be above shrink_at_percent" unless raise_at_percent > shrink_at_percent
  end
end

mapper = Typemap::Mapper.new
ballooning = mapper.load(Ballooning, Tomlrb.load_file("ballooning.toml"), source: :toml)
```

A file that does not fit raises `Typemap::DataError`, with the path of the offending value and,
for a classic mistake, the fix in the file's own syntax:

```
raise_at_percent: expected Integer, got "70"; remove the quotes
raise_at_percent: must be 1 to 100, got 170
pinned_vms: expected Array[String], got a single String; wrap it in [ ]
pinned_vms[1]: expected String, got 7; quote it to make it a string
rasie_at_percent: unknown key, did you mean raise_at_percent?
rasie: unknown key; Ballooning has raise_at_percent, shrink_at_percent, pinned_vms
raise_at_percent must be above shrink_at_percent
```

## Loading and saving

```ruby
mapper = Typemap::Mapper.new

config = mapper.load(Config, Tomlrb.load_file(path), source: :toml)                # Tomlrb, JSON, YAML.safe_load: any Hash
state  = mapper.load(State, JSON.load_file(path), source: :json, unknown: :ignore)  # drop keys a newer version wrote
File.write(path, JSON.pretty_generate(mapper.dump(state)))            # String keys, nested objects as Hashes
```

- **A key present replaces the default; a key absent keeps it.** A nested Hash loads onto the
  default's nested object, so a file that sets one nested key keeps the other nested defaults.
- **`source:` words an error for where the Hash came from**: `:toml`, `:json`, `:yaml`, or
  `:ruby`, the default, for a Hash built in code. The mistake is the same in every source; the
  fix is spelled in its syntax:

  | `source:` | `[server]` where an array belongs | `7` where a String belongs |
  |---|---|---|
  | `:ruby` | `wrap it in an array` | `got Integer 7` |
  | `:toml` | `write [[server]], not [server], or server = [{…}]` | `got 7; quote it to make it a string` |
  | `:json` | `wrap it in [ ]` | `got 7; quote it to make it a string` |
  | `:yaml` | `put "- " before it` | `got 7; quote it to make it a string` |

- **An unknown key raises**, unless `unknown: :ignore`.
- **Keys may be Strings or Symbols** (`JSON.load_file(path, symbolize_names: true)` works).
- **`dump` writes properties in declaration order** and checks every value as `load` would — its
  type, its limits, a required key, the class's `validate` — so a bug that put a wrong value in
  an object is caught before it reaches the file.
- **Every object in the result is validated**, the ones the file left out included: a default
  nested object must pass its limits and `validate` too.
- **The first problem raises.** Typemap does not collect every error.
- **A mapper is safe to share between threads**; it works out each class once and remembers it.

## Your class

Two shapes of class map. A bare `new` is the default instance: every key the file leaves out
keeps its value there.

- **A data class**, `Data.define`: its properties are its members. Give a member a default with
  `def initialize(a: 1, b: "x") = super`; a member without one is a [required key](#required-keys).
- **An accessor class**, mutable: its properties are its **public reader + writer pairs** —
  `attr_accessor`s, or a hand-written `def foo` / `def foo=(value)`, inherited ones included.
  It is built with a bare `new`, then a setter per property.

```ruby
class State
  extend Typemap::Constrain

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
has no type, and Typemap raises when it first reads the class — it never serializes it quietly.

**Validation across properties** goes in the class's own `validate`, which Typemap calls on
every object once the whole result is built, nested objects first, on `load` and on `dump`;
whatever it raises becomes a `Typemap::DataError` carrying the object's path.

### Required keys

A key the file must give, one with no sensible default, such as an API key:

```ruby
class Llm < Data.define(:api_key, :model)
  extend Typemap::Constrain

  constrain :api_key, :model, type: "String"

  def initialize(api_key:, model: "gpt-5") = super   # api_key has no default: required
end

class Secret                                          # an accessor class
  extend Typemap::Constrain

  attr_accessor :api_key

  constrain :api_key, type: "String?", required: true

  def initialize = @api_key = nil
end
```

- **A data class: a keyword without a default.** `api_key` stays a non-nil `String`. A plain
  `Data.define(:a, :b)` requires every member. `required:` on a data class raises.
- **An accessor class: `required: true` on a `T?` defaulting to `nil`.** A bare `new` sets every
  property, so the type admits the `nil` and the app handles it (`config.api_key or raise`). For
  a non-nil type, use a data class.
- **A missing key raises with its full path**, `llm.api_key: required`, also when the file leaves
  out the whole `[llm]` table. An accessor class refuses an explicit JSON `null` too; a data
  class's `String?` keyword takes it.
- **`dump` raises** on a required accessor still `nil`, since the file would not load back.

### Naming an array entry

An error inside an array names the entry by its index, `server[1].url: required`. A class
method `entry_name` adds the name the file gave it, so nobody counts `[[server]]` headers:

```ruby
class Server < Data.define(:id, :url)
  extend Typemap::Constrain

  constrain :id, :url, type: "String"

  def self.entry_name(raw) = raw["id"]   # or "#{raw["host"]}:#{raw["port"]}", anything
end
```

```
server[1] "grok".url: required
```

- **`raw` is the entry as a file would hold it**: a Hash with String keys, its values not yet
  checked. Once the entry is built, for a later check or a `dump`, it is the entry dumped, defaults
  included.
- **No name, just the index**, when `entry_name` returns `nil`, an empty String or anything not
  a String. When it raises, Typemap warns and raises the original error unnamed.

## Types

Every property needs a declared type: from `constrain type:`, or from your RBS signatures (below).
The default never supplies one — a default of `65` would otherwise reject `65.5` from the file.

| Type | Takes | Rejects |
|---|---|---|
| `Integer` | `70`; `70.0`, loaded as `70` | `"70"`, `70.5` |
| `Float` | `0.5`; `1`, loaded as `1.0` | `"0.5"` |
| `String` | `"a"` | `:a` |
| `bool` | `true`, `false` | `0`, `"yes"` |
| `T?` | `nil`, or a `T` | |
| `"short" \| "verbose"` | one of the literals | anything else; `1 \| 2` rejects `1.0` |
| `Array[T]` | an Array of `T` | |
| `Hash[String, T]` | a Hash of `T` | |
| `Ballooning` | a Hash, loaded into your class | |
| `Object` | plain data, passed through as the file holds it | a `Time`, a `Proc`, a key that is no String |

That is the whole list: any other type raises `Typemap::DefinitionError` when the mapper first
reads the class. `Object` is for a value whose meaning is someone else's, such as extra keys an
app sends to a server verbatim (`Hash[String, Object]`). Typemap checks only that it is plain
data — a String, Integer, Float, bool, Array or Hash, `nil` nested inside — on `load` and on
`dump`, and turns every Symbol key into a String.

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

A miss reads `must be 1 to 100, got 170`, `must be at least 1, got 0`. A `format:` miss prints the
pattern, which the person editing the file may not read; for a message in your own words, raise
it from `validate` instead.

## Problems in the class itself

A class Typemap cannot map raises `Typemap::DefinitionError` the first time the mapper reads it —
before it looks at any file, so a gap never waits for a user to set that key:

```
Config#name: no type: give it `constrain :name, type: "…"` (…)
Config#port: its default nil does not fit Integer
Config#port: format: /x/ limits only a String, not Integer
Config#ratio: unsupported type: Set[…]
Config: constrain names prot, not a property
Config#api_key: required: on String, which can never be missing; required: takes a String? defaulting to nil
Config: must build with a bare new, its default instance (wrong number of arguments (given 0, expected 1))
Config#initialize takes [[:keyrest, :opts]]; Typemap reads which keys are required only from `name:` and `name: default` keywords
```

Both `Typemap::DataError` and `Typemap::DefinitionError` are `Typemap::Error`s.

## Types from RBS signatures

A project that keeps `sig/*.rbs` can take its types from there instead of `constrain type:`:

```ruby
mapper = Typemap::Mapper.new(types: Typemap::Mapper::RBSTypes.new)
```

- A property's type is its reader's: `attr_reader` / `attr_accessor name: T`, or
  `def name: () -> T`, along the class's ancestors.
- `RBSTypes` finds the `sig/` directory beside the class's own source, walking up from its file;
  `RBSTypes.new(sig: ["sig/app.rbs"])` names the files instead.
- `constrain` still gives limits; a `constrain type:` for a property the signatures already type
  raises, since a type declared twice drifts.
- It needs the `rbs` gem — add `gem "rbs"` to your Gemfile. Typemap itself never depends on it.

[sord](https://github.com/AaronC81/sord) writes `sig/*.rbs` from YARD tags
(`sord gen sig/app.rbs --rbs`). A data class is typed with YARD's `@!attribute` directive, in the
`class X < Data.define(…)` form:

```ruby
# @!attribute [r] raise_at_percent
#   @return [Integer] grow the guest above this share of its memory
class Ballooning < Data.define(:raise_at_percent)
```

## Example: config and state files on Linux

Typemap does not find files; your app does. The simple Linux case, by the
[XDG Base Directory spec](https://specifications.freedesktop.org/basedir-spec/latest/) —
config read from the first file found, state written whole and renamed into place:

```ruby
require "json"
require "fileutils"
require "tomlrb"
require "typemap"

module Paths
  # An XDG variable, or its default when unset, empty or relative (the spec calls that invalid).
  def self.xdg(var, default) = ENV[var].to_s.start_with?("/") ? ENV[var] : File.join(Dir.home, default)

  def self.config_file(app)
    dirs = [xdg("XDG_CONFIG_HOME", ".config"), *ENV.fetch("XDG_CONFIG_DIRS", "/etc/xdg").split(":"), "/etc"]
    dirs.map { |dir| File.join(dir, app, "config.toml") }.find { |file| File.exist?(file) }
  end

  def self.state_file(app) = File.join(xdg("XDG_STATE_HOME", ".local/state"), app, "state.json")
end

MAPPER = Typemap::Mapper.new

def load_config
  file = Paths.config_file("myapp")
  MAPPER.load(Config, file ? Tomlrb.load_file(file) : {}, source: :toml)   # no file: the defaults, or `api_key: required`
rescue Typemap::DataError => e
  abort "#{file || "config.toml"}: #{e.message}"   # ~/.config/myapp/config.toml: port: expected Integer, got "80"; remove the quotes
end

def load_state
  file = Paths.state_file("myapp")
  File.exist?(file) ? MAPPER.load(State, JSON.load_file(file), source: :json, unknown: :ignore) : State.new
end

def save_state(state)
  file = Paths.state_file("myapp")
  FileUtils.mkdir_p(File.dirname(file))
  File.write("#{file}.tmp", JSON.pretty_generate(MAPPER.dump(state)))
  File.rename("#{file}.tmp", file)   # a crash mid-write never leaves a truncated file
end
```

That is as far as Typemap goes. Merging several config files, `config.d/` fragments, env-var
overrides, macOS and Windows locations are the app's call, or another gem's.

## Design

Why Typemap is shaped this way — and why not dry-struct, ActiveModel or `T::Struct` — is in
[design/decisions.md](design/decisions.md).

## License

MIT; see [LICENSE.txt](LICENSE.txt).
