# frozen_string_literal: true

require "test_helper"
require "delegate"

# The drill-down word `focused` (lib/agentmon/views.rb, Views::Drill), multi-column `spark:` and the
# anomaly mark, on a small view over fixtures at the owner's window size (100x50).
#
# The test views are never registered on Agentmon.registry (that would add them to `--layout`'s
# choices, test/views/layout_cli_test.rb): OneView wraps the global registry and answers only
# `[:view, name]` for its own view, and UI.install takes it as `registry:`.
class DrillViewTest < Minitest::Test
  include Fixtures

  class OneView < SimpleDelegator
    def initialize(view)
      super(Agentmon.registry)
      @view = view
    end

    def [](kind, name) = kind == :view && name.to_sym == @view.name ? @view : __getobj__[kind, name]
  end

  def self.home_rows
    proc do
      row height: 6 do
        panel :machine, title: "Machine" do
          stat "system.ncpu", "focus.processes"
        end
      end
      row { top :session, title: "Sessions", by: :cpu, columns: %i[label processes cpu footprint] }
    end
  end

  def self.focused_rows
    proc do
      row height: 8 do
        panel :s_cpu, title: "Session CPU" do
          stat "focus.cpu", "focus.processes"
        end
      end
      row { top :process, title: "Processes", by: :cpu, columns: %i[pid name cpu footprint] }
      row height: 7 do
        detail :process, columns: 3
      end
    end
  end

  home = home_rows
  drilled = focused_rows
  DRILL = Agentmon::Views.build(:drill_test, title: "agentmon") do
    instance_eval(&home)
    focused { instance_eval(&drilled) }
  end
  HOME_ONLY = Agentmon::Views.build(:drill_home_only, title: "agentmon") { instance_eval(&home) }
  FOCUSED_ONLY = Agentmon::Views.build(:drill_focused_only, title: "agentmon") { instance_eval(&drilled) }
  HOME = %i[machine session].freeze
  FOCUSED = %i[s_cpu process detail].freeze

  def engine = Fixtures.engine(machine(0), machine(2))

  # A fresh app on `view` over Agentmon.engine, feeds refreshed.
  def app_for(view)
    Agentmon::UI.install(engine: Agentmon.engine, view: view.name, registry: OneView.new(view))
    app = R2UI::App.new(R2UI.registry, Agentmon::UI::DASHBOARD)
    app.feeds.each_value(&:refresh!)
    app
  end

  def lines(app, focus: nil) = view_frame(app, focus:).split("\n")

  def names(app) = app.dashboard.panels.map(&:name)

  def titles(text, all)
    all.select { |t| text.include?("─ #{t} ") }
  end

  def session_id = Agentmon.engine.current(focused: false)[:session_ledger].find { |s| s.root_pid == 200 }.id

  # Runs the block with `name` on `object` answering `impl` instead, then puts the original back.
  def swapping(object, name, impl)
    original = object.method(name)
    object.define_singleton_method(name, &impl)
    yield
  ensure
    object.define_singleton_method(name, original)
  end

  # --- the DSL ---

  def test_focused_rows_are_recorded_apart_from_home
    assert_equal 2, DRILL.rows.size
    assert_equal 3, DRILL.focused.size
    assert_predicate DRILL, :drill?
    refute_predicate HOME_ONLY, :drill?
    assert_equal [8, nil, 7], DRILL.focused.map(&:height)
  end

  def test_focused_is_once_and_not_nested
    assert_raises(ArgumentError) { Agentmon::Views.build(:x, title: "t") { focused { focused { row { top :process } } } } }
    assert_raises(ArgumentError) do
      Agentmon::Views.build(:x, title: "t") do
        focused { row { top :process } }
        focused { row { top :process } }
      end
    end
  end

  # --- hiding: each set is laid out as if alone ---

  def test_home_frame_shows_only_home_panels_like_a_view_without_the_drill_down
    with_engine(engine) do
      app = app_for(DRILL)
      text = lines(app).join("\n")

      assert_equal HOME, names(app)
      assert_equal %w[Machine Sessions], titles(text, ["Machine", "Sessions", "Session CPU", "Processes", "Detail"])
      assert_equal :session, app.focus.name # key focus on the first table of the home set
      @drill = lines(app)
    end
    with_engine(engine) do
      app = app_for(HOME_ONLY)
      alone = lines(app, focus: :session)

      assert_equal 50, @drill.size
      assert_equal alone[0...-1], @drill[0...-1] # every row; only the status bar differs
    end
  end

  def test_focused_frame_shows_only_focused_panels_like_a_view_of_just_them
    with_engine(engine) do |e|
      app = app_for(DRILL)
      Agentmon::UI::SessionFocus.focus!(app, e, session_id) # as Enter does: focus, refresh every feed
      text = lines(app).join("\n")

      assert_equal FOCUSED, names(app)
      assert_equal ["Session CPU", "Processes", "Detail"],
                   titles(text, ["Machine", "Sessions", "Session CPU", "Processes", "Detail"])
      assert_equal :process, app.focus.name
      @drill = lines(app)
    end
    with_engine(engine) do |e|
      app = app_for(FOCUSED_ONLY)
      e.focus = session_id
      app.feeds.each_value(&:refresh!)
      alone = lines(app, focus: :process)

      assert_equal alone[0...-1], @drill[0...-1]
      assert_match(/╰─+.*╯\z/, @drill[-2]) # the last row reaches the status bar
    end
  end

  # --- keys ---

  def test_enter_drills_in_and_escape_comes_back_with_key_focus_following
    with_engine(engine) do |e|
      app = app_for(DRILL)
      lines(app)
      selected = Agentmon::UI::SessionFocus.selected_session(app)
      app.press(:enter)

      assert_equal selected, e.focus
      assert_equal FOCUSED, names(app)
      assert_equal :process, app.focus.name
      app.press(:escape)

      assert_nil e.focus
      assert_equal HOME, names(app)
      assert_equal :session, app.focus.name
    end
  end

  def test_escape_restores_the_home_panel_that_had_key_focus
    with_engine(engine) do |e|
      app = app_for(DRILL)
      focus_panel(app, :machine)
      e.focus = session_id
      lines(app) # the frame follows a focus set directly

      assert_equal :process, app.focus.name
      app.press(:escape)

      assert_equal :machine, app.focus.name
    end
  end

  def test_tab_cycles_only_the_visible_panels
    with_engine(engine) do |e|
      app = app_for(DRILL)
      seen = 4.times.map { app.press(:tab) && app.focus.name }

      assert_equal HOME.to_set, seen.to_set
      e.focus = session_id
      lines(app)
      seen = 6.times.map { app.press(:tab) && app.focus.name }

      assert_equal FOCUSED.to_set, seen.to_set
      app.press(:back_tab)

      assert_includes FOCUSED, app.focus.name
    end
  end

  def test_a_session_that_ends_returns_home
    with_engine(engine) do |e|
      app = app_for(DRILL)
      e.focus = "no-such-session"
      text = lines(app).join("\n")

      assert_nil e.focus
      assert_equal HOME, names(app)
      assert_includes text, "─ Sessions "
    end
  end

  # --- the status bar ---

  def test_status_says_where_you_are_and_how_to_go_back
    with_engine(engine) do |e|
      app = app_for(DRILL)

      assert_includes lines(app).last, "sessions · ⏎ open a session"
      e.focus = session_id

      assert_includes lines(app).last, "▸ claude 200 · repo · esc back to sessions"
    end
  end

  def test_status_leads_with_the_name_and_shows_busy_or_idle
    session = Agentmon::Session.new(
      id: "claude-200-1", kind: :cli, name: "claude", root_pid: 200, label: "Fix the login · claude 200 · repo",
      cwd: "/r/repo", started_at: 0.0, first_seen_at: 0.0, last_seen_at: 1.0, ended_at: nil, processes: 1, cpu: 0.0,
      footprint: 0, resident: 0, read_rate: 0.0, write_rate: 0.0, peak_footprint: 0, cpu_seconds: 0.0, bytes_read: 0,
      bytes_written: 0, title: "Fix the login", status: "busy"
    )
    engine = Struct.new(:focus, :focused_session).new("claude-200-1", session)
    rt = Struct.new(:engine) { def drill? = true }.new(engine)

    assert_equal "▸ Fix the login · claude 200 · repo · busy · esc back to sessions", Agentmon::Views::Drill.status(rt)
  end

  def test_problems_still_win_the_status_bar
    with_engine(engine) do
      app = app_for(DRILL)
      swapping(Agentmon, :engine_errors, -> { { "metric x" => "boom" } }) do
        assert_includes lines(app).last, "⚠ metric x: boom"
      end
    end
  end

  def test_views_without_a_drill_down_keep_their_status
    with_engine(engine) do |e|
      app = app_for(HOME_ONLY)
      e.focus = session_id

      assert_includes lines(app, focus: :session).last, "focus: claude 200 · repo (esc: all)"
    end
  end

  # --- spark: on several columns ---

  def test_spark_columns
    view = Agentmon::Views.build(:x, title: "t") do
      row { top :session, by: :cpu, spark: %i[cpu footprint net_out_rate] }
      row { top :process, by: :cpu }
      row { top :process, by: :cpu, spark: false }
    end
    tops = view.rows.map { |r| r.panels.first.items.first }

    assert_equal %i[cpu footprint net_out_rate], tops[0].spark_columns
    assert_equal %i[cpu], tops[1].spark_columns
    assert_empty tops[2].spark_columns
  end

  def test_spark_puts_braille_on_each_listed_column
    view = Agentmon::Views.build(:drill_spark, title: "agentmon") do
      row { top :session, by: :cpu, columns: %i[label processes cpu footprint net_out_rate], spark: %i[cpu footprint net_out_rate] }
    end
    with_engine(engine) do
      app_for(view)
      session = R2UI.registry.resource(:session)

      %i[cpu footprint net_out_rate].each { |key| assert_equal :braille, session.column(key).sparkline, key }
      refute session.column(:processes).sparkline
      refute session.column(:peak_footprint).sparkline
    end
  end

  # --- the anomaly mark ---

  def test_flagged_sessions_are_marked_and_red
    panel = Agentmon::UI::SessionsPanel
    rows = panel.method(:rows)
    flag = lambda do |reading|
      rows.call(reading).map { |r| r[:label].include?("repo") ? r.merge(net_flags: [:out_spike]) : r }
    end
    with_engine(engine) do
      swapping(panel, :rows, flag) do
        app = app_for(DRILL)
        text = view_frame(app)

        assert_includes text, "│ ⚑ claude 200…  " # the label column is 18 cells: cut at a word boundary
        refute_match(/⚑ Claude 300/, text)
        label = R2UI.registry.resource(:session).column(:label)
        red = R2UI::Widgets::Glyphs.fg("#E5484D")

        assert_equal red, label.style.call(label.read({ label: "claude 200 · repo", net_flags: [:many_hosts] }), nil)
        assert_nil label.style.call(label.read({ label: "claude 200 · repo", net_flags: [] }), nil)
        assert_equal "claude 200 · repo", label.read({ label: "claude 200 · repo" }) # missing = normal
      end
    end
  end

  def test_the_mark_is_cut_at_a_word_boundary_to_the_column
    with_engine(engine) do
      app_for(DRILL)
      label = R2UI.registry.resource(:session).column(:label)
      text = label.read({ label: "claude 4242 · funkadelic-astronaut-web", net_flags: [:out_spike] })

      assert_equal 18, label.width
      assert text.start_with?("⚑ claude 4242")
      assert_operator Agentmon::Views::Widgets.visible_width(text), :<=, 18
      assert text.end_with?("…")
    end
  end
end
