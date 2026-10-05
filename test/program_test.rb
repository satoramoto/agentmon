# frozen_string_literal: true

require "test_helper"
require "open3"
require "rbconfig"

class ProgramCoreTest < Minitest::Test
  include Fixtures
  include R2UI::CLI::Testing

  EXE = File.expand_path("../exe/agentmon", __dir__)

  def test_classic_layout_off_a_terminal_prints_one_dashboard_frame
    result = with_engine(Fixtures.engine(machine(0), machine(2))) do
      run_cli(Agentmon::Program.build, "--layout", "classic", width: 160)
    end

    assert result.success?, result.err
    assert_includes result.out, "Processes"
    assert_includes result.out, "claude 200 · repo"
    refute_includes result.out, "\e["
  end

  def test_help_lists_the_commands_and_the_default_layout
    out = run_cli(Agentmon::Program.build, "--help").out

    assert_includes out, "top"
    assert_includes out, "With no command, opens the dashboard in the dense layout"
    assert_includes out, "classic"
  end

  def test_off_macos_exits_1_with_a_message
    script = "Object.send(:remove_const, :RUBY_PLATFORM); RUBY_PLATFORM = 'x86_64-linux'; load #{EXE.dump}"
    out, err, status = Open3.capture3(RbConfig.ruby, "-e", script)

    assert_equal 1, status.exitstatus
    assert_empty out
    assert_includes err, "agentmon: macOS only"
    assert_includes err, "x86_64-linux"
  end
end
