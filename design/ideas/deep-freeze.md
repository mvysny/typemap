# Frozen containers in a data class

A data class is frozen, but only one level down: the Array, Hash and String values inside it stay
mutable. `config.engines << "x"` and `config.llm[0].params["temperature"] = 2` both change a
loaded config in place. A config is meant to be immutable, so pikuri's classes each freeze their
containers in an `initialize` override that exists for nothing else:

```ruby
Search = Data.define(:brave_key, :exa_key, :engines) do
  def initialize(brave_key: nil, exa_key: nil, engines: nil)
    super(brave_key: brave_key, exa_key: exa_key, engines: engines&.freeze)
  end
end
```

**This reverses `D_object_plain_data`'s "Typemap freezes no container"**, which was said of
`Object` (why not deep-freeze what passes through it) with no argument against freezing as such.
The new `D_` entry replaces that clause.

## The rule

**After the load, every Array, Hash and String a data object holds is frozen in place, wherever
it came from.**

- **A data class's properties get frozen containers.** The instance is frozen already; this
  finishes the job. Nested Arrays and Hashes are frozen too, and each String in them. Integer,
  Float, `true`, `false` and `nil` are immutable anyway, and a data instance is frozen.
- **An accessor class's properties stay mutable.** A state file loaded into `attr_accessor`s is
  meant to be changed; `state.items << x` and `state.name << "x"` keep working.
- **Nesting follows the owner.** Data → `Array<Server>` freezes the Array; if `Server` is an
  accessor class, its own `tags` stays mutable, as the class is mutable by design.
- **Defaults too.** A key the file leaves out must be as frozen as one it sets, or
  `config.engines << x` passes in development on defaults and raises `FrozenError` only once a
  user sets the key — the gap the "fully checked the first time" invariant rules out.
- **No keyword.** Whether the result is mutable follows from the class the app wrote, not from
  each `load` call.
- **Not tied to `source:`.** `source:` only words errors; a `:ruby` test and a `:toml` production
  load must give equally mutable results.

## The sketch: one pass, after the load

Loading stays as it is. Once `load_object` has built the whole object, and before `validate` (so
it sees what the app gets), one pass walks it guided by the plans, the way `dump` does — a
`freeze` per type beside `load` and `dump`:

- **In a data object**, each property's Array, Hash and String is frozen in place, then the pass
  descends into its items by their element type. It descends even into an Array already frozen:
  `DEFAULT = ["a", "b"].freeze` in a file without `# frozen_string_literal` holds unfrozen
  Strings. An `Object` value freezes its whole plain-data tree.
- **In an accessor object**, nothing is frozen, but the pass still descends through its
  properties to reach a data object nested below.
- **Only typed properties are walked.** An `ignore`d property is never reached, so an app's
  Logger, IO or Proc stays untouched.

In place, so a data instance never needs rebuilding: a nested default object (`Root.new`'s
`search: Search.new` with `engines: []`) or a data instance inside a default Array
(`servers: [Server.new(tags: [])]`) is frozen where it stands. Rebuilding through `with` would
rerun the class's `initialize` (Ruby 3.3's `with` does, checked), and copying a Hash with `to_h`
would drop its `default_proc`; `freeze` keeps it.

## What else gets frozen

- **The input's Arrays and Hashes: never.** Typemap builds its own while checking — `Array<T>`
  loads through `map`, `Hash{String => T}` through `to_h`, `Object` through `copy` (`type.rb`) —
  so the result never holds the caller's.
- **The input's Strings: those a data object ends up holding.** The String type passes the
  caller's String through, so the pass freezes it in the caller's Hash too. Parsed TOML, JSON or
  YAML is thrown away after the load; a Ruby Hash in a new app holds `# frozen_string_literal`
  Strings, frozen already. It also ends today's aliasing: a loaded String is the caller's object,
  so editing it in the Hash changed the config. Why not a frozen copy (`-s`) on load: two more
  load paths to change, and it would freeze an accessor class's loaded Strings as well.
- **A default's objects.** `fresh_base` builds the base with `klass.new` on every load, so a
  literal default is a fresh object each time. A default naming the app's constant
  (`engines: DEFAULT_ENGINES`) gets that constant frozen: its value is unchanged, and rubocop asks
  a constant to be frozen anyway, but the invariant "Loading never changes a default" becomes
  "Loading never changes a default's value; it may freeze it".

## Why not the alternatives

- **`Ractor.make_shareable`** deep-freezes in one line but walks everything reachable: an
  `ignore`d property holding `$stderr` froze the global `$stderr` without a word, and one holding
  a Proc raised `Ractor::IsolationError` (both checked on 3.3.8).
- **Defaults hand-frozen by the app**: documented only, a forgotten `.freeze` fails silently;
  checked at the class's first read, every `[]` default needs `.freeze`, and on Ruby 3.4 a
  chilled String literal reports `frozen? == false`, so every String default would be flagged.
- **Frozen copies built in `DataShape.build`**: miss a nested default object, which passes
  through as is; reaching it means rebuilding data instances, rerunning `initialize`.

## Costs

- **Breaking** for an app that mutates an Array, Hash or String of a data-class config: a
  CHANGELOG `**Breaking:**` line, its migration "mutate a copy: `config.engines.dup`".
- A String the caller passed in, held by a data object, is frozen in the caller's Hash too.
- A default naming a shared constant freezes that constant.

## Graduation

- A `D_` entry: why a frozen owner freezes its containers, why in place after the load, why the
  input's Strings are frozen and its containers never held, why no keyword and not `source:`, why
  not the alternatives above; `D_object_plain_data`'s clause points at it.
- AGENTS.md: the reworded "Loading never changes a default" invariant.
- `design/architecture.md`: the freezing pass in the load flow.
- README: a data class's Arrays, Hashes and Strings come back frozen, the caller's Strings
  included; an accessor class's do not.
- CHANGELOG: the `**Breaking:**` line.
- pikuri: drop the `initialize` overrides that only freeze.
