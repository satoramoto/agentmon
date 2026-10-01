# agentmon design

agentmon shows what AI coding agents (Claude Code, Codex, their desktop apps) cost a Mac: per
session CPU, real memory (footprint, not just resident size), disk I/O, memory pressure, and a
history of runs. It replaces r2ui's `examples/agents.rb` and is built on r2ui as a real consumer:
dashboards with `require "r2ui"`, the command line with `require "r2ui/cli"`.

This file is the architecture and the work list. Each capability is one **story**: one new file
that registers itself, plus its test. Stories never edit an existing file, so any number of them
can be built at once and merged in any order.

## Architecture

```
          probes                 metrics                 recorders
 ps ─┐   (lib/agentmon/probes)  (lib/agentmon/metrics)  (lib/agentmon/recorders)
 rusage ─► Sampler ─► Sample ─► Reading ─────────────────► Store (JSONL, ~/.local/state/agentmon)
 lsof ─┘                │          │                          │
                        └── Engine ┘ (one per process,        │
                             current(max_age:))               │
                                   │                          │
            ┌──────────────────────┴──────────┐               │
     dashboard (lib/agentmon/ui)        commands (lib/agentmon/commands)
     r2ui resources + panels            r2ui CLI subcommands ◄─┘ (report reads the store)
```

- **Probe** (`Agentmon.probe`): reads the machine once and returns one value, stored as
  `sample[:name]`. `every:` makes a slow probe (lsof) reuse its last value until due. A probe that
  raises keeps its last value; the error goes in `sample.errors`.
- **Sample**: one probe pass: `at` (epoch), `mono` (monotonic), `parts`, `errors`. Raw counters
  only; nothing derived.
- **Metric** (`Agentmon.metric`): derives a value from the sample, the previous sample and its own
  state Hash (kept between samples, so a metric can accumulate). Metrics ask for each other by
  name (`reading[:sessions]`); each is computed once per sample, and every metric runs on every
  sample, so stateful ones never miss one. Stories land in any order, so `reading[:name]` is nil
  for a metric nobody registers yet, and a metric that raises is nil for that sample with its error
  in `reading.errors`; nothing else stops. Every consumer handles nil ("not available").
- **Errors** (`Engine#errors`, `Agentmon.engine_errors`): the latest probe, metric and recorder
  errors, as `{ "metric memory" => "NoMethodError: ..." }`. The dashboard shows the first on the
  left of its status bar ("⚠ metric memory: ..."); every command prints them on stderr after it
  runs.
- **Reading**: the sample plus every metric's value. Built by the Engine, then read-only, so the
  dashboard's feed threads share it safely.
- **Engine** (`Agentmon.engine`): sampler → reading → recorders, behind a lock. `current(max_age:)`
  returns the latest reading, sampling first if it is older than `max_age` (default 0.75 x the
  2 s interval), so every panel's feed and every command share one sample. The first call takes
  two samples 0.5 s apart, so rates exist in the very first frame and in `top --once`.
- **Recorder** (`Agentmon.recorder`): turns a reading into store records, at most every `every`
  seconds, only while the engine is recording (the interactive dashboard, `agentmon record`). It
  gets a state Hash kept for the engine's life (`{ |reading, state| }`), e.g. the ids it already
  wrote a final line for; never use module-level state.
- **Store**: append-only JSON lines, one file per kind per local day:
  `$AGENTMON_STATE_DIR` | `$XDG_STATE_HOME/agentmon` | `~/.local/state/agentmon`, then
  `<kind>/YYYY-MM-DD.jsonl`. `append(kind, hash)`, `each(kind, since:, till:)`, `prune(days:)`.
- **Dashboard** (`lib/agentmon/ui.rb`): `UI.install(engine:)` builds r2ui resources and the
  `:agentmon` dashboard from registrations: `Agentmon.resource` (one definition) plus any number of
  `Agentmon.extend_resource`, `Agentmon.dashboard` blocks (dashboard-level r2ui DSL: keys, mouse,
  theme), and `Agentmon.panel`s placed in `Agentmon.row`s by `order:`. Every block gets the Engine.
- **Command line** (`lib/agentmon/program.rb`): an r2ui CLI program. `agentmon` with no command
  opens the dashboard (r2ui's `dashboard` helper: full screen on a terminal, one plain frame in a
  pipe); `Agentmon.command` adds subcommands and `Agentmon.cli` root-level DSL.

