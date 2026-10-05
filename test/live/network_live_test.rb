# frozen_string_literal: true

require "test_helper"

# The real nettop child (macOS only): a snapshot arrives within a few seconds, and stop leaves no
# nettop behind.
class NetworkLiveTest < Minitest::Test
  def setup
    macos!
    skip "no nettop" unless File.executable?(Agentmon::Probes::Network::COMMAND.first)
  end

  def test_streams_snapshots_and_stops_cleanly
    stream = Agentmon::Probes::Network::Stream.new
    stream.snapshot # starts nettop
    pid = stream.pid

    assert pid, "nettop should have started"
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 3
    snapshot = nil
    until (snapshot = stream.latest) || Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline
      sleep 0.05
    end

    assert_instance_of Agentmon::NetSnapshot, snapshot
    refute_empty snapshot.processes
    assert_kind_of Agentmon::NetProcess, snapshot.processes.values.first
  ensure
    stream&.stop
    assert_raises(Errno::ESRCH) { Process.kill(0, pid) } if pid
  end
end
