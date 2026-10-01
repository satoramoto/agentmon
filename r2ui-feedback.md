# r2ui feedback from building agentmon

agentmon is a dogfooding run: a real app on r2ui's dashboard DSL and CLI toolkit. This is what got
in the way, with references to r2ui at `bba63f4` (main). Most important first. Stories add their
findings in their PR bodies; the plant manager folds them in here.

## Missing

1. **A dashboard can't be assembled from several files.** `R2UI.dashboard` takes one closed block
   (`lib/r2ui/dsl/dashboard.rb:25`), rows are immutable `Row` Data (`:16`) built only inside
   `Builder#row` (`:52`), and `Registry#add_dashboard` replaces by name (`lib/r2ui/registry.rb:14`).
   r2ui's own extension system is one-capability-per-file, but an *app* built on it can't add a
   panel from its own file. agentmon had to write its own registry with rows, `order:` and a layout
   step (`lib/agentmon/registry.rb#layout`, `lib/agentmon/ui.rb`). Wanted: something like
   `R2UI.panel :memory, dashboard: :main, row: :top, order: 10 do ... end` plus named rows.
2. **Resources can't be extended, and redefining one silently replaces it**
   (`lib/r2ui/registry.rb:12`). agentmon added `extend_resource` (collects blocks and replays them
   on one `Resource::Builder`) so a story can add an action or a scope to the process table without
   editing its file. Wanted: `R2UI.resource(:process, extend: true) { action ... }`, and an error
   on accidental redefinition.
3. **No shared or derived sources.** Each resource gets its own feed thread calling its own
   `source` (`lib/r2ui/feed.rb:26-27`). Three panels over one expensive machine sample (ps +
   rusage for 700 processes) would sample three times; agentmon put a cached, locked `Engine` in
   front (`lib/agentmon/engine.rb#current`). Wanted: `source from: :sample { |s| s[:processes] }`
   or a dashboard-level `data` block that feeds several resources once per tick.
4. **The CLI's `dashboard` helper only knows the global registry** (`lib/r2ui/cli/ext/dashboard.rb:72`,
   `:81`) and snapshots with `ticks: 1`. An app that builds its dashboard per run has to write into
   `R2UI.registry`, and tests must `R2UI.reset!` around it. Rate columns need two samples, so
   agentmon primes its engine itself. Wanted: `dashboard(app:)` or `dashboard(registry:, ticks:)`.
5. **`table` (CLI) can only print.** `lib/r2ui/cli/ext/table.rb:127-135` writes through
   `shell.puts`; there's no way to get the lines for a `Live` region, so `agentmon top`'s live mode
   re-implements column alignment (`lib/agentmon/commands/top.rb#lines`). Wanted:
   `table_lines(rows, headers:, align:)` or `table(..., to: :string)`.
6. **No "selected row of panel X".** `selected_rows` is the focused panel's
   (`lib/r2ui/app.rb:98`). A detail pane that follows the process table's selection while another
   panel has focus has to combine `app.panel_state(panel).selected` and `app.panel_lines(panel)`
   by hand, as `lib/r2ui/ext/mouse.rb:40-55` does. Wanted: `selected_row(:process)` on Context.
7. **History is fixed at 120 points and forgets rows that disappear** (`lib/r2ui/history.rb:6`,
   `lib/r2ui/feed.rb:68`). Four minutes at a 2 s refresh is short for "session history"; a session
   that ends loses its sparkline. Wanted: `refresh every: 2, history: 900`, and a way to feed a
   column's sparkline from an app-computed series.
8. **Overlays and whole-view changes exist only as global extension hooks.** `view_override` and
   `status` (`lib/r2ui/extension.rb:87`, `:95`) are registered with `R2UI.extension`, process-wide
   and active for every dashboard. A help overlay for one dashboard needs a global extension that
   checks which dashboard it's on. Wanted: dashboard-scoped `overlay { }` DSL.
9. **The help panel needs the bubbles gem, which pulls in the native upstream bubbletea and
   lipgloss gems** (`lib/r2ui/ext/help.rb:42`, and r2ui's own Gemfile comment). r2ui never loads
   them, but bundler still installs and compiles them. agentmon left `help` out (story a09 draws its
   own overlay). Wanted: a built-in key help with no bubbles dependency, or a bubbles gemspec that
   doesn't drag the native gems in.
10. **`test_shell` has no `height:`** (`lib/r2ui/cli/testing.rb:27`), and the dashboard snapshot
    uses the shell's height, so a command's frame in tests is always 24 lines tall.

## Inconsistent

11. **Two byte formats.** The dashboard's `Format.bytes` is binary with one-letter units
    ("1.5G", `lib/r2ui/format.rb:50`); the CLI's `bytes` helper is decimal with "MB"
    (`lib/r2ui/cli/ext/format.rb:49`). One app shows 1.5G in the dashboard and 1.6 GB in its CLI
    for the same number. agentmon uses `R2UI::Format` in both. Pick one, or name them apart
    (`ibytes`).
12. **`Format.bytes` switches units late**: 1000 bytes is "1000B", 1000 B/s "1000B/s"
    (`lib/r2ui/format.rb:50-54`), wider than the 8-column default and harder to read than "1.0K".
13. **Percent always sums when grouped** (`lib/r2ui/format.rb:7`): right for CPU, wrong for shares
    or pressure. `aggregate:` on the column covers it, but the default surprises.
14. **Root help shows `description` but never `summary`** for the program itself, so a tool's
    one-line summary appears nowhere.

## Awkward but workable

15. Panel item blocks are `instance_eval`ed on the `PanelBuilder` (`lib/r2ui/dsl/dashboard.rb:75`),
    so they can't take arguments; passing the app's engine in needed a wrapping
    `proc { instance_exec(engine, &block) }` (`lib/agentmon/ui.rb`).
16. Panel widths are relative `span:` integers only (`lib/r2ui/renderer.rb:59`); a detail pane
    can't ask for a fixed or minimum width.
17. `R2UI.reset!` drops resources defined at require time, so apps that define them at load can't
    be tested in isolation; agentmon builds its resources in a method instead.

## Worked well

- `R2UI.extension` / `R2UI::CLI.extension` and auto-loaded one-file capabilities: agentmon copied
  the pattern for probes, metrics, panels and commands.
- `App#press` / `App#frame` and `CLI::Testing#run_cli`: every panel and command is tested without a
  terminal.
- A program with both a root `run` and subcommands works (`agentmon` opens the dashboard,
  `agentmon top` is a command), and `dashboard` falls back to a plain frame in a pipe.
- `Live` restored the cursor on ctrl+c in a pty run of `agentmon top`, and the dashboard restored
  the alternate screen on `q`.
