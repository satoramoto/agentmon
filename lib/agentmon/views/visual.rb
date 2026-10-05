# frozen_string_literal: true

# visual: gauges, areas and heat, sessions first (docs/views.md). Home is the machine's breakdown
# over every agent session (Enter on one drills into it: its CPU and memory gauges and areas,
# network and disk areas, processes beside the detail, connections; Escape returns). Its real
# home frame, from `COLUMNS=100 LINES=50 bundle exec exe/agentmon --layout visual | cat` (one
# sample, so areas and sparklines are still empty and network rates still settling):
#
# ╭─ CPU ──────────────────────────────────────────╮╭─ Memory ───────────────────────────────────────╮
# │CPU ▕█████████▌                          ▏ 26.4%││used     ▕███████████████▌     ▏   24G / 32G 74%│
# │last 4 min                                 26.4%││pressure ▕██████▉              ▏           33.0%│
# │⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀││swap     ▕███▏                 ▏ 310M / 2.0G 15%│
# │⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀││app                 14G  wired              3.1G│
# │⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀││compressed         6.9G  cached             7.4G│
# │⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀││used, last 4 min                             24G│
# │⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢠││⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢸│
# │⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢸││⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢸│
# │load 1m    5.6  load 5m    6.2  load 15m   5.3  ││⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢸│
# ╰────────────────────────────────────────────────╯╰────────────────────────────────────────────────╯
# ╭─ Network ──────────────────────────────────────╮╭─ Disk ─────────────────────────────────────────╮
# │net in                                    797B/s││disk read                                   0B/s│
# │⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢸││⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀│
# │⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢸││⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀│
# │net out                                   1.1K/s││disk write                                  0B/s│
# │⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢸││⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀│
# │⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢸││⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀│
# ╰────────────────────────────────────────────────╯╰────────────────────────────────────────────────╯
# ╭─ Sessions ─[Live] All ───────────────────────────────────────────────────────────────────────────╮
# │ Session                         CPU▼  Footprint     Read    Write   Net in        Net out        │
# │ claude 22602…          ⠀⠀⠀⠀⢀   16.2%       389M     0B/s     0B/s     0B/s ⠀⠀⠀⠀⢀     0B/s        │
# │ ChatGPT 2388           ⠀⠀⠀⠀⢀   12.9%       2.7G     0B/s     0B/s     0B/s ⠀⠀⠀⠀⢀     0B/s        │
# │ Claude 21354           ⠀⠀⠀⠀⢀    6.7%       2.0G     0B/s     0B/s     0B/s ⠀⠀⠀⠀⢀     0B/s        │
# │ claude 22034…          ⠀⠀⠀⠀⢀    1.1%       174M     0B/s     0B/s     0B/s ⠀⠀⠀⠀⢀     0B/s        │
# │ claude 36511…          ⠀⠀⠀⠀⢀    0.1%       210M     0B/s     0B/s          ⠀⠀⠀⠀⢀                 │
# │ claude 26329…          ⠀⠀⠀⠀⢀    0.1%       243M     0B/s     0B/s          ⠀⠀⠀⠀⢀                 │
# │ claude 42757 · yahaha  ⠀⠀⠀⠀⢀    0.1%       218M     0B/s     0B/s          ⠀⠀⠀⠀⢀                 │
# │ codex 2903             ⠀⠀⠀⠀⢀    0.0%       693M     0B/s     0B/s     0B/s ⠀⠀⠀⠀⢀     0B/s        │
# │ codex 3064 · Resources ⠀⠀⠀⠀⢀    0.0%        75M     0B/s     0B/s     0B/s ⠀⠀⠀⠀⢀     0B/s        │
# │                                                                                                  │
# │                                                                                                  │
# │                                                                                                  │
# │                                                                                                  │
# │                                                                                                  │
# │                                                                                                  │
# │                                                                                                  │
# │                                                                                                  │
# ╰──────────────────────────────────────────────────────────────────────────────────────────────────╯
# ╭─ All agents ───────────────────────────────────╮╭─ Agents network ───────────────────────────────╮
# │CPU                                         3.7%││net in                                      0B/s│
# │⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀││⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀│
# │⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀││⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀│
# │⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢀││⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀│
# │footprint                                   6.6G││net out                                     0B/s│
# │⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢸││⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀│
# │⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢸││⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀│
# │⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢸││⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀│
# ╰────────────────────────────────────────────────╯╰────────────────────────────────────────────────╯
#  sessions · ⏎ open a session
#
# The Sessions table leaves Procs off so disk read and write both fit at 100 columns; footprint has
# no sparkline (a flat footprint draws a full braille column, not a baseline).
module Agentmon
  view :visual, title: "agentmon" do
    # Home: the machine's breakdown, then every agent session.
    row height: 11 do
      panel :cpu, title: "CPU" do
        meter "system.cpu"
        trend "system.cpu", height: 6, label: "last 4 min"
        stat "system.load1", "system.load5", "system.load15", columns: 3
      end
      panel :memory, title: "Memory" do
        meter "memory.used"
        meter "memory.pressure"
        meter "memory.swap_used"
        stat "memory.app", "memory.wired", "memory.compressed", "memory.cached", columns: 2
        trend "memory.used", height: nil, label: "used, last 4 min"
      end
    end
    row height: 8 do
      panel :network, title: "Network" do
        trend "system.net_in_rate", "system.net_out_rate", height: nil
      end
      panel :disk, title: "Disk" do
        trend "system.disk_read_rate", "system.disk_write_rate", height: nil
      end
    end
    row do
      top :session, title: "Sessions", by: :cpu, spark: %i[cpu net_out_rate],
                    columns: %i[label cpu footprint read_rate write_rate net_in_rate net_out_rate],
                    widths: { label: 22 }
    end
    row height: 10 do
      panel :agents, title: "All agents" do
        trend "focus.cpu", "focus.footprint", height: nil
      end
      panel :agents_net, title: "Agents network" do
        trend "focus.net_in_rate", "focus.net_out_rate", height: nil
      end
    end

    # Drilled into one session: its CPU, memory, network and disk, processes, connections.
    focused do
      row height: 11 do
        panel :s_cpu, title: "CPU" do
          meter "focus.cpu"
          trend "focus.cpu", height: nil, label: "last 4 min"
          stat "focus.processes", "focus.read_rate", "focus.write_rate", columns: 3
        end
        panel :s_memory, title: "Memory" do
          meter "focus.footprint"
          stat "focus.resident", "focus.wired", "focus.growth_rate", "focus.pagein_rate", columns: 2
          trend "focus.footprint", height: nil, label: "footprint, last 4 min"
        end
      end
      row height: 8 do
        panel :s_net, title: "Network" do
          trend "focus.net_in_rate", "focus.net_out_rate", height: nil
        end
        panel :s_disk, title: "Disk" do
          trend "focus.read_rate", "focus.write_rate", height: nil
        end
      end
      row do
        top :process, span: 3, by: :cpu, columns: %i[name cpu footprint net_out_rate], widths: { name: 20 }
        detail :process, span: 2
      end
      row height: 8 do
        top :connection, title: "Connections", by: :out_rate, spark: false, widths: { process: 18 },
                         columns: %i[process remote_text state in_rate out_rate bytes_in bytes_out]
      end
    end
  end
end
