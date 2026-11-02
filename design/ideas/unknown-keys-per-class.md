# Unknown keys, per class — and telling the app what was dropped

`unknown:` is per `load`, so it is all or nothing. A file several programs share needs both in one
load: pikuri's `config.toml` is strict everywhere, except that pikuri-web reads the `[ui]` table
pikuri-tui owns, and a key pikuri-tui adds there tomorrow must not stop pikuri-web from booting.
pikuri-web works around it before calling Typemap (`PikuriWeb::Config.drop_unread_ui_keys`):

```ruby
unread = ui.keys - UiTable.members.map(&:to_s)   # re-derives the property list Typemap already has
logger.info("ignoring [ui] key(s) this shell does not read: #{unread.join(', ')}")
merged.merge('ui' => ui.except(*unread))
```

It re-derives the property list by hand (`members` for a data class; an accessor class would
need the reader/writer rule again), and it only works for a table at a fixed path — not for each
entry of an array.

## The sketch

```ruby
class UiTable < Data.define(:show_thinking, :tool_lines)
  extend Typemap::Constrain

  unknown :ignore     # this class's keys only; nested classes keep their own policy
end
```

And so the app can still log what it dropped — silently ignoring is how a typo goes unnoticed:

```ruby
mapper.load(Root, hash, source: :toml, on_ignored: ->(path, key) { log.info("ignoring #{path}.#{key}") })
```

- **The class's policy wins over the load's**, both ways? A class marked `unknown :raise` inside
  an `unknown: :ignore` load — a state file whose one nested table must stay strict — is
  plausible too.
- `on_ignored` fires for a key ignored by either policy, the per-load one included, so
  `unknown: :ignore` on a state file can finally be logged too.
- **`dump` is unaffected**: it writes properties only.

## Open questions

- `Q_class_or_property` — on the class (`unknown :ignore`), or on the property holding it
  (`constrain :ui, unknown: :ignore`)? The class says "this table is someone else's" wherever it
  appears; the property lets one class be strict in one file and lenient in another. The class
  seems right for the shared-file case, since the table's owner is a fact about the table.
- `Q_callback_shape` — `on_ignored: ->(path, key)` per key, or one call with the whole list at
  the end of the load? Per key composes with the path Typemap already builds; a list lets the
  app write one log line, as pikuri-web does today.
- `Q_macro_name` — `unknown :ignore` reads well next to `ignore :on_change`, but the two mean
  different things (a key in the file vs. a property of the class). Maybe `ignore_unknown_keys`.
