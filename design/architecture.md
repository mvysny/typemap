# Architecture

How the pieces compose — what no single symbol can say and what would be expensive to overturn:
wiring and dependency direction, the lifecycle / threading / data-flow story, the flows a newcomer
needs, where to start reading. **Normative: the code conforms.** Change this file first, then the
code. Not here: why (`decisions.md` — cite the `D_`), what upstream does (`research.md` — cite the
`R_`), one symbol's behaviour (its doc comment), the module map (`AGENTS.md`). Only the sections
with content; the worked example in each is the ruler. Cap 12 KB — over it, research or
doc-comment content has crept in.

---

## Wiring

- `Typemap::Mapper` is the one entry point; it holds a **type strategy** (`BasicTypes` or `RBSTypes`, chosen by the app, never detected) and a cache of one `Plan` per class.
- The class side talks to the mapper only through `Typemap::Constrain`, which records metadata on the class and defines nothing (`D_constrain_macro`); the mapper never touches a class's ivars.
- Both strategies turn a type into the same syntax tree — `TypeParser` for `constrain` strings, the `rbs` gem's AST for `sig/` — and hand it to `TypeBuilder`, so they accept exactly the same subset (`D_types_declared`).
- A **shape** — `DataShape` or `AccessorShape`, picked by `klass < Data` — lists, reads and builds a class's properties, and says which keys are required; the mapper never branches on the kind of class elsewhere (`D_accessor_properties`, `D_required_keys`).
- `load` and `dump` are each a **conversion**, Hash ↔ objects with the strict type check, then a **validation** that walks the finished tree and changes nothing (`D_validation_phase`).
- Each `Type` checks, loads and dumps its own values, and yields the app's objects inside one for validation; `ClassRef` is the one that recurses, back into the mapper.
- An error path names an array entry in one place, `ArrayOf`: it rescues the `DataError` from entry `i` on load, dump and validation alike, and re-raises it with the class's `entry_name` after `[i]` — so nothing is computed until an error passes (`D_entry_name`).
- A load error's hint is worked out where the mismatch is raised, only once the value has failed: a `Type#load` for a quote, an `Array[T]` test-loading the lone value as a `T`, `Session#load_object` test-loading an array's one entry, and `Session#reject_unknown` looking a key up in the enclosing objects' plans (`D_format_neutral_hints`). A test-load is a real load, so it never changes a default either; its result is dropped.

## Flows

**Reading a class** (once per class per mapper, under the mapper's lock):

1. `Mapper#plan_for` → `Plan.build`: the shape, the property names minus `ignore`d ones, the required keywords a data class's `initialize` names, and — when there are none — a bare `klass.new` as the default instance.
2. Per property, the strategy's `type_for` gives a `Type`; `Limits#check_against` checks the `constrain` limits fit it; `required:` must sit on a type that takes `nil`. Then each default must pass its type and limits, and a `required:` one must be `nil`.
3. Any failure is a `DefinitionError` naming `Klass#property`, before a file is looked at. A data class with a required keyword has no default instance, so its defaults are checked on each load's base instead.
4. The plan is cached, then every class nested in it is planned the same way — so a class nested in itself terminates.

**Loading a file** (`Mapper#load`) — conversion:

1. A `Session` carries the mapper, the `unknown:` policy and the enclosing objects' plans down the tree; each object loads its properties with a copy that adds its own.
2. `Session#load_object` gets the plan, normalises the keys to Strings, rejects unknown ones, and takes the base: the parent's nested object, else a fresh one — a bare `klass.new`, or, for a data class with required keywords, `klass.new` given just those, loaded first from the file and each missing one a `DataError`.
3. Per other key present: `Type#load` checks it strictly — a `ClassRef` recurses with the base's nested object as the nested base.
4. The shape builds the object from the base plus the loaded values, never changing the base.

Then validation, over the whole result, so an object the file left out is checked too: `Mapper#validate_object` reaches every object through `Type#each_object` and checks the nested ones first; per object the `in:` / `format:` limits, a `required:` still `nil`, then the object's `validate`, its message gaining the object's path.

**Dumping** — conversion walks the same plan through the getters, each `Type#dump` checking the type as it goes; then the same validation, so a Hash comes back only if a later `load` would take it.

## Where to start reading

`lib/typemap/mapper.rb` — `load`, `dump`, `validate_object`, `plan_for` and the `Session`; then `mapper/plan.rb` for every rule checked when a class is first read.
