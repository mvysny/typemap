# Deep-frozen results: `load(..., freeze: true)`

A data class is frozen, but only one level down: the Array and Hash values inside it stay
mutable. A config is meant to be immutable, so pikuri's classes each freeze their containers in
an `initialize` override that exists for nothing else:

```ruby
Search = Data.define(:brave_key, :exa_key, :engines) do
  def initialize(brave_key: nil, exa_key: nil, engines: nil)
    super(brave_key: brave_key, exa_key: exa_key, engines: engines&.freeze)
  end
end
```

And where nobody wrote one, nothing stops it: `config.llm[0].params["temperature"] = 2` changes
the loaded `LlmTable` in place, `Object`'s nested Hashes included.

**This reverses `D_object_plain_data`'s "Typemap freezes no container"**, which was said of
`Object` (why not deep-freeze what passes through it) without an argument against freezing as
such, as far as the entry shows. It needs revisiting on the record.

## The sketch

```ruby
config = mapper.load(Root, hash, source: :toml, freeze: true)
config.llm[0].params.frozen?      # => true, and every Array, Hash and String inside it
```

- **Opt-in per `load`**, not per class: a state file loaded into accessor classes is meant to be
  mutated, and the app knows which file is which.
- **Everything Typemap built**: each Array, Hash and String it loaded, `Object` values
  recursively. A data class is frozen already; an accessor class gets `freeze` too, so a setter
  raises `FrozenError`.
- **Defaults the file left out are frozen as well** — they are part of the result — which means
  the default instance's own containers. Typemap would freeze a copy, never the class's default,
  or a later `new` would hand out frozen defaults.

## Open questions

- `Q_default_on` — opt-in, or on by default for a data class (already frozen at the top, so a
  deep freeze is only finishing the job) and off for an accessor class (mutable by design)? The
  default-on reading needs no new keyword, but changes what existing apps get.
- `Q_strings` — freeze Strings too? Tomlrb's are already frozen-ish depending on version;
  `# frozen_string_literal` covers only literals. Leaving them out makes `freeze: true` a lie.
- `Q_ractor` — `Ractor.make_shareable(result)` does exactly the deep freeze, Strings included.
  Use it, or walk the tree ourselves (it would also freeze a `Proc` in an `ignore`d property,
  which is the app's, not ours)?
