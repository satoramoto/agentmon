# frozen_string_literal: true

# dense: htop-like, sessions first (docs/views.md). Home is the machine strip, every agent session
# (by name when Claude Code or Codex knows one) with its CPU, footprint, disk and network, and all
# agents together; Enter on a session drills into it (its CPU, memory and network strip, its
# processes, connections and the process detail; Escape returns). Its real home frame, from
# `COLUMNS=100 LINES=50 bundle exec exe/agentmon --layout dense | cat` (one sample, so sparklines
# and areas are still empty and network rates still settling):
#
# ╭─ CPU ──────────────────────────────────╮╭─ Memory ─────────────────╮╭─ I/O ──────────────────────╮
# │CPU  ⣀⣀⣀⣀⣀⣀⣀⣀⣀⣀⣀⣀⣀⣀⣀⣀⣀⣀⣀⣀⣀⣀⣀⣀⣀⣀⣀⣀⣀ 38.2%││used     ⣀⣀⣀⣀⣀⣀⣀⣀⣀⣀⣀   25G││net in  ⣀⣀⣀⣀⣀⣀⣀⣀⣀⣀⣀⣀⣀ 843B/s│
# │user ⣀⣀⣀⣀⣀⣀⣀⣀⣀⣀⣀⣀⣀⣀⣀⣀⣀⣀⣀⣀⣀⣀⣀⣀⣀⣀⣀⣀⣀ 25.3%││pressure ⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⣤ 48.0%││net out ⣀⣀⣀⣀⣀⣀⣀⣀⣀⣀⣀⣀⣀ 1.1K/s│
# │load 1m         5.5  load 5m         6.2││swap     ⣀⣀⣀⣀⣀⣀⣀⣀⣀⣀⣀  255M││disk rd ⣀⣀⣀⣀⣀⣀⣀⣀⣀⣀⣀⣀⣀   0B/s│
# │load 15m        6.0  cores            10││compr    ⣀⣀⣀⣀⣀⣀⣀⣀⣀⣀⣀   11G││disk wr ⣀⣀⣀⣀⣀⣀⣀⣀⣀⣀⣀⣀⣀ 209K/s│
# ╰────────────────────────────────────────╯╰──────────────────────────╯╰────────────────────────────╯
# ╭─ Sessions ─[Live] All ───────────────────────────────────────────────────────────────────────────╮
# │ Session                  Procs          CPU▼  Footprint     Read    Write   Net in        Net out│
# │ Claude 21354                46 ⠀⠀⠀⠀⢀   41.1%       3.8G     0B/s     0B/s     0B/s ⠀⠀⠀⠀⢀     0B/s│
# │ Agentmon r2ui…               5 ⠀⠀⠀⠀⢀   13.7%       372M     0B/s     0B/s     0B/s ⠀⠀⠀⠀⢀     0B/s│
# │ ChatGPT 2388                18 ⠀⠀⠀⠀⢀    9.2%       3.3G     0B/s     0B/s     0B/s ⠀⠀⠀⠀⢀     0B/s│
# │ Project history…             1 ⠀⠀⠀⠀⢀    0.4%       285M     0B/s     0B/s          ⠀⠀⠀⠀⢀         │
# │ EPK component review…        1 ⠀⠀⠀⠀⢀    0.2%       262M     0B/s     0B/s          ⠀⠀⠀⠀⢀         │
# │ Weekly session themes…       1 ⠀⠀⠀⠀⢀    0.2%       181M     0B/s     0B/s     0B/s ⠀⠀⠀⠀⢀     0B/s│
# │ Mods in Desktop vs…          1 ⠀⠀⠀⠀⢀    0.1%       226M     0B/s     0B/s          ⠀⠀⠀⠀⢀         │
# │ Set up a Homebrew tap…       1 ⠀⠀⠀⠀⢀    0.1%       200M     0B/s     0B/s          ⠀⠀⠀⠀⢀         │
# │ Build Magrathea local…      25 ⠀⠀⠀⠀⢀    0.0%      1022M     0B/s     0B/s     0B/s ⠀⠀⠀⠀⢀     0B/s│
# │ codex 3064 · Resources       4 ⠀⠀⠀⠀⢀    0.0%        76M     0B/s     0B/s     0B/s ⠀⠀⠀⠀⢀     0B/s│
# │                                                                                                  │
#   ... 19 more empty table lines ...
# ╰──────────────────────────────────────────────────────────────────────────────────────────────────╯
# ╭─ All agents ───────────────────────────────────╮╭─ Agents network ───────────────────────────────╮
# │procs               103  resident           9.6G││hosts                19  conns                65│
# │CPU                                         6.5%││net in                                      0B/s│
# │⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀││⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀│
# │⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀││⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀│
# │⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢀││⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀│
# │footprint                                   9.6G││net out                                     0B/s│
# │⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢸││⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀│
# │⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢸││⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀│
# ╰────────────────────────────────────────────────╯╰────────────────────────────────────────────────╯
#  sessions · ⏎ open a session
#
# Drilled into "Agentmon r2ui integration" (a pty at 100×50: `/` integration, Enter). The Memory
# panel's RAM meter is the machine (25G of 32G used) with this session's footprint as the accent
# slice at the left, the rest of used memory dim and free memory empty:
#
# ╭─ CPU ─────────────────────────╮╭─ Memory ──────────────────────╮╭─ Network ──────────────────────╮
# │CPU     ⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢀⣀ 0.2%││RAM ▕▏████▌ ▏ 324M 1% · 25G/32G││net in  ⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢀⣸⣄⣀⣀ 0B/s│
# │disk rd ⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢀⣀ 0B/s││pressure                  47.0%││net out ⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢀⣀⣇⣀⣀ 0B/s│
# │disk wr ⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢀⣀ 0B/s││resident                   439M││received                    1.1K│
# │procs                         3││wired                        0B││sent                         51K│
# │cores                        10││growth                  +9.6K/s││hosts                          2│
# ╰───────────────────────────────╯╰───────────────────────────────╯╰────────────────────────────────╯
# ╭─ Processes ─[Agents] All  Busy  Heavy  Writing  Waiting ─────────────────────────────────────────╮
# │      Pid Name                      CPU▼  Footprint   Wait     Read    Write   Net in  Net out    │
# │    22602 claude                    1.6%       321M   1.6%     0B/s     0B/s     0B/s     0B/s    │
# │▴    6766 sleep                     0.0%       832K   0.0%     0B/s     0B/s     0B/s     0B/s    │
# │▾    6543 zsh                       0.0%       2.5M   0.0%     0B/s     0B/s     0B/s     0B/s    │
# │                                                                                                  │
#   ... 19 more empty table lines ...
# ╰──────────────────────────────────────────────────────────────────────────────────────────────────╯
# ╭─ Connections ────────────────────────────────────────────────────────────────────────────────────╮
# │ Process            Remote                         State             In     Out▼     Recv     Sent│
# │ claude 22602       160.79.104.10:443              Established     0B/s     0B/s      39K     2.9M│
# │ claude 22602       160.79.104.10:443              Established     0B/s     0B/s     918K     4.5M│
# │ claude 22602       160.79.104.10:443              Established     0B/s     0B/s     234K     540K│
# │ claude 22602       ….bc.googleusercontent.com:443 Established     0B/s     0B/s      26K     8.3M│
# │ claude 22602       160.79.104.10:443              Established     0B/s     0B/s      13K      25K│
# │ claude 22602       160.79.104.10:443              Established     0B/s     0B/s     3.2K     4.8K│
# ╰──────────────────────────────────────────────────────────────────────────────────────────────────╯
# ╭─ Detail ─────────────────────────────────────────────────────────────────────────────────────────╮
# │claude  pid 22602                                                                                 │
# │Command    /Users/ryan…          Resident   435M                  Started    3h 2m ago            │
# │Directory  ~/The Source…         Peak       368M                  Open files 21                   │
# │Session    Agentmon r2ui…        CPU time   4m 30s                Threads    24 (0 running)       │
# │Footprint  321M                  Written    109M                  CPU wait   1.6% now, 3m 23s…    │
# ╰──────────────────────────────────────────────────────────────────────────────────────────────────╯
#  ▸ Agentmon r2ui integration · claude 22602 · agentmon · busy · esc back to sessions
#
# Sessions has no Age column, and its label (the session's name first) is 23 wide with Procs at
# 5: one cell more pushes Write off at 100 columns. The drilled-in Processes table leaves the sort
# sparkline off so all nine columns fit.
module Agentmon
  view :dense, title: "agentmon" do
    # Home: the machine strip, every agent session with its breakdown, all agents together.
    row height: 6 do
      panel :cpu, title: "CPU", span: 3 do
        spark "system.cpu"
        spark "system.user"
        stat "system.load1", "system.load5", "system.load15", "system.ncpu", columns: 2
      end
      panel :memory, title: "Memory", span: 2 do
        spark "memory.used"
        spark "memory.pressure"
        spark "memory.swap_used"
        spark "memory.compressed", label: "compr"
      end
      panel :io, title: "I/O", span: 2 do
        spark "system.net_in_rate", label: "net in"
        spark "system.net_out_rate", label: "net out"
        spark "system.disk_read_rate", label: "disk rd"
        spark "system.disk_write_rate", label: "disk wr"
      end
    end
    row do
      top :session, title: "Sessions", by: :cpu, spark: %i[cpu net_out_rate],
                    columns: %i[label processes cpu footprint read_rate write_rate net_in_rate net_out_rate],
                    widths: { label: 23, processes: 5 }
    end
    row height: 10 do
      panel :agents, title: "All agents" do
        stat "focus.processes", "focus.resident", columns: 2
        trend "focus.cpu", "focus.footprint", height: nil
      end
      panel :agents_io, title: "Agents network" do
        stat "focus.remote_hosts", "focus.connections", columns: 2
        trend "focus.net_in_rate", "focus.net_out_rate", height: nil
      end
    end

    # Drilled into one session (Enter on Sessions, F on a process; Escape returns).
    focused do
      row height: 7 do
        panel :s_cpu, title: "CPU" do
          spark "focus.cpu"
          spark "focus.read_rate", label: "disk rd"
          spark "focus.write_rate", label: "disk wr"
          stat "focus.processes", "system.ncpu", columns: 2
        end
        panel :s_memory, title: "Memory" do
          # The machine's RAM with the session as the accent slice; pressure as a stat (a second
          # meter's "pressure" label would leave the RAM bar under 6 cells at 100 columns).
          meter "memory.used", part: "focus.footprint", label: "RAM"
          stat "memory.pressure", "focus.resident", "focus.wired", "focus.growth_rate", "focus.pagein_rate",
               columns: 2
        end
        panel :s_net, title: "Network" do
          spark "focus.net_in_rate"
          spark "focus.net_out_rate"
          stat "focus.bytes_in", "focus.bytes_out", "focus.remote_hosts", "focus.connections", columns: 2
        end
      end
      row do
        top :process, title: "Processes", by: :cpu, spark: false,
                      columns: %i[pid name cpu footprint run_wait read_rate write_rate net_in_rate net_out_rate],
                      widths: { name: 22 }
      end
      row height: 9 do
        top :connection, title: "Connections", by: :out_rate, spark: false, widths: { process: 18 },
                         columns: %i[process protocol remote_text state in_rate out_rate bytes_in bytes_out]
      end
      row height: 7 do
        detail :process, columns: 3
      end
    end
  end
end
