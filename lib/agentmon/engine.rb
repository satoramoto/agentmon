# frozen_string_literal: true

module Agentmon
  # Sampler -> Reading (metrics) -> Store (recorders), one tick at a time, shared by everything
  # that shows data: the dashboard's resources (each r2ui feed thread calls `current`), and the CLI
  # commands. `current` samples at most once per `max_age`, so three panels refreshing every two
  # seconds cost one sample, not three.
  #
  # The first call takes two samples PRIME_GAP apart: CPU % and disk rates are deltas, so the very
  # first frame or `agentmon top --once` already has them.
  class Engine
    PRIME_GAP = 0.5

    attr_reader :interval, :store, :run_id, :errors
    attr_accessor :recording

    def initialize(sampler: Sampler.new, registry: Agentmon.registry, store: nil, recording: false, interval: 2.0,
                   prime_gap: PRIME_GAP, clock: Clock)
      @sampler = sampler
      @registry = registry
      @store = store
      @recording = recording
      @interval = interval
      @prime_gap = prime_gap
      @clock = clock
      @lock = Mutex.new
      @states = Hash.new { |h, k| h[k] = {} }
      @recorded_at = {}
      @errors = {}
      @run_id = "#{Process.pid}-#{clock.now.to_i}"
    end

    # The latest Reading, sampling first if it's older than `max_age` seconds.
    def current(max_age: interval * 0.75)
      @lock.synchronize do
        if @reading.nil?
          tick!
          sleep(@prime_gap) if @prime_gap.positive?
          tick!
        elsif @clock.mono - @ticked_at >= max_age
          tick!
        end
        @reading
      end
    end

    # Samples now (callers hold no lock: use `current` from threads).
    def tick!
      sample = @sampler.sample
      reading = Reading.new(sample, previous: @reading&.sample, metrics: @registry.metrics, states: @states)
      reading.evaluate_all
      @ticked_at = @clock.mono
      record(reading) if @recording && @store
      @reading = reading
    end

    private

    def record(reading)
      @registry.recorders.each do |recorder|
        last = @recorded_at[recorder.name]
        next if last && @ticked_at - last < recorder.every

        @recorded_at[recorder.name] = @ticked_at
        rows = recorder.block.call(reading)
        rows = [rows] if rows.is_a?(Hash) # Array(hash) would split it into pairs
        Array(rows).each { |row| @store.append(recorder.name, row.merge(run: run_id)) }
        @errors.delete(recorder.name)
      rescue StandardError => e
        @errors[recorder.name] = "#{e.class}: #{e.message}"
      end
    end
  end
end
