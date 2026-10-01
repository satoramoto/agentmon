# frozen_string_literal: true

# The :memory resource and the Memory panel (top row, left): the RAM deep dive Activity Monitor
# shows, plus which agent sessions push memory pressure.
#
#   ╭ Memory ──────────────────────────────────────╮
#   │Used      ▕██████████████░░░░▏ 12G / 16G 75%  │
#   │App               8.0G Wired             2.0G │
#   │Compressed        2.0G Ratio             3.1x │
#   │Cached            3.0G Swap used         512M │
#   │Swap in         1.0M/s Swap out        256K/s │
#   │Compress        4.0M/s Decompress      3.0M/s │
#   │Pressure ▁▂▂▃▃▄▅▅▆▆▅▄▃▃▂▂▃▄▅▆▇▇█        42.0% │
#   │claude 4242 · repo     1.5G  12.5%   +2.0M/s  │
#   │Claude 59334           1.0G   8.3%   -512K/s  │
#   ╰──────────────────────────────────────────────╯
#
# Used = app + wired + compressed (Activity Monitor's "Memory Used"); Ratio is how much the
# compressor squeezes (stored bytes / bytes it occupies); the rates are bytes per second between
# samples. Pressure is 100 − kern.memorystatus_level, its line the last 60 samples (2 minutes).
# The last lines are the three sessions with the largest footprint: footprint, share of used
# memory, and how fast their footprint grew over the last minute.
#
# The numbers come from the `memory` metric (a MemoryView) and the `pressure_drivers` metric
# (PressureDrivers). While `memory` is unavailable the panel says so and shows no numbers.
module Agentmon
  module UI
    module MemoryPanel
      # What the resource returns: one record per frame, so the gauge, stats and lines agree.
      Record = Data.define(:view, :drivers)

      # [attribute, label, r2ui format] of the MemoryView fields the resource exposes.
      ATTRIBUTES = [
        [:total, "Total", :bytes], [:used, "Used", :bytes], [:app, "App", :bytes], [:wired, "Wired", :bytes],
        [:compressed, "Compressed", :bytes], [:compression_ratio, "Ratio", :ratio], [:cached, "Cached", :bytes],
        [:free, "Free", :bytes], [:swap_used, "Swap used", :bytes], [:swap_total, "Swap total", :bytes],
        [:swapin_rate, "Swap in", :bytes_per_sec], [:swapout_rate, "Swap out", :bytes_per_sec],
        [:compression_rate, "Compress", :bytes_per_sec], [:decompression_rate, "Decompress", :bytes_per_sec],
        [:pressure, "Pressure", :percent]
      ].freeze

      # The stats grid, two per line, in this order.
      STATS = %i[app wired compressed compression_ratio cached swap_used swapin_rate swapout_rate compression_rate
                 decompression_rate].freeze

      DRIVERS = 3

      module_function

      def record(reading)
        view = reading[:memory] or return []
        [Record.new(view:, drivers: reading[:pressure_drivers] || [])]
      end

      def format(key, value)
        _, _, fmt = ATTRIBUTES.find { |a| a.first == key }
        R2UI::Format.call(fmt, value)
      end

      def label(key) = ATTRIBUTES.find { |a| a.first == key }[1]

      # "App        8.0G Wired      2.0G", two cells per line (one when narrower than 40).
      def stats(view, width)
        cols = width >= 40 ? 2 : 1
        cell = (width - (cols - 1)) / cols
        STATS.map { |key| cell_text(label(key), format(key, view.public_send(key)), cell) }
             .each_slice(cols).map { |cells| cells.join(" ") }.join("\n")
      end

      # "Pressure    ▁▂▃▅▆ 42.0%": the trend scaled to 100%, newest next to the current value.
      def pressure(view, width)
        now = format(:pressure, view.pressure)
        room = width - "Pressure ".length - now.length - 1
        spark = room.positive? ? R2UI::Widgets::Sparkline.line(view.pressure_trend || [], room, max: 100) : ""
        "Pressure #{spark.rjust([room, 0].max)} #{now}"
      end

      # "claude 4242 · repo   1.5G  12.5%  +2.0M/s" for the largest three; a nil share is blank.
      def drivers(drivers, width)
        drivers.first(DRIVERS).map do |d|
          right = Kernel.format("%6s  %6s  %8s", R2UI::Format.bytes(d.footprint.to_i),
                                d.share ? Kernel.format("%.1f%%", d.share) : "", growth(d.growth_rate))
          name = d.label.to_s
          room = width - right.length - 1
          name = room > 1 && name.length > room ? "#{name[0, room - 1]}…" : name
          "#{name.ljust([room, 0].max)} #{right}"
        end.join("\n")
      end

      def growth(rate)
        return "" if rate.nil?

        "#{rate.negative? ? "-" : "+"}#{R2UI::Format.bytes(rate.abs)}/s"
      end

      def cell_text(label, value, width) = "#{label.ljust([width - value.length, label.length + 1].max)}#{value}"
    end
  end

  resource :memory do |engine|
    title "Memory"
    source { UI::MemoryPanel.record(engine.current) }
    refresh every: engine.interval

    UI::MemoryPanel::ATTRIBUTES.each do |key, label, fmt|
      attribute(key, label:, format: fmt) { |r| r.view.public_send(key) }
    end
  end

  panel :memory, row: :top, order: 10, span: 1 do |_engine|
    gauge :used, of: :total, label: "Used"
    view do
      record = app.feeds[:memory]&.rows&.first
      record ? UI::MemoryPanel.stats(record.view, width) : "memory: not available"
    end
    view do
      record = app.feeds[:memory]&.rows&.first
      record ? UI::MemoryPanel.pressure(record.view, width) : ""
    end
    view do
      record = app.feeds[:memory]&.rows&.first
      record ? UI::MemoryPanel.drivers(record.drivers, width) : ""
    end
  end
end
