# frozen_string_literal: true

# focus: session-first (docs/views.md). The band of sessions on top (←/→ pick, Enter focuses,
# Escape returns to the machine); under it the focused session's memory and CPU (every agent
# session together when nothing is focused, the "focus.*" signals), then its processes beside
# the selected one's detail and the session's disk I/O. The real frame, nothing focused, from
# `COLUMNS=100 LINES=50 bundle exec exe/agentmon --layout focus | cat`:
#
# ╭─ Sessions ───────────────────────────────────────────────────────────────────────────────────────╮
# │╭─ machine ───────╮╭─ ChatGPT 2388 ──╮╭─ codex 2903 ────╮╭─ codex 3064… ───╮╭─ +4 ───────────────╮│
# ││cpu ▕█     ▏  18%││cpu ▕▌     ▏   8%││cpu ▕      ▏   0%││cpu ▕      ▏   0%││4 more              ││
# ││used          22G││footprint    2.6G││footprint    143M││footprint     75M││→ to pick           ││
# ││ ⣀⣀⣀⣀⣀⣀⣀⣀⣀⣀⣀⣀⣀⣀⣀ ││ ⣀⣀⣀⣀⣀⣀⣀⣀⣀⣀⣀⣀⣀⣀⣀ ││ ⣀⣀⣀⣀⣀⣀⣀⣀⣀⣀⣀⣀⣀⣀⣀ ││ ⣀⣀⣀⣀⣀⣀⣀⣀⣀⣀⣀⣀⣀⣀⣀ ││                    ││
# │╰─────────────────╯╰─────────────────╯╰─────────────────╯╰─────────────────╯╰────────────────────╯│
# ╰──────────────────────────────────────────────────────────────────────────────────────────────────╯
# ╭─ Memory ───────────────────────────────────────╮╭─ CPU ──────────────────────────────────────────╮
# │footprint ▕█████▏               ▏ 5.4G / 22G 24%││procs       58  read      0B/s  write     0B/s  │
# │resident           7.8G  wired              720K││CPU, last 4 min                             3.7%│
# │growth           +10M/s  pageins             0/s││⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀│
# │footprint, last 4 min                       5.4G││⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀│
# │⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢸││⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀│
# │⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢸││⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀│
# │⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢸││⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢀│
# ╰────────────────────────────────────────────────╯╰────────────────────────────────────────────────╯
# ╭─ Processes ─[Agents] All  Busy  Heavy  Writing  Waiting ─╮╭─ Detail ─────────────────────────────╮
# │ Name                              CPU▼  Footprint   Wait ││Claude Helper  pid 21358              │
# │ Claude Helper            ⠀⠀⠀⠀⢀    9.7%       353M   4.4% ││Command    /Applications/Claude.app…  │
# │ claude                   ⠀⠀⠀⠀⢀    5.2%       187M   0.5% ││Directory  /                          │
# │ agentmon --layout focus  ⠀⠀⠀⠀⢀    4.6%        41M   0.3% ││Session    Claude 21354               │
# │ Claude Helper (Renderer) ⠀⠀⠀⠀⢀    4.1%       684M   2.4% ││Footprint  353M                       │
# │ Codex (Renderer)         ⠀⠀⠀⠀⢀    3.2%       773M   0.7% ││Resident   141M                       │
# │ Codex (Service)          ⠀⠀⠀⠀⢀    2.1%       383M   1.3% ││Peak       1.0G                       │
# │ Claude Helper (Renderer) ⠀⠀⠀⠀⢀    1.7%       178M   1.6% ││CPU time   2m 6s                      │
# │ ChatGPT                  ⠀⠀⠀⠀⢀    1.6%       328M   2.0% ││Written    192K                       │
# │ Claude                   ⠀⠀⠀⠀⢀    1.4%       259M   0.3% ││Started    26m 31s ago                │
# │ Claude Helper            ⠀⠀⠀⠀⢀    0.8%        10M   0.0% ││Open files 16                         │
# │ claude                   ⠀⠀⠀⠀⢀    0.5%       262M   0.7% ││Threads    19 (0 running)             │
# │ Codex (Renderer)         ⠀⠀⠀⠀⢀    0.5%       276M   0.6% ││CPU wait   4.4% now, 1m 8s total      │
# │ Claude Helper            ⠀⠀⠀⠀⢀    0.4%        25M   0.4% ││Page-ins   0/s, 1165 total            │
# │ Codex (Renderer)         ⠀⠀⠀⠀⢀    0.3%       226M   1.5% ││Faults     154/s (COW 0/s)            │
# │ claude                   ⠀⠀⠀⠀⢀    0.3%       171M   1.5% ││Switches   815/s                      │
# │ Codex (Service)          ⠀⠀⠀⠀⢀    0.2%        53M   0.3% ││Wired      0B                         │
# │ bare-modifier-monitor    ⠀⠀⠀⠀⢀    0.2%       7.6M   1.3% ││Read       0B/s, 20M total            │
# │ Claude Helper            ⠀⠀⠀⠀⢀    0.0%        19M   0.1% ││session read                      0B/s│
# │ Codex (Service)          ⠀⠀⠀⠀⢀    0.0%        24M   0.0% ││⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀│
# │ Claude Helper            ⠀⠀⠀⠀⢀    0.0%        22M   0.1% ││⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀│
# │ Claude Helper            ⠀⠀⠀⠀⢀    0.0%       117M   0.0% ││⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀│
# │ Claude Helper            ⠀⠀⠀⠀⢀    0.0%        20M   0.0% ││⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀│
# │ node                     ⠀⠀⠀⠀⢀    0.0%        35M   0.0% ││⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀│
# │ Codex (Renderer)         ⠀⠀⠀⠀⢀    0.0%        26M   0.0% ││session write                     0B/s│
# │ Codex (Renderer)         ⠀⠀⠀⠀⢀    0.0%        80M   0.0% ││⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀│
# │ codex-code-mode-host     ⠀⠀⠀⠀⢀    0.0%       9.2M   0.0% ││⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀│
# │ Codex (Service)          ⠀⠀⠀⠀⢀    0.0%        25M   0.0% ││⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀│
# │ Codex (Renderer)         ⠀⠀⠀⠀⢀    0.0%        34M   0.0% ││⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀│
# │ codex                    ⠀⠀⠀⠀⢀    0.0%        17M   0.0% ││⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀│
# │ Codex (Renderer)         ⠀⠀⠀⠀⢀    0.0%       117M   0.0% ││⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀│
# ╰──────────────────────────────────────────────────── 1/58 ╯╰──────────────────────────────────────╯
#  sort: CPU▼       ? help  tab panel  [ ] scope  g group  s/S sort  / search  ⏎ fold  z zoom  q quit
#
# Two trends under the detail (not one with two signals), since `label:` applies to every signal
# of one trend. A focused session with few processes leaves the table short: nothing draws below
# an r2ui table (renderer.rb:161).
module Agentmon
  view :focus, title: "agentmon" do
    row height: 7 do
      band :session, show: %i[cpu footprint]
    end
    row height: 9 do
      panel :focus_memory, title: "Memory" do
        meter "focus.footprint"
        stat "focus.resident", "focus.wired", "focus.growth_rate", "focus.pagein_rate", columns: 2
        trend "focus.footprint", height: nil, label: "footprint, last 4 min"
      end
      panel :focus_cpu, title: "CPU" do
        stat "focus.processes", "focus.read_rate", "focus.write_rate", columns: 3
        trend "focus.cpu", height: nil, label: "CPU, last 4 min"
      end
    end
    row do
      top :process, span: 3, by: :cpu, columns: %i[name cpu footprint run_wait], widths: { name: 24 }
      panel :detail, title: "Detail", span: 2 do
        detail :process
        trend "focus.read_rate", height: 0.5, label: "session read"
        trend "focus.write_rate", height: nil, label: "session write"
      end
    end
  end
end
