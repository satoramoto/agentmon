# frozen_string_literal: true

require "test_helper"

# The memory probe against the real kernel (macOS only, as a normal user).
class MemoryLiveTest < Minitest::Test
  def setup = macos!

  def test_breakdown_fits_in_physical_memory
    stat = Agentmon::Probes::Memory.read

    assert_kind_of Agentmon::MemoryStat, stat
    assert_operator stat.app + stat.wired + stat.compressed, :<=, stat.total
    assert_operator stat.wired, :>, 0
    assert_operator stat.memorystatus_level, :<=, 100
  end

  def test_total_is_hw_memsize
    memsize = Integer(IO.popen(%w[sysctl -n hw.memsize], &:read))

    assert_equal memsize, Agentmon::Probes::Memory.read.total
  end

  def test_a_read_is_fast
    Agentmon::Probes::Memory.read # resolve the Fiddle functions once
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    Agentmon::Probes::Memory.read
    elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started

    assert_operator elapsed, :<, 0.005, "reading memory took #{(elapsed * 1000).round(2)} ms"
  end
end