Sampling cost per tick: one `ps` (~15 ms) and two Fiddle calls per process
(`proc_pid_rusage`, `proc_pidinfo`; ~25 ms for 700 processes), plus `lsof` (~0.4 s) every 10 s.
No subprocess per process, ever.

### Files

| File | What | Who changes it |
|---|---|---|
| `lib/agentmon.rb` | requires the core, then `Agentmon.load_extensions` | contract PR |
| `lib/agentmon/model.rb` | every shared Data shape (below) | contract PR |
| `lib/agentmon/registry.rb` | the extension points and `Registry` | contract PR |
| `lib/agentmon/{darwin,sampler,reading,engine,store,ui,program}.rb` | core | contract PR |
| `lib/agentmon/probes/*.rb` | one probe each | stories |
| `lib/agentmon/metrics/*.rb` | one metric each | stories |
| `lib/agentmon/recorders/*.rb` | one recorder each | stories |
| `lib/agentmon/ui/*.rb` | resources, panels, dashboard behaviour | stories |
| `lib/agentmon/commands/*.rb` | one command each | stories |
| `test/support/fixtures.rb`, `test/support/dashboard.rb`, `test/test_helper.rb` | fixtures and helpers | contract PR |

Extension files load directory by directory (probes, metrics, recorders, ui, commands), each in
name order. Nothing may depend on load order inside a directory: metrics find each other by name
at sample time, panels sort by `order:`, resource extensions run after the definition.

### Data model and units

All shapes live in `lib/agentmon/model.rb`. Units everywhere:

