# JSON Schema as a third type strategy

Not the first thing built: Typemap has `BasicTypes` (`constrain`) and `RBSTypes` (`sig/`). A JSON Schema
may come later as another way to give the same types and limits, through **json_schemer**.

## The shape of it

A JSON Schema file beside the classes, checked with json_schemer before the mapper runs — a
third type strategy beside `BasicTypes` and `RBSTypes`. The classes stay as they are, with their
YARD and `validate`. The mapper still turns the Hash into objects, nested ones included; it only
stops checking types, because the schema has already checked them.

JSON Schema has no notion of a Ruby class, so the schema must name the class of each nested
object: a custom keyword (`"x-ruby-class": "Ballooning"`) or a convention mapping
`$defs/Ballooning` to `Ballooning`. The schema ships with the app, not with the user's file, so
this keeps the promise that the file never names a class.

Spiked with json_schemer 2.5.0 (2026-11-01):

```
"70"                    → value at `/ballooning/raise_at_percent` is not an integer
170                     → number at `/ballooning/raise_at_percent` is greater than: 100
mode: "x"               → value at `/ballooning/mode` is not one of: ["short", "verbose"]
rasie: 1                → object property at `/ballooning/rasie` is a disallowed additional property
70.0                    → passes: JSON Schema's `integer` is any number with no fraction (draft-06 on)
```

## For

- **Every error at once.** The mapper raises on the first; a schema reports them all, each with
  its path.
- **Standard keywords** for types, ranges, enums, nullable properties, arrays and unknown keys.
- **Editor support in TOML**: Taplo and Tombi validate a TOML file against a JSON Schema named
  in a top `#:schema ./app.schema.json` comment, or found through SchemaStore — completion and
  checking while the user types.

## Against

- **Every key listed twice**, once in the class and once in the schema; a spec comparing the
  class's properties with the schema's `properties` catches drift, but cannot stop it.
- **Verbose by hand** for what one `constrain` line says.
- **`70.0` passes as an Integer**, against strict types; it needs a check of our own.
- **Four runtime gems**: hana, regexp_parser, simpleidn and bigdecimal — fine as the app's
  optional dependency, as `rbs` is, never Typemap's.
- Cross-property rules and custom types (`"8 GiB"`) stay in `validate` and the mapper either way.

## TOML

JSON Schema checks the parsed data model, not the syntax, so a `Tomlrb` Hash is checked like a
JSON one. TOML's date and time values have no JSON type. A TOML-native schema exists only as a
proposal: [toml-schema.org](https://github.com/brunoborges/toml-schema), the schema itself
written in TOML; toml-lang has not adopted it (toml-lang#116, #792), and no Ruby implementation
is known.

## Open questions

- `Q_schema_from_class` — generate the schema from the class (`constrain` or `sig/`) instead of
  writing it by hand? That removes the second list of keys, keeps editor completion, and gives
  up only "every error at once", which the mapper could then get from json_schemer as a
  pre-check.
- `Q_toml_time` — what json_schemer does with a Ruby `Time` from TOML. Unverified.
- `Q_who_asks` — which app wants it first; until one does, it stays here.
