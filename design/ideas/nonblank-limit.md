# A non-blank limit: `constrain :name, nonblank: true`

A String that must say something — an id, a URL, a model name — is the commonest rule a type
can't state. Both pikuri shells' configs (pikuri-tui `Shared::Config`, pikuri-web
`PikuriWeb::Config`) write it in `validate`, eight times over:

```ruby
def validate
  %i[name server model].each { |key| raise "`#{key}` must not be blank" if public_send(key).strip.empty? }
end
```

Two costs, and the second is the real one:

- **Boilerplate**, in nearly every class of the file.
- **The path stops at the object.** A `validate` raise carries the object's path, so the message
  reads `llm[0]: \`name\` must not be blank`, where every limit reads
  `llm[0].name: must not be blank`. The app re-states the key by hand inside the message, in its
  own spelling.

`format: /\S/` gets the path right, but the README already warns its message prints the pattern
(`"  " does not match /\S/`), which the person editing the file may not read.

## The sketch

```ruby
constrain :id, :url, nonblank: true
constrain :command, nonblank: true      # Array[String]: at least one element
```

```
server[1] "grok".url: must not be blank
code.mcp[0] "fs".command: must not be empty
```

- A limit, so it lives in `Limits` beside `in:` and `format:`, checked in the validation phase
  after the type (`D_validation_phase`), and on `dump` too.
- **`nil` passes**: on a `String?` the limit says "if given, not blank" — the same reading `in:`
  has on an `Integer?`. Pikuri's `bearer_token` is exactly that.
- `check_against` raises a `DefinitionError` on a type it can't limit (an Integer).

## Open questions

- `Q_blank_vs_empty` — for a String, blank (`"  "`) or only empty (`""`)? Blank: a file holding
  `id = " "` is a typo nobody means, and pikuri strips. Empty-only would match Ruby's `empty?`
  but leaves the typo through.
- `Q_arrays_too` — does it apply to an Array (and a Hash): "at least one element"? pikuri's
  `command` wants it. If yes, `nonblank:` is the wrong word for an Array; `nonempty:` for both,
  with a String's "empty" meaning blank? Or a general `size: (1..)` limit — which covers
  "at most 64 chars" too, but treats `"  "` as size 2, so it doesn't replace non-blank.
- `Q_name` — `nonblank: true`, `blank: false` (Rails' `allow_blank`), or `present: true`?
