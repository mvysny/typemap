# Converter hooks: the app's own Ruby converts a property

Two needs, one mechanism (`D_functions_over_rules`):

- **A custom type** — `min_actual = "8 GiB"` is a String in the file and virtui's `Size` in Ruby;
  `veto = "60s"` would be a `Duration`. Today a class that is neither a data class nor an
  accessor class raises "has no properties", so nothing is converted quietly.
- **A tagged property** — a `[source]` table that is either a `FileSource` or an `HttpSource`.
  The file never names a class, so it cannot say `class = "HttpSource"`; it gives a tag the
  app's code maps to a class. Today `"FileSource | HttpSource"` raises "unsupported type".

Both are a conversion Typemap cannot know, both ways. Rather than a rule language for it (tag
maps, tag positions, unit parsers), the property gets a pair of functions.

## The sketch

```ruby
KINDS = { "file" => FileSource, "http" => HttpSource }.freeze

constrain :source, type: "FileSource | HttpSource",
  load: ->(raw, ctx) {
    klass = KINDS[raw["kind"]] or ctx.fail("unknown kind #{raw["kind"].inspect}; one of #{KINDS.keys.join(", ")}")
    ctx.load(klass, raw.except("kind"))
  },
  dump: ->(obj, ctx) { { "kind" => KINDS.key(obj.class) }.merge(ctx.dump(obj)) }

constrain :min_actual, type: "Size",
  load: ->(raw, ctx) { Size.parse(raw) },   # raises on garbage; ctx adds the path
  dump: ->(size, ctx) { size.to_s }
```

```toml
min_actual = "8 GiB"

[source]
kind = "http"
url = "https://…"
```

## What holds it together

- **The declared type stays and bounds the result.** `type:` says what the property may be;
  the hook says how to get there. Typemap checks the hook's return value against the type, and
  plans `FileSource` and `HttpSource` when the class is first read, so a hook cannot smuggle in
  an unchecked object and a gap in a nested class still shows before any file is read.
- **The file still never names a class.** The app's code picks it, from a closed set it wrote.
- **A context, not the bare mapper.** `ctx.load(klass, hash)` and `ctx.dump(obj)` recurse into
  the mapper with the session — the `unknown:` policy and the path — so an error inside
  `HttpSource` still reads `source.url`. `ctx.fail(msg)` raises with the property's path; an
  exception the hook raises gains it too. Ties into `error-messages.md`.
- **Validation is unchanged.** The returned object goes through the validation phase like any
  other: its limits, its `required:`, its `validate`.
- **Strictness inside the hook is the app's.** A hook may turn `"70"` into 70; Typemap checks
  only what comes out. The guide says so.
- **Prerequisites in `TypeBuilder`:** a union of classes, and a class with no properties
  (`Size`) — each accepted only on a property with a hook, else a `DefinitionError` as today.

## Why it is not built yet

No consumer. virtui, the one app that asked for `Size`, settled its `Q_units` on the unit in
the key — `min_actual_gib = 8`, `veto_seconds = 60` (2026-11-01, its
`design/ideas/config-file.md`). No app has a tagged property.

## Open questions

- `Q_hook_where` — a hook on the property (above), or a protocol on the class — any class with
  `.load(raw)` and `#dump` is a custom type, no `constrain` line needed — or both? The protocol
  suits `Size`, used in many places; the property hook suits a union, which has no class to put
  it on, and a foreign class the app cannot add `.load` to. Both are functions, so either keeps
  `D_functions_over_rules`; the protocol first only if `Size` is the first consumer.
- `Q_hook_base` — a nested load starts from the default's nested object. Which base does
  `ctx.load(HttpSource, …)` start from when the default is a `FileSource`? A fresh one is the
  obvious answer; the default's object when the class matches?
- `Q_dump_required` — must every hook come with `dump:`? Typemap could dump by the value's
  runtime class and let a `dump:` only add to it (the tag), but then a scalar hook without
  `dump:` would write a `Size` it cannot dump.
- `Q_hook_raw` — what `raw` is: the value as the file gave it, a table's keys normalised to
  Strings as `Session#load_object` does? Does the hook see `unknown:`-rejected keys, or must it
  reject them itself through `ctx.load`?
- `Q_class_hook` — a hook on the whole class, handed the keys the mapper did not map, covers a
  tag in a sibling key (`source_kind = "http"` beside `[source]`). A data class is built in one
  go, so it would run before the build, filling keywords. Only with a real use.
- `Q_custom_limits` — may `in:` limit a custom type (`in: Size.gib(1)..Size.gib(64)`)? Only if
  the type is `Comparable`.
