# Bug: the `[[x]]` / `[x]` hint vanishes when the entry is incomplete

The shape hints fire only when the misplaced entry would load on its own (`Type.loads?` in
`ArrayOf#single` and in `Mapper::Session#not_a_hash`). But a table written with the wrong
brackets is usually a table *being* written — half done, a key missing or misspelt — and that is
exactly when the hint goes. Verified at 6ab41a8 with `source: :toml`:

```
[server] id="a" url="u"         server: expected Array[Server], got a single Server; write [[server]], not [server], or server = [{…}]
[server] id="a"                 server: expected Array[Server], got {"id"=>"a"}
[server] id="a" url=3           server: expected Array[Server], got {"id"=>"a", "url"=>3}

[[search]] key="a" n=1          search: expected Search, got an array of one Search; write [search], not [[search]], or search = {…}
[[search]] key="a"              search: expected Search, got [{"key"=>"a"}]
[[search]] key="a" n=1 bogus=2  search: expected Search, got [{"key"=>"a", "n"=>1, "bogus"=>2}]
```

Both directions, and any flaw inside the entry: a missing key, a wrong type, one unknown key. The
message left is the worst of both — no hint, and the entry's own problem hidden behind a dump of
the Hash. A user fixing `url` gets the same message again, since the brackets were the problem.

pikuri-tui's and pikuri-web's config specs both had to add `url = "http://x"` to their
`[server]` example to see the hint at all, which is how this was found.

## Why the gate exists

It is deliberate, and half right: `hints_spec.rb` "shows the value when it would not load as an
entry either" passes `{"port" => 1}` where `Array[Server]` belongs — a Hash that is no Server at
all, where "write [[server]]" would mislead. So the fix keeps a test of *is this an entry*, but a
weaker one than *does it load*.

## The fix, sketched

Hint when the value has an entry's **shape** — for a class element, a Hash sharing at least one
key with the class's properties:

| value where `Array[Server]` belongs | today | proposed |
|---|---|---|
| `{"id" => "a", "url" => "u"}` | hint | hint |
| `{"id" => "a"}` | none | hint |
| `{"id" => "a", "url" => 3}` | none | hint |
| `{"port" => 1}` | none | none |

The same test for an array of one Hash where one entry belongs. For a scalar element
(`Array[String]` given `"brave"`) keep `loads?`: there is no key set to compare, and `7` where
`Array[String]` belongs is not "a single String".

## Open questions

- `Q_overlap_rule` — "at least one key in common" or "most keys"? One is generous: `{"id" =>
  …, "porrt" => …}` still gets the hint, which is right (a typo inside a bracket mistake). A
  majority rule would refuse a two-key table with one typo. Leaning: at least one.
- `Q_then_the_entry` — after the hint, say the entry's own problem too?
  `server: expected Array[Server], got a single Server; write [[server]], not [server] (and
  then: server[0] "a".url: required)`. Saves a round trip, but two problems in one message breaks
  "the first problem raises" (`D_validation_phase`'s last line). Leaning no: fixing the brackets
  surfaces the next error on its own.
- `Q_found_wording` — `got a single Server` claims it *is* a Server, which an incomplete one
  isn't quite. `got a single [server] table` (TOML), `got one object` (JSON)? Probably fine as
  is: it names what the writer meant.
