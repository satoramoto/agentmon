# frozen_string_literal: true

# Session history: store kind `sessions`. While agentmon records (the dashboard, `agentmon
# record`), every 10 s it appends one line per alive agent session, and one final line for each
# session the first time it is seen ended. Each line is `Session#to_record` plus `t` (the sample's
# time) and `run` (the engine's run id), in the model's units (bytes, seconds, epoch seconds):
#
#   ~/.local/state/agentmon/sessions/2026-10-01.jsonl
#   {"t":1790711098.2,"id":"claude-4242-1790711088","kind":"cli","name":"claude","root_pid":4242,
#    "label":"claude 4242 · repo","cwd":"/Users/me/src/repo","started_at":1790711088.4,...,
#    "ended_at":null,"cpu_seconds":12.6,"bytes_read":0,"bytes_written":5244880,"run":"812-1790711090"}
#
# Readers merge lines by `id`, taking each total's maximum (docs/design.md, "Store records").
# Nothing is written while the session ledger is unavailable.
module Agentmon
  module Recorders
    module SessionHistory
      module_function

      # Records for this reading. `state[:ended]` holds the ids this engine already wrote a final
      # line for, kept only while the ledger still lists them (it drops ended sessions after
      # SessionLedger::KEEP_ENDED), so it stays small.
      def call(reading, state)
        ledger = reading[:session_ledger] or return []

        written = state[:ended] ||= {}
        ended_now = ledger.reject(&:alive?).to_h { |s| [s.id, true] }
        written.keep_if { |id, _| ended_now.key?(id) }
        ledger.filter_map do |session|
          next if !session.alive? && written.key?(session.id)

          written[session.id] = true unless session.alive?
          session.to_record.merge(t: reading.at)
        end
      end
    end
  end

  recorder(:sessions, every: 10) { |reading, state| Recorders::SessionHistory.call(reading, state) }
end
