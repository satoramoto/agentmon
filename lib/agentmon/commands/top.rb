# frozen_string_literal: true

# `agentmon top`: the processes of agent sessions, busiest first, with real memory and disk I/O.
#
#   agentmon top              on a terminal: redrawn in place every 2 s until ctrl+c
#   agentmon top --once       one table and exit (plain aligned columns in a pipe, for scripts)
#   agentmon top -a -n 5 --sort footprint
#   agentmon top --session repo   only one session (its id, root pid or part of its label);
#                                 no match, or several, exits 1 and lists the sessions
#
#   PID    Name    Session              CPU  Footprint  Resident   Read  Write
#   4242   claude  claude 4242 · repo  12.5%       512M      600M  1.0K/s     0B/s
#
# Sizes are binary (1M = 1024²), the same units the dashboard shows. An empty cell is unknown:
# footprint and disk rates of other users' processes can't be read without root.
module Agentmon
  module Commands
    module Top
      HEADERS = %w[PID Name Session CPU Footprint Resident Read Write].freeze
      RIGHT = [0, 3, 4, 5, 6, 7].freeze
      # Seconds between the live loop's own redraws (which surface a dead ticker's error).
      CHECK_EVERY = 1
      SORTS = { "cpu" => :cpu, "footprint" => :footprint, "resident" => :resident, "read" => :read_rate,
                "write" => :write_rate }.freeze

      module_function

      def select(rows, sort: "cpu", limit: 20, all: false)
        key = SORTS.fetch(sort)
        rows ||= [] # process_rows failed this sample: an empty table (the error goes to stderr)
        rows = rows.select(&:session) unless all
        rows.sort_by { |r| [-(r.public_send(key) || -1).to_f, r.pid] }.first(limit)
      end

      def cells(row)
        f = R2UI::Format
        [row.pid.to_s, row.name, row.session.to_s, f.call(:percent, row.cpu), f.call(:bytes, row.footprint),
         f.call(:bytes, row.resident), f.call(:bytes_per_sec, row.read_rate), f.call(:bytes_per_sec, row.write_rate)]
      end

      # Plain aligned lines (header first), cut to `width`: the live view.
      def lines(rows, width)
        table = [HEADERS, *rows.map { |r| cells(r) }]
        widths = table.transpose.map { |col| col.map(&:length).max }
        table.map do |cells|
          cells.each_with_index.map { |c, i| RIGHT.include?(i) ? c.rjust(widths[i]) : c.ljust(widths[i]) }
               .join("  ").rstrip[0, width]
        end
      end
    end
  end

  command :top do
    summary "Agent processes by CPU, with footprint and disk I/O"
    flag :once, desc: "Print one table and exit"
    flag :all, short: "a", desc: "Every process, not only agent sessions"
    option :limit, :integer, short: "n", default: 20, desc: "Rows to show"
    option :sort, default: "cpu", in: Commands::Top::SORTS.keys, desc: "Sort by"
    option :session, desc: "Only one session's processes: its id, root pid or part of its label"

    run do
      top = Commands::Top
      pick = ->(reading) { top.select(reading[:process_rows], sort: options[:sort], limit: options[:limit], all: options[:all]) }
      engine = Agentmon.engine
      if (query = options[:session])
        sessions = engine.current(focused: false)[:session_ledger]&.select(&:alive?) || []
        found = Focus.find(sessions, query)
        listing = ->(list) { list.map { |s| "  #{s.label}  (#{s.id})" }.join("\n") }
        abort!("no session matches #{query.inspect}. Sessions:\n#{listing.call(sessions)}") if found.empty?
        abort!("#{query.inspect} matches #{found.size} sessions:\n#{listing.call(found)}") if found.size > 1
        engine.focus = found.first.id
      end
      if options[:once] || !shell.live?
        table(pick.call(engine.current).map { |r| top.cells(r) }, headers: top::HEADERS, align: top::RIGHT.to_h { |i| [i, :right] })
      else
        live = R2UI::CLI::Live.new(shell, fps: 2) { top.lines(pick.call(engine.current), shell.width).join("\n") }
        # `refresh` redraws on this thread: if the ticker died on a raising view, it raises that
        # error here, Live restores the terminal, and the command fails instead of freezing.
        live.run { loop { sleep top::CHECK_EVERY; live.refresh } }
      end
    end
  end
end
