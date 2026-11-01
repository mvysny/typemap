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
- A **shape** — `DataShape` or `AccessorShape`, picked by `klass < Data` — lists, reads and builds a class's properties; the mapper never branches on the kind of class elsewhere (`D_accessor_properties`).
- Each `Type` checks, loads and dumps its own values; `ClassRef` is the one that recurses, back into the mapper.

## Flows

**Reading a class** (once per class per mapper, under the mapper's lock):

1. `Mapper#plan_for` → `Plan.build`: the shape, a bare `klass.new` as the default instance, the property names minus `ignore`d ones.
2. Per property, the strategy's `type_for` gives a `Type`; `Limits#check_against` checks the `constrain` limits fit it; the default must pass both.
3. Any failure is a `DefinitionError` naming `Klass#property`, before a file is looked at.
4. The plan is cached, then every class nested in it is planned the same way — so a class nested in itself terminates.

**Loading a file** (`Mapper#load`):

1. A `Session` carries the mapper and the `unknown:` policy down the tree.
2. `Session#load_object` gets the plan, normalises the keys to Strings, rejects unknown ones, and builds a fresh default (`klass.new`) as the base.
3. Per key present: `Type#load` checks it strictly — a `ClassRef` recurses with the base's nested object as the nested base — then `Limits#check`.
4. The shape builds the object from the base plus the loaded values, never changing the base.
5. `validate` runs if the object has it, so nested objects validate first; its message gains the object's path.

**Dumping** walks the same plan through the getters, each `Type#dump` checking as it goes.

## Where to start reading

`lib/typemap/mapper.rb` — `load`, `dump`, `plan_for` and the `Session`; then `mapper/plan.rb` for every rule checked when a class is first read.
