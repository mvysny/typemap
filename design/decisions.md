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
`T::Array[String]`) — a second type language beside the RBS strings Typemap speaks
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
(`R_rbs_parser`), so Typemap checks a small subset itself — `Integer`, `Float`, `String`, `bool`,
`T?`, `Array[T]`, `Hash[String, T]`, literal unions, mappable classes, `Object`
(`D_object_plain_data`).

## D_constrain_macro — Why a `constrain` macro that records metadata, rather than a constant or an accessor DSL?

`extend Typemap::Constrain` gives the class `constrain :name, type: …, in: …, format: …` and
`ignore :name`; each records metadata and defines nothing. Why not a `CONSTRAINTS` constant the
mapper reads: a map of maps has no type safety, an unknown option (`in_:`) surfaces late, and a
constant written inside `X = Data.define(…) do … end` silently lands outside `X`
(`R_ruby_reflection`). Why not a macro that defines the accessor, as Rails' `attribute` or
sorbet's `prop` do: on a frozen `Data` instance a generated writer raises `FrozenError`; once the
macro owns the property, `default:` and a generated `initialize` follow and the mapper has
imposed a class form (`D_own_mapper`); and a metaprogrammed accessor is invisible to YARD, RBS
and the IDE. Why the name: `constrain` adds limits to a property the class already declares, a
type being the strictest; `validate` is the class's own cross-property hook. The cost: the class
references Typemap.

## D_accessor_properties — Why are an accessor class's properties its public reader + writer pairs?

A data class names its properties (`members`); a mutable class does not, so Typemap reads the
methods, as a Java bean's introspection does and as ActiveModel's `assign_attributes` assumes: a
public reader with a matching public writer is a property, hand-written or `attr_accessor`,
inherited or mixed in. Why not the ivars a bare `new` sets: a cache, a mutex or a path set in
`initialize` would become settings. Why not a list in `constrain`: under `RBSTypes` every
property would need a line it otherwise does not. An accessor that is not a setting goes
`private`, or stays public under `ignore`; left public, it has no declared type and raises when
Typemap first reads the class. The class must build with a bare `new`, which is its default
instance, so a required key is spelled `required:` (`D_required_keys`). An immutable plain class
has no writers and so no properties: immutable means `Data`.

## D_required_keys — Why is a data class's required key a keyword without a default, and an accessor class's `required:`?

A key is required when it has no default, whatever its type: `Data.define(:a)` won't build
without `a`, nor will Kotlin's `val a: String?`. A data class can say "no default", so Typemap
reads `initialize` — `name:` required, `name: x` not — and the app gets a non-nil `String`;
`required:` there would be a second spelling, and raises. A bare `new` sets every accessor, so
`required: true` marks a `T?` whose `nil` default must not survive a load. Why not read it off
the type: a `String` defaulting to `"x"` is optional. Why not a `String` defaulting to `nil` as
"required": a forgotten default would quietly become a required key, and the signature would lie
about the bare instance. Why not `required:` on by default: the partial config file is the main
use, and `RBSTypes` would need a line per optional property. Why no `not_nil:`: refusing a JSON
`null` that type and default allow has no known use. The cost: a data class with a required
keyword has no default instance, so its other defaults are checked on each load.

## D_validation_phase — Why do `load` and `dump` validate the whole result, after the conversion?

A check per key present misses an object the file never mentions: a missing `[llm]` table keeps
the default's nested object, its `required:` `api_key` still `nil`. So validation walks the
finished tree, whatever the file held — per object, nested objects first, the limits, then
`required:`, then `validate`, which may so assume the limits passed. Why on `dump` too: an app
that changes its state in code could otherwise write a file the next `load` rejects. Why types
stay in the conversion: there is nothing to build from `"70"` for an Integer, and the limits
assume the type — `in: 1..100` on a String is nonsense. Why not call `validate` on the default
when the class is first read: a class with a required key can't pass it on its `nil` default, and
a `validate` written for loaded objects may crash on `nil`; the default meets it on every load
anyway. Why the first problem only: nothing has asked for every violation at once.

## D_whole_numbers — Why does a Float take `5` and an Integer `5.0`, when nothing else converts?

Strictness serves the person writing the file, and stops where it would surprise them: a Float
percent takes `70.5`, and must take `100` too. The formats blur the two anyway — JSON has one
number type; JavaScript writes `5.0` as `5`, Python's `json` writes `float(5)` as `5.0`. The crossing
is exact or it does not happen: `5.1` is no Integer, nor is NaN, nor `2**53 + 1` a Float, which
would round. The property then holds its declared class — `5.0`, never `5` — so `ratio / 2`
does not divide as Integers. Why only on load: a default and a dumped value are the app's own
Ruby, where `1` for a Float is a slip the class should fix. Why not a literal union: `1 | 2 | 3`
reads as a pick from a list, where `3.0` is odd rather than a writer's habit — until a real use
says otherwise. Why not `"70"`: a String is no number;
parsing it is the coercion **Strict, never coerced** rules out.

