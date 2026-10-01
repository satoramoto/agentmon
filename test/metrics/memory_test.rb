# frozen_string_literal: true

require "test_helper"

class MemoryMetricTest < Minitest::Test
  include Fixtures

  GB = 1024 * MB

  # A MemoryStat with round numbers; pass only what the test is about.
  def stat(**overrides)
    Agentmon::MemoryStat.new(
      total: 16 * GB, free: 1 * GB, app: 6 * GB, wired: 2 * GB, compressed: 1 * GB,
      compressor_stored: 3 * GB, cached: 5 * GB, purgeable: 512 * MB,
      swap_total: 2 * GB, swap_used: 1 * GB,
      swapins: 0, swapouts: 0, compressions: 0, decompressions: 0, pageins: 0,
      memorystatus_level: 70, **overrides
    )
  end

  def at(t, memory) = sample(t, processes: [], memory:)

  # reading[:memory] after feeding these samples in order through one engine (metric state kept).
  def view(*samples)
    engine = Fixtures.engine(*samples)
    reading = nil
    samples.size.times { reading = engine.tick! }
    reading[:memory]
  end

  def test_breakdown_is_activity_monitors
    m = view(at(0, stat))

    assert_instance_of Agentmon::MemoryView, m
    assert_equal 9 * GB, m.used # app + wired + compressed
    assert_equal 16 * GB, m.total
    assert_equal 6 * GB, m.app
    assert_equal 2 * GB, m.wired
    assert_equal 1 * GB, m.compressed
    assert_equal 5 * GB, m.cached
    assert_equal 1 * GB, m.free
    assert_equal 1 * GB, m.swap_used
    assert_equal 2 * GB, m.swap_total
    assert_in_delta 3.0, m.compression_ratio
    assert_in_delta 30.0, m.pressure # 100 - memorystatus_level
  end

  def test_compression_ratio_is_zero_when_nothing_is_compressed
    assert_in_delta 0.0, view(at(0, stat(compressed: 0, compressor_stored: 0))).compression_ratio
  end

  def test_rates_are_zero_on_the_first_sample
    m = view(at(0, stat(swapins: 4 * MB, swapouts: 8 * MB, compressions: 2 * MB, decompressions: MB)))

    %i[swapin_rate swapout_rate compression_rate decompression_rate].each do |rate|
      assert_in_delta 0.0, m.public_send(rate), 0.0, rate.to_s
      assert_kind_of Float, m.public_send(rate)
    end
  end

  def test_rates_are_counter_deltas_over_the_monotonic_interval
    before = at(0, stat(swapins: 0, swapouts: 2 * MB, compressions: 10 * MB, decompressions: 4 * MB))
    now = at(2, stat(swapins: 4 * MB, swapouts: 2 * MB, compressions: 16 * MB, decompressions: 5 * MB))
    m = view(before, now)

    assert_in_delta 2.0 * MB, m.swapin_rate
    assert_in_delta 0.0, m.swapout_rate
    assert_in_delta 3.0 * MB, m.compression_rate
    assert_in_delta 0.5 * MB, m.decompression_rate
  end

  def test_a_counter_that_went_backwards_gives_zero
    before = at(0, stat(swapins: 9 * MB, compressions: 9 * MB))
    now = at(2, stat(swapins: 1 * MB, compressions: 10 * MB)) # e.g. counters reset over sleep

    m = view(before, now)
    assert_in_delta 0.0, m.swapin_rate
    assert_in_delta 0.5 * MB, m.compression_rate
  end

  def test_pressure_trend_keeps_the_last_sixty_oldest_first
    samples = (0...65).map { |i| at(i * 2, stat(memorystatus_level: 100 - i)) }
    trend = view(*samples).pressure_trend

    assert_equal 60, trend.size
    assert_equal (5...65).map(&:to_f), trend
  end

  def test_pressure_trend_grows_from_one_value
    assert_equal [30.0], view(at(0, stat)).pressure_trend
    assert_equal [30.0, 40.0], view(at(0, stat), at(2, stat(memorystatus_level: 60))).pressure_trend
  end

  def test_nil_when_the_probe_has_no_memory
    assert_nil view(at(0, nil))
    assert_nil Fixtures.reading(machine(0))[:memory] # no memory part at all (probe a01 not merged)
  end

  def test_a_sample_without_memory_neither_breaks_rates_nor_the_trend
    m = view(at(0, stat(swapins: 0)), at(2, nil), at(4, stat(swapins: 8 * MB, memorystatus_level: 60)))

    assert_in_delta 0.0, m.swapin_rate # no previous memory to diff against
    assert_equal [30.0, 40.0], m.pressure_trend
  end

  def test_unknown_fields_stay_unknown
    m = view(at(0, stat(memorystatus_level: nil, compressor_stored: nil)),
             at(2, stat(memorystatus_level: nil, compressor_stored: nil, swapins: nil)))

    assert_nil m.pressure
    assert_empty m.pressure_trend
    assert_nil m.compression_ratio
    assert_nil m.swapin_rate
  end
end
