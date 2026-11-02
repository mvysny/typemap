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

The class says which property identifies one of its instances:

```ruby
class Server < Data.define(:id, :url)
  extend Typemap::Constrain

  constrain :id, :url, type: "String"
  identified_by :id
end
```

and a path through an array of them prints that value alongside the index:

```
server[1] "grok".url: required
```

- **The index stays.** It's always correct; the name helps a person find the entry, but two
  entries might share a name, and a uniqueness check is the app's job.
- **Fallback when the identifier is unusable**: absent, not a String / Integer, or itself the
  error. Then the path is the bare index, as today.
- **Only arrays.** A Hash entry's path already carries its key (`servers.grok.url`).

## Open questions

- `Q_identity_spelling`: a macro (`identified_by :id`), an option on `constrain`
  (`constrain :id, type: "String", identifies: true`), or a function
  (`D_functions_over_rules`), `label: ->(raw) { raw["id"] }`, for an entry identified by two
  keys together?
- `Q_identity_format`: `server[1] "grok".url`, `server["grok"].url` (looks like a Hash
  lookup, which it isn't), or `server[1] (id "grok").url`, which shows which key gave the name?
- `Q_identity_dump`: the same path on `dump` errors? Probably yes, since one path builder
  serves both directions.
