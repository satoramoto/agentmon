# frozen_string_literal: true

require "test_helper"

# The visual layout (lib/agentmon/views/visual.rb) at the owner's window size, over fixtures.
class VisualViewTest < Minitest::Test
  include Fixtures

  GB = 1024 * MB

  def memory_stat
    Agentmon::MemoryStat.new(
      total: 16 * GB, free: 1 * GB, app: 6 * GB, wired: 2 * GB, compressed: 1 * GB,
      compressor_stored: 3 * GB, cached: 5 * GB, purgeable: 512 * MB,
      swap_total: 2 * GB, swap_used: 1 * GB,
      swapins: 0, swapouts: 0, compressions: 0, decompressions: 0, pageins: 0,
      memorystatus_level: 70
    )
  end

  def system_stat(t, busy)
    Agentmon::SystemStat.new(cpu_ticks: [busy, 0, 1000 * t, 0], ncpu: 10, load: [1.5, 2.0, 2.5],
                             net_in: 1000 * t, net_out: 500 * t, at_mono: 1000.0 + t)
  end

  # Two samples of the fixture machine with memory, plus system counters unless `system: false`
  # (then the CPU signals are unknown).
  def samples(system: true)
    [0, 2].map do |t|
      s = machine(t)
      parts = s.parts.merge(memory: memory_stat)
      parts[:system] = system_stat(t, 500 * t) if system
      s.with(parts:)
    end
  end

  def frame_of(app) = view_frame(app)

  def test_visual_shows_every_panel_with_fixture_values
    with_engine(Fixtures.engine(*samples)) do
      text = frame_of(dashboard_app(view: :visual, focus: nil))

      %w[CPU Memory Network Disk Sessions].each { |title| assert_includes text, "─ #{title} " }
      refute_includes text, "─ Processes " # the session list is home; processes are a drill-down
      assert_includes text, "9.0G / 16G" # memory used / total (app + wired + compressed)
      assert_includes text, "claude 200" # a session label
      assert_includes text, "1.0G / 2.0G" # swap used / total
    end
  end

  def test_enter_on_a_session_drills_into_it_and_escape_returns
    with_engine(Fixtures.engine(*samples)) do
      app = dashboard_app(view: :visual, focus: nil)
      frame_of(app) # Enter acts on the line drawn as selected
      app.press(:enter)
      text = frame_of(app)

      %w[CPU Memory Network Disk Processes Detail Connections].each { |t| assert_includes text, "─ #{t} " }
      refute_includes text, "─ Sessions "
      assert_includes text, "node" # a process of the drilled-into session
      assert_match(/▸ .* · esc back to sessions/, text.split("\n").last)
      text.split("\n").each { |line| assert_operator Agentmon::Views::Widgets.visible_width(line), :<=, 100, line }

      app.press(:escape)
      home = frame_of(app)

      assert_includes home, "─ Sessions "
      refute_includes home, "─ Processes "
    end
  end

  def test_no_line_is_wider_than_the_window
    with_engine(Fixtures.engine(*samples)) do
      text = frame_of(dashboard_app(view: :visual, focus: nil))

      text.split("\n").each do |line|
        assert_operator Agentmon::Views::Widgets.visible_width(line), :<=, 100, line
      end
    end
  end

  def test_unknown_cpu_shows_a_dash_not_zero
    with_engine(Fixtures.engine(*samples(system: false))) do
      text = frame_of(dashboard_app(view: :visual, focus: nil))
      cpu_line = text.split("\n").find { |l| l.include?("CPU ▕") || l.match?(/CPU\s.*▏/) }

      refute_nil cpu_line, text
      assert_includes cpu_line, Agentmon::Views::Widgets::UNKNOWN
      refute_match(/0\.0%/, cpu_line)
    end
  end

  def test_a_second_frame_between_samples_still_renders_with_motion_on
    previous = Agentmon::Views.instance_variable_get(:@motion)
    Agentmon::Views.motion = true
    with_engine(Fixtures.engine(*samples)) do
      app = dashboard_app(view: :visual, focus: nil)

      assert app.motion.enabled
      first = frame_of(app)
      second = frame_of(app)

      assert_includes second, "Memory"
      assert_includes second, "9.0G / 16G"
      assert_equal first.lines.size, second.lines.size
    end
  ensure
    Agentmon::Views.motion = previous
  end

  def test_motion_off_disables_app_motion
    previous = Agentmon::Views.instance_variable_get(:@motion)
    Agentmon::Views.motion = false
    with_engine(Fixtures.engine(*samples)) do
      app = dashboard_app(view: :visual, focus: nil)

      refute app.motion.enabled
      assert_includes frame_of(app), "Memory"
    end
  ensure
    Agentmon::Views.motion = previous
  end
end
