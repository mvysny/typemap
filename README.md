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

> **Always pass `source:` when the Hash came from a file.** The messages above speak TOML because
> the load says `source: :toml`. Leave it out and the default, `:ruby`, words them for a Hash
> built in code — `got Integer 7`, `wrap it in an array` — which tells a user editing a file
> nothing about what to type. See [Naming the source](#naming-the-source).

## Loading and saving

```ruby
mapper = Typemap::Mapper.new

config = mapper.load(Config, Tomlrb.load_file(path), source: :toml)                # Tomlrb, JSON, YAML.safe_load: any Hash
state  = mapper.load(State, JSON.load_file(path), source: :json, unknown: :ignore)  # drop keys a newer version wrote
File.write(path, JSON.pretty_generate(mapper.dump(state)))            # String keys, nested objects as Hashes
```

- **A key present replaces the default; a key absent keeps it.** A nested Hash loads onto the
  default's nested object, so a file that sets one nested key keeps the other nested defaults.
- **An unknown key raises**, unless `unknown: :ignore`; a class may set its own policy
  ([Unknown keys](#unknown-keys)).
- **Keys may be Strings or Symbols** (`JSON.load_file(path, symbolize_names: true)` works).
- **`dump` writes properties in declaration order** and checks every value as `load` would — its
  type, its limits, a required key, the class's `validate` — so a bug that put a wrong value in
  an object is caught before it reaches the file.
- **Every object in the result is validated**, the ones the file left out included: a default
  nested object must pass its limits and `validate` too.
- **A data class comes back frozen all the way down.** Every Array, Hash and String it holds is
  frozen, defaults included, so `config.engines << "x"` raises `FrozenError`; mutate a copy,
  `config.engines.dup`. An accessor class's values stay mutable, being meant to change.
  Typemap freezes in place: a String from your Hash that a data object ends up holding is frozen
  there too, and so is a constant a default names (`engines: DEFAULT_ENGINES`). Your Arrays and
  Hashes never are; the result holds Typemap's own.
- **The first problem raises.** Typemap does not collect every error.
- **A mapper is safe to share between threads**; it works out each class once and remembers it.

### Naming the source

`load`'s `source:` names where the Hash came from — `:toml`, `:json`, `:yaml`, or `:ruby`, the
default, for a Hash built in code — and a load error words its fix in that syntax. The mistake is
the same in every source; only the advice changes:

| `source:` | `[server]` where an array belongs | `7` where a String belongs |
|---|---|---|
| `:ruby` (default) | `wrap it in an array` | `got Integer 7` |
| `:toml` | `write [[server]], not [server], or server = [{…}]` | `got 7; quote it to make it a string` |
| `:json` | `wrap it in [ ]` | `got 7; quote it to make it a string` |
| `:yaml` | `put "- " before it` | `got 7; quote it to make it a string` |

The default is `:ruby` because Typemap does not know where your Hash came from; when it came
from a file, say so, or the user who edits that file reads Ruby class names instead of the fix.

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

### `constrain` at a glance

`extend Typemap::Constrain` gives the class three macros. `constrain` declares a property's type
and limits, `ignore` leaves a public accessor out of the mapping, and `unknown` says what a load
does with a key the class has no property for ([Unknown keys](#unknown-keys)). None of them
defines anything on the class.

| Option | Takes | On | A miss reads |
|---|---|---|---|
| `type:` | an RBS type String: `"Integer"`, `"String?"`, `"Array[Server]"` ([Types](#types)) | every property, unless its type comes from [RBS](#types-from-rbs-signatures) | `expected Integer, got "70"` |
| `in:` | a Range: `1..100`, `(1..)` | a number | `must be 1 to 100, got 170` |
| `in:` | an Array of allowed values: `%w[short verbose]` | a number or a String | `must be one of "short", "verbose", got "x"` |
| `format:` | a Regexp | a String | `"ab" does not match /\A[a-z]\z/` |
| `not_blank:` | `true` | a String | `must not be blank` |
| `not_empty:` | `true` | an Array or a Hash | `must not be empty` |
| `unique:` | `true` | an Array | `tags[2]: duplicate of tags[0], both "a"` |
| `unique_by:` | a property, `:id`, or a function, `->(s) { s.url.downcase }` | an Array | `server[2] "local".id: duplicate of server[0], both "local"` |
| `required:` | `true` | an accessor class's `T?` defaulting to `nil` ([Required keys](#required-keys)) | `api_key: required` |

```ruby
constrain :raise_at_percent, :shrink_at_percent, type: "Integer"   # several properties at once
constrain :raise_at_percent, in: 1..100                             # a later call adds to the first
ignore :on_change                                                   # a listener, not a setting
```

- **Calls for one property merge**, and an option given twice for it raises `ArgumentError`, as
  does a misspelled option the moment the class body runs.
- **A limit the type cannot take** is a `Typemap::DefinitionError`, raised when the mapper first
  reads the class: `format:` on an Integer, `unique:` on a Hash, `unique_by: :idd` on a class
  with no `idd`.
- **A subclass inherits its superclass's constraints** and may add to them. Where both give the
  same option, the subclass's wins.
- **A `nil` passes every limit**, so on a `String?`, `not_blank: true` means "if given, not
  blank". The exception is a `nil` entry in an array, which `unique:` and `unique_by:` compare
  like any other value.

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

### Unknown keys

A key the class has no property for raises, unless `load` gets `unknown: :ignore`. That is all
or nothing for one file. A file shared by several programs often needs both: strict everywhere,
except for a table another program owns, which may gain keys tomorrow that this app doesn't
read. `unknown` sets the policy on that table's class:

```ruby
class UiTable < Data.define(:show_thinking)
  extend Typemap::Constrain

  constrain :show_thinking, type: "bool"
  unknown :ignore              # the TUI owns [ui]; a key it adds must not stop this app from starting

  def initialize(show_thinking: true) = super
end
```

- **The class's policy wins over `load`'s, both ways.** `unknown` takes `load`'s two values,
  `:ignore` and `:raise`; a class that gives neither follows `load`'s `unknown:`.
- **It covers the class's own keys, wherever the class appears**: a table, or each entry of an
  array. A class nested in it keeps its own policy, or `load`'s. A subclass inherits it.
- **An ignored key is dropped silently.** Typemap does not report which keys it dropped.
- **`unknown :raise` inside an `unknown: :ignore` load** brings back the failure `:ignore` avoids:
  a newer version of the app that adds a key to that class's table breaks this one.
- **A value other than `:raise` or `:ignore`**, or `unknown` given twice in one class, raises
  `ArgumentError` the moment the class body runs.

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
- **The name is the result's `to_s`, stripped**: an Integer id names the entry too, and
  `" grok "` prints as `"grok"`. **No name, just the index**, when that comes out empty — `nil`,
  `""`, `"  "`. When `entry_name` raises, Typemap warns and raises the original error unnamed.

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
constrain :url, type: "String", not_blank: true             # not "", not "  "
constrain :command, type: "Array[String]", not_empty: true  # at least one element; a Hash too
constrain :tags, type: "Array[String]", unique: true        # no two entries equal
constrain :server, type: "Array[Server]", unique_by: :id    # no two entries share an id
constrain :mirror, type: "Array[Mirror]", unique_by: ->(m) { m.url.downcase }
```

`unique_by:` takes a property of the entries' class, or a function of the entry for anything
more. A duplicate is reported at the second entry, which is named like any entry error, and
the detail gives the first entry's index:

```
server[2] "local".id: duplicate of server[0], both "local"
```

`unique: true` on entries of your own class compares them with `eql?`. A data class has value
equality; on a class that only compares by identity, `unique: true` raises. Two `nil`s are
duplicates, as `nil == nil` is in Ruby.

Parenthesize an endless range at the end of a line: `in: 1..` followed by a newline makes Ruby
read the next line as the range's end.

A miss reads `must be 1 to 100, got 170`, `must be at least 1, got 0`, `must not be blank`. A
`format:` miss prints the pattern, which the person editing the file may not read; for a message
in your own words, raise it from `validate` instead. Every option, in one table:
[`constrain` at a glance](#constrain-at-a-glance).

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
