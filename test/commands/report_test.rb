# frozen_string_literal: true

require "test_helper"
require "json"
require "minitest/mock"

class ReportCommandTest < Minitest::Test
  include Fixtures
  include R2UI::CLI::Testing

  NOW = Fixtures::T0 + 100_000
  HOUR = 3600
  GB = 1024 * MB

  def setup
    @dir = Dir.mktmpdir("agentmon-report")
    @store = Agentmon::Store.new(dir: @dir)
  end

  def teardown = FileUtils.remove_entry(@dir)

  # A `sessions` store line as the a11 recorder writes it: Session#to_record plus t and run.
  def line(id:, t:, run: "run-a", label: nil, started_at: NOW - (4 * HOUR), last_seen_at: t, ended_at: nil,
           cpu_seconds: 0.0, bytes_written: 0, bytes_read: 0, peak_footprint: 0)
    pid = id.split("-")[1].to_i
    session = Agentmon::Session.new(
      id:, kind: :cli, name: "claude", root_pid: pid, label: label || "claude #{pid} · repo", cwd: "/Users/me/src/repo",
      started_at:, first_seen_at: started_at, last_seen_at:, ended_at:, processes: ended_at ? 0 : 2, cpu: 0.0,
      footprint: 0, resident: 0, read_rate: 0.0, write_rate: 0.0, peak_footprint:, cpu_seconds:, bytes_read:,
      bytes_written:
    )
    @store.append(:sessions, session.to_record.merge(t:, run:))
  end

  def report(*argv, **shell)
    Agentmon::Clock.stub(:now, NOW) do
      with_engine(Fixtures.engine(machine(0), store: @store)) { run_cli(Agentmon::Program.build, "report", *argv, **shell) }
    end
  end

  def hhmm(t) = Time.at(t).strftime("%H:%M")

  # Ended after two agentmon runs (the second recounted from the kernel, so lower totals);
  # still running; and one whose writer stopped mid-session five hours ago.
  def write_history
    line(id: "claude-200-1", t: NOW - (3 * HOUR), cpu_seconds: 600.0, bytes_written: 1 * GB, peak_footprint: 900 * MB)
    line(id: "claude-200-1", t: NOW - (2 * HOUR), run: "run-b", cpu_seconds: 500.0, bytes_written: 2 * GB,
         peak_footprint: 512 * MB, ended_at: NOW - (2 * HOUR))
    line(id: "claude-300-1", t: NOW - 20, started_at: NOW - HOUR, cpu_seconds: 60.0, bytes_written: 0,
         peak_footprint: 100 * MB)
    line(id: "claude-400-1", t: NOW - (5 * HOUR), started_at: NOW - (6 * HOUR), cpu_seconds: 3600.0,
         bytes_written: 100 * MB, peak_footprint: 2 * GB)
    line(id: "claude-500-1", t: NOW - (30 * HOUR), started_at: NOW - (31 * HOUR), ended_at: NOW - (30 * HOUR),
         cpu_seconds: 10.0)
  end

  def row(out, label) = out.lines.find { |l| l.include?(label) }.to_s

  def test_summary_merges_lines_by_id_with_maxima
    write_history
    result = report
    out = result.out

    assert result.success?, result.err
    assert_match(/\AAgent sessions · last 24h/, out.lines.first)
    assert_match(/Session\s+Started\s+Duration\s+Peak\s+CPU\s+Written\s+Status/, out)
    ended = row(out, "claude 200 · repo")
    assert_includes ended, hhmm(NOW - (4 * HOUR))
    assert_includes ended, "2h 0m" # started 4h ago, ended 2h ago
    assert_includes ended, "900M"  # peak: the larger of the two runs
    assert_includes ended, "10m 0s" # CPU 600 s, the maximum, not the 1100 s sum
    assert_includes ended, "2.0G"
    assert_includes ended, "ended #{hhmm(NOW - (2 * HOUR))}"
    assert_equal 1, out.scan("claude 200 · repo").size
    refute_includes out, "claude 500" # outside the period
    refute_includes out, "\e["        # plain in a pipe
  end

  def test_a_session_still_written_recently_is_running
    write_history

    assert_match(/running\s*\z/, row(report.out, "claude 300 · repo").rstrip)
  end

  def test_a_session_whose_writer_stopped_is_ended_at_its_last_seen_time_never_running
    write_history
    stale = row(report.out, "claude 400 · repo")

    assert_includes stale, "ended (not seen after #{hhmm(NOW - (5 * HOUR))})"
    refute_includes stale, "running"
    assert_includes stale, "1h 0m" # duration stops at last seen: 6h ago to 5h ago
  end

  def test_totals_line
    write_history

    # 600 + 60 + 3600 s CPU; 2G + 0 + 100M written.
    assert_includes report.out, "3 sessions · 1h 11m CPU · 2.1G written"
  end

  def test_since_widens_and_narrows_the_period
    write_history

    wide = report("--since", "2d").out
    assert_match(/last 2d/, wide)
    assert_includes wide, "claude 500 · repo"
    assert_includes wide, "4 sessions"

    narrow = report("--since", "90m").out
    assert_includes narrow, "claude 300 · repo"
    refute_includes narrow, "claude 200 · repo"
    assert_includes narrow, "1 session ·"
  end

  def test_bad_since_is_a_usage_error
    result = report("--since", "soon")

    assert_equal 2, result.code
    assert_includes result.err, "--since"
  end

  def test_empty_period_says_so
    line(id: "claude-200-1", t: NOW - (3 * HOUR), cpu_seconds: 600.0)
    result = report("--since", "10m")

    assert result.success?
    assert_includes result.out, "No agent sessions recorded in the last 10m."
  end

  def test_empty_store_says_so
    result = report

    assert result.success?
    assert_includes result.out, "No agent sessions recorded in the last 24h."
  end

  def test_json_prints_merged_records_with_raw_units
    write_history
    result = report("--json")
    records = result.out.lines.map { |l| JSON.parse(l) }.to_h { |r| [r["id"], r] }

    assert result.success?, result.err
    assert_equal %w[claude-400-1 claude-200-1 claude-300-1], records.keys # oldest start first
    ended = records["claude-200-1"]
    assert_equal 600.0, ended["cpu_seconds"]
    assert_equal 2 * GB, ended["bytes_written"]
    assert_equal 900 * MB, ended["peak_footprint"]
    assert_equal NOW - (2 * HOUR), ended["ended_at"]
    assert_equal "ended", ended["status"]
    assert_equal "running", records["claude-300-1"]["status"]
    stale = records["claude-400-1"]
    assert_equal "not_seen", stale["status"]
    assert_nil stale["ended_at"]
    assert_equal HOUR.to_f, stale["duration"]
    refute ended.key?("run")
  end

  def test_json_of_an_empty_period_prints_nothing
    result = report("--json")

    assert result.success?
    assert_equal "", result.out
  end
end
