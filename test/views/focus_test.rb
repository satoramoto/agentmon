# frozen_string_literal: true

require "test_helper"

# The focus layout (lib/agentmon/views/focus.rb) at the owner's window size, over fixtures: the
# band of sessions on top, the focused session's (or every agent's) memory, CPU and processes.
class FocusViewTest < Minitest::Test
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

  def system_stat(t)
    Agentmon::SystemStat.new(cpu_ticks: [500 * t, 0, 1000 * t, 0], ncpu: 10, load: [1.5, 2.0, 2.5],
                             net_in: 1000 * t, net_out: 500 * t, at_mono: 1000.0 + t)
  end

  def samples
    [0, 2].map do |t|
      s = machine(t)
      s.with(parts: s.parts.merge(memory: memory_stat, system: system_stat(t)))
    end
  end

  # The app after one drawn frame (keys act on what the last frame drew).
  def app = dashboard_app(view: :focus).tap { |a| view_frame(a) }

  def status(text) = text.lines(chomp: true).last

  def test_machine_state_shows_every_panel_with_fixture_values
    with_engine(Fixtures.engine(*samples)) do |e|
      text = view_frame(app)

      assert_nil e.focus
      %w[Sessions Memory CPU Processes Detail].each { |title| assert_includes text, "─ #{title} " }
      assert_includes text, "─ machine " # the machine tile, first in the band
      assert_includes text, "claude 200" # a session tile
      assert_includes text, "9.0G" # machine used (app + wired + compressed), the footprint's whole
      %w[resident wired growth pageins].each { |label| assert_includes text, label }
      assert_includes text, "CPU, last 4 min"
      assert_includes text, "node" # a process of the Agents scope
      assert_includes text, "Wait" # the run_wait column header, not truncated
      assert_includes text, "session read"
    end
  end

  def test_no_line_is_wider_than_the_window
    with_engine(Fixtures.engine(*samples)) do
      text = view_frame(app)
      lines = text.split("\n")

      assert_equal 50, lines.size
      lines.each { |line| assert_operator Agentmon::Views::Widgets.visible_width(line), :<=, 100, line }
    end
  end

  def test_band_focuses_a_session_and_escape_returns_to_the_machine
    with_engine(Fixtures.engine(*samples)) do |e|
      a = app
      oldest = e.current(focused: false)[:session_ledger].select(&:alive?).min_by { |s| [s.started_at || 0, s.id] }
      a.press(:right, :enter)

      assert_equal oldest.id, e.focus
      text = view_frame(a)

      assert_includes text, "─ #{oldest.label}" # its tile is still in the band
      assert_includes status(text), "focus:"

      a.press(:escape)
      text = view_frame(a)

      assert_nil e.focus
      assert_includes text, "─ machine "
      refute_includes status(text), "focus:"
    end
  end
end
