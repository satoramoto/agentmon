# frozen_string_literal: true

require "test_helper"

class DarwinTest < Minitest::Test
  def setup = Agentmon::Darwin.ns_per_tick = Rational(125, 3) # Apple Silicon's timebase

  def teardown = Agentmon::Darwin.ns_per_tick = nil

  # rusage_info_v4 fields after the uuid, all zero except the ones given.
  def fields(**values)
    Array.new(56, 0).tap do |a|
      values.each { |name, v| a[Agentmon::Darwin::FIELDS.fetch(name)] = v }
    end
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

  def test_sizes_and_io_are_bytes_and_start_is_raw_ticks
    usage = Agentmon::Darwin.decode_rusage(fields(resident_size: 100, phys_footprint: 200, lifetime_max_phys_footprint: 300,
                                                  diskio_bytesread: 400, diskio_byteswritten: 500, proc_start_abstime: 42))

    assert_equal [100, 200, 300, 400, 500, 42],
                 [usage.resident, usage.footprint, usage.peak_footprint, usage.disk_read, usage.disk_written, usage.start_ticks]
  end
end
