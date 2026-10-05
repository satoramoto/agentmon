# frozen_string_literal: true

require "test_helper"
require "tempfile"

# Darwin.open_paths against the real kernel (macOS only).
class SessionNamesLiveTest < Minitest::Test
  def setup = macos!

  def test_open_paths_lists_a_file_this_process_holds_open_and_is_fast
    Tempfile.create("agentmon-open-paths") do |file|
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      paths = Agentmon::Darwin.open_paths(Process.pid)
      elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started

      assert paths, "own open files should be readable (errno #{Agentmon::Darwin.errno})"
      assert_includes paths, File.realpath(file.path) # the kernel reports /private/var, not /var
      assert_operator elapsed, :<, 0.05
    end
  end

  def test_another_users_process_is_nil
    skip "running as root" if Process.uid.zero?

    assert_nil Agentmon::Darwin.open_paths(1) # launchd
  end
end
