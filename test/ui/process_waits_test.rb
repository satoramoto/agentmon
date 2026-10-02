# frozen_string_literal: true

require "test_helper"

# Wait detail, columns and the Waiting scope on the fixture machine. Between machine(0) and
# machine(2) claude 200 waits 25% for a CPU, with 10 pageins/s, 1000 faults/s, 100 COW faults/s
# and 500 context switches/s; nothing else waits or pages in. WindowServer 500 is unreadable.
class ProcessWaitsPanelTest < Minitest::Test
  include Fixtures

  Waits = Agentmon::UI::ProcessWaits
  Detail = Agentmon::UI::ProcessDetail
  PIDS = [1, 100, 200, 201, 202, 203, 300, 301, 302, 303, 400, 500].freeze

  def setup
    @previous = [Detail.command_reader, Detail.file_counter]
    Detail.command_reader = ->(pid) { "/usr/bin/fake-#{pid}" }
    Detail.file_counter = ->(_pid) { nil }
  end

  def teardown
    Detail.command_reader, Detail.file_counter = @previous
  end

  # The pids shown as table rows (a row starts with its pid in the first column).
  def pids(text) = text.scan(/^\W*(\d+)\s+\S/).flatten.map(&:to_i).select { |p| PIDS.include?(p) }.uniq.sort

  # The Processes table line for `pid`.
  def table_line(text, pid) = text.lines.find { |l| l.match?(/^\W*#{pid}\s+\S/) }

  # How many `]` presses from the default scope (Agents) reach Waiting.
  def presses_to_waiting
    scopes = R2UI.registry.resource(:process).scopes
    scopes.index { |s| s.name == :waiting } - scopes.index(&:default)
  end

  def select_pid(app, pid)
    dashboard_frame(app)
    panel = app.dashboard.panels.find { |p| p.name == :process }
    index = app.panel_lines(panel).index { |l| l.rows.map(&:pid) == [pid] }
    assert index, "pid #{pid} not in the table"
    app.press(*([:down] * index))
  end

  def row(pid, *samples)
    reading = nil
    with_engine(Fixtures.engine(*samples)) { reading = Agentmon.engine.current }
    reading[:process_rows].find { |r| r.pid == pid }
  end

  def test_detail_shows_waits_for_the_selected_process
    with_engine(Fixtures.engine(machine(0), machine(2))) do
      text = dashboard_frame(dashboard_app) # first row by CPU: claude 200

      assert_match(/Threads\s+12 \(1 running\)/, text)
      assert_match(/CPU wait\s+25\.0% now, 500ms total/, text) # runnable 12.5 s - CPU 12 s
      assert_match(/Page-ins\s+10\/s, 20 total/, text)
      assert_match(/Faults\s+1000\/s \(COW 100\/s\)/, text)
      assert_match(/Switches\s+500\/s/, text)
      assert_match(/Wired\s+1\.0M/, text)
      assert_match(/Read\s+0B\/s, 0B total/, text)
    end
  end

  def test_detail_follows_the_selection
    with_engine(Fixtures.engine(machine(0), machine(2))) do
      a = dashboard_app
      select_pid(a, 201)
      text = dashboard_frame(a)

      assert_match(/Threads\s+1 \(0 running\)/, text)
      assert_match(/CPU wait\s+0\.0% now, 0ms total/, text)
      assert_match(/Page-ins\s+0\/s, 0 total/, text)
    end
  end

  def test_unreadable_process_says_so
    with_engine(Fixtures.engine(machine(0), machine(2))) do
      a = dashboard_app
      a.press("]") # All
      select_pid(a, 500)
      text = dashboard_frame(a)

      %w[Threads CPU\ wait Page-ins Faults Switches Wired Read].each do |label|
        assert_match(/#{label}\s+not readable without root/, text)
      end
    end
  end

  def test_first_sample_leaves_out_unknown_rates
    lines = Waits.lines(row(200, machine(0))).to_h

    assert_equal "0ms total", lines["CPU wait"]
    assert_equal "0 total", lines["Page-ins"]
    assert_nil lines["Faults"]   # shown as "unknown" by the Detail panel
    assert_nil lines["Switches"]
    assert_equal "0B total", lines["Read"]
  end

  def test_columns_show_wait_and_pagein_rate
    with_engine(Fixtures.engine(machine(0), machine(2))) do
      text = dashboard_frame(dashboard_app)

      assert_match(/Write\s+Wait\s+Pgin\/s │/, text)
      assert_match(/1000B\/s\s+25\.0%\s+10\.0 │/, table_line(text, 200))
      assert_match(/0B\/s\s+0\.0%\s+0\.0 │/, table_line(text, 201))
    end
  end

  # Before two samples run_wait and pagein_rate are unknown: both cells blank (not 0).
  def test_columns_are_blank_when_unknown
    with_engine(Fixtures.engine(machine(0))) do
      text = dashboard_frame(dashboard_app)

      assert_match(/Write\s+Wait\s+Pgin\/s │/, text)
      line = table_line(text, 200)
      assert_match(/600M +│/, line) # Resident, then blank Read, Write, Wait and Pgin/s
      refute_match(/600M.*%/, line.split("││").first)
    end
  end

  def test_waiting_scope_shows_processes_waiting_or_paging_in
    with_engine(Fixtures.engine(machine(0), machine(2))) do
      a = dashboard_app
      a.press(*Array.new(presses_to_waiting, "]"))
      text = dashboard_frame(a)

      assert_match(/Writing.*Waiting/, text)
      assert_equal [200], pids(text)
    end
  end

  def test_waiting_scope_thresholds
    base = row(201, machine(0), machine(2))

    refute Waits.waiting?(base)
    assert Waits.waiting?(base.with(run_wait: 10.5))
    refute Waits.waiting?(base.with(run_wait: 10.0))
    assert Waits.waiting?(base.with(pagein_rate: 0.5))
    refute Waits.waiting?(base.with(run_wait: nil, pagein_rate: nil))
  end
end
