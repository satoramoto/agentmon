# frozen_string_literal: true

# reading[:process_rates]: { pid => ProcessRates } between the previous sample and this one.
#
# CPU % is the change in CPU seconds over the monotonic interval, x100 (percent of one core, so a
# process using four cores shows 400%). Disk rates are byte deltas over the interval. A pid only
# matches the previous sample when its start time matches too, so a reused pid never produces a
# rate from someone else's counters. Unreadable and newly seen processes fall back to ps's %cpu
# and nil disk rates.
module Agentmon
  module Metrics
    # Named apart from the ProcessRates model so `ProcessRates.new` below means the model.
    module Rates
      module_function

      def call(processes, previous, interval)
        before = (previous || []).select(&:readable).to_h { |p| [p.identity, p] }
        (processes || []).to_h do |p|
          q = p.readable && interval&.positive? && before[p.identity]
          [p.pid, q ? delta(p, q, interval) : ProcessRates.new(cpu: p.ps_cpu, read_rate: nil, write_rate: nil)]
        end
      end

      def delta(now, was, seconds)
        ProcessRates.new(
          cpu: [now.cpu_time - was.cpu_time, 0].max / seconds * 100,
          read_rate: [now.disk_read - was.disk_read, 0].max / seconds,
          write_rate: [now.disk_written - was.disk_written, 0].max / seconds
        )
      end
    end
  end

  metric(:process_rates) do |reading|
    Metrics::Rates.call(reading.sample[:processes], reading.previous&.[](:processes), reading.interval)
  end
end
