# frozen_string_literal: true

module Agentmon
  # One sample plus everything derived from it: `reading[:process_rows]`, `reading[:sessions]`.
  # A metric's value is computed once, the first time it is asked for (metrics may ask for each
  # other); the Engine asks for all of them before it publishes the reading, so readers on other
  # threads only look values up.
  #
  # Stories land in any order, so a missing or broken metric never stops the others:
  # `reading[:name]` is nil for a metric nobody registered (its story hasn't merged yet), and a
  # metric that raises is nil too, with its error in `reading.errors[:name]` (the dashboard's
  # status bar and the CLI's stderr show them). Consumers treat nil as "not available".
  #
  # Tests build one directly, with fixture samples and preset `values:` for metrics a story
  # consumes but doesn't own:
  #
  #   Reading.new(sample, previous: earlier, values: { memory: MemoryView.new(...) })
  class Reading
    attr_reader :sample, :previous, :errors

    def initialize(sample, previous: nil, metrics: Agentmon.registry.metrics, states: nil, values: {})
      @sample = sample
      @previous = previous
      @metrics = metrics.to_h { |m| [m.name, m] }
      @states = states || Hash.new { |h, k| h[k] = {} }
      @values = values.transform_keys(&:to_sym)
      @errors = {}
      @computing = []
    end

    # Wall time of the sample (epoch seconds).
    def at = sample.at

    # Seconds between the previous sample and this one (monotonic), nil for the first.
    def interval = previous && (sample.mono - previous.mono)

    def [](name)
      name = name.to_sym
      return @values[name] if @values.key?(name)

      metric = @metrics[name] or return nil
      raise Error, "metric cycle: #{[*@computing, name].join(" -> ")}" if @computing.include?(name)

      @values[name] = compute(metric)
    end

    # True when a metric of that name is registered (or preset).
    def key?(name) = @values.key?(name.to_sym) || @metrics.key?(name.to_sym)

    # Computes every metric (the Engine calls this once per sample).
    def evaluate_all
      @metrics.each_key { |name| self[name] }
      self
    end

    private

    def compute(metric)
      @computing.push(metric.name)
      metric.block.call(self, @states[metric.name])
    rescue Error => e
      raise if e.message.start_with?("metric cycle") # a design bug: fail loudly

      fail_metric(metric, e)
    rescue StandardError => e
      fail_metric(metric, e)
    ensure
      @computing.pop
    end

    def fail_metric(metric, error)
      @errors[metric.name] = "#{error.class}: #{error.message}"
      nil
    end
  end
end