| Quantity | Unit |
|---|---|
| sizes, cumulative I/O | bytes (Integer) |
| rates | bytes per second (Float) |
| CPU time | seconds (Float). The kernel reports Mach ticks (1 ns on Intel, 125/3 ns on Apple Silicon); `Darwin` converts with `mach_timebase_info` and nothing else ever sees a tick, except `start_ticks`, an opaque identity |
| CPU usage | percent of one core (250.0 = two and a half cores) |
| instants | epoch seconds (Float); intervals and rates use the monotonic clock |
| unknown | nil, never 0 (unreadable processes, the first sample's rates) |
| display | r2ui's `Format`: binary sizes (`1.5G` = 1.5 x 1024³), in the dashboard and the CLI alike |

| Shape | Produced by | Notes |
|---|---|---|
| `Sample` | Sampler | `sample[:processes]`, `sample[:cwd]`, `sample[:memory]` |
| `ProcessStat` | probe `processes` | `readable: false` (EPERM: other users' processes) keeps ps's rss and %cpu, nil footprint/CPU time/disk. `identity` = `[pid, start_ticks]` survives pid reuse |
| `{ pid => path }` | probe `cwd` | lsof, every 10 s |
| `MemoryStat` | probe `memory` (a01) | counters cumulative since boot, in bytes |
| `ProcessRates` per pid | metric `process_rates` | deltas only between matching identities |
| `SessionMap` of `SessionInfo` | metric `sessions` | attribution, below |
| `[Session]` | metric `session_ledger` | alive and recently ended sessions with lifetime totals |
| `[ProcessRow]` | metric `process_rows` | what tables show |
| `MemoryView` | metric `memory` (a02) | Activity Monitor breakdown, rates, pressure trend |
| `[PressureDriver]` | metric `pressure_drivers` (a03) | sessions ranked by memory push |

**Sessions.** A process belongs to its outermost `claude`/`codex` CLI ancestor (itself included);
with none, to its topmost desktop app ancestor (Claude, ChatGPT/Codex). Claude Code sessions the
desktop app launches are CLI sessions of their own. Session ids are stable across agentmon runs:
`claude-4242-1790711088` (name, root pid, root start second). Labels: `claude 4242 · repo`
(directory of the root), `Claude 59334` for apps.

**Lifetime totals** (`metrics/session_ledger.rb` has the full reasoning):
- `cpu_seconds` adds each member's growth of own + reaped-children CPU time, so short-lived tools
  count through their parent; a member that exits is subtracted from its session's next growth
  (its parent will report it again as child time); a CLI session that ends under another session's
  process hands its root's total to that session the same way. Nothing is counted twice.
- `bytes_read`/`bytes_written` add each member's growth between samples: lower bounds (I/O of a
  process that lives less than one interval is not seen).
- `peak_footprint`: the largest footprint sum seen.
- Ended sessions stay in the ledger for 15 minutes (`SessionLedger::KEEP_ENDED`), current values 0.

### Store records

| Kind | Written by | Line |
|---|---|---|
| `sessions` | a11 | `Session#to_record` plus `t` and `run` (the engine's run id): one line per alive session every 10 s, and one final line when it ends |
| `memory` | a12 | `MemoryView#to_h` without `pressure_trend`, plus `t` and `run`, every 10 s |

Readers merge `sessions` lines by `id`, taking each total's maximum (`cpu_seconds`,
`bytes_read`, `bytes_written`, `peak_footprint`): every run of agentmon recounts from the kernel's
counters, so maxima never double count; sums would.

A session whose merged lines have no `ended_at` is **running** only while it was seen recently:
its `last_seen_at` is within 60 s (6 recorder intervals) of now. Otherwise agentmon wasn't
running when it ended (or crashed), so readers treat it as ended at its `last_seen_at`, shown as
"ended (not seen after HH:MM)", and its duration stops there. A session is never shown running
forever.

## Extension points

```ruby
module Agentmon
  probe(:name, every: nil) { |state| value }                     # sample[:name]
  metric(:name) { |reading, state| value }                       # reading[:name]
  recorder(:name, every: 10) { |reading, state| hash_or_hashes } # store kind :name
  resource(:name) { |engine| source { engine.current[:x] }; ... } # r2ui resource DSL, once
  extend_resource(:name) { |engine| column ...; action ... }     # more DSL for it
  dashboard { |engine| on_key "x" do ... end }                   # r2ui dashboard DSL
  row(:name, order:, height: nil)                                # :top (10, 14 lines) and :main (100) exist
  panel(:name, row:, order: 100, resource: name, span: 1, title: nil) { |engine| table; view { } }
  command(:name) { summary "..."; option ...; run { ... } }      # r2ui CLI command body
  cli { version Agentmon::VERSION }                              # root-level r2ui CLI DSL
end
```

A name already taken in its kind raises (`Agentmon::Error`), so two stories can't silently take
the same probe, metric, panel or command.

**The reference parts** (first articles, done here): `probes/processes.rb` (Fiddle rusage with
Mach tick conversion and EPERM fallback) with `test/probes/processes_test.rb` and
`test/live/darwin_live_test.rb`; `metrics/process_rates.rb`, `sessions.rb`, `session_ledger.rb`,
`process_rows.rb` with `test/metrics/`; `ui/processes.rb` (resource + panel) with
`test/ui/processes_test.rb`; `commands/top.rb` with `test/commands/top_test.rb`. Copy their shape.

## Rules for story work

- Add only the files your story lists. Edit no existing file (not the core, not another story's).
  If the core is missing something, stop and report the contract change you need.
- Build against the shapes in `model.rb`, not against another story's code: stories are built at
  the same time. A story that consumes a metric another story produces tests with preset values:
  `Reading.new(sample, values: { memory: MemoryView.new(...) })`, or an engine over fixture
  samples (`Fixtures.engine`). Until the producer merges, `reading[:memory]` is nil: handle nil
  (an empty panel, a blank cell, a skipped record, `|| []` in a source) and test that case too.
- Name private modules after your story and never after a model shape or a core module: inside
  `module Agentmon::Metrics::ProcessRates`, `ProcessRates.new` would mean the module, not the
  model (this bit the first articles; that module is `Metrics::Rates`). `grep -rn "module <Name>\|class <Name>\|<Name> = Data" lib/` first.
- Tests are machine-independent: `test/support/fixtures.rb` (`Fixtures.process`, `.sample`,
  `.machine`, `.engine`, `.reading`, `Fixtures::Clock`). Dashboard tests use
  `test/support/dashboard.rb`, as `test/ui/processes_test.rb` does, inside
  `with_engine(Fixtures.engine(...))`: `dashboard_app` (installed, feeds refreshed, keys on the
  Processes panel), `app.press`, and `dashboard_frame(app, focus: :process)` (200x50 plain text,
  focus set explicitly first; `focus: nil` keeps the current one). Never build `R2UI::App` or call
  `app.frame(w, h)` with a small size yourself: other stories' panels share the screen, so rows
  fall off a small frame, columns truncate, and r2ui gives keys to the first panel with a table.
  Press keys meant for another panel after `focus_panel(app, :name)`. Command tests use `R2UI::CLI::Testing#run_cli`
  against `Agentmon::Program.build`. Live macOS checks go in `test/live/<file>_test.rb`, start with
  `macos!`, stay few and fast, and never assume root.
- Test file per story: `test/<dir>/<file>_test.rb` for `lib/agentmon/<dir>/<file>.rb`.
- Test class names are `<Story><Kind>Test`, Kind one of `Probe`, `Metric`, `Recorder`, `Panel`
  (anything in `ui/`), `Command`, `Live`, `Core`: `MemoryProbeTest`, `MemoryMetricTest`,
  `MemoryPanelTest`, `MemoryCommandTest`, `MemoryLiveTest`. `test/probes/memory_test.rb` and
  `test/metrics/memory_test.rb` both exist; with one class name, the second file would reopen the
  first's class and silently replace same-named test methods. Helper classes inside a test go
  inside its test class.
- Sampling must stay under ~100 ms a tick: no subprocess per process (Fiddle, or one subprocess for
  the whole machine), anything slower behind `every:`.
- Numbers: units as above; rates only between samples with the same process identity; totals over
  a process tree count each process once.
- Keys and DSL names are reserved per story (table below); use only yours. r2ui's core keys
  (tab, `[` `]`, g, s/S, /, enter/space, z, q, arrows, j/k) are taken.
- The file's header comment is the user documentation: what it shows or does, with an example.

## Story list

Done here (first articles): **d00** = the core, probes `processes` and `cwd`, metrics
`process_rates`, `sessions`, `session_ledger`, `process_rows`, the Processes panel, `agentmon`
(dashboard) and `agentmon top`.

### Data

| Id | Capability | Reserves | Acceptance criteria | New files |
|---|---|---|---|---|
| a01-memory-probe | System memory counters | probe `memory`; module `Probes::Memory` | `sample[:memory]` is a `MemoryStat` read without subprocesses: `host_statistics64(HOST_VM_INFO64)` through Fiddle for page counts (pages x `vm_kernel_page_size` → bytes), `sysctlbyname` for `hw.memsize`, `vm.swapusage` (struct `xsw_usage`), `vm.page_pageable_internal_count` and `kern.memorystatus_level`. `app` = internal − purgeable pages, `cached` = file-backed + purgeable, `compressed` = pages occupied by the compressor, `compressor_stored` = pages stored in it; swapins/swapouts/compressions/decompressions/pageins are cumulative bytes. Decoding is a pure function tested on recorded struct bytes; a live test checks `app + wired + compressed <= total`, `total == hw.memsize` and that a read takes < 5 ms. | `lib/agentmon/probes/memory.rb`, `test/probes/memory_test.rb`, `test/live/memory_live_test.rb` |
| a02-memory-metric | Activity Monitor breakdown, rates, pressure | metric `memory`; module `Metrics::MemoryBreakdown` | `reading[:memory]` is a `MemoryView` (nil when `sample[:memory]` is nil): `used = app + wired + compressed`, `compression_ratio = compressor_stored / compressed` (0.0 when nothing is compressed), swap-in/out, compression and decompression rates in bytes/s from counter deltas over the monotonic interval (0.0 on the first sample, never negative, a counter that went backwards after sleep gives 0.0), `pressure = 100 − memorystatus_level`, `pressure_trend` the last 60 pressures, oldest first (metric state). Tested with fixture `MemoryStat`s. | `lib/agentmon/metrics/memory.rb`, `test/metrics/memory_test.rb` |
| a03-pressure-drivers | Which sessions drive memory pressure | metric `pressure_drivers`; module `Metrics::Drivers` | `reading[:pressure_drivers]` lists alive sessions from `reading[:session_ledger]` as `PressureDriver`s, largest footprint first: `share` = footprint / `reading[:memory].used` x 100 (nil when memory is unknown), `growth_rate` = footprint change per second over the last 60 s of samples (metric state, per session id; 0.0 until two samples). Sessions with zero footprint are left out. Tested with preset `session_ledger` and `memory` values across several readings. | `lib/agentmon/metrics/pressure_drivers.rb`, `test/metrics/pressure_drivers_test.rb` |

### Dashboard

| Id | Capability | Reserves | Acceptance criteria | New files |
|---|---|---|---|---|
| a04-memory-panel | RAM deep dive panel | resource and panel `memory` (row `:top`, order 10, span 1) | A `:memory` resource over `engine.current[:memory]` (one record) with attributes in r2ui formats; the panel shows a used/total gauge, stats for app, wired, compressed, compression ratio, cached, swap used, swap in/out and compression rates, a pressure sparkline, and (a `view` item) the top three pressure drivers as "label  footprint  share%  +growth/s". A frame test with preset `memory` and `pressure_drivers` values shows each number in its unit; with no memory value the panel shows no numbers and doesn't raise. | `lib/agentmon/ui/memory.rb`, `test/ui/memory_test.rb` |
| a05-sessions-panel | Agent sessions panel | resource and panel `session` (row `:top`, order 20, span 2) | A `:session` resource over `engine.current[:session_ledger]` keyed by `id`: label, processes, CPU % (sparkline), footprint (sparkline), peak, CPU seconds, written, read/write rates, age ("12m"); sorted by CPU; scopes "Live" (default, alive) and "All" (with ended ones, whose label ends in "· ended 3m ago"). Frame tests over fixture engines show a session's sums equal its members', and an ended session only under All. | `lib/agentmon/ui/sessions.rb`, `test/ui/sessions_test.rb` |
| a06-process-detail | Detail pane for the selected process | panel `detail` (row `:main`, order 200, span 1); module `UI::ProcessDetail` | A panel with no resource whose `view` shows the row selected in the `:process` panel (found through `app.panel_state`/`app.panel_lines`, whatever panel has focus): full command line (`ps -o args= -p PID`, one call when the selection changes, cached), cwd, session, footprint vs resident vs peak footprint, CPU time, disk written, started ("2h 5m ago"), open file count (Fiddle `proc_pidinfo(PROC_PIDLISTFDS)` size / 8, nil when unreadable). Unreadable processes say "not readable without root" for the rusage fields. Frame test with an injected command reader; a live test reads this process's open file count. | `lib/agentmon/ui/process_detail.rb`, `test/ui/process_detail_test.rb`, `test/live/process_detail_live_test.rb` |
| a07-process-actions | Terminate / kill with confirm | keys `K` (terminate), `X` (kill); `extend_resource(:process)` actions `terminate`, `kill` | `K` sends TERM and `X` sends KILL to the selected process (all rows of a selected group), each after r2ui's y/n confirm; pid 1, pid 0 and agentmon itself are refused with a flash message; EPERM and ESRCH show "terminate failed: ..." instead of raising. Tests press the keys on a fixture dashboard with the signal sender injected and assert who got which signal. | `lib/agentmon/ui/process_actions.rb`, `test/ui/process_actions_test.rb` |
| a08-process-scopes | Quick filters | `extend_resource(:process)` scopes `busy`, `heavy`, `writing` | Three more scopes on the process table, after Agents and All: Busy (CPU > 5%), Heavy (footprint > 500 MiB), Writing (write rate > 0); `]` cycles to them and the table shows only matching rows; `/` search still applies inside a scope. Frame tests over a fixture machine. | `lib/agentmon/ui/process_scopes.rb`, `test/ui/process_scopes_test.rb` |
| a09-mouse-and-help | Mouse and a help overlay | dashboard `mouse`; key `?`; r2ui extension `agentmon_help` | `Agentmon.dashboard { mouse :cell }`: clicks focus panels and select rows, the wheel scrolls. `?` toggles a full-screen help overlay (an r2ui extension's `view_override` registered in this file; no bubbles gem) listing every key from `app.hint_pairs` plus agentmon's own (`K`, `X`, `?`), and what each panel shows; any key closes it. Tests: click/wheel messages select rows; `?` shows and hides the overlay. | `lib/agentmon/ui/interaction.rb`, `test/ui/interaction_test.rb` |
| a10-theme-and-title | Look and window title | dashboard `theme`, `window_title` | A theme (r2ui s18) with an accent for sessions and alert colours for pressure; the window title is "agentmon · N sessions · P% pressure" (pressure left out while `reading[:memory]` is unavailable), updated as it changes. Tests read the title command and the styles. | `lib/agentmon/ui/theme.rb`, `test/ui/theme_test.rb` |

### History and command line

| Id | Capability | Reserves | Acceptance criteria | New files |
|---|---|---|---|---|
| a11-session-recorder | Session history | recorder `sessions` | Every 10 s, one `sessions` store line per alive session (`Session#to_record`), plus exactly one final line for each session the first time it is seen ended (the ended ids it wrote live in the recorder's state Hash, so two engines don't share them). Engine test with a temp store and fixture samples: lines, fields and units round-trip; an ended session's final line has `ended_at`. | `lib/agentmon/recorders/sessions.rb`, `test/recorders/sessions_test.rb` |
| a12-memory-recorder | Memory history | recorder `memory` | Every 10 s, one `memory` line (`MemoryView#to_h` without `pressure_trend`); nothing while `reading[:memory]` is nil. Engine test with preset values and a temp store. | `lib/agentmon/recorders/memory.rb`, `test/recorders/memory_test.rb` |
| a13-sessions-command | `agentmon sessions` | command `sessions` | Lists live sessions now (engine ledger): label, processes, CPU %, footprint, peak, CPU s, written, age, as an r2ui `table` (boxed on a terminal, plain aligned columns in a pipe); `--all` adds ended ones; `--json` prints one JSON object per line with raw units (bytes, seconds) for scripts; "No agent sessions running." when empty (exit 0). run_cli tests over fixture engines. | `lib/agentmon/commands/sessions.rb`, `test/commands/sessions_test.rb` |
| a14-report-command | `agentmon report [--since 2h]` | command `report` | Reads `sessions` lines from the store since `--since` (`90m`, `2h`, `3d`; default 24h; a bad value is a usage error), merges them by id (maxima, see "Store records"), and prints an npm-quality summary: a heading with the period, one table row per session (label, started, duration, peak footprint, CPU seconds, written, ended/running), where a session without `ended_at` whose last line is older than 60 s is shown ended at its last seen time ("ended (not seen after 14:02)"), never running (see "Store records"; a test covers a store whose writer stopped mid-session), then totals ("4 sessions · 3h 12m CPU · 2.1G written") with r2ui CLI helpers (`heading`, `table`, `duration`, `plural`); `--json` prints merged records; an empty period says so. run_cli tests over a temp store written with fixture lines. | `lib/agentmon/commands/report.rb`, `test/commands/report_test.rb` |
| a15-record-command | `agentmon record` | command `record` | Runs the engine headless with recording on (`--interval`, default 2 s) until ctrl+c or TERM, printing one status line per minute ("recording 3 sessions to …") off a terminal and a live line on one; `--prune 14` deletes day files older than 14 days at start. Exits 0 on TERM, 130 on ctrl+c, with the store flushed. Test drives it with a fixture engine and a stop flag. | `lib/agentmon/commands/record.rb`, `test/commands/record_test.rb` |
| a16-memory-command | `agentmon memory` | command `memory` | Prints the RAM breakdown now with r2ui `pairs` (Total, Used, App, Wired, Compressed (ratio), Cached, Swap used/total, swap in/out and compression rates, Pressure %), then the top pressure drivers; `--json` raw. Plain in a pipe. run_cli test with preset values. | `lib/agentmon/commands/memory.rb`, `test/commands/memory_test.rb` |
| a17-tree-command | `agentmon tree [SESSION]` | command `tree` | Prints each session's process tree with r2ui `tree` (pid name · footprint · CPU %), the session label as root; an argument (id, root pid or label substring) narrows it to one session; unknown → exit 1 with the list of sessions. run_cli test over the fixture machine. | `lib/agentmon/commands/tree.rb`, `test/commands/tree_test.rb` |
| a18-cli-options | Version, completion, trace | root keywords `version`, `completion`, `trace_option`, `color_option` | `Agentmon.cli { ... }` adds `agentmon --version` ("agentmon 0.1.0"), `agentmon completion zsh\|bash\|fish`, `--trace` and `--[no-]color` from r2ui's CLI extensions. run_cli tests. | `lib/agentmon/commands/cli_options.rb`, `test/commands/cli_options_test.rb` |

Stories never depend on each other's code. Pairs that meet through a shape: a01 → a02 → a03, a04,
a10, a12, a16 (`MemoryStat`, `MemoryView`, `PressureDriver`); a11 → a14 (store kind `sessions`).

## Follow-ups (not stories yet)

- `--json` for `agentmon top` needs an edit to `commands/top.rb` (a contract-sized change).
- Session-long sparklines (r2ui keeps 120 points per series: 4 minutes at 2 s) need a downsampled
  history metric plus a way to feed it to a column's sparkline, which r2ui doesn't have.
- GPU and energy (`ri_billed_energy`, `ri_energy_nj` are already in rusage v4) per session.
- A launchd agent for `agentmon record` (install/uninstall commands).
- Processes reparented to launchd stop counting toward their session; following them by
  process group would keep them.
