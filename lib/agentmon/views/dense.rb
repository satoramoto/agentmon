# frozen_string_literal: true

# dense: htop-like, everything on one screen (docs/views.md). Its real frame, from
# `COLUMNS=100 LINES=50 bundle exec exe/agentmon --layout dense | cat`:
#
# ╭─ CPU ──────────────────────────────────╮╭─ Memory ─────────────────╮╭─ I/O ──────────────────────╮
# │CPU  ⣀⣀⣀⣀⣀⣀⣀⣀⣀⣀⣀⣀⣀⣀⣀⣀⣀⣀⣀⣀⣀⣀⣀⣀⣀⣀⣀⣀⣀ 16.6%││used     ⣀⣀⣀⣀⣀⣀⣀⣀⣀⣀⣀   22G││net in  ⣀⣀⣀⣀⣀⣀⣀⣀⣀⣀⣀⣀⣀ 1.5K/s│
# │user ⣀⣀⣀⣀⣀⣀⣀⣀⣀⣀⣀⣀⣀⣀⣀⣀⣀⣀⣀⣀⣀⣀⣀⣀⣀⣀⣀⣀⣀  9.7%││pressure ⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⣀ 28.0%││net out ⣀⣀⣀⣀⣀⣀⣀⣀⣀⣀⣀⣀⣀ 1.5K/s│
# │load 1m         5.1  load 5m         4.1││swap     ⣀⣀⣀⣀⣀⣀⣀⣀⣀⣀⣀  310M││disk rd ⣀⣀⣀⣀⣀⣀⣀⣀⣀⣀⣀⣀⣀   0B/s│
# │load 15m        4.1  cores            10││compr    ⣀⣀⣀⣀⣀⣀⣀⣀⣀⣀⣀  5.5G││disk wr ⣀⣀⣀⣀⣀⣀⣀⣀⣀⣀⣀⣀⣀   0B/s│
# ╰────────────────────────────────────────╯╰──────────────────────────╯╰────────────────────────────╯
# ╭─ Sessions ─[Live] All ───────────────────────────────────────────────────────────────────────────╮
# │ Session                                                   Procs          CPU▼  Footprint     Age │
# │ Claude 21354                                                 28 ⠀⠀⠀⠀⢀   24.2%       1.9G     26m │
# │ ChatGPT 2388                                                 17 ⠀⠀⠀⠀⢀    9.7%       2.6G 12h 14m │
# │ claude 22602 · agentmon                                       5 ⠀⠀⠀⠀⢀    7.8%       305M     25m │
# │ claude 22034 · agentmon                                       1 ⠀⠀⠀⠀⢀    0.5%       171M     25m │
# │ claude 26329 · funkadelic-astronaut-web                       1 ⠀⠀⠀⠀⢀    0.3%       188M     14m │
# │ codex 3064 · Resources                                        4 ⠀⠀⠀⠀⢀    0.0%        75M 12h 14m │
# ╰───────────────────────────────────────────────────────────────────────────────────────────── 1/7 ╯
# ╭─ Processes ─[Agents] All  Busy  Heavy  Writing  Waiting ─────────────────────────────────────────╮
# │      Pid Name                Session             CPU▼  Footprint   Wait  Pgin/s     Read    Write│
# │    21358 Claude Helper       Claude 21354       11.2%       353M   3.7%     0.0     0B/s     0B/s│
# │    21393 Claude Helper…      Claude 21354        8.8%       680M   1.6%     0.0     0B/s     0B/s│
# │     2905 Codex (Renderer)    ChatGPT 2388        4.3%       773M   1.7%     0.0     0B/s     0B/s│
# │    31832 agentmon --layout…  claude 22602…       4.1%        41M   0.0%     0.0     0B/s     0B/s│
# │    22602 claude              claude 22602…       3.6%       261M   2.3%     0.0     0B/s     0B/s│
# │     2388 ChatGPT             ChatGPT 2388        3.0%       329M   3.8%     0.0     0B/s     0B/s│
# │     2405 Codex (Service)     ChatGPT 2388        1.8%       382M   1.7%     0.0     0B/s     0B/s│
# │    29798 Claude Helper…      Claude 21354        1.8%       182M   1.0%     0.0     0B/s     0B/s│
# │    21354 Claude              Claude 21354        1.5%       255M   0.1%     0.0     0B/s     0B/s│
# │    21916 Claude Helper       Claude 21354        0.9%        10M   0.1%     0.0     0B/s     0B/s│
# │    22034 claude              claude 22034…       0.5%       171M   0.8%     0.0     0B/s     0B/s│
# │    26329 claude              claude 26329…       0.3%       188M   1.6%     0.0     0B/s     0B/s│
# │     2987 bare-modifier…      ChatGPT 2388        0.2%       7.6M   0.3%     0.0     0B/s     0B/s│
# │     3353 Codex (Renderer)    ChatGPT 2388        0.2%       226M   0.4%     0.0     0B/s     0B/s│
# │     2409 Codex (Service)     ChatGPT 2388        0.1%        53M   0.0%     0.0     0B/s     0B/s│
# │     2904 Codex (Renderer)    ChatGPT 2388        0.1%       256M   0.0%     0.0     0B/s     0B/s│
# │     3004 Codex (Renderer)    ChatGPT 2388        0.0%       276M   0.0%     0.0     0B/s     0B/s│
# │     2425 Codex (Service)     ChatGPT 2388        0.0%        29M   0.0%     0.0     0B/s     0B/s│
# │    21907 disclaimer          Claude 21354        0.0%       944K   0.0%     0.0     0B/s     0B/s│
# │    21689 Claude Helper       Claude 21354        0.0%        22M   0.0%     0.0     0B/s     0B/s│
# │    21678 Claude Helper       Claude 21354        0.0%        19M   0.0%     0.0     0B/s     0B/s│
# │    21623 Claude Helper       Claude 21354        0.0%        20M   0.0%     0.0     0B/s     0B/s│
# │    21621 Claude Helper       Claude 21354        0.0%       117M   0.0%     0.0     0B/s     0B/s│
# │    21374 Claude Helper…      Claude 21354        0.0%        26M   0.0%     0.0     0B/s     0B/s│
# ╰──────────────────────────────────────────────────────────────────────────────────────────── 1/58 ╯
# ╭─ Detail ─────────────────────────────────────────────────────────────────────────────────────────╮
# │Claude Helper  pid 21358                                                                          │
# │Command    /Applications…        Resident   141M                  Started    26m 50s ago          │
# │Directory  /                     Peak       1.0G                  Open files 16                   │
# │Session    Claude 21354          CPU time   2m 8s                 Threads    19 (0 running)       │
# │Footprint  353M                  Written    192K                  CPU wait   3.7% now, 1m 9s…     │
# ╰──────────────────────────────────────────────────────────────────────────────────────────────────╯
#  sort: CPU▼       ? help  tab panel  [ ] scope  g group  s/S sort  / search  ⏎ fold  z zoom  q quit
#
# The CPU panel takes span 3 so `stat` keeps two columns (it drops to one below 40 cells). The
# Processes table leaves the sort sparkline off so all nine columns fit at 100 cells.
module Agentmon
  view :dense, title: "agentmon" do
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
    row height: 9 do
      top :session, title: "Sessions", by: :cpu, columns: %i[label processes cpu footprint age], widths: { label: 54 }
    end
    row do
      top :process, title: "Processes", by: :cpu, spark: false,
                    columns: %i[pid name session cpu footprint run_wait pagein_rate read_rate write_rate],
                    widths: { name: 19, session: 16 }
    end
    row height: 7 do
      detail :process, columns: 3
    end
  end
end
