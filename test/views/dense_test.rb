# frozen_string_literal: true

require "test_helper"

# The dense layout (lib/agentmon/views/dense.rb) at the owner's window size, over fixtures: the
# session list at home, one session's breakdown, processes and connections when drilled in.
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

  # Home has no :process panel, so keys stay where the view puts them (the Sessions table).
  def with_app
    with_engine(Fixtures.engine(*samples)) { yield dashboard_app(view: :dense, focus: nil) }
  end

  def assert_fits(text, width = 100, height = 50)
    lines = text.split("\n")

    assert_equal height, lines.size
    lines.each { |line| assert_operator Agentmon::Views::Widgets.visible_width(line), :<=, width, line }
  end

  def test_home_is_the_session_list_with_the_machine_strip
    with_app do |app|
      text = view_frame(app)

      %w[CPU Memory I/O Sessions].each { |title| assert_includes text, "─ #{title} " }
      assert_includes text, "─ All agents "
      %w[Processes Detail Connections].each { |title| refute_includes text, "─ #{title} " }
      assert_includes text, "claude 200 · repo" # a session label, uncut
      ["Session", "Procs", "Footprint", "Read", "Write", "Net in", "Net out"].each { |h| assert_includes text, h }
      assert_match(/sessions · ⏎/, text.split("\n").last)
      assert_fits(text)
    end
  end

  def test_a_name_cut_by_the_session_column_is_still_found_by_search
    names = Agentmon::Metrics::SessionNames
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, "200.json"), '{"pid":200,"name":"Agentmon r2ui integration","status":"busy"}')
      names.claude_dir = dir
      with_app do |app|
        text = view_frame(app)

        assert_includes text, "Agentmon r2ui…" # name first, cut at a word boundary to 23 cells
        refute_includes text, "integration"

        app.press("/", *"integration".chars, "enter")
        found = view_frame(app)

        assert_includes found, "Agentmon r2ui…"
        refute_includes found, "claude 303"
      end
    ensure
      names.claude_dir = NO_NAMES_DIR
    end
  end

  def test_machine_strip_shows_fixture_values
    with_app do |app|
      lines = view_frame(app).split("\n")

      assert_match(/cores\s+10/, lines.find { |l| l.include?("cores") })
      assert_match(/load 1m\s+1\.5/, lines.find { |l| l.include?("load 1m") })
      assert_match(/swap\s.*1\.0G/, lines.find { |l| l.include?("swap") })
    end
  end

  def test_enter_drills_into_the_selected_session_and_escape_returns
    with_app do |app|
      view_frame(app) # Enter acts on the line drawn as selected
      app.press(:enter)
      text = view_frame(app)

      %w[Processes Connections Detail Network].each { |title| assert_includes text, "─ #{title} " }
      refute_includes text, "─ Sessions "
      %w[Pid Name Wait Read Write].each { |h| assert_includes text, h }
      assert_match(/▸ .* · esc back to sessions/, text.split("\n").last)
      assert_equal :process, app.focus.name
      assert_fits(text)

      app.press(:escape)
      home = view_frame(app)

      assert_includes home, "─ Sessions "
      refute_includes home, "─ Processes "
      assert_equal :session, app.focus.name
    end
  end

  # The drilled-in Memory panel shows the machine's RAM (used of total) with the session's
  # footprint as a slice, and pressure, not the footprint as a share of used memory.
  def test_drilled_in_memory_shows_the_machine_with_the_session_slice
    with_app do |app|
      view_frame(app)
      app.press(:enter)
      lines = view_frame(app).split("\n")
      ram = lines.find { |l| l.include?("RAM ▕") }

      refute_nil ram, lines.first(7).join("\n")
      assert_match(%r{RAM ▕.{6,}▏ \d[\d.]*[KMG] (<1|\d+)% · 9\.0G/16G│}, ram)
      assert_match(/pressure\s+30\.0%/, lines[0, 7].find { |l| l.include?("pressure") })
      refute_includes lines.first(7).join, "footprint ▕"
    end
  end

  def test_fits_other_window_sizes
    with_app do |app|
      [[120, 40], [200, 50]].each do |w, h|
        [nil, :enter, :escape].each do |key|
          app.press(key) if key
          assert_fits(app.frame(w, h).plain_lines.join("\n"), w, h)
        end
      end
    end
  end
end
