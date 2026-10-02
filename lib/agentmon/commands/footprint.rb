# frozen_string_literal: true

require "json"

# `agentmon footprint`: real memory by agent session now, largest first, with what is growing and
# what is paging.
#
#   agentmon footprint          a table (boxed on a terminal, plain aligned columns in a pipe)
#   agentmon footprint --json   one JSON object per session per line, raw units, for scripts
#
#   Session            Processes  Footprint  Share  Resident  Wired  Peak    Growth  Pageins/s
#   claude 200 · repo          4       628M   5.1%      630M   1.0M  628M  +1.0M/s       10.0
#   Claude 300                 3       501M   4.1%      530M     0B  501M    +0B/s        0.0
#
#   compressed 2.0G · swap 512M (per-process compressed/swap needs root)
#
# Footprint is what Activity Monitor calls Memory, summed over the session's processes (each
# once); Share is its percent of the machine's used memory; Peak the largest footprint seen over
# the session's life; Growth the footprint change per second over the last minute (a single run
# sees only the half second between its two samples); Pageins/s counts page-ins (each waited for
# the disk). Sizes are binary (1M = 1024²), as in the dashboard. The last line is the machine's
# compressed memory and swap used: macOS splits those out per process only for root. `--json`
# prints SessionMemory fields (bytes, bytes/s, percent, events/s; null when unknown).
module Agentmon
  module Commands
    module FootprintList
      HEADERS = ["Session", "Processes", "Footprint", "Share", "Resident", "Wired", "Peak", "Growth",
                 "Pageins/s"].freeze
      RIGHT = (1..8).to_h { |i| [i, :right] }.freeze
      EMPTY = "No agent sessions running."

      module_function

      def cells(m)
        f = R2UI::Format
        [m.label, m.processes.to_s, f.call(:bytes, m.footprint), f.call(:percent, m.share), f.call(:bytes, m.resident),
         f.call(:bytes, m.wired), f.call(:bytes, m.peak_footprint), growth(m.growth_rate),
         f.call(:number, m.pagein_rate)].map(&:to_s)
      end

      # "+1.5M/s", "-12K/s"; "" when unknown.
      def growth(rate)
        return "" if rate.nil?

        "#{rate.negative? ? "-" : "+"}#{R2UI::Format.bytes(rate.abs)}/s"
      end

      # The machine's compressed and swap, or nil without a MemoryView.
      def machine(memory)
        memory && "compressed #{R2UI::Format.bytes(memory.compressed.to_i)} · swap #{R2UI::Format.bytes(memory.swap_used.to_i)} " \
                  "(per-process compressed/swap needs root)"
      end

      def json(m) = JSON.generate(m.to_h)
    end
  end

  command :footprint do
    summary "Real memory by agent session now: footprint, share, growth, paging"
    flag :json, desc: "One JSON object per session per line, in raw units"

    run do
      list = Commands::FootprintList
      reading = Agentmon.engine.current
      rows = reading[:session_memory] || [] # nil when the metric failed this sample (the error goes to stderr)
      if options[:json]
        rows.each { |m| shell.puts(list.json(m)) }
      elsif rows.empty?
        shell.puts(list::EMPTY)
      else
        table(rows.map { |m| list.cells(m) }, headers: list::HEADERS, align: list::RIGHT)
        if (line = list.machine(reading[:memory]))
          shell.puts
          shell.puts(line)
        end
      end
    end
  end
end
