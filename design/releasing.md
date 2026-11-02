# Releasing

Typemap is published to [RubyGems](https://rubygems.org/gems/typemap). The release task comes
from `bundler/gem_tasks`, gated on the project's check suite: `rake release` runs `rake check`
(specs, RuboCop and the design-doc tripwires) before it tags or pushes anything, so a release with
failing tests or lint offenses aborts before it can publish. See `Rakefile` —
`task "release:guard_clean" => %w[release:guard_version check]`.

## 1. Pre-flight checks

The release gate re-runs these, but run them by hand first: a failure caught here is a quick
fix, whereas the same failure during `rake release` aborts mid-release after the gem is built.

From a clean working tree on `main`:

```sh
bundle install
bundle exec rake check      # specs + RuboCop + design tripwires
```

If you ran the suite with `COVERAGE=true`, double-check `coverage/` isn't committed.

## 2. Bump the version

Edit `lib/typemap/version.rb` and set `Typemap::VERSION` to the new value following
[SemVer](https://semver.org/); pre-1.0, a breaking change bumps the minor.

Update `CHANGELOG.md`:

- **Reconcile it against the log first.** `git log --oneline vX.Y.Z..HEAD` (the whole log for
  the first release) and check every user-visible change has an entry — an entry is written when
  the change lands, so the ones that got skipped are exactly the ones nobody will notice missing.
- **Then reconcile it against the public surface, which catches what the log cannot.** A commit
  message reports what its author noticed; the code reports what actually changed:

  ```sh
  git diff vX.Y.Z..HEAD -- lib/ | grep -E '^[-+]\s*(def |class |module |attr|constrain |ignore |unknown )'
  git diff vX.Y.Z..HEAD -- README.md
  ```

  The removed (`-`) lines are the high-signal half — a deleted or re-scoped method, a renamed
  keyword, a changed error message is a breaking change whether or not anyone wrote it down.
  Many `+` lines are private internals; check them against the file's `private` markers before
  writing an entry. The README documents every user-facing API (AGENTS.md, "Conventions"), so its
  diff is the user's-eye view of the same surface.
- **Review every entry's length** against the rule in `CHANGELOG.md`'s header: lead with `Add` /
  `Fix` / `**Breaking:**`, one sentence of ≈40 words, a second sentence only for a breaking
  change's migration, rationale deferred to `design/decisions.md`. Entries are drafted
  mid-development, when the design argument is still warm and wants to spill into them; this is
  the checkpoint that catches it. Group the section `Add`, then `Fix`, then `**Breaking:**`.
- Move the entries from `## [Unreleased]` into a new `## [x.y.z] - YYYY-MM-DD` section.
- Leave a fresh empty `## [Unreleased]` heading at the top.

Refresh `Gemfile.lock`. The gemspec reads `Typemap::VERSION`, so the lock pins
`typemap (x.y.z)`; bumping the version leaves it stale, and the next `bundle install` (the release
gate runs one) rewrites it — dirtying the tree so `release:guard_clean` aborts mid-release. Run it
now and confirm the `typemap (x.y.z)` lines updated:

```sh
bundle install
```

Commit all three files (no need to push — `rake release` pushes the branch and tag in step 3):

```sh
git add lib/typemap/version.rb CHANGELOG.md Gemfile.lock
git commit -m "Release x.y.z"
```

## 3. Cut the release

```sh
bundle exec rake release
```

This task (from `bundler/gem_tasks`, with our guards) runs in order:

1. **build** — builds `typemap-x.y.z.gem` into `pkg/`.
2. **release:guard_version** — aborts unless `CHANGELOG.md` has a dated `## [x.y.z] - YYYY-MM-DD`
   section for the current `Typemap::VERSION` (catches a forgotten section or a placeholder
   date), and unless the `vx.y.z` tag does *not* yet exist (a present tag means the version was
   already released — bump `Typemap::VERSION` first). It runs before the spec suite so these
   cheap metadata mistakes fail fast.
3. **check** — runs `spec`, `rubocop` and `design_tripwires`; aborts the release on any test
   failure, lint offense or tripwire.
4. **release:guard_clean** — refuses to proceed unless the working tree and index are clean.
5. **release:source_control_push** — creates the `vx.y.z` tag, then pushes the current branch
   followed by the tag to its remote.
6. **release:rubygem_push** — pushes the gem to RubyGems.

The tag check in step 2 is local (it reads `git tag`), so a release cut from another clone that
this machine hasn't fetched won't be seen here — RubyGems' own duplicate-version rejection is the
backstop then.

You need a RubyGems account with push rights on the `typemap` gem and 2FA configured (the gemspec
sets `rubygems_mfa_required = true`, so `gem push` prompts for an OTP).

To rehearse the gate without touching anything, run `bundle exec rake check` — the same suite the
release gate runs, building, tagging and pushing nothing.

## 4. Post-release

- Verify the new version appears at <https://rubygems.org/gems/typemap>.
- Verify the tag is on GitHub: <https://github.com/mvysny/typemap/tags>.

## If something goes wrong mid-release

The sub-tasks run in the order listed in step 3. If the gem push (step 6) fails after the tag was
pushed (step 5), fix the underlying issue and run `gem push pkg/typemap-x.y.z.gem` directly —
**do not** re-run `rake release`: the tag now exists, so `guard_version` would abort. If the tag
itself is wrong, delete it locally *and* on the remote (`git push --delete origin vx.y.z`) before
retrying; `source_control_push` pushes the branch *before* the tag, so a tag-push failure can
leave the branch already pushed.
