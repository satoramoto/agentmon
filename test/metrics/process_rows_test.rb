# frozen_string_literal: true

require "test_helper"

class ProcessRowsMetricTest < Minitest::Test
  include Fixtures

  def rows(now, before) = Fixtures.reading(now, previous: before)[:process_rows].to_h { |r| [r.pid, r] }

  def test_paging_and_scheduling_counters_and_rates_reach_the_rows
    claude = rows(machine(2), machine(0))[200]

    assert_equal [1 * MB, 20, 2000, 200, 1000, 12, 1],
                 [claude.wired, claude.pageins, claude.faults, claude.cow_faults, claude.context_switches,
                  claude.threads, claude.running_threads]
    assert_in_delta 12.5, claude.runnable_time
    assert_equal 0, claude.disk_read
    assert_in_delta 10.0, claude.pagein_rate
    assert_in_delta 1000.0, claude.fault_rate
    assert_in_delta 100.0, claude.cow_fault_rate
    assert_in_delta 500.0, claude.context_switch_rate
    assert_in_delta 25.0, claude.run_wait
  end

  def test_unreadable_and_first_seen_processes_have_nil_paging
    first = rows(machine(0), nil)
    server = first[500]

    assert_nil server.pageins
    assert_nil server.run_wait
    assert_nil first[200].pagein_rate
    assert_equal 0, first[200].pageins
  end
end
