# frozen_string_literal: true

require "json"

# `agentmon report`: what agent sessions cost this Mac over a period, from the recorded history
# (the `sessions` store lines that the dashboard and `agentmon record` write).
#
#   agentmon report               the last 24 hours
#   agentmon report --since 90m   or 2h, 3d
#   agentmon report --json        one merged record per line, raw units (bytes, seconds)
#
#   Agent sessions · last 24h
#
#   Session             Started  Duration  Peak    CPU  Written  Status
#   claude 4242 · repo    09:14    2h 0m   900M  10m 0s    2.0G  ended 11:14
#   claude 4300 · web     13:40    1h 0m   2.0G  1h 0m    100M  ended (not seen after 14:02)
#   claude 4410 · repo    15:02   20m 5s   100M  1m 0s      0B  running
#
#   3 sessions · 1h 11m CPU · 2.1G written
#
# Lines of one session (several agentmon runs record it) are merged taking each lifetime total's
# maximum: every run recounts from the kernel's counters, so a sum would double count. A session
# with no end whose last line is over a minute old is shown ended when it was last seen, never
# running: agentmon wasn't running when it ended. Sizes are binary (1G = 1024³), as in the
# dashboard; written bytes are a lower bound (see docs/design.md, "Lifetime totals").
module Agentmon
  module Commands
    module Report
      PERIOD = /\A([1-9]\d*)([mhd])\z/
      UNIT = { "m" => 60, "h" => 3600, "d" => 86_400 }.freeze
      # A session with no ended_at is running only if it was seen this recently (6 recorder lines).
      RUNNING_WITHIN = 60
      TOTALS = %i[cpu_seconds bytes_read bytes_written peak_footprint].freeze
      HEADERS = %w[Session Started Duration Peak CPU Written Status].freeze
      RIGHT = { 1 => :right, 2 => :right, 3 => :right, 4 => :right, 5 => :right }.freeze

      # The --since value type: the text back when it's a period ("90m", "2h", "3d").
      SINCE = lambda do |text|
        raise ArgumentError, "expects a period like 90m, 2h or 3d" unless PERIOD.match?(text)

        text
      end

      module_function

      def seconds(period)
        number, unit = PERIOD.match(period).captures
        Integer(number) * UNIT.fetch(unit)
      end

      # Store lines → one Hash per session id, oldest start first, with `status` ("running",
      # "ended", "not_seen") and `duration` (seconds) added, and the per-line `t` and `run` gone.
      def merge(lines, now:)
        lines.group_by { |l| l[:id] }.map do |_id, group|
          group = group.sort_by { |l| l[:t].to_f }
          merged = group.last.except(:t, :run)
          TOTALS.each { |k| merged[k] = group.filter_map { |l| l[k] }.max }
          merged[:started_at] = group.filter_map { |l| l[:started_at] }.min
          merged[:first_seen_at] = group.filter_map { |l| l[:first_seen_at] }.min
          merged[:last_seen_at] = group.filter_map { |l| l[:last_seen_at] }.max
          merged[:ended_at] = group.filter_map { |l| l[:ended_at] }.max
          finish(merged, now)
        end.sort_by { |s| [(s[:started_at] || s[:first_seen_at]).to_f, s[:id].to_s] }
      end

      def finish(session, now)
        last = session[:last_seen_at]
        session[:status] = if session[:ended_at] then "ended"
                           elsif last && now - last <= RUNNING_WITHIN then "running"
                           else "not_seen"
                           end
        start = session[:started_at] || session[:first_seen_at]
        stop = session[:ended_at] || last
        session[:duration] = start && stop ? [stop - start, 0.0].max : nil
        session
      end

      # "14:02" today, "Sep 30 14:02" on another day.
      def clock(t, now)
        return "" unless t

        time = Time.at(t)
        time.strftime("%F") == Time.at(now).strftime("%F") ?time.strftime("%H:%M") : time.strftime("%b %-d %H:%M")
      end

      def status(session, now)
        case session[:status]
        when "running" then "running"
        when "ended" then "ended #{clock(session[:ended_at], now)}"
        else "ended (not seen after #{clock(session[:last_seen_at], now)})"
        end
      end
    end
  end

  command :report do
    summary "Agent sessions recorded over a period, with their peak memory, CPU and disk writes"
    option :since, Commands::Report::SINCE, default: "24h", placeholder: "period", desc: "How far back: 90m, 2h, 3d"
    flag :json, desc: "One merged session record per line, raw units"

    run do
      report = Commands::Report
      now = Clock.now
      store = Agentmon.engine.store || Store.new
      sessions = report.merge(store.each(:sessions, since: now - report.seconds(options[:since])).to_a, now:)

      if options[:json]
        sessions.each { |s| shell.puts(JSON.generate(s)) }
      elsif sessions.empty?
        say "No agent sessions recorded in the last #{options[:since]}."
      else
        bytes = ->(n) { R2UI::Format.call(:bytes, n) }
        time = ->(s) { s ? duration(s) : "" }
        heading "Agent sessions · last #{options[:since]}"
        rows = sessions.map do |s|
          [s[:label].to_s, report.clock(s[:started_at] || s[:first_seen_at], now), time.call(s[:duration]),
           bytes.call(s[:peak_footprint]), time.call(s[:cpu_seconds]), bytes.call(s[:bytes_written]), report.status(s, now)]
        end
        table rows, headers: report::HEADERS, align: report::RIGHT
        say
        cpu = sessions.sum { |s| s[:cpu_seconds].to_f }
        written = sessions.sum { |s| s[:bytes_written].to_i }
        say "#{plural(sessions.size, "session")} · #{duration(cpu)} CPU · #{bytes.call(written)} written"
      end
    end
  end
end
