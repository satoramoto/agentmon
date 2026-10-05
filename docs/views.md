# Views: a performance-view DSL (prototype, branch `proto/design-directions`)

agentmon's ethos: r2ui is the UI framework; agentmon is *the UI framework for performance
monitoring*. A ten-line view definition must already look good: coloured, animated, fitting the
window, with nothing wrapped or cut mid-word. Agent sessions are one lens (a grouping of
processes), not the whole product; a view of the machine, of one process or of memory pressure is
defined the same way.

This document is the contract for the prototype. It is not a story and nothing here merges as is:
the three layouts below exist so the owner can run them in a 100×50 terminal and pick a direction.

## Vocabulary

**Signal.** A named number on the machine with a unit: `"system.cpu"` is `reading[:system].cpu`,
`"memory.used"` is `reading[:memory].used`. The part before the dot is a metric name, the part
after a member of the value it returns (a `Data` member or a Hash key). A signal that is nil (metric
missing, first sample) draws as unknown, never as 0.

Signals carry defaults from a small table (`lib/agentmon/views/signals.rb`): label, unit and
natural maximum. Unknown signals fall back to inference from the member name (`*_rate` → bytes/s,
`cpu`/`pressure`/`share`/`user`/`system` → percent with max 100, `load*` → number, else bytes).
Any widget takes `label:`, `unit:` and `max:`/`of:` overrides.

| Unit | Format | Example |
|---|---|---|
| `:percent` | r2ui `:percent` | `42.0%` |
| `:bytes` | r2ui `:bytes` | `1.5G` |
| `:bytes_per_sec` | r2ui `:bytes_per_sec` | `3.2M/s` |
| `:number` | r2ui `:number` | `1.52` |
| `:integer` | r2ui `:integer` | `10` |

**The `focus` metric.** `"focus.*"` signals are the focused session, else every alive agent session
together (`Signals::Focus.value`; the reading is already narrowed while a session is focused):
`cpu` (percent of the machine), `processes`, `read_rate`, `write_rate` (ledger), `footprint`,
`resident`, `wired`, `peak_footprint`, `growth_rate`, `pagein_rate` (session memory), and from
`reading[:session_network]`:

| Signal | Label | Unit | Sums |
|---|---|---|---|
| `focus.net_in_rate` | net in | bytes/s | `in_rate` |
| `focus.net_out_rate` | net out | bytes/s | `out_rate` |
| `focus.bytes_in` | received | bytes | `bytes_in` |
| `focus.bytes_out` | sent | bytes | `bytes_out` |
| `focus.connections` | conns | integer | `connections` |
| `focus.remote_hosts` | hosts | integer | `remote_hosts` (per session, so a host two sessions share counts twice) |

An unknown metric stays unknown (nil, never 0); an empty list sums to 0. While one session is
focused, `trend "focus.net_in_rate"` / `"focus.net_out_rate"` draw that session's own
`in_trend` / `out_trend`; otherwise the views History keeps the series.

**History.** The views layer keeps the last 120 values (four minutes at 2 s) of every signal a
view draws, appended once per new Reading (keyed by `reading.at`), so `trend "memory.used"` works
for any signal without the metric storing a `*_trend`. Metrics that already keep a trend
(`memory.pressure_trend`, `system.cpu_trend`, ...) are used when a signal names them.

**Motion.** Every widget animates through r2ui's `R2UI::Motion` (`app.motion` / `motion` in a
Context): bars ease to a new value over 0.35 s (`tween`), a value that changed flashes in the
accent colour and fades over 0.5 s (`pulse`), tables mark moved and new lines in a gutter
(`motion: true`). Animation runs in a burst after each 2 s sample at 10 fps (`program_options`);
frames are drawn only while something moves (r2ui `App#frame_due?`), so the screen is idle
between samples. The gutter marks don't keep frames going on their own (a process list reorders
on nearly every sample, which would mean 20 fps forever): they fade with the burst's frames and go
at the next sample. `--no-motion` (and `AGENTMON_MOTION=0`) turns it off.

