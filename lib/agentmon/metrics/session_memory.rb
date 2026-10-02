# frozen_string_literal: true

# reading[:session_memory]: how much memory each alive agent session holds, as SessionMemory
# records (lib/agentmon/model.rb), largest footprint first. For example:
#
#   claude 4242 · repo   footprint 2.1G  resident 2.4G  wired 1.0M  26.3%  +1.5M/s  10 pageins/s
#   Claude 59334         footprint 900M  resident 1.1G  wired   0B  11.0%  -12K/s    0 pageins/s
#
# - footprint, resident, wired, pageins, pagein_rate, fault_rate: sums over the session's live
#   members in reading[:process_rows], each pid once. A member whose value is unknown (nil: an
#   unreadable process, or a rate before two samples) is skipped; a sum with no known member is
#   nil, never 0. Members are rows whose session_id is the session's, so a process tree counts
#   each process once (sessions.rb puts every pid in at most one session).
# - processes: the live members seen in process_rows.
# - peak_footprint: the ledger's (Session#peak_footprint), the largest footprint sum over its life.
# - share: footprint as a percent of used memory (reading[:memory].used); nil while memory is
#   unknown.
# - growth_rate: footprint change in bytes per second over the last WINDOW seconds of samples, on
#   the monotonic clock; 0.0 until a session has two samples (as pressure_drivers does), nil while
#   its footprint is unknown. Only samples with the same readable members (pids with a known
#   footprint) are compared, so a member joining, leaving or turning unreadable restarts the
#   window rather than showing as growth.
#
# Compressed and swapped bytes per process need task_for_pid (root), so they aren't here; the
# machine's are in reading[:memory]. Empty when the ledger is nil; when reading[:process_rows] is
# nil, one record per alive session with nil sums, since no member is known. Stateful: a short
# footprint history per session id, dropped when the session is no longer alive.
module Agentmon
  module Metrics
    class SessionFootprint
      WINDOW = 60.0

      def initialize(state) = @state = state

      def call(reading)
        history = (@state[:history] ||= {}) # session id => [[mono, footprint], ...], oldest first
        alive = (reading[:session_ledger] || []).select(&:alive?)
        history.select! { |id, _| alive.any? { |s| s.id == id } }
        members = (reading[:process_rows] || []).uniq(&:pid).group_by(&:session_id)
        used = reading[:memory]&.used
        mono = reading.sample.mono

        alive.map do |session|
          rows = members[session.id] || []
          footprint = sum(rows, :footprint)
          SessionMemory.new(
            session_id: session.id, label: session.label, processes: rows.size, footprint:,
            resident: sum(rows, :resident), wired: sum(rows, :wired), peak_footprint: session.peak_footprint,
            share: footprint && used&.positive? ? footprint * 100.0 / used : nil,
            growth_rate: growth(history[session.id] ||= [], mono, footprint, readable(rows)),
            pageins: sum(rows, :pageins), pagein_rate: sum(rows, :pagein_rate), fault_rate: sum(rows, :fault_rate)
          )
        end.sort_by { |m| [-(m.footprint || 0), m.session_id] }
      end

      private

      # The sum of the known values; nil when none is known.
      def sum(rows, field)
        known = rows.filter_map { |r| r.public_send(field) }
        known.empty? ? nil : known.sum
      end

      # The pids whose footprint is known, sorted.
      def readable(rows) = rows.reject { |r| r.footprint.nil? }.map(&:pid).sort

      # Adds this sample to a session's points, forgets those older than WINDOW or with other
      # readable members, and returns the rate from the oldest left to this one; nil (and nothing
      # recorded) while the footprint is unknown.
      def growth(points, mono, footprint, pids)
        return nil if footprint.nil?

        points.pop if points.last && points.last[0] >= mono # the same sample seen again
        points.clear if points.last && points.last[2] != pids # members changed: restart the window
        points << [mono, footprint, pids]
        points.shift while mono - points.first[0] > WINDOW
        since, was, = points.first
        mono > since ? (footprint - was) / (mono - since) : 0.0
      end
    end
  end

  metric(:session_memory) { |reading, state| Metrics::SessionFootprint.new(state).call(reading) }
end
