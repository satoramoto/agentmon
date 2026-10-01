# frozen_string_literal: true

require "test_helper"

# Story a12: every 10 s one `memory` store line (MemoryView#to_h without pressure_trend, plus t and
# run); nothing while reading[:memory] is nil.
class MemoryRecorderTest < Minitest::Test
  include Fixtures

  GB = 1024 * MB

  VIEW = Agentmon::MemoryView.new(
    total: 16 * GB, used: 11 * GB, app: 7 * GB, wired: 2 * GB, compressed: 2 * GB, cached: 3 * GB,
    free: 512 * MB, swap_used: 1 * GB, swap_total: 2 * GB, compression_ratio: 3.1,
    swapin_rate: 0.0, swapout_rate: 4096.0, compression_rate: 1.5 * MB, decompression_rate: 0.25 * MB,
    pressure: 38.0, pressure_trend: [30.0, 35.0, 38.0]
  )

  # The memory metric belongs to story a02: a stand-in metric presets its value (nil = not merged).
  def engine(view, store:, clock:)
    registry = Agentmon::Registry.new
    registry.add(:metric, Agentmon::Metric.new(name: :memory, block: ->(_reading, _state) { view }))
    registry.add(:recorder, Agentmon.registry.recorders.find { |r| r.name == :memory })
    samples = (0..30).step(5).map { |t| machine(t) }
    Agentmon::Engine.new(sampler: Sampler.new(*samples), registry:, store:, recording: true, prime_gap: 0, clock:)
  end

  def run_ticks(engine, clock, count)
    count.times do
      engine.tick!
      clock.advance(5)
    end
  end

  def test_is_registered_every_ten_seconds
    recorder = Agentmon.registry.recorders.find { |r| r.name == :memory }

    refute_nil recorder
    assert_equal 10, recorder.every
  end

  def test_writes_one_line_every_ten_seconds_with_the_view_without_its_trend
    Dir.mktmpdir do |dir|
      clock = Clock.new
      store = Agentmon::Store.new(dir:, clock:)
      engine = engine(VIEW, store:, clock:)
      run_ticks(engine, clock, 5) # t = 0, 5, 10, 15, 20

      lines = store.each(:memory).to_a
      assert_equal 3, lines.size
      assert_equal [T0, T0 + 10, T0 + 20], lines.map { |l| l[:t] }
      expected = VIEW.to_h.except(:pressure_trend).merge(run: engine.run_id)
      assert_equal expected, lines.first.except(:t)
      refute lines.first.key?(:pressure_trend)
      assert_empty engine.errors
    end
  end

  def test_units_round_trip_bytes_as_integers_and_rates_as_floats
    Dir.mktmpdir do |dir|
      clock = Clock.new
      store = Agentmon::Store.new(dir:, clock:)
      run_ticks(engine(VIEW, store:, clock:), clock, 1)

      line = store.each(:memory).first
      %i[total used app wired compressed cached free swap_used swap_total].each do |key|
        assert_kind_of Integer, line[key], key
      end
      assert_equal 16 * GB, line[:total]
      %i[swapin_rate swapout_rate compression_rate decompression_rate pressure compression_ratio].each do |key|
        assert_kind_of Float, line[key], key
      end
      assert_in_delta 1.5 * MB, line[:compression_rate]
    end
  end

  def test_writes_nothing_while_memory_is_unavailable
    Dir.mktmpdir do |dir|
      clock = Clock.new
      store = Agentmon::Store.new(dir:, clock:)
      engine = engine(nil, store:, clock:)
      run_ticks(engine, clock, 5)

      assert_empty store.each(:memory).to_a
      assert_empty engine.errors
    end
  end
end
