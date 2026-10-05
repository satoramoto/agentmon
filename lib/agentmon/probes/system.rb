# frozen_string_literal: true

require "fiddle"

module Agentmon
  # sample[:system]: machine-wide CPU, load and network counters, read once per sample.
  #
  #   cpu_ticks  [user, system, idle, nice]: cumulative ticks over all CPUs since boot
  #              (host_statistics(HOST_CPU_LOAD_INFO), Integers; only deltas mean anything)
  #   ncpu       logical CPUs (hw.logicalcpu, else hw.ncpu)
  #   load       [1, 5, 15]-minute load averages (getloadavg, Floats)
  #   net_in     cumulative bytes received over every interface except lo0 (netstat -ibn)
  #   net_out    cumulative bytes sent, likewise
  #   at_mono    monotonic clock when read (seconds), for rates
  #
  # One `netstat -ibn` per sample (no per-interface work). It prints one `<Link#N>` row per
  # interface plus one row per address with the same counters; only the Link rows are summed, so an
  # interface with three addresses counts once. CPU, load and ncpu come through Fiddle.
  #
  # Each part is read on its own: one that fails (netstat missing, a sysctl refused) leaves its
  # fields nil and the others still arrive. Off macOS the probe is nil.
  SystemStat = Data.define(:cpu_ticks, :ncpu, :load, :net_in, :net_out, :at_mono)

  module Probes
    module System
      HOST_CPU_LOAD_INFO = 3
      CPU_STATES = 4 # CPU_STATE_USER, CPU_STATE_SYSTEM, CPU_STATE_IDLE, CPU_STATE_NICE
      NETSTAT = %w[netstat -ibn].freeze

      module_function

      # Reads the live machine.
      def read
        net_in, net_out = attempt { parse_netstat(netstat) }
        SystemStat.new(cpu_ticks: attempt { Native.cpu_ticks }, ncpu: attempt { Native.ncpu },
                       load: attempt { Native.load_average }, net_in:, net_out:,
                       at_mono: Process.clock_gettime(Process::CLOCK_MONOTONIC))
      end

      # [bytes in, bytes out] summed over the `<Link#N>` rows of `netstat -ibn` output, lo0 left
      # out; nil when there is no Link row (not netstat's table). Pure; tests feed it captured text.
      #
      # Columns: Name Mtu Network Address Ipkts Ierrs Ibytes Opkts Oerrs Obytes Coll. Address is
      # empty for some interfaces (utun, gif), so the counters are taken from the right.
      def parse_netstat(text)
        found = false
        totals = text.each_line.each_with_object([0, 0]) do |line, sums|
          fields = line.split
          next unless fields.size >= 10 && fields[2]&.start_with?("<Link#")
          next if fields[0].delete_suffix("*") == "lo0"

          ibytes = Integer(fields[-5], exception: false)
          obytes = Integer(fields[-2], exception: false)
          next unless ibytes && obytes

          found = true
          sums[0] += ibytes
          sums[1] += obytes
        end
        found ? totals : nil
      end

      def netstat = IO.popen(NETSTAT, err: File::NULL, &:read)

      # The block's value, or nil when it raises (a part that can't be read stays unknown).
      def attempt
        yield
      rescue StandardError # Fiddle::DLError, Errno::ENOENT (no netstat), Agentmon::Error
        nil
      end

      # The Fiddle calls. Buffers are per call, so reads from several threads don't share memory.
      module Native
        module_function

        # host_cpu_load_info: natural_t cpu_ticks[CPU_STATE_MAX], in user/system/idle/nice order.
        def cpu_ticks
          buffer = Fiddle::Pointer.malloc(4 * CPU_STATES, Fiddle::RUBY_FREE)
          count = Fiddle::Pointer.malloc(4, Fiddle::RUBY_FREE)
          count[0, 4] = [CPU_STATES].pack("L")
          result = functions[:host_statistics].call(host, HOST_CPU_LOAD_INFO, buffer, count)
          raise Error, "host_statistics failed (kern_return_t #{result})" unless result.zero?

          buffer[0, 4 * CPU_STATES].unpack("L<#{CPU_STATES}")
        end

        def load_average
          buffer = Fiddle::Pointer.malloc(8 * 3, Fiddle::RUBY_FREE)
          n = functions[:getloadavg].call(buffer, 3)
          raise Error, "getloadavg failed" unless n == 3

          buffer[0, 24].unpack("d3")
        end

        # Logical CPUs: constant for the process's life, so read once.
        def ncpu = @ncpu ||= sysctl_int("hw.logicalcpu") || sysctl_int("hw.ncpu")

        # An integer sysctl of 4 or 8 bytes, or nil.
        def sysctl_int(name)
          buffer = Fiddle::Pointer.malloc(8, Fiddle::RUBY_FREE)
          length = Fiddle::Pointer.malloc(8, Fiddle::RUBY_FREE)
          length[0, 8] = [8].pack("Q")
          return nil unless functions[:sysctlbyname].call(name, buffer, length, nil, 0).zero?

          case length[0, 8].unpack1("Q")
          when 4 then buffer[0, 4].unpack1("l<")
          when 8 then buffer[0, 8].unpack1("q<")
          end
        end

        # mach_host_self() returns a send right each call; take it once.
        def host = @host ||= functions[:mach_host_self].call

        def lib = @lib ||= Fiddle.dlopen(nil)

        def functions
          @functions ||= {
            mach_host_self: Fiddle::Function.new(lib["mach_host_self"], [], -Fiddle::TYPE_INT),
            host_statistics: Fiddle::Function.new(lib["host_statistics"],
                                                  [-Fiddle::TYPE_INT, Fiddle::TYPE_INT, Fiddle::TYPE_VOIDP,
                                                   Fiddle::TYPE_VOIDP], Fiddle::TYPE_INT),
            getloadavg: Fiddle::Function.new(lib["getloadavg"], [Fiddle::TYPE_VOIDP, Fiddle::TYPE_INT],
                                             Fiddle::TYPE_INT),
            sysctlbyname: Fiddle::Function.new(lib["sysctlbyname"],
                                               [Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP,
                                                Fiddle::TYPE_VOIDP, Fiddle::TYPE_SIZE_T], Fiddle::TYPE_INT)
          }
        end
      end
    end
  end

  probe(:system) { Darwin.available? ? Probes::System.read : nil }
end
