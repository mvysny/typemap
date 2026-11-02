# `entry_name`: a blank String is no name, so `raw["id"]` is the whole method

Every `entry_name` in both pikuri shells is the same line:

```ruby
def self.entry_name(raw) = raw['id'].to_s.strip
```

`.to_s` is unnecessary — `nil` and a non-String already mean "no name". The `.strip` is not: an
`id = "  "` gives `server[1] "  ".url: required`, a name that names nothing, so each app strips
and relies on the empty String falling back to the bare index. Every app writing `entry_name`
will hit that, or ship the `"  "` path.

## The sketch

Typemap treats a whitespace-only name like an empty one: just the index. The method shrinks to
what it means:

```ruby
def self.entry_name(raw) = raw['id']
```

Should Typemap also strip a name it prints — `" grok "` → `"grok"`? The name is printed
`inspect`ed, so the spaces show between the quotes; that is arguably the more useful message,
since the file really does say `" grok "`.

## Not this

`D_entry_name` already rejected `identified_by :id` in favour of a function — a name may be two
keys joined, or a fallback. A macro `entry_name :id` is the same thing again; the boilerplate it
saves is the `.to_s.strip`, which this idea removes without a second way to say it.

## Open questions

- `Q_blank_rule` — "blank" by `String#strip.empty?`, or also the Unicode spaces `strip` leaves
  (` `, `​`)? `/\A[[:space:]]*\z/` covers them, and agrees with the `nonblank-limit.md`
  idea's `Q_blank_vs_empty` if that one lands — one definition of blank for both.
