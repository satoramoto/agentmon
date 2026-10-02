# frozen_string_literal: true

require "test_helper"

class ProcessesProbeTest < Minitest::Test
  PS = <<~PS
        1     0  21728   0.0 /sbin/launchd
    59334     1 340000   1.5 /Applications/Claude.app/Contents/MacOS/Claude
    59351 59334  10000   0.2 /Applications/Claude.app/Contents/Frameworks/Claude Helper (Renderer).app/Contents/MacOS/Claude Helper (Renderer)
  PS

  # Darwin's reader interface over fixed values: launchd is EPERM.
  class Reader
    def rusage(pid)
      return nil if pid == 1

      Agentmon::Darwin::Rusage.new(cpu_time: 2.5, child_cpu_time: 0.5, resident: 300 * 1024, footprint: 200 * 1024,
                                   peak_footprint: 250 * 1024, disk_read: 7, disk_written: 9, start_ticks: pid * 10,
                                   wired: 4096, pageins: 11, runnable_time: 3.0)
    end

    # The Claude Helper's task info fails (as if it exited between the two calls).
    def task_info(pid)
      return nil if pid == 59_351

      Agentmon::Darwin::TaskInfo.new(started_at: 1_790_000_000.0 + pid, faults: 100, cow_faults: 5,
                                     context_switches: 70, threads: 4, running_threads: 1)
    end

    def started_at(pid) = 1_700_000_000.0 + pid
  end

  def processes = Agentmon::Probes::Processes.read(ps_text: PS, reader: Reader.new)

  def test_names_come_from_paths_with_spaces
    assert_equal ["launchd", "Claude", "Claude Helper (Renderer)"], processes.map(&:name)
    assert_equal 59_334, processes.last.ppid
  end

  def test_readable_processes_use_rusage
    claude = processes[1]

    assert claude.readable
    assert_equal [2.5, 0.5, 300 * 1024, 200 * 1024, 9], [claude.cpu_time, claude.child_cpu_time, claude.resident,
                                                          claude.footprint, claude.disk_written]
    assert_equal [59_334, 593_340], claude.identity
    assert_in_delta 1_790_059_334.0, claude.started_at
  end

  def test_paging_and_scheduling_come_from_rusage_and_task_info
    claude = processes[1]

    assert_equal [4096, 11, 100, 5, 70, 4, 1], [claude.wired, claude.pageins, claude.faults, claude.cow_faults,
                                                 claude.context_switches, claude.threads, claude.running_threads]
    assert_in_delta 3.0, claude.runnable_time
  end

  def test_task_info_failure_keeps_rusage_and_reads_the_start_time_alone
    helper = processes.last

    assert helper.readable
    assert_in_delta 1_700_059_351.0, helper.started_at
    assert_equal 11, helper.pageins
    assert_nil helper.faults
    assert_nil helper.threads
  end

  def test_unreadable_processes_fall_back_to_ps_in_bytes
    launchd = processes.first

    refute launchd.readable
    assert_equal 21_728 * 1024, launchd.resident # ps rss is KiB
    assert_nil launchd.footprint
    assert_nil launchd.cpu_time
    assert_nil launchd.disk_written
    assert_nil launchd.pageins
    assert_nil launchd.faults
    assert_nil launchd.runnable_time
    assert_in_delta 0.0, launchd.ps_cpu
  end

  def test_cwd_probe_parses_lsof_fields
    text = "p1\nfcwd\nn/\np4242\nfcwd\nn/Users/me/src/repo\n"

    assert_equal({ 1 => "/", 4242 => "/Users/me/src/repo" }, Agentmon::Probes::Cwd.parse(text))
  end
end
