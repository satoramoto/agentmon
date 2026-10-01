# frozen_string_literal: true

# reading[:session_ledger]: every agent session alive now or ended in the last KEEP_ENDED seconds,
# as Session records (lib/agentmon/model.rb) with current values and lifetime totals. Stateful: it
# sees every sample the Engine takes.
#
# How the totals are counted, and what they can't see:
#
# - cpu_seconds adds, for each member process, the growth of its own + reaped-children CPU time
#   between samples (a member seen for the first time counts all of it, so a session that started
#   before agentmon still shows its whole life). Child time matters: the kernel adds a process's
#   CPU time to its parent's when the parent reaps it, so short-lived tools (git, rg) that start
#   and exit between two samples are still counted, through their parent.
#   That also means a member that exits is about to be counted again inside its parent's child
#   time, so its last seen total goes into the session's `pending` pool and is subtracted from the
#   session's next growth. When a CLI session ends under a parent in another session (Claude Code
#   under the desktop app), its root's total goes into that session's pool the same way.
#   A member that leaves the tree alive (an orphan reparented to launchd) keeps what it was
#   counted and stops counting.
# - bytes_read / bytes_written add each member's growth between samples (first seen: all of it).
#   Disk I/O isn't passed to parents, so a process that starts and exits between two samples
#   isn't seen: these are lower bounds.
# - peak_footprint is the largest footprint sum (readable members) seen in any sample.
module Agentmon
  module Metrics
    class SessionLedger
      KEEP_ENDED = 15 * 60

      # Mutable per-session accumulator (the metric's state); `to_session` makes the record.
      Account = Struct.new(:info, :first_seen_at, :last_seen_at, :ended_at, :pending, :cpu_seconds, :bytes_read,
                           :bytes_written, :peak_footprint, :now, :parent_session) do
        def alive? = ended_at.nil?
      end

      def initialize(state) = @state = state

      def call(reading)
        accounts = (@state[:accounts] ||= {})
        seen = @state[:seen] || {} # identity => [session id, cpu total, disk read, disk written]
        map = reading[:sessions]
        rates = reading[:process_rates]
        processes = reading.sample[:processes] || []
        live = processes.select(&:readable).to_h { |p| [p.identity, true] }
        at = reading.at

        end_missing(accounts, map, at)
        hand_over_exits(accounts, seen, live)
        members = processes.group_by { |p| map.by_pid[p.pid] }
        @state[:seen] = next_seen = {}
        map.sessions.each do |info|
          account = accounts[info.id] ||= Account.new(info:, first_seen_at: at, pending: 0.0, cpu_seconds: 0.0,
                                                      bytes_read: 0, bytes_written: 0, peak_footprint: 0)
          update(account, info, members.fetch(info.id, []), rates, seen, next_seen, at, map)
        end
        accounts.delete_if { |_, a| a.ended_at && at - a.ended_at > KEEP_ENDED }
        accounts.values.sort_by { |a| [a.info.started_at || a.first_seen_at, a.info.id] }.map { |a| to_session(a) }
      end

      private

      def end_missing(accounts, map, _at)
        alive = map.sessions.to_h { |s| [s.id, true] }
        accounts.each_value do |account|
          next if alive[account.info.id] || account.ended_at

          account.ended_at = account.last_seen_at
          account.now = nil
        end
      end

      # Members that exited since the last sample will show up again as their parent's child time.
      def hand_over_exits(accounts, seen, live)
        seen.each do |identity, (session_id, total)|
          next if live[identity]

          account = accounts[session_id] or next
          if account.alive?
            account.pending += total
          elsif identity[0] == account.info.root_pid && account.info.kind == :cli
            heir = accounts[account.parent_session]
            heir.pending += total if heir&.alive?
          end
        end
      end

      def update(account, info, procs, rates, seen, next_seen, at, map)
        grown = 0.0
        readable = procs.select(&:readable)
        readable.each do |p|
          total = p.cpu_time + p.child_cpu_time
          was = seen[p.identity]
          was = nil unless was && was[0] == info.id
          grown += was ? [total - was[1], 0.0].max : total
          account.bytes_read += was ? [p.disk_read - was[2], 0].max : p.disk_read
          account.bytes_written += was ? [p.disk_written - was[3], 0].max : p.disk_written
          next_seen[p.identity] = [info.id, total, p.disk_read, p.disk_written]
        end
        absorbed = [grown, account.pending].min
        account.pending -= absorbed
        account.cpu_seconds += grown - absorbed

        footprint = readable.sum(&:footprint)
        account.peak_footprint = [account.peak_footprint, footprint].max
        account.info = info
        account.last_seen_at = at
        account.ended_at = nil
        account.parent_session = map.by_pid[procs.find { |p| p.pid == info.root_pid }&.ppid]
        account.now = {
          processes: procs.size,
          cpu: procs.sum { |p| rates[p.pid]&.cpu || 0.0 },
          footprint:,
          resident: procs.sum { |p| p.resident || 0 },
          read_rate: procs.sum { |p| rates[p.pid]&.read_rate || 0.0 },
          write_rate: procs.sum { |p| rates[p.pid]&.write_rate || 0.0 }
        }
      end

      def to_session(account)
        info = account.info
        now = account.now || { processes: 0, cpu: 0.0, footprint: 0, resident: 0, read_rate: 0.0, write_rate: 0.0 }
        Session.new(
          id: info.id, kind: info.kind, name: info.name, root_pid: info.root_pid, label: info.label, cwd: info.cwd,
          started_at: info.started_at || account.first_seen_at, first_seen_at: account.first_seen_at,
          last_seen_at: account.last_seen_at, ended_at: account.ended_at,
          peak_footprint: account.peak_footprint, cpu_seconds: account.cpu_seconds,
          bytes_read: account.bytes_read, bytes_written: account.bytes_written, **now
        )
      end
    end
  end

  metric(:session_ledger) { |reading, state| Metrics::SessionLedger.new(state).call(reading) }
end
