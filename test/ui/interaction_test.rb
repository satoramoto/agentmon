# frozen_string_literal: true

require "test_helper"

# a09-mouse-and-help: clicks focus panels and select rows, the wheel moves the selection, and `?`
# toggles a full-screen help overlay that any key closes.
class InteractionPanelTest < Minitest::Test
  include Fixtures

  Mouse = Bubbletea::MouseMessage
  # A real left click arrives as SGR button 0 (r2ui's Ext::Mouse::LEFT), not Mouse::BUTTON_LEFT.
  LEFT = R2UI::Ext::Mouse::LEFT
  WIDTH = 150
  HEIGHT = 30

  def app
    Agentmon::UI.install(engine: Agentmon.engine)
    R2UI::App.new(R2UI.registry, Agentmon::UI::DASHBOARD).tap do |a|
      a.feeds.each_value(&:refresh!)
      a.update(Bubbletea::WindowSizeMessage.new(width: WIDTH, height: HEIGHT))
      a.frame(WIDTH, HEIGHT)
    end
  end

  def lines(app) = app.frame(WIDTH, HEIGHT).plain_lines

  # [x, y] of the first cell matching `pattern` in the current frame.
  def where(app, pattern)
    lines(app).each_with_index do |line, y|
      x = line =~ pattern
      return [x, y] if x
    end
    flunk "#{pattern.inspect} not on screen:\n#{lines(app).join("\n")}"
  end

  def mouse(app, x, y, button) = app.update(Mouse.new(x:, y:, button:, action: Mouse::ACTION_PRESS))

  def process_panel(app) = app.dashboard.panels.find { |p| p.name == :process }

  def selected_pid(app) = app.selected_rows.first&.pid

  def test_mouse_reporting_is_on
    with_engine(Fixtures.engine(machine(0), machine(2))) do
      assert app.program_options[:mouse_cell_motion]
    end
  end

  def test_clicking_a_row_selects_it
    with_engine(Fixtures.engine(machine(0), machine(2))) do
      a = app
      refute_equal 203, selected_pid(a)

      mouse(a, *where(a, /\b203\b/), LEFT)

      assert_equal process_panel(a), a.focus
      assert_equal 203, selected_pid(a)
    end
  end

  def test_the_wheel_moves_the_selection
    with_engine(Fixtures.engine(machine(0), machine(2))) do
      a = app
      x, y = where(a, /\b203\b/)
      first = selected_pid(a)

      mouse(a, x, y, Mouse::BUTTON_WHEEL_DOWN)
      lines(a)
      second = selected_pid(a)
      refute_equal first, second

      mouse(a, x, y, Mouse::BUTTON_WHEEL_UP)
      assert_equal first, selected_pid(a)
    end
  end

  def test_question_mark_shows_and_any_key_hides_the_help
    with_engine(Fixtures.engine(machine(0), machine(2))) do
      a = app
      refute_includes a.view, "agentmon help"

      a.press("?")
      help = a.view

      assert_includes help, "agentmon help"
      a.hint_pairs.each { |key, _| assert_includes help, key }
      assert_match(/^\s*K\s+terminate/, help)
      assert_match(/^\s*X\s+kill/, help)
      assert_match(/^\s*\?\s+.*help/, help)
      assert_match(/Processes.*every process/, help)
      refute_includes help, "claude 200 · repo" # the dashboard is hidden
      help.lines.each { |line| assert_operator line.chomp.length, :<=, WIDTH }
      assert_operator help.lines.size, :<=, HEIGHT

      commands = a.press("q") # closes the help; doesn't quit

      assert_empty commands
      refute_includes a.view, "agentmon help"
      assert_includes a.view, "claude 200 · repo"
    end
  end

  def test_question_mark_toggles_and_the_status_bar_hints_it
    with_engine(Fixtures.engine(machine(0), machine(2))) do
      a = app
      assert_match(/\? help/, lines(a).last)

      a.press("?")
      a.press("?")

      refute_includes a.view, "agentmon help"
    end
  end

  def test_clicks_while_the_help_is_open_do_not_reach_the_dashboard
    with_engine(Fixtures.engine(machine(0), machine(2))) do
      a = app
      x, y = where(a, /\b203\b/)
      a.press("?")

      mouse(a, x, y, LEFT)

      refute_equal 203, selected_pid(a)
      assert_includes a.view, "agentmon help"
    end
  end

  def test_works_without_process_rows
    registry = Agentmon::Registry.new # no metrics: reading[:process_rows] is nil
    engine = Agentmon::Engine.new(sampler: Sampler.new(machine(0), machine(2)), registry:, prime_gap: 0)
    with_engine(engine) do
      a = app
      mouse(a, 10, 5, LEFT)
      mouse(a, 10, 5, Mouse::BUTTON_WHEEL_DOWN)

      assert_nil selected_pid(a)
      a.press("?")
      assert_includes a.view, "agentmon help"
    end
  end
end
