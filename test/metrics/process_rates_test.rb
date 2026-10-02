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
    assert_nil rates(now, nil)[7].pagein_rate
    assert_nil rates(now, nil)[7].run_wait
  end

  def test_paging_and_scheduling_rates
    r = rates(machine(2), machine(0))[200]

    assert_in_delta 10.0, r.pagein_rate
    assert_in_delta 1000.0, r.fault_rate
    assert_in_delta 100.0, r.cow_fault_rate
    assert_in_delta 500.0, r.context_switch_rate
    assert_in_delta 25.0, r.run_wait # runnable grew 2.5 s, 2 of them on a CPU: 0.5 s waiting in 2 s
  end

  def test_a_wrapped_32_bit_counter_still_gives_its_rate
    before = sample(0, processes: [process(pid: 7, faults: (2**32) - 100)])
    now = sample(2, processes: [process(pid: 7, faults: 100)])

    assert_in_delta 100.0, rates(now, before)[7].fault_rate
  end

  def test_unknown_counters_give_nil_rates
    before = sample(0, processes: [process(pid: 7).with(faults: nil, runnable_time: nil)])
    now = sample(2, processes: [process(pid: 7, faults: 10, runnable_time: 5.0)])

    assert_nil rates(now, before)[7].fault_rate
    assert_nil rates(now, before)[7].run_wait
  end
end
