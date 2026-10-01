# frozen_string_literal: true

require "test_helper"

class EngineTest < Minitest::Test
  include Fixtures

  def registry_with_recorder(every: 10, &block)
    Agentmon::Registry.new.tap do |r|
      r.add(:metric, Agentmon::Metric.new(name: :count, block: ->(reading, _state) { reading.sample[:processes].size }))
      r.add(:recorder, Agentmon::Recorder.new(name: :counts, every:, block: block || ->(reading) { { n: reading[:count] } }))
    end
  end

  def test_first_reading_is_primed_with_two_samples
    reading = Fixtures.engine(machine(0), machine(2)).current

    assert_in_delta 2.0, reading.interval
    assert_in_delta 100.0, reading[:process_rates][200].cpu # 2 CPU seconds in 2 s
  end

  def test_current_reuses_a_fresh_reading_and_resamples_a_stale_one
    clock = Clock.new
    engine = Fixtures.engine(machine(0), machine(2), machine(4), clock:)
    first = engine.current
    clock.advance(1.0)

    assert_same first, engine.current
    clock.advance(1.0)
    refute_same first, engine.current
  end

  def test_recorders_append_to_the_store_at_most_every_n_seconds
    Dir.mktmpdir do |dir|
      clock = Clock.new
      store = Agentmon::Store.new(dir:, clock:)
      engine = Agentmon::Engine.new(sampler: Sampler.new(machine(0)), registry: registry_with_recorder, store:,
                                    recording: true, prime_gap: 0, clock:)
      engine.tick!
      clock.advance(5)
      engine.tick!
      clock.advance(5)
      engine.tick!

      records = store.each(:counts).to_a
      assert_equal 2, records.size
      assert_equal [12, engine.run_id], [records.first[:n], records.first[:run]]
    end
  end

  def test_nothing_is_recorded_unless_recording
    Dir.mktmpdir do |dir|
      store = Agentmon::Store.new(dir:)
      Agentmon::Engine.new(sampler: Sampler.new(machine(0)), registry: registry_with_recorder, store:, prime_gap: 0).tick!

      assert_empty store.each(:counts).to_a
    end
  end

  def test_a_failing_recorder_is_reported_not_raised
    Dir.mktmpdir do |dir|
      registry = registry_with_recorder { raise "disk full" }
      engine = Agentmon::Engine.new(sampler: Sampler.new(machine(0)), registry:, store: Agentmon::Store.new(dir:),
                                    recording: true, prime_gap: 0)
      engine.tick!

      assert_match(/disk full/, engine.errors[:counts])
    end
  end

  def test_unknown_metric_names_raise
    error = assert_raises(Agentmon::Error) { Fixtures.reading(machine(0))[:no_such_metric] }
    assert_match(/no metric no_such_metric/, error.message)
  end

  def test_preset_values_stand_in_for_metrics_a_story_does_not_own
    assert_equal :preset, Fixtures.reading(machine(0), values: { memory: :preset })[:memory]
  end

  def test_a_probe_that_raises_keeps_its_last_value
    registry = Agentmon::Registry.new
    calls = 0
    registry.add(:probe, Agentmon::Probe.new(name: :flaky, every: nil, block: lambda { |_state|
      calls += 1
      raise "lsof missing" if calls == 2

      calls
    }))
    sampler = Agentmon::Sampler.new(registry:)
    sampler.sample
    second = sampler.sample

    assert_equal 1, second[:flaky]
    assert_match(/lsof missing/, second.errors[:flaky])
  end

  def test_a_probe_with_every_is_reused_until_due
    registry = Agentmon::Registry.new
    calls = 0
    registry.add(:probe, Agentmon::Probe.new(name: :slow, every: 10, block: ->(_state) { calls += 1 }))
    clock = Clock.new
    sampler = Agentmon::Sampler.new(registry:, clock:)
    sampler.sample
    clock.advance(5)
    sampler.sample
    clock.advance(5)

    assert_equal 2, sampler.sample[:slow]
  end
end
