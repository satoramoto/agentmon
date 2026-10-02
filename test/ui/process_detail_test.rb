# frozen_string_literal: true

require "test_helper"

# The Detail pane on fixture data: it follows the row selected in the Processes panel.
class ProcessDetailPanelTest < Minitest::Test
  include Fixtures

  Detail = Agentmon::UI::ProcessDetail

  def setup
    @calls = []
    @previous = [Detail.command_reader, Detail.file_counter]
    Detail.command_reader = lambda do |pid|
      @calls << pid
      "/usr/bin/fake-#{pid} --resume --verbose"
    end
    Detail.file_counter = ->(pid) { pid == 200 ? 42 : nil }
  end

  def teardown
    Detail.command_reader, Detail.file_counter = @previous
  end

  def app = dashboard_app

  # The full dashboard, keys on Processes (the Detail pane follows its selection).
  def frame(app) = dashboard_frame(app)

  def process_panel(app) = app.dashboard.panels.find { |p| p.name == :process }

  def select_pid(app, pid)
    frame(app)
    index = app.panel_lines(process_panel(app)).index { |l| l.rows.map(&:pid) == [pid] }
    assert index, "pid #{pid} not in the table"
    app.press(*([:down] * index))
  end

  def test_shows_the_selected_process_in_full
    with_engine(Fixtures.engine(machine(0), machine(2))) do
      text = frame(app) # first row by CPU: claude 200

      assert_includes text, "/usr/bin/fake-200"
      assert_includes text, "/Users/me/src/repo"
      assert_match(/Session\s+claude 200 · repo/, text)
      assert_match(/Footprint\s+512M/, text)
      assert_match(/Resident\s+600M/, text)
      assert_match(/Peak\s+512M/, text)
      assert_match(/CPU time\s+12\.0s/, text)              # 10 s + 2 s of fixture growth
      assert_match(/Written\s+#{Regexp.escape(R2UI::Format.bytes(2000))}/, text)
      assert_match(/Started\s+56m 42s ago/, text)          # started T0 - 3400, now T0 + 2
      assert_match(/Open files\s+42/, text)
    end
  end

  def test_reads_the_command_line_once_per_selection
    with_engine(Fixtures.engine(machine(0), machine(2))) do
      a = app
      3.times { frame(a) }
      select_pid(a, 201)
      2.times { frame(a) }

      assert_equal [200, 201], @calls
      assert_includes frame(a), "/usr/bin/fake-201"
    end
  end

  def test_unreadable_process_says_so_for_rusage_fields
    with_engine(Fixtures.engine(machine(0), machine(2))) do
      a = app
      a.press("]") # All
      select_pid(a, 500)
      text = frame(a)

      assert_includes text, "WindowServer"
      assert_match(/Resident\s+134M/, text) # ps's value still shows
      assert_match(/Footprint\s+not readable without root/, text)
      assert_match(/CPU time\s+not readable without root/, text)
      assert_match(/Open files\s+not readable without root/, text)
    end
  end

  def test_a_group_line_asks_for_one_process
    with_engine(Fixtures.engine(machine(0), machine(2))) do
      a = app
      a.press("g") # group by session
      text = frame(a)

      assert_match(/4 processes/, text)
      assert_empty @calls
    end
  end

  def test_nothing_selected_without_process_rows
    with_engine(Fixtures.engine(sample(0, processes: []), sample(2, processes: []))) do
      text = frame(app)

      assert_includes text, "No process selected"
      assert_empty @calls
    end
  end

  def test_a_failing_command_reader_falls_back_to_the_path
    Detail.command_reader = ->(_pid) {}
    with_engine(Fixtures.engine(machine(0), machine(2))) do
      assert_includes frame(app), "/usr/bin/claude"
    end
  end

  # Agentmon.detail_section: other stories' lines go under the process's own; one that raises
  # shows its error instead of breaking the pane.
  def test_detail_sections_add_lines_in_order
    ok = Agentmon::DetailSection.new(name: :waits, order: 10, block: ->(row, reading) { [["Pageins", "#{row.pageins} at #{reading.at.to_i}"], ["Nothing", nil]] })
    broken = Agentmon::DetailSection.new(name: :broken, order: 20, block: ->(_row, _reading) { raise "boom" })
    row = Agentmon::Metrics::ProcessRows.call(machine(2)[:processes], nil, {}, nil).find { |r| r.pid == 200 }
    reading = Fixtures.reading(machine(2))

    lines = Detail.lines(row, "claude", now: reading.at, width: 60, reading:, sections: [ok, broken])

    assert_equal "Open files", lines[-4][0, 10]
    assert_match(/\APageins\s+20 at #{reading.at.to_i}\z/, lines[-3])
    assert_match(/\ANothing\s+unknown\z/, lines[-2])
    assert_match(/\Abroken\s+RuntimeError: boom\z/, lines[-1])
  end
end
