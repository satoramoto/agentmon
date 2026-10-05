# frozen_string_literal: true

# visual: gauges, areas and heat, sessions first (docs/views.md). Home is the machine's breakdown
# over every agent session, by name when Claude Code or Codex knows one (Enter on one drills into
# it: its CPU gauge and area beside the machine's RAM with the session's slice, network and disk
# areas, processes beside the detail, connections; Escape returns). Its real home frame, from
# `COLUMNS=100 LINES=50 bundle exec exe/agentmon --layout visual | cat` (one sample, so areas and
# sparklines are still empty and network rates still settling):
#
# ╭─ CPU ──────────────────────────────────────────╮╭─ Memory ───────────────────────────────────────╮
# │CPU ▕███████████████▏                    ▏ 41.8%││used     ▕████████████████▌    ▏   25G / 32G 79%│
# │last 4 min                                 41.8%││pressure ▕██████████▏          ▏           48.0%│
# │⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀││swap     ▕█████▎               ▏ 255M / 1.0G 25%│
# │⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀││app                 10G  wired              3.5G│
# │⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀││compressed          11G  cached             5.7G│
# │⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢠││used, last 4 min                             25G│
# │⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢸││⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢸│
# │⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢸││⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢸│
# │load 1m    5.5  load 5m    6.2  load 15m   6.0  ││⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢸│
# ╰────────────────────────────────────────────────╯╰────────────────────────────────────────────────╯
# ╭─ Network ──────────────────────────────────────╮╭─ Disk ─────────────────────────────────────────╮
# │net in                                    1.7K/s││disk read                                 933K/s│
# │⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢸││⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢸│
# │⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢸││⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢸│
# │net out                                   1.8K/s││disk write                                  0B/s│
# │⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢸││⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀│
# │⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢸││⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀│
# ╰────────────────────────────────────────────────╯╰────────────────────────────────────────────────╯
# ╭─ Sessions ─[Live] All ───────────────────────────────────────────────────────────────────────────╮
# │ Session                                 CPU▼  Footprint     Read    Write   Net in        Net out│
# │ Claude 21354                   ⠀⠀⠀⠀⢀   23.4%       3.7G     0B/s     0B/s     0B/s ⠀⠀⠀⠀⢀     0B/s│
# │ Agentmon r2ui integration…     ⠀⠀⠀⠀⢀   14.6%       372M     0B/s     0B/s     0B/s ⠀⠀⠀⠀⢀     0B/s│
# │ ChatGPT 2388                   ⠀⠀⠀⠀⢀   10.0%       3.3G     0B/s     0B/s     0B/s ⠀⠀⠀⠀⢀     0B/s│
# │ Project history · claude…      ⠀⠀⠀⠀⢀    1.0%       285M     0B/s     0B/s          ⠀⠀⠀⠀⢀         │
# │ EPK component review · claude… ⠀⠀⠀⠀⢀    0.5%       262M     0B/s     0B/s          ⠀⠀⠀⠀⢀         │
# │ Mods in Desktop vs Code…       ⠀⠀⠀⠀⢀    0.3%       226M     0B/s     0B/s          ⠀⠀⠀⠀⢀         │
# │ Set up a Homebrew tap for…     ⠀⠀⠀⠀⢀    0.1%       200M     0B/s     0B/s          ⠀⠀⠀⠀⢀         │
# │ Weekly session themes review…  ⠀⠀⠀⠀⢀    0.1%       181M     0B/s     0B/s     0B/s ⠀⠀⠀⠀⢀     0B/s│
# │ codex 3064 · Resources         ⠀⠀⠀⠀⢀    0.0%        76M     0B/s     0B/s     0B/s ⠀⠀⠀⠀⢀     0B/s│
# │ Build Magrathea local POC +8…  ⠀⠀⠀⠀⢀    0.0%      1022M     0B/s     0B/s     0B/s ⠀⠀⠀⠀⢀     0B/s│
# │                                                                                                  │
#   ... 6 more empty table lines ...
# ╰──────────────────────────────────────────────────────────────────────────────────────────────────╯
# ╭─ All agents ───────────────────────────────────╮╭─ Agents network ───────────────────────────────╮
# │CPU                                         5.0%││net in                                      0B/s│
# │⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀││⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀│
# │⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀││⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀│
# │⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢀││⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀│
# │footprint                                   9.6G││net out                                     0B/s│
# │⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢸││⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀│
# │⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢸││⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀│
# │⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢸││⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀│
# ╰────────────────────────────────────────────────╯╰────────────────────────────────────────────────╯
#  sessions · ⏎ open a session
#
# Drilled into "Agentmon r2ui integration" (a pty at 100×50: `/` integration, Enter). The RAM
# meter is the machine (25G of 32G used) with this session's footprint as the accent slice at the
# left, the rest of used memory dim and free memory empty:
#
# ╭─ CPU ──────────────────────────────────────────╮╭─ Memory ───────────────────────────────────────╮
# │CPU ▕                                     ▏ 0.1%││RAM      ▕▏█████████████▉    ▏ 323M 1% · 25G/32G│
# │last 4 min                                  0.1%││pressure ▕█████████▏         ▏             48.0%│
# │⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀││resident           439M  wired                0B│
# │⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀││growth             0B/s  pageins             0/s│
# │⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀││footprint, last 4 min                       323M│
# │⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀││⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⣿│
# │⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀││⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⣿│
# │⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀││⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⣿│
# │⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⣀││⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⣿│
# ╰────────────────────────────────────────────────╯╰────────────────────────────────────────────────╯
# ╭─ Network ──────────────────────────────────────╮╭─ Disk ─────────────────────────────────────────╮
# │net in                                    337B/s││read                                        0B/s│
# │⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢸││⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀│
# │⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⡀⢸││⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀│
# │net out                                   647B/s││write                                       0B/s│
# │⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢸││⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀│
# │⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢸││⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀│
# ╰────────────────────────────────────────────────╯╰────────────────────────────────────────────────╯
# ╭─ Processes ─[Agents] All  Busy  Heavy  Writing  Waiting ─╮╭─ Detail ─────────────────────────────╮
# │ Name                          CPU▼  Footprint  Net out   ││claude  pid 22602                     │
# │ claude               ⣀⣀⣀⣀⣀    1.0%       320M   647B/s   ││Command    /Users/ryan/Library…       │
# │▴sleep                ⠀⠀⠀⠀⣀    0.0%       832K     0B/s   ││Directory  ~/The Source/agentmon      │
# │▾zsh                  ⣀⣀⣀⣀⣀    0.0%       2.5M     0B/s   ││Session    Agentmon r2ui integration… │
# │                                                          ││Footprint  320M                       │
#   ... 16 more lines: the Detail pairs beside empty table lines ...
# ╰──────────────────────────────────────────────────────────╯╰──────────────────────────────────────╯
# ╭─ Connections ────────────────────────────────────────────────────────────────────────────────────╮
# │ Process            Remote                         State             In     Out▼     Recv     Sent│
# │▴claude 22602       160.79.104.10:443              Established   337B/s   647B/s      15K      28K│
# │▾claude 22602       160.79.104.10:443              Established     0B/s     0B/s      39K     2.9M│
# │▾claude 22602       160.79.104.10:443              Established     0B/s     0B/s     918K     4.5M│
# │▾claude 22602       160.79.104.10:443              Established     0B/s     0B/s     234K     540K│
# │▾claude 22602       ….bc.googleusercontent.com:443 Established     0B/s     0B/s      26K     8.3M│
# ╰───────────────────────────────────────────────────────────────────────────────────────────── 2/6 ╯
#  ▸ Agentmon r2ui integration · claude 22602 · agentmon · busy · esc back to sessions
#
# The Sessions table leaves Procs off so disk read and write both fit at 100 columns (its label,
# the session's name first, is 30 wide); footprint has no sparkline (a flat footprint draws a full
# braille column, not a baseline).
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
                    widths: { label: 30 }
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
          meter "memory.used", part: "focus.footprint", label: "RAM" # the session's slice of the machine
          meter "memory.pressure"
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
