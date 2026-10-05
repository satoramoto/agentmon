# frozen_string_literal: true

module Agentmon
  module Views
    # The last CAPACITY values of every signal a view draws (docs/views.md, "History"), appended
    # once per Reading: `record` ignores a second call with the same `at` for a key, so a view
    # drawn many times between samples (animation frames) appends each sample once.
    #
    #   history.record("memory.used", reading.at, value)
    #   history["memory.used"]   # => [..., 23.1e9], oldest first (frozen)
    #
    # Unknown (nil) values are not appended, but their `at` still counts as seen. Meant for one
    # drawing thread: no lock.
    class History
      CAPACITY = 120 # four minutes at 2 s

      attr_reader :capacity

      def initialize(capacity: CAPACITY)
        raise ArgumentError, "capacity must be a positive Integer" unless capacity.is_a?(Integer) && capacity.positive?

        @capacity = capacity
        @series = {}
        @last_at = {}
      end

      # Appends value.to_f to key's series unless `at` was already recorded for it; returns the
      # series (frozen).
      def record(key, at, value)
        if !@last_at.key?(key) || @last_at[key] != at
          @last_at[key] = at
          append(key, value.to_f) unless value.nil?
        end
        self[key]
      end

      # The series for `key`, oldest first: a frozen Array, [] when unknown.
      def [](key) = @series.fetch(key) { EMPTY }

      def keys = @last_at.keys

      def forget(key)
        @last_at.delete(key)
        @series.delete(key)
        nil
      end

      EMPTY = [].freeze
      private_constant :EMPTY

      private

      # Keeps each stored series frozen: a new Array per append, so a series handed out earlier
      # never changes under its holder.
      def append(key, value)
        series = [*@series[key], value]
        series.shift(series.size - capacity) if series.size > capacity
        @series[key] = series.freeze
      end
    end
  end
end
