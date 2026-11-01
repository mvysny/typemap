# Tagged properties: one of several classes

A property that may hold one of several classes — a `[source]` table that is either a
`FileSource` or an `HttpSource`. The file never names a class (a promise), so it cannot say
`class = "HttpSource"`; it gives a **tag** the class side maps to a closed set:

```ruby
constrain :source, type: "FileSource | HttpSource", tag: "kind",
                   tags: { "file" => "FileSource", "http" => "HttpSource" }
```

```toml
[source]
kind = "http"
url = "https://…"
```

The mapper reads `kind`, looks it up in the closed map, and loads the rest of the table into
that class; an unknown tag raises with the allowed ones. Dump writes the tag back.

## Why it is not built yet

No app has such a property. The type subset has no union of classes either: today
`"FileSource | HttpSource"` raises "unsupported type".

## Open questions

- `Q_tag_where` — the tag inside the table (as above), or the table's key (`[source.http]`)?
- `Q_tag_in_rbs` — under `RBSTypes` the union comes from `sig/`; the tag map still needs
  `constrain`. Is that "declared twice"?
