# frozen_string_literal: true

require "test_helper"

class MemoryProbeTest < Minitest::Test
  # Recorded on a 32 GiB Apple Silicon Mac (16 KiB pages) under memory pressure:
  # host_statistics64(HOST_VM_INFO64) as the kernel wrote it (struct vm_statistics64, 152 bytes)
  # and sysctl vm.swapusage (struct xsw_usage, 32 bytes). vm_stat printed the same counts.
  VM_BYTES = [
    "3b1302002ad30700617f0700d25504009475fa7502000000c5e7fd0a000000004a83430700000000" \
    "86c51700000000001eb0809201000000b468081c0000000000000000000000000000000000000000" \
    "9b8efd0100000000412300001f5100001d83aa0600000000e658d90800000000a98c010000000000" \
    "8137040000000000e166090000000000f01f0500ba830a005a42180000000000"
  ].pack("H*")
  SWAP_BYTES = ["000000c00000000000007944000000000000877b000000000040000001000000"].pack("H*")
  PAGE = 16_384
  MEMSIZE = 34_359_738_368
  PAGEABLE_INTERNAL = 688_159

  def decode(**overrides)
    Agentmon::Probes::Memory.decode(vm: VM_BYTES, page_size: PAGE, memsize: MEMSIZE, swap: SWAP_BYTES,
                                    pageable_internal: PAGEABLE_INTERNAL, memorystatus_level: 55, **overrides)
  end

  def test_decodes_a_memory_stat_in_bytes
    stat = decode

    assert_kind_of Agentmon::MemoryStat, stat
    assert_equal MEMSIZE, stat.total
    assert_equal (135_995 - 20_767) * PAGE, stat.free # free minus speculative, as vm_stat shows it
    assert_equal 284_114 * PAGE, stat.wired
    assert_equal 9_025 * PAGE, stat.purgeable
    assert_equal 55, stat.memorystatus_level
  end

  def test_activity_monitor_breakdown
    stat = decode

    assert_equal (PAGEABLE_INTERNAL - 9_025) * PAGE, stat.app       # internal - purgeable
    assert_equal (335_856 + 9_025) * PAGE, stat.cached              # file-backed + purgeable
    assert_equal 616_161 * PAGE, stat.compressed                    # occupied by the compressor
    assert_equal 1_589_850 * PAGE, stat.compressor_stored           # stored in it, uncompressed
    assert_operator stat.app + stat.wired + stat.compressed, :<=, stat.total
  end

  def test_cumulative_counters_are_bytes
    stat = decode

    assert_equal [101_545, 276_353, 148_461_798, 111_837_981, 121_865_034].map { |pages| pages * PAGE },
                 [stat.swapins, stat.swapouts, stat.compressions, stat.decompressions, stat.pageins]
  end

  def test_swap_usage
    stat = decode

    assert_equal 3 * 1024**3, stat.swap_total
    assert_equal 2_072_444_928, stat.swap_used
  end

  def test_missing_sysctls_are_nil_not_zero
    stat = decode(swap: nil, memorystatus_level: nil)

    assert_nil stat.swap_total
    assert_nil stat.swap_used
    assert_nil stat.memorystatus_level
    assert_equal 284_114 * PAGE, stat.wired
  end

  def test_app_falls_back_to_anonymous_pages_without_the_pageable_count
    assert_equal (689_082 - 9_025) * PAGE, decode(pageable_internal: nil).app
  end

  def test_short_struct_raises
    assert_raises(ArgumentError) { decode(vm: VM_BYTES.byteslice(0, 96)) }
  end

  def test_registered_as_the_memory_probe
    assert Agentmon.registry[:probe, :memory]
  end
end
