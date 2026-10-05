# frozen_string_literal: true

require "test_helper"

class DarwinCoreTest < Minitest::Test
  def setup = Agentmon::Darwin.ns_per_tick = Rational(125, 3) # Apple Silicon's timebase

  def teardown = Agentmon::Darwin.ns_per_tick = nil

  # rusage_info_v4 fields after the uuid, all zero except the ones given.
  def fields(**values)
    Array.new(Agentmon::Darwin::RUSAGE_FIELDS, 0).tap do |a|
      values.each { |name, v| a[Agentmon::Darwin::FIELDS.fetch(name)] = v }
    end
  end

  # Byte offsets of struct rusage_info_v4 as xnu's bsd/sys/resource.h lays it out (a 16-byte
  # ri_uuid, then uint64s), written out by hand so a wrong Darwin::FIELDS index can't pass.
  OFFSETS = {
    ri_user_time: 16, ri_system_time: 24, ri_resident_size: 64, ri_phys_footprint: 72, ri_proc_start_abstime: 80,
    ri_child_user_time: 96, ri_child_system_time: 104, ri_diskio_bytesread: 144, ri_diskio_byteswritten: 152,
    ri_lifetime_max_phys_footprint: 240, ri_pageins: 48, ri_wired_size: 56, ri_runnable_time: 288
  }.freeze

  # struct proc_taskallinfo: proc_bsdinfo (136 bytes, start time at 120), then proc_taskinfo:
  # six uint64s (48 bytes), then int32 pti_policy, pti_faults, pti_pageins, pti_cow_faults, ...
  TASK_OFFSETS = { pbi_start_tvsec: 120, pbi_start_tvusec: 128, pti_faults: 136 + 52, pti_pageins: 136 + 56,
                   pti_cow_faults: 136 + 60, pti_csw: 136 + 80, pti_threadnum: 136 + 84, pti_numrunning: 136 + 88 }.freeze

  def test_struct_size_is_rusage_info_v4
    assert_equal 296, Agentmon::Darwin::RUSAGE_SIZE # 16 + 35 x 8: ri_user_time .. ri_runnable_time
  end

  def test_decodes_the_kernels_bytes_at_the_v4_offsets
    Agentmon::Darwin.ns_per_tick = 1
    bytes = ("\xAB".b * 16) + ("\x00".b * 280) # a uuid, then zeroes
    values = { ri_user_time: 1_000_000_000, ri_system_time: 500_000_000, ri_resident_size: 111,
               ri_phys_footprint: 222, ri_proc_start_abstime: 333, ri_child_user_time: 2_000_000_000,
               ri_child_system_time: 0, ri_diskio_bytesread: 444, ri_diskio_byteswritten: 555,
               ri_lifetime_max_phys_footprint: 666 }
    values.each { |field, v| bytes[OFFSETS.fetch(field), 8] = [v].pack("Q<") }
    bytes[32, 8] = [999].pack("Q<") # ri_pkg_idle_wkups: a neighbour that must not leak in

    usage = Agentmon::Darwin.decode_rusage_bytes(bytes)

    assert_in_delta 1.5, usage.cpu_time
    assert_in_delta 2.0, usage.child_cpu_time
    assert_equal [111, 222, 666, 444, 555, 333],
                 [usage.resident, usage.footprint, usage.peak_footprint, usage.disk_read, usage.disk_written, usage.start_ticks]
  end

  def test_cpu_times_are_mach_ticks_converted_to_seconds
    # 24_000_000 ticks x 125/3 ns = 1 s
    usage = Agentmon::Darwin.decode_rusage(fields(user_time: 18_000_000, system_time: 6_000_000,
                                                  child_user_time: 48_000_000, child_system_time: 0))

    assert_in_delta 1.0, usage.cpu_time, 1e-9
    assert_in_delta 2.0, usage.child_cpu_time, 1e-9
  end

  def test_intel_ticks_are_nanoseconds
    Agentmon::Darwin.ns_per_tick = 1

    assert_in_delta 1.5, Agentmon::Darwin.decode_rusage(fields(user_time: 1_500_000_000)).cpu_time, 1e-9
  end

  def test_paging_and_runnable_time_at_the_v4_offsets
    bytes = ("\x00".b * 296)
    { ri_pageins: 77, ri_wired_size: 4096, ri_runnable_time: 48_000_000 }.each do |field, v|
      bytes[OFFSETS.fetch(field), 8] = [v].pack("Q<")
    end

    usage = Agentmon::Darwin.decode_rusage_bytes(bytes)

    assert_equal [77, 4096], [usage.pageins, usage.wired]
    assert_in_delta 2.0, usage.runnable_time, 1e-9 # Mach ticks x 125/3 ns, like CPU time
  end

  def test_decodes_task_all_info_at_the_kernel_offsets
    bytes = ("\x00".b * Agentmon::Darwin::TASKALLINFO_SIZE)
    bytes[TASK_OFFSETS[:pbi_start_tvsec], 8] = [1_790_000_000].pack("Q<")
    bytes[TASK_OFFSETS[:pbi_start_tvusec], 8] = [500_000].pack("Q<")
    { pti_faults: 4_000_000_000, pti_pageins: 9, pti_cow_faults: 3, pti_csw: 1234, pti_threadnum: 12,
      pti_numrunning: 2 }.each { |field, v| bytes[TASK_OFFSETS.fetch(field), 4] = [v].pack("L<") }

    info = Agentmon::Darwin.decode_task_info_bytes(bytes)

    assert_equal 232, Agentmon::Darwin::TASKALLINFO_SIZE
    assert_in_delta 1_790_000_000.5, info.started_at
    assert_equal 4_000_000_000, info.faults # past 2**31: read unsigned, never negative
    assert_equal [3, 1234, 12, 2], [info.cow_faults, info.context_switches, info.threads, info.running_threads]
  end

  def test_decodes_the_fd_list
    bytes = [0, 1, 1, 1, 7, 2, 12, 1].pack("l<L<l<L<l<L<l<L<") + "\x00\x00".b # a partial trailing entry is ignored

    assert_equal [[0, 1], [1, 1], [7, 2], [12, 1]], Agentmon::Darwin.decode_fdinfo_list(bytes)
    assert_empty Agentmon::Darwin.decode_fdinfo_list("".b)
  end

  # struct vnode_fdinfowithpath: proc_fileinfo (24) + vnode_info (vinfo_stat 136 + 4 + 4 + fsid 8),
  # then vip_path[1024] at 176 (xnu bsd/sys/proc_info.h), written out by hand.
  def test_decodes_the_vnode_path_at_the_kernel_offset
    assert_equal 1200, Agentmon::Darwin::VNODE_PATH_SIZE
    bytes = ("\xFF".b * 176) + ("\x00".b * 1024)
    path = "/Users/me/.codex/sessions/2026/10/04/rollout-é.jsonl"
    bytes[176, path.bytesize] = path.b

    assert_equal path, Agentmon::Darwin.decode_vnode_path(bytes)
    assert_equal "", Agentmon::Darwin.decode_vnode_path(("\xFF".b * 176) + ("\x00".b * 1024))
  end

  def test_sizes_and_io_are_bytes_and_start_is_raw_ticks
    usage = Agentmon::Darwin.decode_rusage(fields(resident_size: 100, phys_footprint: 200, lifetime_max_phys_footprint: 300,
                                                  diskio_bytesread: 400, diskio_byteswritten: 500, proc_start_abstime: 42))

    assert_equal [100, 200, 300, 400, 500, 42],
                 [usage.resident, usage.footprint, usage.peak_footprint, usage.disk_read, usage.disk_written, usage.start_ticks]
  end
end
