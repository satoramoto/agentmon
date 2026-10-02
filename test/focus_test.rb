# frozen_string_literal: true

require "test_helper"

# Session focus (lib/agentmon/focus.rb): the engine narrows every per-session value to one
# session, and panels that only read engine.current follow it.
class FocusCoreTest < Minitest::Test
  include Fixtures

  REPO = "claude-200-#{(T0 - 3600 + 200).to_i}".freeze # the fixture machine's CLI session
  APP = "Claude-300-#{(T0 - 3600 + 300).to_i}".freeze  # the desktop app

  def engine = Fixtures.engine(machine(0), machine(2))

  def test_unfocused_engine_returns_the_whole_reading
    e = engine

    assert_nil e.focus
    assert_nil e.current.focus
    assert_instance_of Agentmon::Reading, e.current
    assert_includes e.current[:process_rows].map(&:pid), 400
  end

  def test_focus_narrows_every_per_session_value
    e = engine
    e.current
    e.focus = REPO
    r = e.current

    assert_equal REPO, r.focus
    assert_equal [200, 201, 202, 203], r[:process_rows].map(&:pid).sort
    assert_equal [200, 201, 202, 203], r[:process_rates].keys.sort
    assert_equal [REPO], r[:sessions].sessions.map(&:id)
    assert_equal [200, 201, 202, 203], r[:sessions].by_pid.keys.sort
    assert_equal [REPO], r[:session_ledger].map(&:id)
  end

  def test_machine_wide_values_and_the_sample_pass_through
    memory = Agentmon::MemoryView.new(total: 1, used: 1, app: 1, wired: 0, compressed: 0, cached: 0, free: 0,
                                      swap_used: 0, swap_total: 0, compression_ratio: 0.0, swapin_rate: 0.0,
                                      swapout_rate: 0.0, compression_rate: 0.0, decompression_rate: 0.0,
                                      pressure: 10.0, pressure_trend: [])
    reading = Fixtures.reading(machine(2), previous: machine(0), values: { memory: })
    focused = Agentmon::Focus.apply(reading, REPO)

    assert_same memory, focused[:memory]
    assert_same reading.sample, focused.sample
    assert_equal 12, focused.sample[:processes].size
    assert_same reading, focused.unfocused
  end

  def test_preset_per_session_shapes_are_filtered_too
    drivers = [Agentmon::PressureDriver.new(session_id: REPO, label: "repo", footprint: 1, share: nil, growth_rate: 0.0),
               Agentmon::PressureDriver.new(session_id: APP, label: "app", footprint: 1, share: nil, growth_rate: 0.0)]
    memory = [session_memory(session_id: REPO), session_memory(session_id: APP)]
    reading = Fixtures.reading(machine(0), values: { pressure_drivers: drivers, session_memory: memory })
    focused = Agentmon::Focus.apply(reading, APP)

    assert_equal [APP], focused[:pressure_drivers].map(&:session_id)
    assert_equal [APP], focused[:session_memory].map(&:session_id)
  end

  def test_missing_metrics_stay_nil_when_focused
    focused = Agentmon::Focus.apply(Fixtures.reading(machine(0), values: { process_rows: nil, session_memory: nil }), REPO)

    assert_nil focused[:process_rows]
    assert_nil focused[:session_memory]
  end

  def test_unfocused_view_and_clearing
    e = engine
    e.current
    e.focus = APP

    assert_equal 12, e.current(focused: false)[:process_rows].size
    assert_equal APP, e.focused_session.id
    e.focus = nil

    assert_nil e.current.focus
    assert_nil e.focused_session
    assert_equal 12, e.current[:process_rows].size
  end

  def test_a_session_that_left_the_ledger_shows_nothing
    e = engine
    e.focus = "claude-9999-1"

    assert_empty e.current[:process_rows]
    assert_nil e.focused_session
  end

  def test_focused_reading_is_built_once_per_reading
    e = engine
    e.focus = REPO

    assert_same e.current, e.current
  end

  def test_find_matches_id_root_pid_then_label
    sessions = Fixtures.reading(machine(0))[:session_ledger]

    assert_equal [REPO], Agentmon::Focus.find(sessions, REPO).map(&:id)
    assert_equal [REPO], Agentmon::Focus.find(sessions, "200").map(&:id)
    assert_equal [REPO], Agentmon::Focus.find(sessions, "REPO").map(&:id)
    assert_empty Agentmon::Focus.find(sessions, "nothing")
  end

  # The proof that panels follow focus without knowing about it: the Processes panel only reads
  # engine.current[:process_rows].
  def test_the_processes_panel_follows_the_focus
    with_engine(engine) do |e|
      e.current
      e.focus = REPO
      text = dashboard_frame(dashboard_app)

      assert_match(/^\W*200\s+claude/, text)
      refute_match(/^\W*303\s+claude/, text)
    end
  end
end
