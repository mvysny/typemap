# Error messages written for the person editing the file

A `DataError` is read by whoever wrote the file, someone who knows its keys but not the app's
classes or Ruby's syntax. virtui's config spike (2026-11-01, its `design/ideas/config-file.md`)
loaded a `Config` data class holding a nested `Config::Ballooning`, typed from RBS, and these
are the messages Typemap gave:

| File | Message | Verdict |
|---|---|---|
| `raise_at_percent = "70"` | `ballooning.raise_at_percent: expected Integer, got "70"` | good |
| `raise_at_percent = 70.5` | `ballooning.raise_at_percent: expected Integer, got 70.5` | good |
| `raise_at_percent = 170` | `ballooning.raise_at_percent: 170 is not in 1..100` | readable, but Ruby syntax |
| `min_actual_gib = 0` | `ballooning.min_actual_gib: 0 is not in 1..` | Ruby syntax a user can't read |
| `rasie_at_percent = 70` | `ballooning.rasie_at_percent: unknown key; Config::Ballooning has raise_at_percent, shrink_at_percent, min_actual_gib` | doesn't say which key was meant |
| `[balooning]` | `balooning: unknown key; Config has ballooning` | the same |
| `ballooning = 5` | `ballooning: expected Config::Ballooning, got 5` | good: the class name is concrete, `got 5` shows what's wrong |
| `validate` raises | `ballooning: raise_at_percent (50) must be above shrink_at_percent (55)` | good |

The key path and the offending value are always there, which is most of the job. The rest is
agreed; what follows is how each lands.

## 1. A misspelled key gets a suggestion

`rasie_at_percent: unknown key, did you mean raise_at_percent?` — `DidYouMean::SpellChecker`,
a default gem, so no runtime dependency. `mapper.rb` requires `"did_you_mean"` itself:
under `ruby --disable-did_you_mean` the constant is undefined until required (checked).

- **Every match the checker returns, no cutoff of our own.** On the spike's keys it returns one
  (`rasie_at_percent` → `raise_at_percent`, `balooning` → `ballooning`); `raise_bt` against
  `raise_at, raise_by` returns both, and both are worth showing.
- **A match replaces the key list**; with none, the message stays as it is today:
  `unknown key; Config::Ballooning has raise_at_percent, …`. The class name stays: a concrete
  Ruby type, as in a type mismatch.
- **A misspelled required key reports the typo, not `required`**: `reject_unknown` runs before
  `fresh_base`. It already does; a spec pins it.

## 2. Ranges worded per shape

`limits.rb` prints `allowed.inspect` today. Instead, the value last, as `got` in a type mismatch:

| `in:` | Message |
|---|---|
| `1..100` | `must be 1 to 100, got 170` |
| `1..` | `must be at least 1, got 0` |
| `..100` | `must be at most 100, got 170` |
| `...10` | `must be below 10, got 10` |
| `1...10` | `must be at least 1 and below 10, got 10` — not `1 to 9`, which a Float range can't say |
| `1.0..` / `1.0...` | as above, with the Float ends |
| `%w[a b]` | `must be one of "a", "b", got "c"` |

`plan.rb:138` wraps the same message as `its default #{e.message}` for a `DefinitionError`;
`its default must be 1 to 3, got 0` still reads.

## 3. Types keep their RBS spelling; "table" goes

A type mismatch names the type as RBS spells it, on load and dump alike:
`ballooning: expected Config::Ballooning, got 5`, `expected Hash[String, Integer], got 5`. A
concrete Ruby type beats a format's word for the shape: TOML's "table", YAML's "mapping" and
JSON's "object" each mean something only to that format's users, and a class name is exact.

- **One message, not two.** `Session#load_object` (`mapper.rb:172`) says `expected a table of
  Config's properties, got [1]`, reached only at the root since `ClassRef#load` checks first. It
  becomes `Type.mismatch`'s `expected Config, got [1]`.
- **"table" becomes "Hash"** where it names the shape rather than TOML's `[section]`: the README's
  type table (`a Hash of T`, `a Hash, loaded into your class`) and line 54, the doc comments at
  `mapper.rb:50` and `type.rb:130`, `:155`, `:196`. README line 132 and `D_validation_phase`
  speak of a TOML `[llm]` table and stay.

The value shown stays `inspect`: `got "70"` reads well in TOML, JSON and YAML alike.

## Known gap: `format:`

`"abc" does not match /\A\d+\z/` prints a Regexp, which the person editing the file can't read,
and no wording fixes that. Not a `description:` option on `constrain`: an app that needs a
readable message raises it from `validate`, in its own words (`D_functions_over_rules`).

## Out of scope

**Every error at once** (`D_validation_phase`: nothing has asked for it, and virtui's config, the
first to ask, chose to fix one error per run), and **line numbers**, which the parsers (Tomlrb,
`JSON`) don't keep in the Hash they return. The key path stands in for them.

## Where it lands

- `lib/typemap/mapper/limits.rb`: the range and list wording.
- `lib/typemap/mapper.rb`: the unknown-key raise and the root non-Hash raise.
- "table" → "Hash" in the README and doc comments listed under 3.
- The README's error examples (lines 37–40); the specs asserting the old strings
  (`validation_spec`, `data_class_spec`, `type_spec`, `rbs_types_spec`, `definition_error_spec`).
- CHANGELOG: `**Breaking:**` the messages change; an app matching on them updates its pattern.
