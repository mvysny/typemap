# Decisions

Why this project is the way it is and not otherwise — FAQ-shaped: each entry is a question and
its current answer. Rewrite the answer when it changes; delete the entry when nobody asks any
more. An entry is earned by what it would cost to reverse — half the code base — or by research
the next person would otherwise redo (cited as its `R_`). Not an entry: windows → panels
"because that's the trend", this red over that red, `get_foo` over `is_foo?`, the testing library,
the CI host, a version bump — a comment at the site of the choice, or nothing; nothing about
`design/` itself. Cite by slug, `D_<slug>`, never by position; `grep '^## D_' design/decisions.md`
is the index. The first entry is the ruler: every later one trims to its length — which is how
long this file gets, so keep it short. When you have written an entry, re-read it against the one
above, open the doc comments it touches and cut what they already say, then cut the fat.

---

## D_own_mapper — Why write our own mapper rather than build on dry-struct, ActiveModel or shale?

Ruby has no counterpart of pydantic, serde or Jackson: a mapper that fills a class the app
already wrote — a `Data` class or a plain accessor class — from a Hash, with strict types. Each
candidate imposes what a promise rules out. Why not dry-struct (1.8.1): it is its own class form,
`< Dry::Struct` with dry-types attributes, against **Your class stays yours**, and it brings
dry-types, dry-core, dry-logic, dry-inflector, ice_nine and bigdecimal, against **No runtime
dependencies**; dry-validation adds dry-schema, dry-initializer and dry-configurable and spells
every key twice, in the contract and in the value object. Why not ActiveModel's `attribute`: it
casts leniently — `"70"` becomes 70, against **Strict, never coerced** — and pulls in
activesupport. Why not shale (1.2.2): a typed mapper that reads TOML, but again its own class
form, 447k downloads in all and quiet since 2025-03. Why not `T::Struct`: `D_no_t_struct`. The
cost we carry: the type subset, its parser and the RBS reader are ours to maintain.

## D_no_t_struct — Why neither build on T::Struct nor map onto it?

sorbet-runtime's `T::Struct` is the closest existing thing: typed props, defaults, per-prop
mutability, nested structs, `from_hash` and `serialize`. Why not build on it: `from_hash` — the
one path a config file takes — assigns blindly, so `"70"` lands in an `Integer` prop though `new`
and the setters raise (`R_t_struct_from_hash`), against **Strict, never coerced**; it is a class
form, `< T::Struct`, against **Your class stays yours**; and it carries Stripe's ODM history
(`dont_store`, `redaction`). Why not map a user's `T::Struct` as one more shape: its props and its
type-checking `new` would make that easy, but its types are Sorbet's (`T.nilable(Integer)`,
`T::Array[String]`) — a second type language beside the RBS strings Confect speaks
(`D_types_declared`) — and a Sorbet user already has `from_hash` and `serialize`. It comes back
only with a real user asking for it.

## D_types_declared — Why must a property's type be declared, never read off its default?

A type comes from `constrain type:` or from the project's `sig/*.rbs`, through a type strategy
the app picks — `BasicTypes`, the default, or `RBSTypes`, which needs the `rbs` gem — and from
exactly one of the two: a duplicate drifts. Why not the default's class: with strict types the
guess has consequences — a default of `65` would reject `65.5` — and `nil`, `[]` and `{}` have no
type to read. Why not inline RBS (`#:` comments): experimental, and blind to a `Data.define`
class (`R_rbs_parser`); a `sig/` file is the standard, and sord writes one from YARD. Why RBS
strings even in `constrain`, not Ruby classes: `type: Integer` leaves open whether nil is
allowed, where `'Integer'` and `'Integer?'` say it, and a `T.nilable`-style wrapper would be a
second type language. Why not RBS's own checker: it needs the whole type environment
(`R_rbs_parser`), so Confect checks a small subset itself — `Integer`, `Float`, `String`, `bool`,
`T?`, `Array[T]`, `Hash[String, T]`, literal unions, mappable classes.

## D_constrain_macro — Why a `constrain` macro that records metadata, rather than a constant or an accessor DSL?

`extend Confect::Constrain` gives the class `constrain :name, type: …, in: …, format: …` and
`ignore :name`; each records metadata and defines nothing. Why not a `CONSTRAINTS` constant the
mapper reads: a map of maps has no type safety, an unknown option (`in_:`) surfaces late, and a
constant written inside `X = Data.define(…) do … end` silently lands outside `X`
(`R_ruby_reflection`). Why not a macro that defines the accessor, as Rails' `attribute` or
sorbet's `prop` do: on a frozen `Data` instance a generated writer raises `FrozenError`; once the
macro owns the property, `default:` and a generated `initialize` follow and the mapper has
imposed a class form (`D_own_mapper`); and a metaprogrammed accessor is invisible to YARD, RBS
and the IDE. Why the name: `constrain` adds limits to a property the class already declares, a
type being the strictest; `validate` is the class's own cross-property hook. The cost: the class
references Confect.

## D_accessor_properties — Why are an accessor class's properties its public reader + writer pairs?

A data class names its properties (`members`); a mutable class does not, so Confect reads the
methods, as a Java bean's introspection does and as ActiveModel's `assign_attributes` assumes: a
public reader with a matching public writer is a property, hand-written or `attr_accessor`,
inherited or mixed in. Why not the ivars a bare `new` sets: a cache, a mutex or a path set in
`initialize` would become settings. Why not a list in `constrain`: under `RBSTypes` every
property would need a line it otherwise does not. An accessor that is not a setting goes
`private`, or stays public under `ignore`; left public, it has no declared type and raises when
Confect first reads the class. The class must build with a bare `new`, which is its default
instance, so there are no required keys yet. An immutable plain class has no writers and so no
properties: immutable means `Data`.
