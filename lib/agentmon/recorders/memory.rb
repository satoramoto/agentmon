# frozen_string_literal: true

# Memory history: while agentmon records (the interactive dashboard, `agentmon record`), one line
# every 10 s in the store's `memory` kind, e.g. ~/.local/state/agentmon/memory/2026-10-01.jsonl:
#
#   {"t":1790000010.0,"total":17179869184,"used":11811160064,"app":7516192768,"wired":2147483648,
#    "compressed":2147483648,"cached":3221225472,"free":536870912,"swap_used":1073741824,
#    "swap_total":2147483648,"compression_ratio":3.1,"swapin_rate":0.0,"swapout_rate":4096.0,
#    "compression_rate":1572864.0,"decompression_rate":262144.0,"pressure":38.0,"run":"4242-1790000000"}
#
# The line is `reading[:memory]` (a MemoryView: sizes in bytes, rates in bytes/s, pressure in
# percent) without `pressure_trend` (the line's own history is the trend), stamped with the
# sample's time `t` and the engine's `run`. Nothing is written while memory is unavailable.
module Agentmon
  recorder(:memory, every: 10) do |reading, _state|
    view = reading[:memory]
    view && { t: reading.at, **view.to_h.except(:pressure_trend) }
  end
end
