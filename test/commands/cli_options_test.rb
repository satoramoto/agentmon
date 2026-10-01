# frozen_string_literal: true

require "test_helper"

class CliOptionsCommandTest < Minitest::Test
  include Fixtures
  include R2UI::CLI::Testing

  def agentmon(*argv, registry: Agentmon.registry, **shell)
    run_cli(Agentmon::Program.build(registry:), *argv, **shell)
  end

  # The real root-level options plus one command that fails unexpectedly, wrapped in a cause.
  def failing_registry
    registry = Agentmon::Registry.new
    Agentmon.registry.cli_blocks.each { |b| registry.cli_blocks << b }
    registry.add(:command, Agentmon::Command.new(name: :boom, block: proc {
      run do
        begin
          raise IOError, "store unreadable"
        rescue IOError
          raise "report failed"
        end
      end
    }))
    registry
  end

  def test_version_prints_name_and_version
    result = agentmon("--version")

    assert result.success?, result.err
    assert_equal "agentmon 0.1.0\n", result.out
    assert_equal "agentmon #{Agentmon::VERSION}\n", agentmon("-V").out
  end

  def test_version_works_on_a_command_without_running_it
    result = agentmon("top", "--version")

    assert result.success?
    assert_equal "agentmon 0.1.0\n", result.out
  end

  def test_help_starts_with_the_version_and_lists_completion
    out = agentmon("--help").out

    assert out.start_with?("agentmon 0.1.0"), out.lines.first
    assert_includes out, "completion"
    assert_includes out, "--trace"
    assert_includes out, "--color"
    assert_includes out, "--no-color"
  end

  def test_completion_scripts_for_each_shell_cover_the_commands
    { "zsh" => ["#compdef agentmon", "--once"], "bash" => ["complete -o default -F _agentmon agentmon", "--once"],
      "fish" => ["complete -c agentmon", "-l once"] }.each do |kind, (marker, once)|
      result = agentmon("completion", kind)

      assert result.success?, "#{kind}: #{result.err}"
      assert_includes result.out, marker, kind
      assert_includes result.out, "top", kind
      assert_includes result.out, once, kind
      assert_includes result.out, "cpu footprint resident read write", kind # --sort choices
      assert_equal "", result.err, kind # no setup hint off a terminal
    end
  end

  def test_unknown_completion_shell_is_a_usage_error
    result = agentmon("completion", "zhs")

    assert_equal 2, result.code
    assert_includes result.err, "unknown shell 'zhs' (expected bash, zsh or fish)"
    assert_equal "", result.out
  end

  def test_trace_prints_the_backtrace_and_causes_of_an_unexpected_error
    result = agentmon("boom", "--trace", registry: failing_registry)

    assert_equal 1, result.code
    assert_includes result.err, "report failed"
    assert_includes result.err, "RuntimeError"
    assert_match(/cli_options_test\.rb:\d+/, result.err)
    assert_includes result.err, "Caused by IOError: store unreadable"
    assert_equal "", result.out
  end

  def test_without_trace_an_unexpected_error_has_no_backtrace
    result = agentmon("boom", registry: failing_registry)

    assert_equal 1, result.code
    assert_includes result.err, "report failed"
    refute_match(/cli_options_test\.rb:\d+/, result.err)
  end

  # Lipgloss's colour profile is process-wide and picked from this process's stdout (a pipe under
  # the test runner), so a colour test raises it as a real terminal would and restores it.
  def with_lipgloss_profile(profile)
    renderer = R2UI::Compat::Gloss::Renderer
    previous = renderer.color_profile
    renderer.color_profile = profile
    yield
  ensure
    renderer.color_profile = previous
  end

  def test_no_color_turns_colour_off_on_a_colour_terminal
    with_lipgloss_profile(:ansi) do
      assert_includes agentmon("--version", tty: true, color: true).out, "\e[" # the default there

      result = agentmon("--version", "--no-color", tty: true, color: true)

      assert result.success?
      assert_equal "agentmon 0.1.0\n", result.out
    end
  end

  def test_color_colours_output_in_a_pipe
    with_lipgloss_profile(:ascii) do
      result = agentmon("--version", "--color")

      assert result.success?
      assert_includes result.out, "\e["
      assert_equal "agentmon 0.1.0", result.out.gsub(/\e\[[\d;]*m/, "").chomp
    end
  end

  def test_without_color_flags_a_pipe_stays_plain
    refute_includes agentmon("--version").out, "\e["
  end
end
