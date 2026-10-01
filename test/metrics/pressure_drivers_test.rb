# frozen_string_literal: true

require "test_helper"

class PressureDriversMetricTest < Minitest::Test
  include Fixtures

  GB = 1024 * MB

  # A Session as the ledger reports it; only what pressure_drivers reads matters.
  def session(id, footprint:, ended_at: nil, label: nil)
    Agentmon::Session.new(
      id:, kind: :cli, name: "claude", root_pid: id.hash.abs % 10_000, label: label || "claude #{id}", cwd: nil,
      started_at: T0, first_seen_at: T0, last_seen_at: T0, ended_at:, processes: 1, cpu: 0.0,
      footprint:, resident: footprint, read_rate: 0.0, write_rate: 0.0, peak_footprint: footprint,
      cpu_seconds: 0.0, bytes_read: 0, bytes_written: 0
    )
  end

  def memory(used:)
    Agentmon::MemoryView.new(
      total: 16 * GB, used:, app: used, wired: 0, compressed: 0, cached: 0, free: 0, swap_used: 0, swap_total: 0,
      compression_ratio: 0.0, swapin_rate: 0.0, swapout_rate: 0.0, compression_rate: 0.0,
      decompression_rate: 0.0, pressure: 20.0, pressure_trend: []
    )
  end

  # Readings at the given times (seconds after T0) sharing one metric state, as the Engine's are;
  # each step is [t, ledger, memory]. Returns the last reading's drivers.
  def drivers(*steps)
    states = Hash.new { |h, k| h[k] = {} }
    previous = nil
    result = nil
    steps.each do |t, ledger, mem|
      sample = Fixtures.sample(t, processes: [])
      reading = Agentmon::Reading.new(sample, previous:, states:, values: { session_ledger: ledger, memory: mem })
      result = reading[:pressure_drivers]
      previous = sample
    end
    result
  end

  def test_alive_sessions_largest_footprint_first_with_share_of_used
    ledger = [session("a", footprint: 1 * GB), session("b", footprint: 3 * GB), session("c", footprint: 2 * GB)]

    list = drivers([0, ledger, memory(used: 8 * GB)])
    assert_equal %w[b c a], list.map(&:session_id)
    assert_kind_of Agentmon::PressureDriver, list.first
    assert_equal "claude b", list.first.label
    assert_equal 3 * GB, list.first.footprint
    assert_in_delta 37.5, list.first.share
    assert_in_delta 12.5, list.last.share
  end

  def test_ended_and_zero_footprint_sessions_are_left_out
    ledger = [session("alive", footprint: 1 * GB), session("ended", footprint: 0, ended_at: T0),
              session("idle", footprint: 0)]

    assert_equal %w[alive], drivers([0, ledger, memory(used: 4 * GB)]).map(&:session_id)
  end

  def test_share_is_nil_while_memory_is_unknown
    list = drivers([0, [session("a", footprint: 1 * GB)], nil])

    assert_nil list.first.share
    assert_equal 1 * GB, list.first.footprint
  end

  def test_empty_without_a_ledger
    assert_equal [], drivers([0, nil, memory(used: 4 * GB)])
  end

  def test_growth_is_zero_until_two_samples
    assert_in_delta 0.0, drivers([0, [session("a", footprint: 1 * GB)], nil]).first.growth_rate
  end

  def test_growth_rate_is_bytes_per_second_over_the_samples_seen
    list = drivers([0, [session("a", footprint: 100 * MB)], nil],
                   [2, [session("a", footprint: 110 * MB)], nil],
                   [4, [session("a", footprint: 120 * MB)], nil])

    assert_in_delta 5.0 * MB, list.first.growth_rate
  end

  def test_growth_rate_covers_only_the_last_minute
    # Flat for a minute, then +60 MB in the last 30 s: the old flat start is forgotten.
    steps = (0..60).step(10).map { |t| [t, [session("a", footprint: 100 * MB)], nil] }
    steps += [[90, [session("a", footprint: 160 * MB)], nil]]

    # Window is t = 30..90: 100 MB -> 160 MB over 60 s.
    assert_in_delta 1.0 * MB, drivers(*steps).first.growth_rate
  end

  def test_shrinking_footprint_has_negative_growth
    list = drivers([0, [session("a", footprint: 200 * MB)], nil], [10, [session("a", footprint: 100 * MB)], nil])

    assert_in_delta(-10.0 * MB, list.first.growth_rate)
  end

  def test_growth_is_tracked_per_session_and_a_new_session_starts_at_zero
    list = drivers([0, [session("a", footprint: 100 * MB)], nil],
                   [10, [session("a", footprint: 200 * MB), session("b", footprint: 50 * MB)], nil])
      .to_h { |d| [d.session_id, d] }

    assert_in_delta 10.0 * MB, list["a"].growth_rate
    assert_in_delta 0.0, list["b"].growth_rate
  end

  def test_a_session_that_ends_forgets_its_history
    list = drivers([0, [session("a", footprint: 100 * MB)], nil],
                   [10, [session("a", footprint: 100 * MB, ended_at: T0 + 5)], nil],
                   [20, [session("a", footprint: 300 * MB)], nil])

    assert_in_delta 0.0, list.first.growth_rate
  end

  def test_runs_on_the_engine_without_raising
    engine = Fixtures.engine(machine(0), machine(2))
    engine.tick!
    reading = engine.tick!

    assert_empty reading.errors
    ids = reading[:session_ledger].select { |s| s.alive? && s.footprint.positive? }.map(&:id)
    assert_equal ids.sort, reading[:pressure_drivers].map(&:session_id).sort
    assert(reading[:pressure_drivers].each_cons(2).all? { |a, b| a.footprint >= b.footprint })
  end
end