## D_functions_over_rules — Why a function the app writes, rather than one more declarative option?

A declaration states what a value may be — a type, a range, a format — and Typemap checks it.
Once it must say how to get there — which class a tagged table becomes, how `"8 GiB"` becomes a
`Size` — it starts a rule language, and every rule language is outgrown: serde's enum tagging grew
four representations plus `rename`, `alias` and `flatten`, and apps still hand-write
`Deserialize`. So the app gets a hook in plain Ruby, as it already does for cross-property checks
with `validate`. Why it stays safe: the app's code picks the class, so **The file never names a
class** holds. Why the declaration stays beside the hook: the declared type bounds what the
function may return and is checked when the class is first read, so a hook cannot smuggle in an
unchecked object. The cost: strictness inside the hook is the app's; Typemap checks only what
comes out. A hook is still an extension point, added with its first real use.

## D_object_plain_data — Why does `Object` take only plain data with String keys, not whatever the parser produced?

`Object` passes through a value whose meaning is someone else's — keys sent to a server verbatim,
another program's table. It is a type, not a hook: it says what the value may be
(`D_functions_over_rules`). Plain data is what Typemap's other types load — String, Integer,
Float, bool, Array, Hash, `nil` nested inside — so a new type such as `Time` would widen it. Why
not whatever the parser gave: `load` and `dump` would part — a Tomlrb `LocalDate` would load,
then `dump` must reject it or name a gem's class — and `JSON.generate` writes a `Proc` as its
`to_s`. Why String keys only: converting `1` to `"1"` is coercion; passing `1` through makes
`dump` format-dependent, and JSON reloads `{1 => "a"}` as `{"1" => "a"}`; it also catches YAML
1.1's boolean keys, `on:` and `yes:` both read as `true`, one value lost. Why `nil` only as
`Object?`: as for every type. Why not `untyped` too: sord writes it where it gave up. Why not
deep-freeze: Typemap freezes no container. The cost: a TOML date-time inside raises.

## D_entry_name — Why does an array entry get its name from a class method taking a Hash?

In `server[1].url: required` the reader counts `[[server]]` headers to find the entry; the
entry's own name, `server[1] "grok".url`, finds it at a glance. Why not `identified_by :id`: a
name may be two keys joined or a fallback, and a function says that (`D_functions_over_rules`).
Why not `to_s`: the app's logs or UI already own it, and it needs an instance, which a
conversion error never has — hence a class method. Why `raw` is always plain data with String
keys, the file's Hash on load and the entry dumped afterwards: a function given sometimes a
Hash and sometimes the object is a bug waiting to happen. Why the index stays: two entries may
share a name; uniqueness is the app's check. Why only arrays: a Hash entry's path already
carries its key. Why the name is printed whole: it shows only when a load fails. Why
`entry_name` unprefixed: a mapped class is a data carrier, and `constrain` and `validate` carry
no prefix either. The cost: a raising `entry_name` only warns, so the original error survives.

## D_source_wording — Why does a load error word its fix for the `source:` the app names, `[[server]]` for TOML?

A classic mistake leaves the same trace in the Hash whatever the format, so the types detect it
there; only the spelling of the fix depends on the format, and a neutral one served none:
`wrap it in an array` is far from TOML's `[[server]]`, and `quote it` means nothing for a Hash
built in Ruby. Why the format's syntax needs no parser knowledge: Tomlrb's `Time` and Psych's
`no` → `false` decide which values arrive, which is detection; `[[x]]` is the TOML spec. Why a
TOML header holds inside arrays: a header names no index, `llm[0].servers` → `[[llm.servers]]`,
written where the path already points. Why `:ruby` is the default: a hint that assumes a text
file shows only when the app says there is one, so a forgotten `source:` gives fewer hints,
never wrong ones; and a Ruby programmer reads `got Integer 70` best. Why a `load` keyword and not
a `Mapper.new` one: the source belongs to the data, and one mapper may load TOML and JSON; dump
errors are worded for Ruby, their reader being the programmer. Why one private module per source
rather than a `case` at each hint site: each format's voice sits in one place. Why the TOML array
hints name the inline `server = [{…}]` too: Typemap can't tell which spelling the file used, and
longer beats wrong. Why a misplaced key is looked up in the enclosing objects only: that chain has
it or not, while a search across the tree guesses. The costs: TOML inline tables and YAML flow
style are told about headers and `- `; a hint shows the parser's value, `got 1.1` where the file
says `1.10`.
