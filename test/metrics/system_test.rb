# frozen_string_literal: true

require "test_helper"

class SystemMetricTest < Minitest::Test
  include Fixtures

  # A SystemStat at `t` (at_mono follows the sample's mono); pass only what the test is about.
  def stat(t, cpu_ticks: [0, 0, 0, 0], net_in: 0, net_out: 0, **overrides)
    Agentmon::SystemStat.new(cpu_ticks:, ncpu: 10, load: [1.5, 2.0, 2.5], net_in:, net_out:,
                             at_mono: 1000.0 + t, **overrides)
  end

  def at(t, system, processes: []) = sample(t, processes:, system:)

  # reading[:system] after each sample, fed in order through one engine (metric state kept).
  def views(*samples)
    engine = Fixtures.engine(*samples)
    samples.map { engine.tick![:system] }
  end

  def view(*samples) = views(*samples).last

  def test_first_sample_has_no_rates
    v = view(at(0, stat(0, cpu_ticks: [100, 50, 800, 10], net_in: 5000)))

    assert_instance_of Agentmon::SystemView, v
    assert_nil v.cpu
    assert_nil v.user
    assert_nil v.net_in_rate
    assert_nil v.net_out_rate
    assert_equal 10, v.ncpu
    assert_in_delta 1.5, v.load1
    assert_in_delta 2.0, v.load5
    assert_in_delta 2.5, v.load15
    assert_empty v.cpu_trend
  end

  def test_cpu_percent_of_the_whole_machine
    # Over 2 s: 300 user, 100 system, 50 nice, 550 idle ticks = 1000 total.
    v = view(at(0, stat(0, cpu_ticks: [1000, 1000, 1000, 1000])),
             at(2, stat(2, cpu_ticks: [1300, 1100, 1550, 1050])))

    assert_in_delta 30.0, v.user
    assert_in_delta 10.0, v.system
    assert_in_delta 45.0, v.cpu # user + system + nice
    assert_equal [45.0], v.cpu_trend
  end

  def test_network_rates_use_the_probe_clock
    # The probe read 4 s apart though the samples are 2 s apart: rates use the probe's at_mono.
    v = view(at(0, stat(0, net_in: 1_000, net_out: 0)),
             at(2, stat(2, net_in: 9_000, net_out: 4_000, at_mono: 1004.0)))

    assert_in_delta 2_000.0, v.net_in_rate
    assert_in_delta 1_000.0, v.net_out_rate
    assert_equal [2_000.0], v.net_in_trend
    assert_equal [1_000.0], v.net_out_trend
  end

  def test_falls_back_to_the_sample_interval_without_at_mono
    v = view(at(0, stat(0, net_in: 0, at_mono: nil)), at(2, stat(2, net_in: 4_000, at_mono: nil)))

    assert_in_delta 2_000.0, v.net_in_rate
  end

  def test_counter_going_backwards_is_nil_not_negative
    first, second, third = views(at(0, stat(0, net_in: 10_000, net_out: 10_000, cpu_ticks: [500, 500, 500, 500])),
                                 at(2, stat(2, net_in: 100, net_out: 12_000, cpu_ticks: [10, 10, 10, 10])),
                                 at(4, stat(4, net_in: 4_100, net_out: 14_000, cpu_ticks: [20, 20, 20, 20])))

    assert_nil first.net_in_rate
    assert_nil second.net_in_rate # interface reset
    assert_in_delta 1_000.0, second.net_out_rate
    assert_nil second.cpu
    assert_in_delta 2_000.0, third.net_in_rate # counts again from the reset value
    assert_in_delta 75.0, third.cpu # user + system + nice of four equal deltas
    assert_equal [2_000.0], third.net_in_trend # the unknown sample isn't in the trend
  end

  def test_disk_rates_sum_known_process_rows
    # machine(): claude 200 writes 1000 B/s, every other readable process 0; WindowServer unknown.
    engine = Fixtures.engine(machine(0).then { |s| s.with(parts: s.parts.merge(system: stat(0))) },
                             machine(2).then { |s| s.with(parts: s.parts.merge(system: stat(2))) })
    first = engine.tick![:system]
    second = engine.tick![:system]

    assert_nil first.disk_read_rate # no process has a rate yet
    assert_nil first.disk_write_rate
    assert_in_delta 0.0, second.disk_read_rate
    assert_in_delta 1_000.0, second.disk_write_rate
    assert_equal [1_000.0], second.disk_trend
  end

  def test_disk_rates_are_nil_without_rows
    v = Agentmon::Reading.new(at(0, stat(0)), values: { process_rows: nil })[:system]

    assert_nil v.disk_read_rate
    assert_nil v.disk_write_rate
  end

  def test_trends_keep_the_last_120_oldest_first
    samples = (0..130).map { |i| at(i, stat(i, net_in: i * i)) } # rate between i-1 and i: 2i - 1
    v = view(*samples)

    assert_equal 120, v.net_in_trend.size
    assert_in_delta (2 * 11) - 1.0, v.net_in_trend.first
    assert_in_delta (2 * 130) - 1.0, v.net_in_trend.last
    assert_predicate v.net_in_trend, :frozen?
  end

  def test_nil_without_a_system_stat
    assert_nil view(at(0, nil))
  end
end
