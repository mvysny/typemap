# Confect

Confect loads a config file into a Ruby class you already wrote, and checks every value on the
way: `"70"` is never 70, and the file never names a class. Your class stays yours — a
`Data.define` or a plain class with `attr_accessor`s, typed by `constrain` lines or by your RBS
signatures. TOML, JSON and YAML parsing stays with their own gems; Confect owns the mapping, the
checking, and optionally where an app's config and state files live.

To confect is to prepare something from raw ingredients: a raw file in, a checked Ruby object
served out.

## Status

Pre-release: the design is in [design/ideas/mapper.md](design/ideas/mapper.md), and no API
exists yet.

## License

MIT; see [LICENSE.txt](LICENSE.txt).
