# frozen_string_literal: true

require "fiddle"

# sample[:memory]: the machine's memory counters, as a MemoryStat (lib/agentmon/model.rb), in
# bytes. The same numbers Activity Monitor's Memory tab and vm_stat show, e.g. on a 32 GiB Mac:
#
#   total 32.0G   app 10.4G   wired 4.3G   compressed 9.4G (stores 24.3G)   cached 5.3G
#   swap 1.9G of 3.0G used   memorystatus_level 55 (pressure 45%)
#
# No subprocesses: host_statistics64(HOST_VM_INFO64) through Fiddle for the page counts
# (pages x vm_kernel_page_size: 16 KiB on Apple Silicon, 4 KiB on Intel), and sysctlbyname for
# hw.memsize, vm.swapusage, vm.page_pageable_internal_count and kern.memorystatus_level. A read
# takes well under a millisecond.
#
#   app        = pageable internal (anonymous) pages - purgeable pages
#   cached     = file-backed pages + purgeable pages
#   compressed = pages the compressor occupies; compressor_stored = pages stored in it
#   free       = free pages minus speculative ones (those are file-backed, so already in cached)
#   swapins, swapouts, compressions, decompressions, pageins: cumulative bytes since boot
#
# A sysctl that fails leaves its fields nil (swap, memorystatus_level); without
# vm.page_pageable_internal_count, app uses the anonymous page count instead. Off macOS the probe
# is nil.
module Agentmon
  module Probes
    module Memory
      HOST_VM_INFO64 = 4
      # struct vm_statistics64 (xnu osfmk/mach/vm_statistics.h): 152 bytes, 38 integer_t's.
      VM_SIZE = 152
      VM_COUNT = VM_SIZE / 4
      VM_FORMAT = "L<4Q<9L<2Q<4L<4Q<"
      VM_FIELDS = %i[
        free_count active_count inactive_count wire_count
        zero_fill_count reactivations pageins pageouts faults cow_faults lookups hits purges
        purgeable_count speculative_count
        decompressions compressions swapins swapouts
        compressor_page_count throttled_count external_page_count internal_page_count
        total_uncompressed_pages_in_compressor
      ].freeze
      # struct xsw_usage: xsu_total, xsu_avail, xsu_used (uint64), xsu_pagesize, xsu_encrypted.
      SWAP_SIZE = 32

      module_function

      # Reads the live machine. Raises when host_statistics64 fails.
      def read
        decode(vm: Native.vm_statistics, page_size: Native.page_size, memsize: Native.sysctl_int("hw.memsize"),
               swap: Native.sysctl("vm.swapusage", SWAP_SIZE),
               pageable_internal: Native.sysctl_int("vm.page_pageable_internal_count"),
               memorystatus_level: Native.sysctl_int("kern.memorystatus_level"))
      end

      # Builds the MemoryStat from the raw kernel answers: `vm` is a vm_statistics64 as the kernel
      # wrote it, `swap` an xsw_usage (or nil), the rest Integers (or nil). Pure; tests feed it
      # recorded bytes.
      def decode(vm:, page_size:, memsize:, swap: nil, pageable_internal: nil, memorystatus_level: nil)
        raise ArgumentError, "vm_statistics64 is #{vm.bytesize} bytes, want #{VM_SIZE}" if vm.bytesize < VM_SIZE

        v = VM_FIELDS.zip(vm.byteslice(0, VM_SIZE).unpack(VM_FORMAT)).to_h
        bytes = ->(pages) { pages * page_size }
        purgeable = v[:purgeable_count]
        internal = pageable_internal || v[:internal_page_count]
        swap_total, _avail, swap_used = swap&.byteslice(0, 24)&.unpack("Q<3")
        MemoryStat.new(
          total: memsize,
          free: bytes[[v[:free_count] - v[:speculative_count], 0].max],
          app: bytes[[internal - purgeable, 0].max],
          wired: bytes[v[:wire_count]],
          compressed: bytes[v[:compressor_page_count]],
          compressor_stored: bytes[v[:total_uncompressed_pages_in_compressor]],
          cached: bytes[v[:external_page_count] + purgeable],
          purgeable: bytes[purgeable],
          swap_total:, swap_used:,
          swapins: bytes[v[:swapins]], swapouts: bytes[v[:swapouts]],
          compressions: bytes[v[:compressions]], decompressions: bytes[v[:decompressions]],
          pageins: bytes[v[:pageins]],
          memorystatus_level:
        )
      end

      # The Fiddle calls. Buffers are per call, so reads from several threads don't share memory.
      module Native
        module_function

        def vm_statistics
          buffer = Fiddle::Pointer.malloc(VM_SIZE, Fiddle::RUBY_FREE)
          count = Fiddle::Pointer.malloc(4, Fiddle::RUBY_FREE)
          count[0, 4] = [VM_COUNT].pack("L")
          result = functions[:host_statistics64].call(host, HOST_VM_INFO64, buffer, count)
          raise Error, "host_statistics64 failed (kern_return_t #{result})" unless result.zero?

          buffer[0, VM_SIZE]
        end

        # vm_kernel_page_size, a libSystem global (vm_size_t).
        def page_size = @page_size ||= Fiddle::Pointer.new(lib["vm_kernel_page_size"])[0, 8].unpack1("Q")

        # The sysctl's raw bytes (at most `size`), or nil when it fails.
        def sysctl(name, size)
          buffer = Fiddle::Pointer.malloc(size, Fiddle::RUBY_FREE)
          length = Fiddle::Pointer.malloc(8, Fiddle::RUBY_FREE)
          length[0, 8] = [size].pack("Q")
          return nil unless functions[:sysctlbyname].call(name, buffer, length, nil, 0).zero?

          buffer[0, length[0, 8].unpack1("Q")]
        end

        # An integer sysctl of 4 or 8 bytes (they differ by name and OS version), or nil.
        def sysctl_int(name)
          raw = sysctl(name, 8)
          case raw&.bytesize
          when 4 then raw.unpack1("l<")
          when 8 then raw.unpack1("q<")
          end
        end

        # mach_host_self() returns a send right each call; take it once.
        def host = @host ||= functions[:mach_host_self].call

        def lib = @lib ||= Fiddle.dlopen(nil)

        def functions
          @functions ||= {
            mach_host_self: Fiddle::Function.new(lib["mach_host_self"], [], -Fiddle::TYPE_INT),
            host_statistics64: Fiddle::Function.new(lib["host_statistics64"],
                                                    [-Fiddle::TYPE_INT, Fiddle::TYPE_INT, Fiddle::TYPE_VOIDP,
                                                     Fiddle::TYPE_VOIDP], Fiddle::TYPE_INT),
            sysctlbyname: Fiddle::Function.new(lib["sysctlbyname"],
                                               [Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP,
                                                Fiddle::TYPE_VOIDP, Fiddle::TYPE_SIZE_T], Fiddle::TYPE_INT)
          }
        end
      end
    end
  end

  probe(:memory) { Darwin.available? ? Probes::Memory.read : nil }
end
