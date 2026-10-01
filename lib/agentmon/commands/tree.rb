# frozen_string_literal: true

# `agentmon tree [SESSION]`: each agent session's process tree, the session label as root, each
# process as "pid name · footprint · CPU %".
#
#   agentmon tree             every live session
#   agentmon tree repo        one session, by id, root pid or label substring (any case)
#
#   claude 200 · repo
#   └── 200 claude · 512M · 100.0%
#       ├── 201 node · 100M · 50.0%
#       └── 202 zsh · 8.0M · 0.0%
#           └── 203 git · 8.0M · 0.0%
#
# A SESSION that matches nothing, or more than one session, exits 1 and lists the candidates.
# "n/a" is unknown: other users' processes have no readable footprint without root. Sizes are
# binary (1M = 1024²). Plain lines in a pipe, so `agentmon tree | grep node` works.
module Agentmon
  module Commands
    module SessionTree
      NONE = "No agent sessions running."

      module_function

      # The live sessions from a reading, root pid order; [] while `sessions` is unavailable.
      def sessions(reading)
        map = reading[:sessions]
        map ? map.sessions.sort_by(&:root_pid) : []
      end

      # Sessions a SESSION argument names: an exact id or root pid first, else label substrings.
      def find(sessions, query)
        exact = sessions.select { |s| s.id == query || s.root_pid.to_s == query }
        return exact unless exact.empty?

        sessions.select { |s| s.label.downcase.include?(query.downcase) }
      end

      # { "pid name · footprint · cpu" => children } for one session's processes, nested by ppid.
      # Members whose parent isn't in the session (normally just the root) are the top level.
      def branches(session, rows)
        members = (rows || []).select { |r| r.session_id == session.id }
        pids = members.to_h { |r| [r.pid, true] }
        kids = members.group_by(&:ppid)
        top = members.reject { |r| pids[r.ppid] }
        nest(top, kids, {})
      end

      def nest(rows, kids, seen)
        rows.sort_by(&:pid).each_with_object({}) do |row, tree|
          next if seen[row.pid] # a ppid cycle (pid reuse between ps lines) would never end

          seen[row.pid] = true
          below = nest(kids.fetch(row.pid, []), kids, seen)
          tree[label(row)] = below.empty? ? nil : below
        end
      end

      def label(row)
        f = R2UI::Format
        footprint = f.call(:bytes, row.footprint)
        cpu = f.call(:percent, row.cpu)
        "#{row.pid} #{row.name} · #{footprint.empty? ? 'n/a' : footprint} · #{cpu.empty? ? 'n/a' : cpu}"
      end

      def listing(sessions) = sessions.map { |s| "  #{s.label}  (#{s.id})" }.join("\n")
    end
  end

  command :tree do
    summary "Process tree of each agent session, with footprint and CPU"
    argument :session, required: false, desc: "Session id, root pid or label substring"

    run do
      st = Commands::SessionTree
      reading = Agentmon.engine.current
      sessions = st.sessions(reading)
      query = args[:session]
      if query
        abort!("no session matches #{query.inspect}: #{st::NONE}") if sessions.empty?
        found = st.find(sessions, query)
        abort!("no session matches #{query.inspect}. Sessions:\n#{st.listing(sessions)}") if found.empty?
        abort!("#{query.inspect} matches #{found.size} sessions:\n#{st.listing(found)}") if found.size > 1
        sessions = found
      end
      if sessions.empty?
        say st::NONE
      else
        sessions.each_with_index do |s, i|
          say if i.positive?
          tree(s.label, st.branches(s, reading[:process_rows]))
        end
      end
    end
  end
end
