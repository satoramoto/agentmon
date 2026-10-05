# frozen_string_literal: true

require "test_helper"

# The dense layout (lib/agentmon/views/dense.rb) at the owner's window size, over fixtures.
class DenseViewTest < Minitest::Test
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

  def samples
    [0, 2].map do |t|
      s = machine(t)
      s.with(parts: s.parts.merge(memory: memory_stat, system: system_stat(t, 500 * t)))
    end
  end

  def frame
    with_engine(Fixtures.engine(*samples)) { return view_frame(dashboard_app(view: :dense)) }
  end

  def test_dense_shows_every_panel
    text = frame

    %w[CPU Memory I/O Sessions Processes Detail].each { |title| assert_includes text, "─ #{title} " }
  end

  def test_machine_strip_shows_fixture_values
    lines = frame.split("\n")

    assert_match(/cores\s+10/, lines.find { |l| l.include?("cores") })
    assert_match(/load 1m\s+1\.5/, lines.find { |l| l.include?("load 1m") })
    assert_match(/swap\s.*1\.0G/, lines.find { |l| l.include?("swap") })
  end

  def test_tables_show_sessions_and_processes_with_every_header
    text = frame

    assert_includes text, "claude 200 · repo" # a session label, uncut
    %w[Session Procs Footprint Age Pid Name Wait Pgin/s Read Write].each { |h| assert_includes text, h }
    assert_match(/\b201 node\s/, text) # a process of the Agents scope with its pid
  end

  def test_no_line_is_wider_than_the_window
    frame.split("\n").each do |line|
      assert_operator Agentmon::Views::Widgets.visible_width(line), :<=, 100, line
    end
  end
end
