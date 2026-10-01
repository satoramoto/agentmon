# frozen_string_literal: true

require "test_helper"

class SessionLedgerMetricTest < Minitest::Test
  include Fixtures

  # Ledger after feeding these samples in order, as { root_pid => Session }.
  def ledger(*samples)
    engine = Fixtures.engine(*samples)
    reading = nil
    samples.size.times { reading = engine.tick! }
    reading[:session_ledger].to_h { |s| [s.root_pid, s] }
  end

  def without(sample, *pids, **overrides)
    procs = sample.parts[:processes].reject { |p| pids.include?(p.pid) }
    procs = procs.map { |p| overrides.key?(p.pid) ? p.with(**overrides[p.pid]) : p }
    Fixtures.sample(sample.mono - 1000.0, processes: procs, cwd: sample.parts[:cwd])
  end

  def test_first_sample_counts_the_whole_life_so_far
    s = ledger(machine(0))[200]

    assert_in_delta 12.6, s.cpu_seconds # 10 + 2 + 0.5 + 0.1 CPU seconds already used
    assert s.alive?
    assert_equal 4, s.processes
  end

  def test_growth_adds_up
    assert_in_delta 15.6, ledger(machine(0), machine(2))[200].cpu_seconds # claude +2, node +1
  end

  def test_a_reaped_child_is_counted_once
    # git (0.1 s when last seen, 0.3 s at exit) is reaped by zsh, whose child time grows by 0.3.
    reaped = without(machine(2), 203, 202 => { child_cpu_time: 0.3 })

    assert_in_delta 15.8, ledger(machine(0), reaped)[200].cpu_seconds
  end

  def test_an_orphan_leaving_keeps_its_time
    orphaned = machine(4, 201 => { ppid: 1 }) # node reparented to launchd: alive, out of the tree
    later = machine(6, 201 => { ppid: 1 })

    s = ledger(machine(0), machine(2), orphaned, later)[200]
    assert_in_delta 15.6 + 2 + 2, s.cpu_seconds # node's 4 s stay; claude's +4 after it left still count
  end

  def test_a_cli_session_ended_under_the_app_is_not_counted_again_by_the_app
    # claude 303 exits and disclaimer 302 reaps it: 302's child time grows by 303's 5 s.
    ended = without(machine(2), 303, 302 => { child_cpu_time: 5.0 })

    sessions = ledger(machine(0), ended)
    assert_in_delta 70.0, sessions[300].cpu_seconds
    refute sessions[303].alive?
    assert_in_delta 5.0, sessions[303].cpu_seconds
    assert_equal 0, sessions[303].footprint
  end

  def test_an_exit_nobody_reports_as_child_time_expires_from_the_pool
    # git exits but no parent's child time ever grows (reaped outside the tree, or a zombie).
    still = machine(0).parts[:processes].reject { |p| p.pid == 203 }
    frozen = (1..Agentmon::Metrics::SessionLedger::PENDING_SAMPLES).map { |i| Fixtures.sample(2 * i, processes: still) }
    grows = Fixtures.sample(12, processes: still.map { |p| p.pid == 200 ? p.with(cpu_time: p.cpu_time + 1) : p })

    assert_in_delta 12.6 + 1.0, ledger(machine(0), *frozen, grows)[200].cpu_seconds # the +1 isn't swallowed
  end

  def test_bytes_written_add_increases_and_reused_pids_start_over
    reused = without(machine(2), 203)
    reused = Fixtures.sample(2, processes: reused.parts[:processes] +
      [process(pid: 203, ppid: 202, name: "git", start_ticks: 999, disk_written: 100)], cwd: reused.parts[:cwd])

    s = ledger(machine(0), reused)[200]
    assert_equal (5 * MB) + 2000 + 100, s.bytes_written # git's 5 MB, claude +2000, the new git's 100
  end

  def test_peak_footprint_holds_the_maximum
    smaller = machine(2, 200 => { footprint: 100 * MB })

    s = ledger(machine(0), smaller)[200]
    assert_equal (512 + 100 + 8 + 8) * MB, s.peak_footprint
    assert_equal (100 + 100 + 8 + 8) * MB, s.footprint
  end

  def test_current_rates_are_summed_over_members
    s = ledger(machine(0), machine(2))[200]

    assert_in_delta 150.0, s.cpu # claude 1 s/s + node 0.5 s/s
    assert_in_delta 1000.0, s.write_rate
  end

  def test_ended_sessions_stay_for_a_while_then_go
    gone = without(machine(2), 303)
    keep = Agentmon::Metrics::SessionLedger::KEEP_ENDED

    assert ledger(machine(0), gone).key?(303)
    later = without(machine(2 + keep + 1), 303)
    refute ledger(machine(0), gone, later).key?(303)
  end
end
