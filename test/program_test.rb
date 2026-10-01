# frozen_string_literal: true

require "test_helper"

class ProgramTest < Minitest::Test
  include Fixtures
  include R2UI::CLI::Testing

  def test_no_command_off_a_terminal_prints_one_dashboard_frame
    result = with_engine(Fixtures.engine(machine(0), machine(2))) { run_cli(Agentmon::Program.build, width: 160) }

    assert result.success?, result.err
    assert_includes result.out, "Processes"
    assert_includes result.out, "claude 200 · repo"
    refute_includes result.out, "\e["
  end

  def test_help_lists_the_commands
    out = run_cli(Agentmon::Program.build, "--help").out

    assert_includes out, "top"
    assert_includes out, "With no command, opens the dashboard"
  end
end
