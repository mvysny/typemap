# An error path names the array entry, not only its index

Asked by pikuri-tui, whose config is mostly arrays of tables:

```toml
[[server]]
id  = "local"
url = "http://localhost:8080"

[[server]]
id = "grok"
# url forgotten
```

Its own validation says `` server "grok": `url` is required ``. Typemap would say
`server[1].url: required`. That's accurate, but the reader has to count `[[server]]`
headers to find the entry, and in a file with six `[[llm]]` tables, counting is where
mistakes happen. The entry already has a name the user wrote; the message could use it.

## The sketch

The class names an entry with a class method that takes the entry as a Hash:

```ruby
Server = Data.define(:id, :url) do
  extend Typemap::Constrain

  constrain :id, :url, type: "String"
  def initialize(id:, url:) = super

  def self.entry_name(raw) = raw["id"]
end
```

and a path through an array of them prints that name alongside the index:

```
server[1] "grok".url: required
```

- **A function, not a macro.** An `identified_by :id` can name only one property; a name may
  be computed — two keys joined, a fallback when `id` is absent — and only a function can say
  that (`D_functions_over_rules`). The mapper already calls an optional `validate` the same
  way, when the class defines one.
- **Not `to_s`.** The app may use `to_s` for its own purposes, logs or UI, and a message
  shouldn't change when those do. And `to_s` needs an instance, which a conversion error never
  has.
- **A class method**, for the same reason: when the entry's type check fails, or a data class
  misses a required keyword, no instance was ever built.
- **`raw` is always the entry as a file would write it**: String keys, nested objects as
  Hashes. Never the app's object: a function that sometimes gets a Hash and sometimes an
  object is a bug waiting to happen. Per phase:
  - conversion error: the file's Hash, keys normalised to Strings, values unchecked;
  - validation error: `Mapper#dump_object` of the finished entry, which cannot fail since
    conversion checked every type, and which runs no `in:` / `format:` / `validate`;
  - `dump` error: the same, but one property at a time, leaving out any key whose value
    won't dump — the bad value is what the error is about. If that's `id`, `raw["id"]` is
    `nil`, and so is the name.
- **Called only when reporting an error**, so its cost and the dump's don't matter. The
  array type rescues the `DataError` from entry `i`, calls `entry_name` once, and re-raises
  with the name spliced in after `[i]`; a load that succeeds never calls it.
- **No name** when `entry_name` is absent, returns `nil`, an empty String or anything not a
  String, or raises a `StandardError`. The original error is what the user needs; a broken
  `entry_name` must not replace it. The cost: a function that always raises goes unnoticed —
  the names just never show.
- **Defaults show up in validation, not in conversion.** A validation error's `raw` holds every
  property, defaults included; a conversion error's holds only what the file wrote. An entry
  whose `id` defaulted to `"default"` is named in one and not the other. Fine: the name finds
  the entry, it doesn't claim the file wrote it.
- **The index stays.** It's always correct; the name helps a person find the entry, but two
  entries might share a name, and a uniqueness check is the app's job.
- **Only arrays.** A Hash entry's path already carries its key (`servers.grok.url`).
- **Spelled `entry_name`, unprefixed.** A class Typemap maps is a data carrier, likely written
  for this mapping alone, so a clash is unlikely; and a `typemap_` prefix would ask why
  `constrain` and `validate` have none.
- **Printed after the index, through `inspect`**: `server[1] "grok".url` reads as the entry's
  nickname, which it is. The quotes keep a name with a space or a dot readable, and `inspect`
  escapes a newline, so a name can't break the message. `server["grok"].url` is out: it reads
  as a Hash lookup, which it isn't.
- **Printed whole, never cut.** It shows only when a load or dump fails, where a long name
  (`grok (https://api.x.ai/v1)`) costs little.
