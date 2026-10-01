# frozen_string_literal: true

require "test_helper"

class ProcessRatesMetricTest < Minitest::Test
  include Fixtures

  def rates(now, before) = Fixtures.reading(now, previous: before)[:process_rates]

  def test_cpu_percent_is_cpu_seconds_over_the_interval
    before = sample(0, processes: [process(pid: 7, cpu_time: 10.0, disk_read: 0, disk_written: 1000)])
    now = sample(2, processes: [process(pid: 7, cpu_time: 13.0, disk_read: 4096, disk_written: 5000)])

    r = rates(now, before)[7]
    assert_in_delta 150.0, r.cpu # 3 CPU seconds in 2 s: one and a half cores
    assert_in_delta 2048.0, r.read_rate
    assert_in_delta 2000.0, r.write_rate
  end

  def test_a_reused_pid_gets_no_rate_from_the_old_process
    before = sample(0, processes: [process(pid: 7, start_ticks: 1, cpu_time: 100.0, ps_cpu: 0.0)])
    now = sample(2, processes: [process(pid: 7, start_ticks: 2, cpu_time: 0.5, ps_cpu: 3.0)])

    r = rates(now, before)[7]
    assert_in_delta 3.0, r.cpu
    assert_nil r.write_rate
  end

  def test_first_sample_and_unreadable_processes_use_ps
    now = sample(0, processes: [process(pid: 7, ps_cpu: 4.0), process(pid: 8, readable: false, ps_cpu: 9.0)])

    assert_in_delta 4.0, rates(now, nil)[7].cpu
    assert_in_delta 9.0, rates(now, nil)[8].cpu
    assert_nil rates(now, nil)[8].read_rate
  end
end
