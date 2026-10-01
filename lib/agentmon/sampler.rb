# frozen_string_literal: true

module Agentmon
  # Runs every registered probe once and returns a Sample. A probe with `every:` keeps its last
  # value until it is due again; a probe that raises keeps its last value and its error goes in
  # `sample.errors`, so one broken probe never stops the others.
  #
  # Tests don't use this: they hand an Engine a FixtureSampler (anything with `#sample`).
  class Sampler
    def initialize(registry: Agentmon.registry, clock: Clock)
      @registry = registry
      @clock = clock
      @states = Hash.new { |h, k| h[k] = {} }
      @last = {} # probe name => [value, mono when taken]
    end

    def sample
      mono = @clock.mono
      at = @clock.now
      errors = {}
      parts = @registry.probes.to_h do |probe|
        [probe.name, run(probe, mono, errors)]
      end
      Sample.new(at:, mono:, parts:, errors:)
    end

    private

    def run(probe, mono, errors)
      last = @last[probe.name]
      return last[0] if last && probe.every && mono - last[1] < probe.every

      value = probe.block.call(@states[probe.name])
      @last[probe.name] = [value, mono]
      value
    rescue StandardError => e
      errors[probe.name] = "#{e.class}: #{e.message}"
      last&.first
    end
  end

  # The two clocks: wall time for instants people read, monotonic time for intervals and rates.
  module Clock
    module_function

    def now = Time.now.to_f

    def mono = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  end
end
