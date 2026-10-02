# frozen_string_literal: true

require "fiddle"

module Agentmon
  # macOS kernel data through Fiddle, without subprocesses: per-process resource usage
  # (proc_pid_rusage, RUSAGE_INFO_V4), process start time plus fault and scheduling counters
  # (proc_pidinfo PROC_PIDTASKALLINFO; PROC_PIDTBSDINFO for the start time alone) and the Mach
  # clock (mach_timebase_info).
  #
  # Units: CPU times come from the kernel in Mach absolute-time ticks. On Intel a tick is 1 ns; on
  # Apple Silicon it is 125/3 ns (41.67 ns), so ticks are always converted with the timebase and
  # everything this module returns is in seconds (Float) or bytes (Integer).
  #
  # Other users' processes (root daemons) can't be read without root: the kernel answers EPERM and
  # the readers here return nil. Callers fall back to what ps reports.
  module Darwin
    RUSAGE_INFO_V4 = 4
    # struct rusage_info_v4: a 16-byte uuid, then 35 uint64 fields (ri_user_time ..
    # ri_runnable_time) = 296 bytes. v5 and v6 append fields; v4 is what we ask for.
    RUSAGE_FIELDS = 35
    RUSAGE_SIZE = 16 + (8 * RUSAGE_FIELDS)
    PROC_PIDTASKALLINFO = 2
    PROC_PIDTBSDINFO = 3
    # struct proc_bsdinfo is 136 bytes; pbi_start_tvsec/usec are its last two uint64 fields.
    BSDINFO_SIZE = 136
    BSDINFO_START = 120
    # struct proc_taskallinfo = proc_bsdinfo (136) + proc_taskinfo (96): six uint64s
    # (pti_virtual_size .. pti_threads_system), then twelve int32s (pti_policy .. pti_priority).
    TASKINFO_SIZE = 96
    TASKALLINFO_SIZE = BSDINFO_SIZE + TASKINFO_SIZE
    # Indexes of the int32 fields after the six uint64s (xnu bsd/sys/proc_info.h).
    TASK_FIELDS = { faults: 1, pageins: 2, cow_faults: 3, csw: 8, threadnum: 9, numrunning: 10 }.freeze

    # Indexes of the uint64 fields after the uuid (xnu bsd/sys/resource.h).
    FIELDS = {
      user_time: 0, system_time: 1, pageins: 4, wired_size: 5, resident_size: 6, phys_footprint: 7,
      proc_start_abstime: 8, child_user_time: 10, child_system_time: 11, diskio_bytesread: 16,
      diskio_byteswritten: 17, lifetime_max_phys_footprint: 28, runnable_time: 34
    }.freeze

    EPERM = 1
    ESRCH = 3

    # One process's counters, converted: seconds and bytes. Cumulative since the process started.
    Rusage = Data.define(
      :cpu_time,        # user + system CPU seconds (Float)
      :child_cpu_time,  # user + system CPU seconds of children it has reaped (Float)
      :resident,        # resident set size, bytes
      :footprint,       # physical footprint (Activity Monitor's "Memory"), bytes
      :peak_footprint,  # lifetime maximum footprint, bytes
      :disk_read,       # bytes read from disk
      :disk_written,    # bytes written to disk
      :start_ticks,     # start time in Mach ticks: with the pid, identifies the process across pid reuse
      :wired,           # wired bytes
      :pageins,         # count of faults that read from disk
      :runnable_time    # seconds runnable (running or waiting for a CPU)
    ) do
      def initialize(wired: nil, pageins: nil, runnable_time: nil, **) = super
    end

    # proc_taskallinfo, decoded: start time plus the task's fault and scheduling counters.
    # Counts are the kernel's 32-bit counters, read unsigned (they wrap at 2**32).
    TaskInfo = Data.define(
      :started_at,       # epoch seconds (Float)
      :faults,           # page faults, any kind
      :cow_faults,       # copy-on-write faults
      :context_switches,
      :threads,          # threads now
      :running_threads   # threads running now
    )

    class << self
      def available? = RUBY_PLATFORM.include?("darwin")

      # Rusage for `pid`, or nil when it can't be read (EPERM for other users' processes, ESRCH
      # when it has exited). `errno` after a nil says which.
      def rusage(pid)
        buffer = Fiddle::Pointer.malloc(RUSAGE_SIZE, Fiddle::RUBY_FREE)
        return fail_with(Fiddle.last_error) unless functions[:rusage].call(pid, RUSAGE_INFO_V4, buffer).zero?

        Thread.current[:agentmon_errno] = 0
        decode_rusage_bytes(buffer[0, RUSAGE_SIZE])
      end

      # Decodes a whole rusage_info_v4 as the kernel wrote it (uuid included, native-endian
      # uint64s; every Mac agentmon runs on is little-endian). Public for tests.
      def decode_rusage_bytes(bytes) = decode_rusage(bytes.byteslice(16, RUSAGE_SIZE - 16).unpack("Q<*"))

      # Decodes the uint64 fields of a rusage_info_v4 (after the uuid), by FIELDS index.
      def decode_rusage(values)
        f = ->(name) { values.fetch(FIELDS.fetch(name)) }
        Rusage.new(
          cpu_time: ticks_to_seconds(f[:user_time] + f[:system_time]),
          child_cpu_time: ticks_to_seconds(f[:child_user_time] + f[:child_system_time]),
          resident: f[:resident_size],
          footprint: f[:phys_footprint],
          peak_footprint: f[:lifetime_max_phys_footprint],
          disk_read: f[:diskio_bytesread],
          disk_written: f[:diskio_byteswritten],
          start_ticks: f[:proc_start_abstime],
          wired: f[:wired_size],
          pageins: f[:pageins],
          # Mach ticks, like the CPU times (checked: 30 busy processes on 10 cores for 2 s report
          # ~2.0 s runnable as ticks, 0.05 s if they were ns; it counts time on a CPU too).
          runnable_time: ticks_to_seconds(f[:runnable_time])
        )
      end

      # Wall-clock start time of `pid` as epoch seconds (Float), or nil when unreadable.
      def started_at(pid)
        buffer = Fiddle::Pointer.malloc(BSDINFO_SIZE, Fiddle::RUBY_FREE)
        return fail_with(Fiddle.last_error) unless functions[:pidinfo].call(pid, PROC_PIDTBSDINFO, 0, buffer, BSDINFO_SIZE) == BSDINFO_SIZE

        decode_start(buffer[0, BSDINFO_SIZE])
      end

      # Start time plus fault and scheduling counters in one proc_pidinfo(PROC_PIDTASKALLINFO)
      # call (the same cost as PROC_PIDTBSDINFO alone), or nil when unreadable.
      def task_info(pid)
        buffer = Fiddle::Pointer.malloc(TASKALLINFO_SIZE, Fiddle::RUBY_FREE)
        unless functions[:pidinfo].call(pid, PROC_PIDTASKALLINFO, 0, buffer, TASKALLINFO_SIZE) == TASKALLINFO_SIZE
          return fail_with(Fiddle.last_error)
        end

        Thread.current[:agentmon_errno] = 0
        decode_task_info_bytes(buffer[0, TASKALLINFO_SIZE])
      end

      # Decodes a whole proc_taskallinfo as the kernel wrote it. Public for tests.
      def decode_task_info_bytes(bytes)
        counts = bytes.byteslice(BSDINFO_SIZE + 48, 48).unpack("L<12") # unsigned: wrapped counters stay positive
        c = ->(name) { counts.fetch(TASK_FIELDS.fetch(name)) }
        TaskInfo.new(started_at: decode_start(bytes), faults: c[:faults], cow_faults: c[:cow_faults],
                     context_switches: c[:csw], threads: c[:threadnum], running_threads: c[:numrunning])
      end

      # errno of the last failed read on this thread (EPERM, ESRCH, ...), 0 after a success.
      def errno = Thread.current[:agentmon_errno] || 0

      # Nanoseconds per Mach tick (Rational): 1 on Intel, 125/3 on Apple Silicon.
      def ns_per_tick
        @ns_per_tick ||= begin
          buffer = Fiddle::Pointer.malloc(8, Fiddle::RUBY_FREE)
          functions[:timebase].call(buffer)
          numer, denom = buffer[0, 8].unpack("LL")
          Rational(numer, denom)
        end
      end

      # Overrides the timebase (tests decode fixtures recorded on another machine). nil resets.
      attr_writer :ns_per_tick

      def ticks_to_seconds(ticks) = (ticks * ns_per_tick).fdiv(1_000_000_000)

      private

      # pbi_start_tvsec/usec from the head of a proc_bsdinfo (or proc_taskallinfo).
      def decode_start(bytes)
        sec, usec = bytes.byteslice(BSDINFO_START, 16).unpack("Q<Q<")
        sec + (usec / 1_000_000.0)
      end

      def fail_with(errno)
        Thread.current[:agentmon_errno] = errno
        nil
      end

      def functions
        @functions ||= begin
          lib = Fiddle.dlopen(nil) # libSystem: libproc and the Mach clock are in the default namespace
          uint64 = -Fiddle::TYPE_LONG_LONG
          {
            rusage: Fiddle::Function.new(lib["proc_pid_rusage"], [Fiddle::TYPE_INT, Fiddle::TYPE_INT, Fiddle::TYPE_VOIDP],
                                         Fiddle::TYPE_INT),
            pidinfo: Fiddle::Function.new(lib["proc_pidinfo"],
                                          [Fiddle::TYPE_INT, Fiddle::TYPE_INT, uint64, Fiddle::TYPE_VOIDP, Fiddle::TYPE_INT],
                                          Fiddle::TYPE_INT),
            timebase: Fiddle::Function.new(lib["mach_timebase_info"], [Fiddle::TYPE_VOIDP], Fiddle::TYPE_INT)
          }
        end
      end
    end
  end
end
