# frozen_string_literal: true

# reading[:pressure_drivers]: the alive agent sessions ranked by how much memory they hold, as
# PressureDriver records (lib/agentmon/model.rb), largest footprint first. For example:
#
#   claude 4242 · repo   2.1G   26.3%   +1.5M/s
#   Claude 59334         900M   11.0%   -12K/s
#
# - footprint: the session's physical footprint now (bytes; readable members only).
# - share: footprint as a percent of used memory (reading[:memory].used); nil while memory is
#   unknown (no memory metric, or it failed this sample).
# - growth_rate: footprint change in bytes per second over the last WINDOW seconds of samples
#   (oldest kept sample to this one, on the monotonic clock); 0.0 until a session has two samples.
#   Negative when it shrinks.
#
# Sessions with zero footprint (all members unreadable, or ended) are left out. Stateful: a short
# footprint history per session id, dropped when the session is no longer alive.
module Agentmon
  module Metrics
    class Drivers
      WINDOW = 60.0

      def initialize(state) = @state = state

      def call(reading)
        history = (@state[:history] ||= {}) # session id => [[mono, footprint], ...], oldest first
        alive = (reading[:session_ledger] || []).select(&:alive?)
        history.select! { |id, _| alive.any? { |s| s.id == id } }
        used = reading[:memory]&.used
        mono = reading.sample.mono

        alive.filter_map do |session|
          footprint = session.footprint || 0
          growth = growth(history[session.id] ||= [], mono, footprint)
          next unless footprint.positive?

          PressureDriver.new(session_id: session.id, label: session.label, footprint:,
                             share: used&.positive? ? footprint * 100.0 / used : nil, growth_rate: growth)
        end.sort_by { |d| [-d.footprint, d.session_id] }
      end

      private

      # Adds this sample to a session's points, forgets those older than WINDOW and returns the
      # rate from the oldest left to this one.
      def growth(points, mono, footprint)
        points.pop if points.last && points.last[0] >= mono # the same sample seen again
        points << [mono, footprint]
        points.shift while mono - points.first[0] > WINDOW
        since, was = points.first
        mono > since ? (footprint - was) / (mono - since) : 0.0
      end
    end
  end

  metric(:pressure_drivers) { |reading, state| Metrics::Drivers.new(state).call(reading) }
end
