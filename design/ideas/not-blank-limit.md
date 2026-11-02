# Non-blank and non-empty limits: `constrain :name, not_blank: true`

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
constrain :id, :url, not_blank: true     # String: not "" and not "  "
constrain :command, not_empty: true      # Array[String]: at least one element
```

```
server[1] "grok".url: must not be blank
code.mcp[0] "fs".command: must not be empty
```

- Limits, so they live in `Limits` beside `in:` and `format:`, checked in the validation phase
  after the type (`D_validation_phase`), and on `dump` too.
- **Two names, one meaning each.** `not_blank:` limits only a String; `not_empty:` only an Array
  or a Hash. One name meaning different things per type would have to say what "empty" is for a
  String.
- **`not_empty:` on a String raises a `DefinitionError` naming `not_blank:`.** Written by habit,
  it would let `"  "` through, the typo nobody means (pikuri strips). Bean Validation's
  `@NotEmpty` takes a String; this differs on purpose, loudly.
- **Only `true`.** `not_blank: false` is a double negative that says nothing leaving the key out
  doesn't; anything but `true` raises a `DefinitionError`.
- **`nil` passes**: on a `String?` the limit says "if given, not blank" — the same reading `in:`
  has on an `Integer?`. Pikuri's `bearer_token` is exactly that. On a plain `String` the type
  already refuses `nil`, so `not_blank:` there reads as Bean Validation's `@NotBlank`; the
  `String?` case is where it differs (`@NotBlank` refuses null), and the doc comment says so.
- `check_against` raises a `DefinitionError` on a type neither limits (an Integer).

## Why these names

- **`not_blank:` mirrors its message**, `must not be blank`; a reader of the error finds the line.
- **Snake_case, like every other `constrain` key.** `nonblank` reads as one word; Ruby's
  `nonzero?` is the old exception, not the pattern.
- **Bean Validation's `@NotBlank` / `@NotEmpty`** — the pair a Java developer already knows.
- **Not `present: true`**: next to `required: true` ("the file must give this key") it reads as
  that same rule.
- **Not `blank: false`**: no negation, but `false` would switch a check *on*, the only key in
  `constrain` that works so.

## What counts as blank

`String#strip.empty?` — the rule `entry-name-blank.md` uses too, one definition of blank for
both. A person types the file, so the blank is ASCII spaces nearly always; the Unicode spaces
`strip` leaves (` `, `​`) wait for a real report, and `/\A[[:space:]]*\z/` is the
widening then.
