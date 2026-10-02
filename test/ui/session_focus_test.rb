# frozen_string_literal: true

require "test_helper"

# Session focus (story a19): enter on a Sessions row, F from a Processes row, escape to clear, on
# the whole dashboard over the fixture machine.
class SessionFocusTest < Minitest::Test
  include Fixtures

  def engine = Fixtures.engine(machine(0), machine(2))

  # The dashboard after one frame (keys act on the lines the last frame drew).
  def app(focus: :process) = dashboard_app(focus:).tap { |a| dashboard_frame(a, focus:) }

  # Pids the Processes panel lists (from the last frame drawn).
  def process_pids(app)
    panel = app.dashboard.panels.find { |p| p.name == :process }
    app.panel_lines(panel).flat_map { |l| l.rows.map(&:pid) }.sort
  end

  def session_labels(app)
    panel = app.dashboard.panels.find { |p| p.name == :session }
    app.panel_lines(panel).flat_map { |l| l.rows.map { |r| r[:label] } }
  end

  def status(text) = text.lines(chomp: true).last

  # Selects the Processes line for `pid` (All scope, searched by name, then moved down to it).
  def select_process(app, pid, name)
    app.press("]", "/", *name.chars, :enter)
    dashboard_frame(app)
    panel = app.dashboard.panels.find { |p| p.name == :process }
    index = app.panel_lines(panel).index { |l| l.id == pid } || flunk("pid #{pid} not listed")
    app.press(*[:down] * index)
  end

  def test_enter_on_a_session_narrows_every_panel_to_it
    with_engine(engine) do |e|
      a = app(focus: :session) # sorted by CPU: claude 200 first
      a.press(:enter)

      assert_equal e.current(focused: false)[:session_ledger].find { |s| s.root_pid == 200 }.id, e.focus
      text = dashboard_frame(a, focus: :session)

      assert_equal [200, 201, 202, 203], process_pids(a)
      assert_equal ["claude 200 · repo"], session_labels(a)
      assert_includes status(text), "focus: claude 200 · repo (esc: all)"
      assert(e.current[:pressure_drivers].all? { |d| d.session_id == e.focus })
    end
  end

  def test_escape_clears_the_focus
    with_engine(engine) do |e|
      a = app(focus: :session)
      a.press(:enter)
      dashboard_frame(a)

      refute_includes process_pids(a), 303

      a.press(:escape)
      text = dashboard_frame(a)

      assert_nil e.focus
      assert_includes process_pids(a), 303
      refute_includes status(text), "focus:"
    end
  end

  def test_escape_while_unfocused_passes_on
    with_engine(engine) do |e|
      a = app
      a.press(:escape)

      assert_nil e.focus
    end
  end

  def test_enter_on_a_processes_group_still_toggles_it
    with_engine(engine) do |e|
      a = app
      a.press("g", "g", "g", "g") # Session, Directory, Name, then the tree
      dashboard_frame(a)
      panel = a.dashboard.panels.find { |p| p.name == :process }
      index = a.panel_lines(panel).index(&:expandable?) || flunk("no expandable line")
      line = a.panel_lines(panel)[index]
      a.press(*[:down] * index, :enter)

      assert_nil e.focus
      assert_includes a.panel_state(panel).collapsed, line.id
    end
  end

  def test_f_focuses_the_session_of_the_selected_process
    with_engine(engine) do |e|
      a = app
      select_process(a, 303, "claude")
      a.press("F")
      text = dashboard_frame(a)

      assert_equal "claude 303 · web", e.focused_session.label
      assert_equal [303], process_pids(a)
      assert_includes status(text), "focus: claude 303 · web (esc: all)"
    end
  end

  def test_f_on_a_process_in_no_session_flashes
    with_engine(engine) do |e|
      a = app
      select_process(a, 400, "Finder")
      a.press("F")

      assert_nil e.focus
      assert_includes status(dashboard_frame(a)), "not in an agent session"
    end
  end

  def test_a_focused_session_that_left_the_ledger_clears_itself
    with_engine(engine) do |e|
      a = app
      e.focus = "claude-gone-1"

      assert_nil e.focused_session
      text = dashboard_frame(a)

      assert_nil e.focus
      refute_includes status(text), "focus:"
      assert_includes process_pids(a), 303 # feeds refreshed unfocused in the same frame
    end
  end

  def test_other_dashboards_ignore_the_keys
    with_engine(engine) do |e|
      R2UI.dashboard(:other) { title "other" }
      other = R2UI::App.new(R2UI.registry, :other)
      other.press("F", :escape)

      assert_nil e.focus
    end
  end
end
