# frozen_string_literal: true

require "json"

# `agentmon memory`: this Mac's RAM right now, the way Activity Monitor breaks it down, then the
# agent sessions pushing memory pressure hardest.
#
#   agentmon memory
#
#   Memory
#     Total          16G
#     Used           12G
#     App            8.0G
#     Wired          2.0G
#     Compressed     2.0G (3.1x)
#     Cached         3.0G
#     Swap           1.0G / 2.0G
#     Swap in        1.0K/s
#     Swap out       0B/s
#     Compression    2.0M/s
#     Decompression  512K/s
#     Pressure       35.0%
#
#   Pressure drivers
#   Session            Footprint  Share   Growth
#   claude 200 · repo       512M   4.2%  +1.0M/s
#
#   agentmon memory --json    one JSON object: {"memory": {...}, "pressure_drivers": [...]} in raw
#                             units (bytes, bytes/s, percent) for scripts
#
# Used = App + Wired + Compressed; Compressed is the RAM the compressor occupies and (3.1x) how much
# it holds per byte. Rates are since the previous sample. Pressure is 100 - kern.memorystatus_level.
# Share is a session's footprint as a percent of used memory; Growth its footprint change per
# second over the last minute. Sizes are binary (1G = 1024³), as in the dashboard. "—" is unknown.
module Agentmon
  module Commands
    module MemoryReport
      DRIVERS = 5
      HEADERS = %w[Session Footprint Share Growth].freeze
      RIGHT = { 1 => :right, 2 => :right, 3 => :right }.freeze

      module_function

      # [[key, value]] for r2ui `pairs`; nil values print as "—".
      def pairs(view)
        size = ->(v) { v && R2UI::Format.bytes(v) }
        rate = ->(v) { v && R2UI::Format.call(:bytes_per_sec, v) }
        compressed = size.(view.compressed)
        compressed = "#{compressed} (#{R2UI::Format.call(:ratio, view.compression_ratio)})" if compressed && view.compression_ratio
        swap = [view.swap_used, view.swap_total].all?(&:nil?) ? nil : "#{size.(view.swap_used) || "—"} / #{size.(view.swap_total) || "—"}"
        [
          ["Total", size.(view.total)], ["Used", size.(view.used)], ["App", size.(view.app)],
          ["Wired", size.(view.wired)], ["Compressed", compressed], ["Cached", size.(view.cached)], ["Swap", swap],
          ["Swap in", rate.(view.swapin_rate)], ["Swap out", rate.(view.swapout_rate)],
          ["Compression", rate.(view.compression_rate)], ["Decompression", rate.(view.decompression_rate)],
          ["Pressure", view.pressure && R2UI::Format.call(:percent, view.pressure)]
        ]
      end

      def cells(driver)
        f = R2UI::Format
        [driver.label, f.call(:bytes, driver.footprint), f.call(:percent, driver.share), growth(driver.growth_rate)]
      end

      # "+1.0M/s", "-2.0K/s", "0B/s" (Format.bytes doesn't take negatives).
      def growth(rate)
        return "" if rate.nil?

        sign = if rate.positive? then "+" elsif rate.negative? then "-" else "" end
        "#{sign}#{R2UI::Format.call(:bytes_per_sec, rate.abs)}"
      end

      def json(view, drivers)
        JSON.generate(memory: view.to_h, pressure_drivers: drivers&.map(&:to_h))
      end
    end
  end

  command :memory do
    summary "RAM breakdown, pressure and the sessions driving it"
    flag :json, desc: "Print raw values as one JSON object"

    run do
      report = Commands::MemoryReport
      reading = Agentmon.engine.current
      view = reading[:memory]
      drivers = reading[:pressure_drivers]
      unless view
        # abort! skips after_run hooks, so say what broke here.
        Agentmon.engine_errors.each { |name, message| shell.err_puts("#{shell.symbol(:warn)} #{name}: #{message}") }
        abort!("Memory isn't available (no memory metric, or it failed this sample)")
      end

      if options[:json]
        shell.puts(report.json(view, drivers))
      else
        pairs report.pairs(view), title: "Memory"
        if drivers
          say
          say "Pressure drivers", :heading
          if drivers.empty?
            say "No agent sessions are using memory.", :muted
          else
            table(drivers.first(report::DRIVERS).map { |d| report.cells(d) }, headers: report::HEADERS, align: report::RIGHT)
          end
        end
      end
    end
  end
end
