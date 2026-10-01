# frozen_string_literal: true

module Agentmon
  # One sample plus everything derived from it: `reading[:process_rows]`, `reading[:sessions]`.
  # A metric's value is computed once, the first time it is asked for (metrics may ask for each
  # other); the Engine asks for all of them before it publishes the reading, so readers on other
  # threads only look values up.
  #
  # Tests build one directly, with fixture samples and preset `values:` for metrics a story
  # consumes but doesn't own:
  #
  #   Reading.new(sample, previous: earlier, values: { memory: MemoryView.new(...) })
  class Reading
    attr_reader :sample, :previous

    def initialize(sample, previous: nil, metrics: Agentmon.registry.metrics, states: nil, values: {})
      @sample = sample
      @previous = previous
      @metrics = metrics.to_h { |m| [m.name, m] }
      @states = states || Hash.new { |h, k| h[k] = {} }
      @values = values.transform_keys(&:to_sym)
      @computing = []
    end

    # Wall time of the sample (epoch seconds).
    def at = sample.at

    # Seconds between the previous sample and this one (monotonic), nil for the first.
    def interval = previous && (sample.mono - previous.mono)

    def [](name)
      name = name.to_sym
      return @values[name] if @values.key?(name)

      metric = @metrics[name] or raise Error, "no metric #{name} (is its story merged?)"
      raise Error, "metric cycle: #{[*@computing, name].join(" -> ")}" if @computing.include?(name)

      @computing.push(name)
      begin
        @values[name] = metric.block.call(self, @states[name])
      ensure
        @computing.pop
      end
    end

    def key?(name) = @values.key?(name.to_sym) || @metrics.key?(name.to_sym)

    # Computes every metric (the Engine calls this once per sample).
    def evaluate_all
      @metrics.each_key { |name| self[name] }
      self
    end
  end
end
