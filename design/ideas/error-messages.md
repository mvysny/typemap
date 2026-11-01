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
| `rasie_at_percent = 70` | `ballooning.rasie_at_percent: unknown key; Config::Ballooning has raise_at_percent, shrink_at_percent, min_actual_gib` | names a Ruby class; doesn't say which key was meant |
| `[balooning]` | `balooning: unknown key; Config has ballooning` | the same |
| `ballooning = 5` | `ballooning: expected Config::Ballooning, got 5` | names a Ruby class where the file needs a table |
| `validate` raises | `ballooning: raise_at_percent (50) must be above shrink_at_percent (55)` | good |

The key path and the offending value are always there, which is most of the job. Three things
fall short.

## The gaps

- **A class name where the file needs a shape.** `expected Config::Ballooning` means nothing to
  someone editing a TOML file; `expected a table` (or `an object`, since Typemap doesn't know the
  format) does. The same goes for `Config::Ballooning has …` in the unknown-key message: the
  path already names where the error is, so `expected one of raise_at_percent, …` is enough.
- **Ranges printed with `inspect`.** `1..` and `1...10` are Ruby. Wording per range shape reads
  better: `must be at least 1`, `must be at most 100`, `must be 1 to 100`, `must be below 10`. A
  list `in:` reads fine as it is (`must be one of "short", "verbose"`).
- **No suggestion for a misspelled key.** A misspelled key is the most common config error, and
  `DidYouMean::SpellChecker`, part of Ruby since 2.3 and so no runtime dependency, makes the fix
  obvious: `rasie_at_percent: unknown key, did you mean raise_at_percent?`. With no close match,
  the list of keys stays.

The value shown is still `inspect`: `got "70"` reads well in TOML, JSON and YAML alike, and a
Hash or Array value is rare enough in a mismatch that its Ruby form can stay.

Out of scope here: **every error at once** (`D_validation_phase`: nothing has asked for it, and
virtui's config, the first to ask, chose to fix one error per run), and **line numbers**, which
the parsers (Tomlrb, `JSON`) don't keep in the Hash they return. The key path stands in for
them.

## Where it lands

`Type.mismatch` (`lib/typemap/mapper/type.rb`) for a class type, `Limits`
(`lib/typemap/mapper/limits.rb`) for the range wording, the unknown-key raise in
`lib/typemap/mapper.rb` for the suggestion; the README's error examples and
`spec/typemap/mapper/data_class_spec.rb`'s `assert_match` on the class name change with them.

## Open questions

- `Q_shape_word` — `expected a table` (TOML's word, and what most config files are) or
  `expected an object` (JSON's)? Typemap is format-agnostic. `a Hash` is accurate but Ruby again.
- `Q_did_you_mean_cutoff` — take `SpellChecker`'s default distance as it is, or show only the
  best match? Several close keys (`raise_at`, `raise_by`) argue for listing them all.
