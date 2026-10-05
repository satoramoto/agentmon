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

Cost (agentmon's own CPU, 100×50, 20 s in a pty, this Mac): default dashboard 3.8%; dense 10.6%
/ 4.4% (motion / `--no-motion`), focus 14.2% / 5.8%, visual 14.3% / 6.3%. A frame costs ~16 ms in
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
| `top resource, by: nil, limit: nil, columns: nil, group_by: nil, widths: {}, spark: true` | the resource's r2ui table with `motion: true`, only `columns:` (in that order), sorted by `by:` desc. Percent columns draw heat, bytes the accent, the sort column a braille sparkline (`spark: false` leaves it off in narrow panels). Text columns get fixed widths (name 18, session 16, cwd 20, label 18; `widths:` overrides) so values are cut at a word boundary by agentmon, not mid-word by r2ui; columns drop by priority when the panel is narrow | rest of the panel |
| `band :session, show: %i[cpu footprint]` | the machine tile, then one tile per live session side by side: label, a CPU meter, the `show` values and a braille spark; the focused session's tile in the accent border; `←`/`→` (and `h`/`l`) pick a tile, Enter focuses that session (`engine.focus=`), Escape clears. Tiles are at least 18 cells wide (a `claude 12345` title fits uncut); more sessions than fit show a `+N` tail. No status-bar hint (r2ui drops all hints when one more doesn't fit) | rest of the panel |
| `detail :process, columns: 1` | the Detail panel for the selected process (`UI::ProcessDetail.lines`): its heading (name, pid) on a full-width line, the pairs reflowed into `columns` columns under it; a wide drawer under the table uses 3 | rest of the panel |
| `use :name, span: nil, title: nil` | an existing registered agentmon panel (`:memory`, `:session`, `:process`, `:detail`, `:session_memory`) at this spot, as the row-level word `use` | its own |

`use` is a row-level word (beside `panel`); the others are panel items. A `panel` with only view
items takes `resource: nil` implicitly.

Every word fits its width: labels are padded, values right-aligned, a label too long is cut with
`…` at a word boundary when one exists (a space or `·`, `-`, `,`, `:`, `/`: `bare-modifier…`),
never mid-word; paths are cut from the left (`…/long/repo`). A widget given less height than it needs
draws its first lines; it never wraps.

## Running a view

```
agentmon --layout visual        # one of dense, focus, visual (the registered views)
agentmon --layout visual | cat  # one plain frame, for tests and reviews
agentmon --no-motion            # no animation (also AGENTMON_MOTION=0)
```

Without `--layout` the dashboard is today's (rows and panels from `Agentmon.row`/`Agentmon.panel`).
`Agentmon.view` registers a view (`registry` kind `:view`); `UI.install(engine:, view: name)` builds
the r2ui dashboard from the view's rows instead of the registry layout. The views layer is an
r2ui extension (`R2UI.extension :agentmon_views`) with `dsl :panel` keywords and `panel_item`
drawers, in `lib/agentmon/views.rb` + `lib/agentmon/views/*.rb`; tests in `test/views/`.

Testing: `test/support/dashboard.rb` gets `dashboard_app(view: :visual)` and frames are taken at
**100×50** for the three layouts (the owner's window), beside the default 200×50.

## The three directions (all 100×50, nothing wrapped or cut mid-word, no empty rows of panels)

Each is one file, `lib/agentmon/views/<name>.rb`, written in the DSL above and nothing else (if a
layout needs a word the DSL lacks, add the word to the DSL, not a one-off `view {}` block).

**dense** — htop-like, everything on one screen, no side pane.
Rows: a 4-line machine strip in three panels (CPU: `spark` CPU and user, `stat` load 1/5/15 and
cores; Memory: `spark` used, pressure, swap, compressed; I/O: `spark` net in/out, disk read/write),
a 9-line Sessions table (`top :session` with label, procs, CPU, footprint, age), the Processes
table taking the rest (`top :process` with pid, name, session, CPU, footprint, wait, pgin/s, read,
write, no sort sparkline so all nine fit at 100 columns; columns drop by priority as the width
shrinks), and a 7-line `detail :process, columns: 3` drawer at the bottom. Keys as today
(Enter/F/esc for focus work on the Sessions table).

**focus** — session-first. A 7-line `band :session` across the top; under it, for the focused
session (or all agent sessions together when none, so the machine state is never empty): a 9-line
row with the session's memory (`meter` footprint of machine used, `stat` resident, wired, growth,
pageins/s, a footprint `trend`) beside its CPU (`stat` procs, read, write and a CPU `trend`); then
its processes (`top :process` with name, cpu, footprint, wait) beside `detail :process` with the
session's read and write `trend`s under it (span 3:2). The band shows which session is focused;
Escape returns to the machine.

**visual** — gauges, areas and heat. Top row (11 lines): CPU `meter` + `trend` + load `stat`
beside Memory `meter` used/total, pressure, swap + `stat` + a used `trend`. Middle row (9 lines):
Network `trend` in/out beside Disk `trend` read/write. Bottom: `top :process` (fills the panel)
with name, session, cpu (heat + braille), footprint, beside a Sessions panel: all agents' CPU and
footprint `trend`s (`height: 0.65`) over a `top :session` with label, cpu, footprint (span 3:2).
Heat colours everywhere a fraction exists; the accent for bytes.

Each layout's file starts with a comment showing its frame (the real one, from `| cat`).

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