Cost (agentmon's own CPU, 100×50, 20 s after a 5 s warm-up in a pty, this Mac, with motion):
dense 9.1% (7.7% before the sessions-first rework), visual 9.4% (12.1% before), plus nettop's
own 1.2–1.7% for per-session network. Earlier: default dashboard 3.8%; dense 10.6% / 4.4% (motion /
`--no-motion`), visual 14.3% / 6.3%. A frame costs ~16 ms in
r2ui (`Canvas#write_ansi` measures every character's width; the bubbletea renderer rewrites every
line every frame), so motion costs ~3 frames' worth per sample; the drawn strings are cached
(braille areas per series, headers per pulse level) so agentmon's own share is small.

**Colour.** 24-bit where the terminal has it: heat (`Glyphs.heat`) runs green → amber → red over
a fraction (`#5FAF5F`, `#E5A50A`, `#E5484D`); the accent is `#D97757`; dim is `#555555`. Percent
cells and bars take heat by their fraction; bytes take the accent; unknown values are dim.

## The DSL

```ruby
Agentmon.view :visual, title: "agentmon" do
  row height: 9 do
    panel :cpu, title: "CPU" do
      meter "system.cpu"                                 # busy ▕████▎     ▏ 42%
      trend "system.cpu", height: 4                      # braille area of the last 4 min
      stat "system.load1", "system.load5", "system.load15"
    end
    panel :memory, title: "Memory", span: 1 do
      meter "memory.used", of: "memory.total"            # used ▕██████░░░▏ 23G / 32G 71%
      meter "memory.pressure"
      stat "memory.app", "memory.wired", "memory.compressed", "memory.swap_used", columns: 2
    end
  end
  row do
    top :process, by: :cpu, limit: 20, columns: %i[name session cpu footprint read_rate write_rate]
  end
end
```

The dashboard-level words are r2ui's (`title`, `row height:`, `panel name, title:, span:,
resource:`). Inside a panel, the view words are:

| Word | Draws | Lines |
|---|---|---|
| `meter sig, of: nil, max: nil, label: nil, heat: true` | `label ▕bar▏ value` or `value / total pct`; the bar is eighth-block precise (`Glyphs.bar`), eased, heat-coloured (or accent when `heat: false`) | 1 |
| `trend sig, ..., height: 3, label: nil, max: nil` | a label line (`label … current value`, value pulsing on change) and a braille area chart (`Glyphs.braille_area`), newest at the right, coloured by heat of the latest fraction (accent when the signal has no max). Several signals stack, sharing the height. `height: nil` takes the rest of the panel; a Float below 1 takes that share of what is left (labels included), e.g. `0.65` above a `top` | height + 1 per signal |
| `spark sig, label: nil, max: nil` | one line: `label ⣀⣀⣠⣴⣾⣿ value` (`Glyphs.braille_line`) | 1 |
| `stat sig, ..., columns: 2` | a label/value grid, `columns` per line (1 when the panel is narrower than 40), values pulse on change, percents heat-coloured | ceil(n / columns) |
| `top resource, by: nil, limit: nil, columns: nil, group_by: nil, widths: {}, spark: true` | the resource's r2ui table with `motion: true`, only `columns:` (in that order), sorted by `by:` desc. Percent columns draw heat, bytes the accent; `spark:` puts a braille sparkline (5 cells, percent ones heat-coloured on a 0–100 scale) on the sort column (`true`), on none (`false`, narrow panels) or on the listed columns (`spark: %i[cpu footprint net_out_rate]`). Sparklines are per resource on a view: one `top` asking for a column's sparkline puts it on every table of that resource in the view. Text columns get fixed widths (name 18, session 16, cwd 20, label 18; `widths:` overrides) so values are cut at a word boundary by agentmon, not mid-word by r2ui; columns drop by priority when the panel is narrow | rest of the panel |
| `band :session, show: %i[cpu footprint]` | the machine tile, then one tile per live session side by side: label, a CPU meter, the `show` values and a braille spark; the focused session's tile in the accent border; `←`/`→` (and `h`/`l`) pick a tile, Enter focuses that session (`engine.focus=`), Escape clears. Tiles are at least 18 cells wide (a `claude 12345` title fits uncut); more sessions than fit show a `+N` tail. No status-bar hint (r2ui drops all hints when one more doesn't fit) | rest of the panel |
| `detail :process, columns: 1` | the Detail panel for the selected process (`UI::ProcessDetail.lines`): its heading (name, pid) on a full-width line, the pairs reflowed into `columns` columns under it; a wide drawer under the table uses 3 | rest of the panel |
| `use :name, span: nil, title: nil` | an existing registered agentmon panel (`:memory`, `:session`, `:process`, `:detail`, `:session_memory`) at this spot, as the row-level word `use` | its own |

`use` is a row-level word (beside `panel`); the others are panel items. A `panel` with only view
items takes `resource: nil` implicitly.

### Drilling into a session: `focused`

```ruby
Agentmon.view :dense do
  row height: 6 do ... end                # home rows: shown while no session is focused
  row { top :session, by: :cpu, ... }
  focused do                              # shown instead while a session is focused
    row height: 8 do panel :s_cpu, title: "CPU" do ... end end
    row { top :process, ... }
    row height: 7 do detail :process, columns: 3 end
  end
end
```

`focused` is a view-level word (once per view, not nested) whose rows replace the home rows while
a session is focused (`engine.focus`, lib/agentmon/focus.rb). Named after the state it shows, as
in "the focused session", and matching `engine.focus` / `focus.*` signals; `drill`/`detail` would
clash with the `detail` word. Enter on the Sessions table (or a band tile) focuses that session, F
on a Processes row its session, Escape comes back (ui/session_focus.rb); a focused session that
leaves the ledger comes back on its own.

- **Layout.** Each set is laid out exactly as a view with only those rows: `row height:` is fixed
  lines (an Integer) or nil (rows without a height share what is left), and the last row of the
  set takes whatever remains. The r2ui dashboard holds both sets (so every panel has its feed and
  table state from the start) and `Views::Drill` swaps `dashboard.rows` to the visible set before
  every key and every frame: hidden panels are not on the dashboard, so they draw nothing, cost no
  drawing, and tab / shift-tab cycle only the visible ones. Panel names may repeat across the two
  sets (`:process` in both): lookups by name (`:session`, `:process`, `:detail`, used by session
  focus and the Detail panel) find the visible one. Feeds are per resource and keep refreshing
  as before; nothing samples more.
- **Key focus follows the mode.** Drilling in moves keys to the first table panel of the focused
  rows (the processes); coming back restores the home panel that had keys before. A view with a
  `focused` section opens with keys on its first home table (Sessions, when it comes first).
- **Status bar.** At home `sessions · ⏎ open a session`; drilled in `▸ claude 4242 · repo · esc
  back to sessions`. A probe or metric problem (`⚠ ...`) still wins. Views without `focused`, and
  the default dashboard, keep their status (`focus: ... (esc: all)` while focused).

### The anomaly mark

On a view, a session row whose `net_flags` is not empty shows `⚑ ` before its label, the label
cell in red (`#E5484D`), still cut at a word boundary to the column width. The metric decides
(metrics/network.rb, `SessionNetwork#flags`): a session is flagged when its net out (or in) rate
is ≥ 8× the median of its previous 30 known values and ≥ 1 MiB/s (`:out_spike`, `:in_spike`), or
when it talks to ≥ 20 distinct remote hosts (`:many_hosts`). The view only marks it; empty or
missing flags are normal.

Every word fits its width: labels are padded, values right-aligned, a label too long is cut with
`…` at a word boundary when one exists (a space or `·`, `-`, `,`, `:`, `/`: `bare-modifier…`),
never mid-word; paths are cut from the left (`…/long/repo`). A widget given less height than it needs
draws its first lines; it never wraps.

## Running a view

```
agentmon                        # the dense layout (the default)
agentmon --layout visual        # one of classic, dense, visual (classic plus the registered views)
agentmon --layout visual | cat  # one plain frame, for tests and reviews
agentmon --no-motion            # no animation (also AGENTMON_MOTION=0)
```

`agentmon` with no `--layout` opens dense. `--layout classic` is the panel dashboard (rows and
panels from `Agentmon.row`/`Agentmon.panel`; `UI.install(view: nil)`).
`Agentmon.view` registers a view (`registry` kind `:view`); `UI.install(engine:, view: name)` builds
the r2ui dashboard from the view's rows instead of the registry layout. The views layer is an
r2ui extension (`R2UI.extension :agentmon_views`) with `dsl :panel` keywords and `panel_item`
drawers, in `lib/agentmon/views.rb` + `lib/agentmon/views/*.rb`; tests in `test/views/`.

Testing: `test/support/dashboard.rb` gets `dashboard_app(view: :visual)` and frames are taken at
**100×50** for the three layouts (the owner's window), beside the default 200×50.

## The two directions (all 100×50, nothing wrapped or cut mid-word, no empty rows of panels)

Each is one file, `lib/agentmon/views/<name>.rb`, written in the DSL above and nothing else (if a
layout needs a word the DSL lacks, add the word to the DSL, not a one-off `view {}` block). Both
are sessions first: home is the session list (the biggest panel, sorted by CPU, keys on it), with
no all-processes table; Enter on a session (or F on a process) drills into it with `focused`, and
Escape returns. The machine breakdown stays on the home screen. The all-processes list is still one
key away: drill into a session and press `[`/`]` for the Processes table's All scope.

The focus layout (a band of session tiles over the focused session) is gone: its content is now
every layout's drill-down, and its band duplicated the session list. The `band` word stays.

**dense** — htop-like. Home: a 4-line machine strip (CPU: `spark` CPU and user, `stat` load and
cores; Memory: `spark` used, pressure, swap, compressed; I/O: `spark` net in/out, disk read/write),
the Sessions table taking the rest (`top :session` with label, procs, CPU, footprint, disk read and
write, net in and out; braille sparklines on CPU and net out, `spark: %i[cpu net_out_rate]`), and an
8-line all-agents strip (procs, resident, CPU and footprint `trend`s; remote hosts, connections and
net in/out `trend`s). Drilled in: a 5-line strip of the session's CPU (CPU, disk read/write
`spark`s, procs), Memory (footprint `meter` of machine used, footprint `spark`, resident, wired,
growth, pageins) and Network (net in/out `spark`s, received, sent, hosts, connections); its
Processes (`top :process` with pid, name, CPU, footprint, wait, read, write, net in, net out); a
9-line Connections table; a 7-line `detail :process, columns: 3` drawer.

**visual** — gauges, areas and heat. Home: CPU `meter` + `trend` + load beside Memory `meter`s +
`stat` + used `trend` (11 lines); Network and Disk `trend`s (8 lines); the Sessions table (label,
CPU, footprint, read, write, net in, net out; sparklines on CPU and net out); an all-agents row of
CPU/footprint and net in/out `trend`s (10 lines). Drilled in: the session's CPU `meter` + `trend` +
procs/read/write beside its footprint `meter` + memory `stat` + footprint `trend`; its Network and
Disk `trend`s; its processes (name, CPU, footprint, net out) beside the process `detail` (span
3:2); an 8-line Connections table.

Each layout's file starts with a comment showing its home frame (the real one, from `| cat`).

**Network data.** One long-lived `nettop -x -L 0 -s 1 -J interface,state,bytes_in,bytes_out`
child under a pty (piped, nettop block-buffers) streams every process's sockets once a second; a
reader thread parses each block into a `NetSnapshot` (lib/agentmon/probes/network.rb) and the probe
returns the latest. Connection mode (no `-P`) lists each process's line and its flows, so the
per-process totals and the per-connection rows come from the same stream. The child is killed on
quit, ctrl+c, exceptions and one-frame `| cat` runs (`at_exit`), dies with the pty if agentmon is
killed, and is restarted (at most every 10 s) if it dies; without nettop the network values are
unknown and the rest works. Cost on this Mac: nettop 1.2–1.7% of one core; a probe call ~2 µs.

## r2ui needs (prototyped on r2ui's `proto/design-directions`, listed for the real r2ui stories)

- `R2UI::Motion` (`lib/r2ui/motion.rb`), `App#motion`, `Context#motion`, `App#frame_due?`, the
  runner drawing only due frames, DEC 2026 synchronized output.
- `R2UI::Widgets::Glyphs` (braille line and area, eighth bars, heat and 24-bit SGR helpers).
- Column `style:`, `priority:`, `sparkline: :braille`, `spark_width:`, `spark_max:`, `spark_style:`.
- `table(columns: [...], motion: true)`; `row(height: callable)`; `panel(border_style:)`.
- Still missing after this prototype goes in the feedback file: a panel item that draws below a
  table (`renderer.rb:161`), a signed byte format, per-panel column widths, a word-boundary cut
  for flexible text columns (`widgets/table.rb` `fit`), a way to amend a column another file
  declared (views.rb edits `resource.columns`), a frame cost that doesn't scale with every cell
  (`canvas.rb:55` width per character, `compat/bubbletea/renderer.rb:63` rewrites every line),
  gutter marks that don't hold the motion for off-screen or shifted-by-one lines
  (`panel_state.rb:41`, `widgets/table.rb:57`), status hints that drop one by one rather than all
  at once (`renderer.rb` `draw_status`).
