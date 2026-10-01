# frozen_string_literal: true

# reading[:memory]: the machine's memory as Activity Monitor breaks it down, as a MemoryView
# (lib/agentmon/model.rb), derived from the memory probe's MemoryStat (sample[:memory]). Nil while
# there is no MemoryStat (the probe hasn't merged, or failed before its first read).
#
#   used               app + wired + compressed (Activity Monitor's "Memory Used")
#   compression_ratio  compressor_stored / compressed: 3.0 means 3 GiB of app memory squeezed into
#                      1 GiB of RAM; 0.0 when nothing is compressed
#   *_rate             swap-ins, swap-outs, compressions and decompressions in bytes/s: the counter
#                      deltas over the monotonic interval since the previous sample. 0.0 on the first
#                      sample (or after one without memory) and when a counter went backwards (it
#                      can reset across sleep); never negative
#   pressure           100 - kern.memorystatus_level, in percent (0 = no pressure)
#   pressure_trend     the last 60 pressures (two minutes at 2 s), oldest first: metric state
#
# Example, 16 GiB Mac under some load:
#
#   MemoryView(total: 16G, used: 9G, app: 6G, wired: 2G, compressed: 1G, compression_ratio: 3.0,
#              swapin_rate: 2097152.0, ..., pressure: 30.0, pressure_trend: [28.0, 29.0, 30.0])
#
# A field the probe couldn't read (nil) stays nil here: its sum, ratio or rate is unknown, not 0.
module Agentmon
  module Metrics
    # Named apart from the MemoryView/MemoryStat models and the memory probe's module.
    module MemoryBreakdown
      TREND = 60
      COUNTERS = { swapin_rate: :swapins, swapout_rate: :swapouts,
                   compression_rate: :compressions, decompression_rate: :decompressions }.freeze

      module_function

      # `now` and `before` are MemoryStats (`before` nil on the first sample); `trend` is the
      # metric's state Array, appended to in place.
      def call(now, before, interval, trend)
        return nil unless now

        pressure = now.memorystatus_level && (100.0 - now.memorystatus_level)
        if pressure
          trend << pressure
          trend.shift while trend.size > TREND
        end

        MemoryView.new(
          total: now.total, used: sum(now.app, now.wired, now.compressed),
          app: now.app, wired: now.wired, compressed: now.compressed, cached: now.cached, free: now.free,
          swap_used: now.swap_used, swap_total: now.swap_total,
          compression_ratio: ratio(now.compressor_stored, now.compressed),
          **COUNTERS.to_h { |rate, counter| [rate, rate(now.public_send(counter), before&.public_send(counter), interval)] },
          pressure:, pressure_trend: trend.dup.freeze
        )
      end

      def sum(*parts) = parts.include?(nil) ? nil : parts.sum

      def ratio(stored, compressed)
        return nil if stored.nil? || compressed.nil?

        compressed.positive? ? stored.to_f / compressed : 0.0
      end

      # Bytes/s between two readings of a cumulative counter.
      def rate(now, was, interval)
        return nil if now.nil?
        return 0.0 if was.nil? || interval.nil? || !interval.positive?

        [now - was, 0].max / interval.to_f
      end
    end
  end

  metric(:memory) do |reading, state|
    Metrics::MemoryBreakdown.call(reading.sample[:memory], reading.previous&.[](:memory), reading.interval,
                                  state[:trend] ||= [])
  end
end
