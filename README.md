# agentmon

What AI coding agents (Claude, Codex) cost your Mac: per-session CPU, real memory, disk and network I/O, memory pressure, and a history of runs, in your terminal.

## Install

With Homebrew (brings its own Ruby):

```
brew install satoramoto/tap/agentmon
```

Or as a gem:

```
gem install agentmon
```

Requirements: macOS; the gem needs Ruby 3.3 or newer. No root needed (other users' processes show only what `ps` gives). The network columns come from `nettop`, which ships with macOS; without it they show as unknown and the rest works.

## Usage

```
agentmon                    # live dashboard, dense layout
agentmon --layout visual    # gauges, areas and heat
agentmon --layout classic   # the original dashboard: sessions, memory, processes, detail
agentmon --no-motion        # no animation (also AGENTMON_MOTION=0)
agentmon | cat              # one plain frame, no terminal needed
agentmon top --once         # agent processes by CPU, one plain table
agentmon --help             # every command and option
```

Commands:

| Command | Shows |
|---|---|
| `top` | Agent processes by CPU, with footprint and disk I/O (`--once`, `--all`, `--sort`, `--session`, `-n`) |
| `sessions` | Agent sessions now, with CPU, real memory and lifetime totals (`--all` adds recently ended, `--json`) |
| `tree [SESSION]` | Process tree of each agent session, with footprint and CPU |
| `memory` | RAM breakdown, pressure and the sessions driving it (`--json`) |
| `footprint` | Real memory by session: footprint, share, growth, paging (`--json`) |
| `record` | Record sessions to the history until ctrl+c (`--interval`, `--prune DAYS`) |
| `report` | Sessions recorded over a period: peak memory, CPU, disk writes (`--since 2h`, `--json`) |
| `completion zsh\|bash\|fish` | A shell completion script |

Every command takes `--version`, `--color`/`--no-color` and `--trace`. Off a terminal, output is plain text for scripts.

## Layouts

- **dense** (default): an htop-like strip of machine CPU, memory and I/O, the Sessions table, and all agents together. Enter on a session drills into it: its CPU, memory and network, its processes, connections and a detail drawer.
- **visual**: the same content as meters, braille area charts and heat colours.
- **classic**: the first dashboard: Sessions, Memory, Processes and the Detail panel side by side.

## Keys

| Key | Does |
|---|---|
| `enter` | Open the selected session (dense, visual) |
| `F` | Open the selected process's session |
| `esc` | Back to all sessions; clears a search |
| `tab` / `shift-tab` | Next / previous panel |
| `↑` `↓` `j` `k` | Move the selection |
| `[` `]` | Previous / next scope: Agents, All, Busy, Heavy, Writing, Waiting |
| `g` | Group by session, directory, name, or as a tree |
| `s` / `S` | Next sort column / reverse |
| `/` | Search: free text, or `footprint>500M`, `cpu>5`, `session~repo` |
| `z` | Zoom the focused panel |
| `K` / `X` | Terminate (TERM) / kill (KILL) the selected process or group, after a y/n |
| `?` | Help: every key and what each panel shows |
| `q` | Quit |

The mouse works too: click focuses a panel and selects a row, the wheel moves the selection.

## What the numbers mean

- **Session**: a `claude` or `codex` CLI and everything under it (its outermost one), or a desktop app (Claude, ChatGPT/Codex) and its children. Labelled `claude 4242 · repo`.
- **CPU**: percent of one core, so 250% is two and a half cores. A session's CPU is the sum of its processes.
- **Footprint** (real memory): the kernel's `phys_footprint`, what Activity Monitor calls Memory. It counts compressed pages, unlike resident size, which is also shown.
- **Disk read/write**: bytes per second from each process's own I/O counters. Session totals add each process's growth, so very short-lived tools may be missed.
- **Network in/out**: bytes per second per process and connection, from one `nettop` stream; hosts and connections are counted per session. A session with a sudden spike or many remote hosts is marked `⚑`.
- **Memory pressure**: `100 − kern.memorystatus_level`, in percent; the Memory panel lists which sessions push it (footprint share and growth per second).
- **Wait** and **page-ins**: time runnable but waiting for a CPU, and page-ins per second (each one waited for the disk).
- **Lifetime totals** (CPU seconds, written, peak footprint): counted from when agentmon sees the session; nothing in a process tree is counted twice.

Unknown values (an unreadable process, the first sample's rates) are blank, never 0. Sizes are binary (`1.5G` = 1.5 × 1024³ bytes).

## History

While the dashboard is open, or under `agentmon record`, agentmon writes one JSON line per session (and the memory breakdown) every 10 seconds to `~/.local/state/agentmon/<kind>/YYYY-MM-DD.jsonl` (or `$XDG_STATE_HOME/agentmon`, or `$AGENTMON_STATE_DIR`). `agentmon report` reads it; `agentmon record --prune 30` deletes days older than 30.

## Development

agentmon is built on [r2ui](https://github.com/satoramoto/r2ui). With an r2ui checkout beside this one (`../r2ui`), the Gemfile uses it; otherwise it uses r2ui's `main` on GitHub.

```
bundle install
bundle exec rake test
bundle exec exe/agentmon
```

See [AGENTS.md](AGENTS.md) for targeted tests, [docs/design.md](docs/design.md) for the architecture and [docs/releasing.md](docs/releasing.md) for releases.

## License

MIT, see [LICENSE.txt](LICENSE.txt).
