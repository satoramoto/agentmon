# frozen_string_literal: true

# dense: htop-like, sessions first (docs/views.md). Home is the machine strip, every agent session
# with its CPU, footprint, disk and network, and all agents together; Enter on a session drills
# into it (its CPU, memory and network strip, its processes, connections and the process detail;
# Escape returns). Its real home frame, from
# `COLUMNS=100 LINES=50 bundle exec exe/agentmon --layout dense | cat` (one sample, so sparklines
# and areas are still empty and network rates still settling):
#
# ╭─ CPU ──────────────────────────────────╮╭─ Memory ─────────────────╮╭─ I/O ──────────────────────╮
# │CPU  ⣀⣀⣀⣀⣀⣀⣀⣀⣀⣀⣀⣀⣀⣀⣀⣀⣀⣀⣀⣀⣀⣀⣀⣀⣀⣀⣀⣀⣀ 23.2%││used     ⣀⣀⣀⣀⣀⣀⣀⣀⣀⣀⣀   23G││net in  ⣀⣀⣀⣀⣀⣀⣀⣀⣀⣀⣀⣀⣀ 605B/s│
# │user ⣀⣀⣀⣀⣀⣀⣀⣀⣀⣀⣀⣀⣀⣀⣀⣀⣀⣀⣀⣀⣀⣀⣀⣀⣀⣀⣀⣀⣀ 15.6%││pressure ⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⣀ 33.0%││net out ⣀⣀⣀⣀⣀⣀⣀⣀⣀⣀⣀⣀⣀ 1.1K/s│
# │load 1m         6.6  load 5m         6.5││swap     ⣀⣀⣀⣀⣀⣀⣀⣀⣀⣀⣀  310M││disk rd ⣀⣀⣀⣀⣀⣀⣀⣀⣀⣀⣀⣀⣀   0B/s│
# │load 15m        5.4  cores            10││compr    ⣀⣀⣀⣀⣀⣀⣀⣀⣀⣀⣀  6.9G││disk wr ⣀⣀⣀⣀⣀⣀⣀⣀⣀⣀⣀⣀⣀ 192K/s│
# ╰────────────────────────────────────────╯╰──────────────────────────╯╰────────────────────────────╯
# ╭─ Sessions ─[Live] All ───────────────────────────────────────────────────────────────────────────╮
# │ Session                 Procs          CPU▼  Footprint     Read    Write   Net in        Net out │
# │ claude 22602…               9 ⠀⠀⠀⠀⢀   14.5%       387M     0B/s     0B/s     0B/s ⠀⠀⠀⠀⢀     0B/s │
# │ Claude 21354               35 ⠀⠀⠀⠀⢀    5.6%       2.0G     0B/s     0B/s     0B/s ⠀⠀⠀⠀⢀     0B/s │
# │ ChatGPT 2388               17 ⠀⠀⠀⠀⢀    4.6%       2.6G     0B/s     0B/s     0B/s ⠀⠀⠀⠀⢀     0B/s │
# │ claude 42757…               1 ⠀⠀⠀⠀⢀    0.9%       218M     0B/s     0B/s          ⠀⠀⠀⠀⢀          │
# │ claude 26329…               1 ⠀⠀⠀⠀⢀    0.8%       243M     0B/s     0B/s          ⠀⠀⠀⠀⢀          │
# │ claude 22034…               1 ⠀⠀⠀⠀⢀    0.7%       174M     0B/s     0B/s     0B/s ⠀⠀⠀⠀⢀     0B/s │
# │ claude 36511…               1 ⠀⠀⠀⠀⢀    0.4%       217M     0B/s     0B/s          ⠀⠀⠀⠀⢀          │
# │ codex 2903                 13 ⠀⠀⠀⠀⢀    0.0%       744M     0B/s     0B/s     0B/s ⠀⠀⠀⠀⢀     0B/s │
# │ codex 3064…                 4 ⠀⠀⠀⠀⢀    0.0%        75M     0B/s     0B/s     0B/s ⠀⠀⠀⠀⢀     0B/s │
# │                                                                                                  │
#   ... 20 more empty table lines ...
# │                                                                                                  │
# ╰──────────────────────────────────────────────────────────────────────────────────────────────────╯
# ╭─ All agents ───────────────────────────────────╮╭─ Agents network ───────────────────────────────╮
# │procs                82  resident           9.1G││hosts                20  conns                56│
# │CPU                                         2.7%││net in                                      0B/s│
# │⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀││⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀│
# │⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀││⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀│
# │⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢀││⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀│
# │footprint                                   6.7G││net out                                     0B/s│
# │⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢸││⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀│
# │⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢸││⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀│
# ╰────────────────────────────────────────────────╯╰────────────────────────────────────────────────╯
#  sessions · ⏎ open a session
#
# Sessions has no Age column (it would push Write off at 100 columns); the drilled-in Processes
# table leaves the sort sparkline off so all nine columns fit.
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
                    widths: { label: 20 }
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
          meter "focus.footprint"
          spark "focus.footprint", label: "trend"
          stat "focus.resident", "focus.wired", "focus.growth_rate", "focus.pagein_rate", columns: 2
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
