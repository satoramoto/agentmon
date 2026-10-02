# frozen_string_literal: true

module Agentmon
  # Sampler -> Reading (metrics) -> Store (recorders), one tick at a time, shared by everything
  # that shows data: the dashboard's resources (each r2ui feed thread calls `current`), and the CLI
  # commands. `current` samples at most once per `max_age`, so three panels refreshing every two
  # seconds cost one sample, not three.
  #
  # The first call takes two samples PRIME_GAP apart: CPU % and disk rates are deltas, so the very
  # first frame or `agentmon top --once` already has them.
  #
  # Metrics and recorders get a state Hash kept for this engine's life (one per metric, one per
  # recorder), so nothing needs module-level state and two engines (tests) never share it.
  class Engine
    PRIME_GAP = 0.5

    attr_reader :interval, :store, :run_id
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
      @states = Hash.new { |h, k| h[k] = {} } # metric name => state; [:recorder, name] => state
      @recorded_at = {}
      @recorder_errors = {}
      @run_id = "#{Process.pid}-#{clock.now.to_i}"
    end

    # The latest Reading, sampling first if it's older than `max_age` seconds. While a session is
    # focused it is a FocusedReading narrowed to it (lib/agentmon/focus.rb); `focused: false`
    # returns the whole machine regardless.
    def current(max_age: interval * 0.75, focused: true)
      @lock.synchronize do
        if @reading.nil?
          tick!
          sleep(@prime_gap) if @prime_gap.positive?
          tick!
        elsif @clock.mono - @ticked_at >= max_age
          tick!
        end
        focused ? focused_reading : @reading
      end
    end

    # The focused session's id (Session#id / ProcessRow#session_id), nil when unfocused.
    def focus = @focus

    # Focuses every reader of `current` on one session; nil clears. Takes effect on each panel's
    # next feed refresh. Recorders and `errors` always see the whole machine.
    def focus=(session_id)
      @lock.synchronize { @focus = session_id }
    end

    # The focused Session from the ledger (alive or recently ended), or nil when nothing is
    # focused or the session has left the ledger.
    def focused_session
      id = focus or return nil
      current(focused: false)[:session_ledger]&.find { |s| s.id == id }
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

    # What's broken right now: { "probe cwd" => "Errno::ENOENT: ...", "metric memory" => ...,
    # "recorder sessions" => ... } from the latest sample's probes, the latest reading's metrics and
    # the recorders' last runs. The dashboard's status bar and the CLI's stderr show it.
    def errors
      reading = @reading
      found = {}
      reading&.sample&.errors&.each { |name, message| found["probe #{name}"] = message }
      reading&.errors&.each { |name, message| found["metric #{name}"] = message }
      @recorder_errors.each { |name, message| found["recorder #{name}"] = message }
      found
    end

    private

    # The latest reading narrowed to the focus, built once per (reading, focus) under the lock.
    def focused_reading
      return @reading unless @focus

      @focused = nil unless @focused&.unfocused.equal?(@reading) && @focused.focus == @focus
      @focused ||= Focus.apply(@reading, @focus)
    end

    def record(reading)
      @registry.recorders.each do |recorder|
        last = @recorded_at[recorder.name]
        next if last && @ticked_at - last < recorder.every

        @recorded_at[recorder.name] = @ticked_at
        rows = recorder.block.call(reading, @states[[:recorder, recorder.name]])
        rows = [rows] if rows.is_a?(Hash) # Array(hash) would split it into pairs
        Array(rows).each { |row| @store.append(recorder.name, row.merge(run: run_id)) }
        @recorder_errors.delete(recorder.name)
      rescue StandardError => e
        @recorder_errors[recorder.name] = "#{e.class}: #{e.message}"
      end
    end
  end
end
