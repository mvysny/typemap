# Locations: where an app's config and state files live

The second, optional layer, built on the mapper (which is done): find and read an app's config,
read and write its state, by the Linux conventions — so an app says `Confect.config(Config,
app: "virtui")` and gets a checked object. The top-level `Confect` namespace is kept free for it.

## The shape of it

- **Config is read** from `$XDG_CONFIG_HOME` (default `~/.config`), then each `$XDG_CONFIG_DIRS`
  entry (default `/etc/xdg`), then `/etc/<app>/`; **state is read from and written to**
  `$XDG_STATE_HOME` (default `~/.local/state`); an explicit path always wins.
- **Formats by file extension, required lazily**: `.toml` → `tomlrb`, `.json` → `json`,
  `.yaml` → `psych`. The gemspec declares none of them; a missing one raises with a hint to add
  it. tomlrb only reads, which suits config (read-only) and state (JSON); writing TOML comes in
  only with a "print the default config" feature.
- **Error messages gain the file**: `~/.config/virtui/config.toml: ballooning.raise_at_percent:
  expected Integer, got "70"` — the mapper's `DataError` already carries the path.
- **State is written atomically**: to a temp file, then renamed into place, so a crash mid-write
  never leaves a truncated file (virtui's `State#save` does this today).

## Scope creep is the risk

Config libraries grow env-var and CLI overrides, deep merge, macOS and Windows paths, reloading on
change. The first version holds to first found, XDG plus `/etc`, Linux only — what virtui and
pikuri need — and adds each extra only when a real app asks for it.

## Compared, from rubygems on 2026-11-01

- **tty-config** (0.6.0, last released 2022-06-18, 0.9M downloads, no runtime dependencies):
  the closest prior art — YAML, JSON, TOML, INI, a search path, env vars, read and write, built
  for terminal tools. But Hash-based (`config.fetch('a', 'b')`), no typed objects, no XDG
  unless the app appends the paths itself, and dormant.
- **anyway_config** (2.9.1, 36M downloads, depends on ruby-next-core): twelve-factor, env
  first, YAML under `config/`; shaped for Rails apps.
- **config** (5.6.1, 60M downloads, depends on deep_merge, ostruct): multi-environment
  `settings.yml`, Rails conventions, untyped.
- **xdg** (10.4.0, 2.2M downloads, no runtime dependencies): the XDG Base Directory paths only,
  no loading, no types. A dependency this layer could take rather than re-derive the spec — but
  it would be Confect's first runtime dependency.

## Open questions

- `Q_layers` — first found, or a deep merge of `/etc/xdg` and `~/.config`? virtui's
  `design/ideas/config-file.md` leans first found; pikuri has a case for merging (a system file
  holding API keys). Bring that file's search-path reasoning over when this is designed.
- `Q_xdg_gem` — re-derive the XDG rules (a dozen lines: unset, empty or relative means the
  default) or depend on the `xdg` gem?
- `Q_api` — `Confect.config(Config, app:)` and `Confect.state(State, app:)` returning objects, or a
  `Confect::Store` an app keeps to `save` its state through?
