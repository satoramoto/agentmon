# frozen_string_literal: true

require "test_helper"

# Busy, Heavy and Writing scopes on the Processes table, over the fixture machine. Between
# machine(0) and machine(2): claude 200 runs at 100% with 512M footprint writing 1000 B/s, node 201
# at 50%, WindowServer (unreadable) at ps's 11.2%; nothing else is above 5%, 500 MiB or 0 B/s.
class ProcessScopesPanelTest < Minitest::Test
  include Fixtures

  def app
    Agentmon::UI.install(engine: Agentmon.engine)
    R2UI::App.new(R2UI.registry, Agentmon::UI::DASHBOARD).tap { |a| a.feeds.each_value(&:refresh!) }
  end

  def frame(app, width: 150, height: 24) = app.frame(width, height).plain_lines.join("\n")

  # The pids shown as table rows (a row starts with its pid in the first column).
  def pids(text) = text.scan(/^\W*(\d+)\s+\S/).flatten.map(&:to_i).select { |p| [1, 100, 200, 201, 202, 203, 300, 301, 302, 303, 400, 500].include?(p) }.sort

  def in_scope(presses)
    with_engine(Fixtures.engine(machine(0), machine(2))) do
      a = app
      a.press(*Array.new(presses, "]"))
      yield a, frame(a)
    end
  end

  def test_scopes_follow_agents_and_all
    in_scope(0) do |_a, text|
      assert_match(/Agents.*All.*Busy.*Heavy.*Writing/, text)
    end
  end

  def test_busy_shows_processes_above_five_percent_cpu
    in_scope(2) do |_a, text|
      assert_equal [200, 201, 500], pids(text)
      assert_match(/WindowServer.*11\.2%/, text) # unreadable: ps's %cpu counts
    end
  end

  def test_heavy_shows_processes_above_500_mib_footprint
    in_scope(3) do |_a, text|
      assert_equal [200], pids(text)
      assert_match(/claude.*512M/, text)
    end
  end

  def test_writing_shows_processes_with_a_write_rate
    in_scope(4) do |_a, text|
      assert_equal [200], pids(text)
      assert_match(/1000B\/s/, text)
    end
  end

  def test_search_applies_inside_a_scope
    in_scope(2) do |a, _text|
      a.press("/", *"node".chars, "enter")
      assert_equal [201], pids(frame(a))
    end
  end

  def test_unknown_values_are_left_out
    row = Agentmon::ProcessRow.new(pid: 500, ppid: 1, name: "WindowServer", path: nil, cwd: nil, session: nil,
                                   session_id: nil, cpu: nil, footprint: nil, resident: nil, peak_footprint: nil,
                                   read_rate: nil, write_rate: nil, cpu_time: nil, disk_written: nil,
                                   started_at: nil, readable: false)
    scopes = Agentmon::UI::ProcessScopes

    refute scopes.busy?(row)
    refute scopes.heavy?(row)
    refute scopes.writing?(row)
  end

  def test_first_frame_without_rates_shows_no_writers
    with_engine(Fixtures.engine(machine(0))) do
      a = app
      a.press("]", "]", "]", "]")
      assert_empty pids(frame(a))
    end
  end
end
