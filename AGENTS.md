# agentmon

A macOS terminal monitor for what AI coding agents (Claude, Codex) cost the machine: per-session CPU, real memory and disk I/O, memory pressure, and a history of runs. Built on [r2ui](https://github.com/satoramoto/r2ui) (dashboards with `require "r2ui"`, CLI output with `require "r2ui/cli"`), as a real consumer of that library: if r2ui gets in the way, say so in your result (that feedback is part of the product).

## Tests

| Command | When |
|---|---|
| `bundle exec rake test` | After any change; CI runs it on macOS |
| `bundle exec ruby -Itest -Ilib test/<file>_test.rb` | Targeted: one file (`test/<dir>/<file>_test.rb` for `lib/agentmon/<dir>/<file>.rb`) |
| `COLUMNS=150 LINES=40 bundle exec exe/agentmon \| cat` | After changing a panel or the dashboard: prints one real frame of this Mac (plain, no terminal needed) |
| `bundle exec exe/agentmon top --once \| cat` | After changing process data or a command: one plain table |

Tests run on fixtures (`test/support/fixtures.rb`); only `test/live/*_test.rb` read the real machine (macOS only, a few seconds, never as root). The interactive dashboard needs a terminal; tests drive it through `test/support/dashboard.rb`: `dashboard_app`, `app.press` and `dashboard_frame(app, focus: :process)` (a 200x50 frame with focus set explicitly), never a hand-sized `app.frame(w, h)`, since every story's panels share the screen.

CI (`.github/workflows/ci.yml`, macos-latest) is the final check.

agentmon builds on released r2ui only: the gemspec's `r2ui ~> 0.2.0` from RubyGems, in CI and locally. A new r2ui minor arrives as a Dependabot PR; taking it is agentmon's call. To try an unreleased r2ui locally, set `R2UI_PATH` (`R2UI_PATH=../r2ui bundle exec rake test`; `../../r2ui` from a worktree in `agentmon-wt/<id>/`), but don't merge code that needs it. Don't change r2ui from this repo; report what you need from it.

## Factory

Built by the software-factory job shop: `factory/job-shop.js` (dispatcher), `factory/stations/*.md` (station SOPs). The plant manager merges; stations never merge.

**Design and story list:** `docs/design.md` (architecture, data model and units, extension points, rules for story work, stories `a01-...`). A story adds only its listed files.

**Shared files** (change only through a small contract PR): `lib/agentmon.rb`, `lib/agentmon/{model,registry,darwin,sampler,reading,focus,engine,store,ui,program}.rb`, `test/test_helper.rb`, `test/support/*.rb`, `exe/agentmon`, `Gemfile`, `agentmon.gemspec`, `LICENSE.txt`, `CHANGELOG.md`, `Rakefile`, `.github/workflows/ci.yml`, this file, `docs/design.md`.

`r2ui-feedback.md` collects what was awkward, missing or buggy in r2ui while building agentmon. Stories don't edit it (it would conflict): put r2ui feedback, with file and line, in your PR body and result; the plant manager folds it in.

## Releasing

Agents never tag or publish: a pushed `vX.Y.Z` tag publishes the gem (`.github/workflows/publish.yml`), and only the owner pushes one. Put user-facing changes under `## Unreleased` in CHANGELOG.md, in the PR that makes them. The steps are in `docs/releasing.md`.

## Review checklist

Reviewers flag only real bugs and these rules, never style:
- Wrong numbers: units (bytes vs KiB, Mach ticks vs ns), rates computed across a pid that was reused, totals that double count a process tree.
- Sampling that's too slow for a 1–2 s refresh, or that spawns a subprocess per process.
- Terminal state not restored on every exit path.
- A story editing files outside the ones it may add.
