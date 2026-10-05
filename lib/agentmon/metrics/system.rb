# frozen_string_literal: true

module Agentmon
  # reading[:system]: the whole machine's CPU, load, network and disk now, as a SystemView, derived
  # from the system probe's SystemStat (sample[:system]) and reading[:process_rows]. Nil while there
  # is no SystemStat (off macOS, or the probe failed).
  #
  #   cpu, user, system  percent of the whole machine (0..100): tick deltas over all CPUs since the
  #                      previous sample / total tick delta. cpu counts user + system + nice
  #   ncpu               logical CPUs
  #   load1/5/15         load averages
  #   net_in_rate,       bytes/s over the monotonic interval (the probes' at_mono, else the
  #   net_out_rate       samples' mono)
  #   disk_read_rate,    bytes/s: the sum of read_rate / write_rate over reading[:process_rows]
  #   disk_write_rate    where known (readable processes; other users' are not counted). Nil with
  #                      no rows or no known rate
  #   *_trend            the last 120 values (four minutes at 2 s), oldest first: metric state
  #
  # Every delta is nil on the first sample and when a counter went backwards (an interface reset,
  # a wrapped tick counter): unknown, never negative. Unknown values are not appended to trends.
  #
  # Metrics are computed on demand (Reading#[]), so reading[:process_rows] is ready whichever order
  # the metrics are registered in. Session focus does not narrow this value: it is machine-wide.
  SystemView = Data.define(
    :cpu, :user, :system,                  # percent of the machine
    :ncpu,
    :load1, :load5, :load15,
    :net_in_rate, :net_out_rate,           # bytes/s
    :disk_read_rate, :disk_write_rate,     # bytes/s
    :cpu_trend, :net_in_trend, :net_out_trend, :disk_trend # last TREND values, oldest first
  )

  module Metrics
    # Named apart from the SystemView/SystemStat models and the system probe's module.
    module MachineLoad
      TREND = 120
      TRENDS = %i[cpu net_in net_out disk].freeze

      module_function

      # `now`/`before` are SystemStats (`before` nil on the first sample), `rows` the reading's
      # process rows, `fallback` the samples' monotonic interval; `state` the metric's state Hash.
      def call(now, before, rows, fallback, state)
        return nil unless now

        user, system, cpu = percents(now.cpu_ticks, before&.cpu_ticks)
        interval = interval(now, before, fallback)
        net_in = rate(now.net_in, before&.net_in, interval)
        net_out = rate(now.net_out, before&.net_out, interval)
        disk_read = disk(rows, :read_rate)
        disk_write = disk(rows, :write_rate)
        disk_total = disk_read && disk_write ? disk_read + disk_write : nil

        trends = TRENDS.to_h { |name| [name, state[name] ||= []] }
        { cpu:, net_in:, net_out:, disk: disk_total }.each { |name, value| push(trends[name], value) }

        load1, load5, load15 = now.load
        SystemView.new(cpu:, user:, system:, ncpu: now.ncpu, load1:, load5:, load15:,
                       net_in_rate: net_in, net_out_rate: net_out,
                       disk_read_rate: disk_read, disk_write_rate: disk_write,
                       cpu_trend: trends[:cpu].dup.freeze, net_in_trend: trends[:net_in].dup.freeze,
                       net_out_trend: trends[:net_out].dup.freeze, disk_trend: trends[:disk].dup.freeze)
      end

      # [user, system, busy] percents between two [user, system, idle, nice] tick readings, or
      # [nil, nil, nil] when either is unknown, no ticks passed, or a counter went backwards.
      def percents(now, was)
        return [nil, nil, nil] unless now && was

        user, system, idle, nice = now.zip(was).map { |a, b| a - b }
        total = user + system + idle + nice
        return [nil, nil, nil] if [user, system, idle, nice].any?(&:negative?) || !total.positive?

        pct = ->(ticks) { ticks * 100.0 / total }
        [pct[user], pct[system], pct[user + system + nice]]
      end

      # Seconds between the two probe reads, else between the samples.
      def interval(now, before, fallback)
        return nil unless before

        if now.at_mono && before.at_mono
          now.at_mono - before.at_mono
        else
          fallback
        end
      end

      # Bytes/s between two readings of a cumulative counter; nil when unknown or it went backwards.
      def rate(now, was, interval)
        return nil if now.nil? || was.nil? || interval.nil? || !interval.positive? || now < was

        (now - was) / interval.to_f
      end

      def disk(rows, field)
        known = rows&.filter_map(&field)
        known.nil? || known.empty? ? nil : known.sum.to_f
      end

      def push(trend, value)
        return if value.nil?

        trend << value
        trend.shift while trend.size > TREND
      end
    end
  end

  metric(:system) do |reading, state|
    Metrics::MachineLoad.call(reading.sample[:system], reading.previous&.[](:system), reading[:process_rows],
                              reading.interval, state)
  end
end
