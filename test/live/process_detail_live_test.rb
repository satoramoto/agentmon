# frozen_string_literal: true

require "test_helper"

# The Detail pane's open file count against the real kernel (macOS only, as a normal user).
class ProcessDetailLiveTest < Minitest::Test
  Detail = Agentmon::UI::ProcessDetail

  def setup = macos!

  def test_counts_this_process_open_files
    before = Detail.open_files(Process.pid)
    assert_operator before, :>=, 3 # stdin, stdout, stderr

    files = Array.new(5) { File.open(__FILE__) }
    assert_equal before + 5, Detail.open_files(Process.pid)
  ensure
    files&.each(&:close)
  end

  def test_other_users_processes_are_unreadable_not_errors
    skip "running as root" if Process.uid.zero?

    assert_nil Detail.open_files(1) # launchd
  end

  def test_reads_this_process_command_line
    assert_includes Detail.read_command(Process.pid), "ruby"
  end
end
