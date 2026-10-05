# frozen_string_literal: true

require "json"

# `agentmon sessions`: the agent sessions running now (Claude Code, Codex, their desktop apps),
# busiest first, with what each has cost over its life.
#
#   agentmon sessions          a table (boxed on a terminal, plain aligned columns in a pipe)
#   agentmon sessions --all    also sessions that ended in the last 15 minutes
#   agentmon sessions --json   one JSON object per line, raw units (bytes, seconds, epoch), for scripts
#
#   Session            Processes     CPU  Footprint  Peak  CPU time  Written      Age
#   claude 200 · repo          4  150.0%       628M  628M     15.6s     5.0M  56m 42s
#
# CPU is percent of one core now; Footprint is real memory now and Peak the largest seen; CPU time
# and Written are lifetime totals (Written is a lower bound: see docs/design.md). Sizes are binary
# (1M = 1024²), as in the dashboard. Age runs from the session's start to now, or to its end.
module Agentmon
  module Commands
    module SessionList
      HEADERS = ["Session", "Processes", "CPU", "Footprint", "Peak", "CPU time", "Written", "Age"].freeze
      RIGHT = (1..7).to_h { |i| [i, :right] }.freeze
      EMPTY = "No agent sessions running."

      module_function

      # Alive sessions (and ended ones with `all`), alive first, then by CPU, then by root pid.
      def select(ledger, all: false)
        ledger ||= [] # session_ledger failed or isn't there this sample (the error goes to stderr)
        ledger = ledger.select(&:alive?) unless all
        ledger.sort_by { |s| [s.alive? ? 0 : 1, -(s.cpu || 0.0), s.root_pid] }
      end

      def cells(session, now)
        f = R2UI::Format
        human = R2UI::CLI::Ext::HumanFormat
        label = session.alive? ? session.label : "#{session.label} · ended #{human.duration(now - session.ended_at)} ago"
        [label, session.processes.to_s, f.call(:percent, session.cpu), f.call(:bytes, session.footprint),
         f.call(:bytes, session.peak_footprint), session.cpu_seconds && human.duration(session.cpu_seconds),
         f.call(:bytes, session.bytes_written), human.duration(session.duration)].map(&:to_s)
      end

      def json(session) = JSON.generate(session.to_record)

      # Narrowest a label is cut to, however many other columns there are: on a very narrow
      # terminal (or a pipe without COLUMNS, 80) the table overflows rather than lose the label.
      MIN_LABEL = 20

      # `rows` (Arrays of Strings) with column `column` cut at a word boundary ("·", " ", ...) so
      # the table r2ui draws fits `width`: r2ui's plain table never cuts and its boxed one wraps
      # cells, so a long session name would overflow a pipe or wrap mid-word on a terminal.
      # `boxed` is the terminal table: each cell padded by one space each side plus n+1 borders;
      # plain columns are joined by two spaces. A cell's part matching `keep` (at its end) is kept
      # whole and the rest cut. Used by sessions, footprint and top.
      def fit(rows, headers, width:, boxed:, column: 0, keep: nil)
        return rows if rows.empty?

        measure = ->(text) { R2UI::CLI::Ext::Tabulate.width(text.to_s) }
        others = headers.each_index.sum do |i|
          i == column ? 0 : [measure[headers[i]], *rows.map { |r| measure[r[i]] }].max
        end
        n = headers.size
        overhead = boxed ? (3 * n) + 1 : 2 * (n - 1)
        room = [width - others - overhead, MIN_LABEL, measure[headers[column]]].max
        rows.map do |row|
          text = row[column].to_s
          tail = (keep && text[keep]).to_s
          head = text.delete_suffix(tail)
          row.dup.tap { |r| r[column] = Views::Widgets.cut(head, [room - measure[tail], MIN_LABEL].max) + tail }
        end
      end

      # The " · ended 3m ago" an ended session's label ends in: never cut.
      ENDED = / · ended [^·]* ago\z/
    end
  end

  command :sessions do
    summary "Agent sessions now, with CPU, real memory and lifetime totals"
    flag :all, short: "a", desc: "Also sessions that ended in the last 15 minutes"
    flag :json, desc: "One JSON object per session per line, in raw units"

    run do
      list = Commands::SessionList
      reading = Agentmon.engine.current
      sessions = list.select(reading[:session_ledger], all: options[:all])
      if options[:json]
        sessions.each { |s| shell.puts(list.json(s)) }
      elsif sessions.empty?
        shell.puts(list::EMPTY)
      else
        rows = list.fit(sessions.map { |s| list.cells(s, reading.at) }, list::HEADERS, width: shell.width,
                                                                                      boxed: shell.live?, keep: list::ENDED)
        table(rows, headers: list::HEADERS, align: list::RIGHT)
      end
    end
  end
end
