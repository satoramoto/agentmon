# frozen_string_literal: true

# reading[:process_rates]: { pid => ProcessRates } between the previous sample and this one.
#
# CPU % is the change in CPU seconds over the monotonic interval, x100 (percent of one core, so a
# process using four cores shows 400%). Disk rates are byte deltas over the interval. A pid only
# matches the previous sample when its start time matches too, so a reused pid never produces a
# rate from someone else's counters. Unreadable and newly seen processes fall back to ps's %cpu
# and nil disk rates.
#
# Paging and scheduling rates the same way: pageins, faults, copy-on-write faults and context
# switches per second, and `run_wait`, the percent of one core the process spent runnable but
# waiting for a CPU (runnable time grows while a thread is on a CPU too, so CPU time is taken off).
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
        cpu = [now.cpu_time - was.cpu_time, 0].max
        ProcessRates.new(
          cpu: cpu / seconds * 100,
          read_rate: [now.disk_read - was.disk_read, 0].max / seconds,
          write_rate: [now.disk_written - was.disk_written, 0].max / seconds,
          pagein_rate: per_second(now.pageins, was.pageins, seconds),
          fault_rate: per_second(now.faults, was.faults, seconds, wrap: true),
          cow_fault_rate: per_second(now.cow_faults, was.cow_faults, seconds, wrap: true),
          context_switch_rate: per_second(now.context_switches, was.context_switches, seconds, wrap: true),
          run_wait: run_wait(now, was, cpu, seconds)
        )
      end

      # Events per second between two counts; nil when either is unknown. The task counters are
      # 32 bits in the kernel, so with `wrap:` a count that went down wrapped at 2**32.
      def per_second(now, was, seconds, wrap: false)
        return nil if now.nil? || was.nil?

        diff = now - was
        diff %= 2**32 if wrap
        [diff, 0].max / seconds.to_f
      end

      # Runnable time counts time on a CPU too, so waiting for one is runnable growth minus CPU
      # growth, as percent of one core.
      def run_wait(now, was, cpu, seconds)
        return nil if now.runnable_time.nil? || was.runnable_time.nil?

        [now.runnable_time - was.runnable_time - cpu, 0].max / seconds * 100
      end
    end
  end

  metric(:process_rates) do |reading|
    Metrics::Rates.call(reading.sample[:processes], reading.previous&.[](:processes), reading.interval)
  end
end
