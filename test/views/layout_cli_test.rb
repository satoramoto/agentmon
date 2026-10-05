# frozen_string_literal: true

require "test_helper"

# `agentmon --layout NAME` and `--[no-]motion` (lib/agentmon/program.rb), off a terminal: one
# plain frame over a fixture engine.
class LayoutCliTest < Minitest::Test
  include Fixtures
  include R2UI::CLI::Testing

  def agentmon(*argv)
    with_engine(Fixtures.engine(machine(0), machine(2))) { run_cli(Agentmon::Program.build, *argv, width: 100) }
  end

  # Runs the block with Views.motion unset and AGENTMON_MOTION as given, restoring both.
  def with_motion_env(value)
    motion = Agentmon::Views.instance_variable_get(:@motion)
    env = ENV.fetch("AGENTMON_MOTION", nil)
    Agentmon::Views.motion = nil
    value.nil? ? ENV.delete("AGENTMON_MOTION") : ENV["AGENTMON_MOTION"] = value
    yield
  ensure
    Agentmon::Views.motion = motion
    env.nil? ? ENV.delete("AGENTMON_MOTION") : ENV["AGENTMON_MOTION"] = env
  end

  def test_layout_visual_prints_its_panels
    result = with_motion_env(nil) { agentmon("--layout", "visual") }

    assert result.success?, result.err
    assert_includes result.out, "CPU"
    assert_includes result.out, "Memory"
    assert_includes result.out, "Network"
    refute_includes result.out, "\e["
  end

  def test_unknown_layout_fails_naming_the_choices
    result = with_motion_env(nil) { agentmon("--layout", "nope") }

    refute result.success?
    message = result.err + result.out
    assert_includes message, "nope"
    assert_includes message, "visual"
  end

  def test_no_motion_turns_motion_off
    with_motion_env(nil) do
      result = agentmon("--layout", "visual", "--no-motion")

      assert result.success?, result.err
      refute Agentmon::Views.motion?
    end
  end

  def test_motion_is_on_by_default
    with_motion_env(nil) do
      result = agentmon("--layout", "visual")

      assert result.success?, result.err
      assert Agentmon::Views.motion?
    end
  end

  def test_agentmon_motion_0_turns_motion_off
    with_motion_env("0") do
      result = agentmon("--layout", "visual")

      assert result.success?, result.err
      refute Agentmon::Views.motion?
    end
  end
end
