# Research — the Ruby runtime and the gems Typemap reads types from: Ruby 3.3, rbs, sorbet-runtime

What the things we don't own actually do. About *them*, never us: a sentence starting "we chose"
is a `D_`. `## R_<slug> — <title>`, one claim per bullet, one provenance marker per claim —
**[docs]**, **[src]**, **[verified <date>, <version>]**, **[unverified]** (a hypothesis; a design
built on it says so). A claim is earned by its provenance, or by having cost real work to find
out. Checked against Ruby 3.3.8; a version-sensitive claim names the version it was seen on.
Cite by slug, `R_<slug>`, never by position; `grep '^## R_' design/research.md` is the index. The
first entry is the ruler: every later one trims to its length — which is how long this file
gets, so keep it short. When you have written an entry, re-read it against the one above and
cut the fat — a marker already says where a claim came from.

---

## R_t_struct_from_hash — sorbet-runtime: `T::Struct.from_hash` does not type-check

- `new` and the generated setters type-check: `raise_at_percent: "70"` on an `Integer` prop
  raises `TypeError: Can't set Ballooning.raise_at_percent to "70" … need a Integer`.
  **[verified 2026-11-01, sorbet-runtime 0.6.13506]**
- **`from_hash` assigns blindly**: `"70"` and `70.0` land in an `Integer` prop with no error.
  **[verified 2026-11-01, sorbet-runtime 0.6.13506]**
- A required prop (no `default:`) missing from the Hash raises `Tried to deserialize a required
  prop from a nil value`. **[verified 2026-11-01, sorbet-runtime 0.6.13506]**
- `from_hash!` raises `Unknown properties for Ballooning: ["rasie"]` on an unknown key;
  `from_hash` keeps it in `@_extra_props`. **[verified 2026-11-01, sorbet-runtime 0.6.13506]**
- `serialize` returns a String-keyed Hash. **[verified 2026-11-01, sorbet-runtime 0.6.13506]**

## R_rbs_parser — rbs: parsing signatures without the type environment

- `RBS::Parser.parse_signature(buffer)` parses a `.rbs` file on its own, returning
  `[buffer, directives, decls]`; `RBS::Parser.parse_type("Integer?")` parses one type.
  **[verified 2026-11-01, rbs 4.2.0]**
- tuile's 870 KB `sig/tuile.rbs` parses in about 58 ms. **[verified 2026-11-01, rbs 4.2.0]**
- `RBS::Test::TypeCheck#value(val, type)` checks a value, but its constructor wants a
  `DefinitionBuilder` — the whole environment, core signatures included. **[src]**
- The inline parser (RBS 4.0+, `#:` comments, marked experimental) sees
  `Ballooning = Data.define(…)` as a constant, not a class with attributes. **[src]**
- Whether rbs 3.4, bundled with Ruby 3.3, has the same `parse_signature`. **[unverified]**

## R_ruby_reflection — Ruby: method order, source locations, constants in blocks

- `public_instance_methods(false)` is in no declared order: a class declaring `b`, `a`, `c`
  lists `[:b, :b=, :a=, :c, :c=, :a]`. **[verified 2026-11-01, Ruby 3.3.8]**
- `instance_method(:x).source_location` of an `attr_accessor` is the line of the
  `attr_accessor` call; of a `Struct` member it is `nil`. **[verified 2026-11-01, Ruby 3.3.8]**
- A constant assigned inside `X = Data.define(:a) do … end` lands in the enclosing scope, not
  in `X`, with no warning even under `-W`; `class X < Data.define(:a)` keeps it in `X`.
  **[verified 2026-11-01, Ruby 3.3.8]**
- `JSON.load_file` calls `JSON.parse`, not `JSON.load`, so it never honours `json_class`.
  **[src, json 2.21.2]**
