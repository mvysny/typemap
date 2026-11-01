# Typemap — AGENTS.md

## What this is

Typemap maps a Hash onto a Ruby class you already wrote, and back, checking every value on the
way: `"70"` is never 70, and the data never names a class. Your class stays yours — a
`Data.define` or a plain class with `attr_accessor`s, typed by `constrain` lines or by your RBS
signatures. Reading and writing TOML, JSON or YAML, and finding the file, stay with the app;
Typemap owns the mapping and the checking, and does that one thing well.

## Promises

- **A Hash goes in, a checked object of your own class comes out.** Why Typemap exists: Ruby has no typed hash-object mapper, only Hash-based config loaders and schema libraries that bring their own class shapes.
- **One thing: the mapping.** Finding config files, file formats, env-var overrides and the platforms' conventions stay the app's; a README example shows the simple Linux case, nothing more.
- **Strict, never coerced.** A value of the wrong type raises with its path; nothing is converted quietly, save a whole number crossing exactly between Integer and Float (`D_whole_numbers`).
- **The file never names a class.** A rogue file cannot instantiate an arbitrary constant.
- **Your class stays yours.** Typemap defines no class and no accessor; a `Data` class or a plain accessor class works as written.
- **No runtime dependencies.** `rbs` is the app's, required only when its types come from `sig/`.

## Design docs

| File | Owns | Loaded |
|---|---|---|
| `README.md` | the pitch, install, the guide a user reads | — |
| `AGENTS.md` (this) | promises, invariants, the module map, conventions, commands | every turn |
| `design/architecture.md` | how the pieces compose — strategies, shapes, plans, the load and dump flows; normative | lazy |
| `design/decisions.md` | why this and not that — `D_` entries, FAQ-shaped | lazy |
| `design/research.md` | what Ruby, rbs and sorbet-runtime actually do — `R_` entries, each claim with provenance | lazy |
| `design/ideas/*.md` | one scratchpad per idea in flight; deleted once its nuggets land in a row above | lazy |
| doc comments | what one symbol does, why it is shaped so, why a constant has its value | at the symbol |

Every fact lives in exactly one of these; the others link to it.

## Invariants

- **No class is looked up from a string read out of the file.** Classes come from the caller and the class side only; a `const_get` on input is the gadget hole the promise closes.
- **Nothing under `lib/` requires `rbs` at load time.** Only `RBSTypes.new` does, so an app without signatures never needs the gem.
- **Every type, from either strategy, is built by `TypeBuilder`.** A strategy building its own lets the two subsets drift; a spec feeds both the same strings. See `D_types_declared`.
- **Loading never changes a default.** The base a load starts from may be a constant the app shares; a shape builds a new object instead.
- **A class is fully checked the first time the mapper reads it.** A check deferred to a key's first appearance hides the gap until a user sets that key; the flow is in architecture.md. The one exception: a data class with a required keyword has no default instance, so its defaults are checked on each load (`D_required_keys`).

## Module map

- `lib/typemap.rb` — the `Typemap` namespace and its `require_relative`s.
- `lib/typemap/` → `Typemap::` — the errors, `Constrain`, and `Mapper`.
- `lib/typemap/mapper/` → `Typemap::Mapper::` — the types, the two type strategies and their parser, the two shapes, limits, the per-class plan.
- `spec/` — rspec; `spec/fixtures/rbs_app/` is an app with its own `lib/` and `sig/` for `RBSTypes`.
- `design/` — the lazy docs above, the tripwire script and `design/ideas/`.

## Conventions

- **Ruby 3.3+, no Rails, no runtime dependencies.** Plain classes, `Data.define` for value objects; `require_relative` inside `lib/`, no Zeitwerk.
- **Tests: rspec-core with minitest-style asserts.** `describe` / `it`, but `assert_equal` / `refute`; no rspec-mocks.
- **`# frozen_string_literal: true`** atop every Ruby file; double-quoted strings, as rubocop enforces.
- **YARD on every public module, class and method**, concrete types in every tag, `@raise` for expected exceptions.
- **Errors are loud.** Unexpected input or state raises with the offending value and its path; never a silent default.
- **Composition over inheritance.** Shared mechanics become a concrete helper taking keyword parameters, not a base class.
- **Readable, not obfuscated.** The simplest implementation that does the job; no option or extension point ahead of a real use.
- **Pre-1.0: break APIs freely**, with a `**Breaking:**` CHANGELOG line carrying the migration.

## Commands

```bash
bundle exec rake                  # the gate: specs, rubocop, design tripwires — what CI runs (.github/workflows/ci.yml)
bundle exec rake check            # the same, spelled out
bundle exec rspec spec/path/to_spec.rb:LINE     # one test
bundle exec rubocop               # just the lint
design/verify_design_tripwires.sh # the doc-layer checks alone
```

## Skills this project follows

- **Doc comments carry the contract, the gotcha and a one-line why-not**; the argument goes to `design/` — the `writing-rdoc` skill.
- **An idea is one file under `design/ideas/`, deleted once its nuggets land in the Design docs table** — the `ideas-folder` skill.

## Maintenance of this file

Loaded every turn; cap 34 KB, a module's own `AGENTS.md` 10 KB. Over it, in this order:
delete what has no home — status, history, class lists, what the code already says; trim
each line to its fact plus one clause and send the explanation home — why →
`design/decisions.md`, how across symbols → `design/architecture.md`, how in one symbol →
its doc comment, what upstream does → `design/research.md`; only then a module's own
`AGENTS.md`, peripheral modules first, never the core. Never paraphrase a lazy entry into a
line here. `design/verify_design_tripwires.sh` checks the caps and the cites.
