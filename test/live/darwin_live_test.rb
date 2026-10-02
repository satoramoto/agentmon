# frozen_string_literal: true

require "test_helper"

# Smoke tests against the real kernel (macOS only; CI runs on macos-latest as a normal user).
class DarwinLiveTest < Minitest::Test
  def setup = macos!

  def test_reads_this_process
    usage = Agentmon::Darwin.rusage(Process.pid)

    assert usage, "own process should be readable (errno #{Agentmon::Darwin.errno})"
    assert_operator usage.footprint, :>, 1024 * 1024
    assert_operator usage.resident, :>, 1024 * 1024
    assert_operator usage.start_ticks, :>, 0
    assert_in_delta Time.now.to_f, Agentmon::Darwin.started_at(Process.pid), 3600
  end

  def test_reads_this_process_task_info
    info = Agentmon::Darwin.task_info(Process.pid)

    assert info, "own task info should be readable (errno #{Agentmon::Darwin.errno})"
    assert_in_delta Agentmon::Darwin.started_at(Process.pid), info.started_at, 0.001
    assert_operator info.faults, :>, 0
    assert_operator info.threads, :>=, 1
    assert_operator info.context_switches, :>, 0
    assert_operator Agentmon::Darwin.rusage(Process.pid).runnable_time, :>=, 0.0
  end

  def test_cpu_time_matches_the_process_clock
    before = Agentmon::Darwin.rusage(Process.pid).cpu_time
    clock_before = Process.clock_gettime(Process::CLOCK_PROCESS_CPUTIME_ID)
    x = 0
    x += 1 while Process.clock_gettime(Process::CLOCK_PROCESS_CPUTIME_ID) - clock_before < 0.2
    burned = Process.clock_gettime(Process::CLOCK_PROCESS_CPUTIME_ID) - clock_before

    # If ticks weren't converted, this would be off by 41x on Apple Silicon.
    assert_in_delta burned, Agentmon::Darwin.rusage(Process.pid).cpu_time - before, burned * 0.5
  end

  def test_other_users_processes_are_unreadable_not_errors
    skip "running as root" if Process.uid.zero?

    assert_nil Agentmon::Darwin.rusage(1)
    assert_equal Agentmon::Darwin::EPERM, Agentmon::Darwin.errno
    assert_nil Agentmon::Darwin.started_at(1)
    assert_nil Agentmon::Darwin.task_info(1)
  end

  def test_exited_process_is_nil
    pid = Process.spawn("true")
    Process.wait(pid)

    assert_nil Agentmon::Darwin.rusage(pid)
  end

  def test_whole_machine_sample_is_fast_and_degrades
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    processes = Agentmon::Probes::Processes.read
    elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started

    assert_operator processes.size, :>, 20
    assert_operator elapsed, :<, 1.0, "sampling every process took #{elapsed.round(2)}s"
    me = processes.find { |p| p.pid == Process.pid }
    assert me.readable
    assert_operator me.faults, :>, 0
    assert_operator me.threads, :>=, 1
    launchd = processes.find { |p| p.pid == 1 }
    assert launchd, "ps lists launchd"
    assert_operator launchd.resident, :>, 0, "unreadable processes keep ps's rss" unless Process.uid.zero?
  end
end
