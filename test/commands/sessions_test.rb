# frozen_string_literal: true

require "test_helper"
require "json"

class SessionsCommandTest < Minitest::Test
  include Fixtures
  include R2UI::CLI::Testing

  def sessions(*argv, samples: [machine(0), machine(2)], **shell)
    with_engine(Fixtures.engine(*samples)) { run_cli(Agentmon::Program.build, "sessions", *argv, **shell) }
  end

  # machine(2) without claude 303 (reaped by disclaimer 302): its session has ended.
  def ended_303
    still = machine(2).parts[:processes].reject { |p| p.pid == 303 }
    Fixtures.sample(2, processes: still, cwd: machine(2).parts[:cwd])
  end

  def lines(result) = result.out.lines.map(&:rstrip)

  def test_lists_live_sessions_busiest_first_as_plain_columns
    result = sessions
    out = lines(result)

    assert result.success?, result.err
    assert_match(/\ASession\s+Processes\s+CPU\s+Footprint\s+Peak\s+CPU time\s+Written\s+Age\z/, out.first.strip)
    # claude 200: 4 processes, claude +2 s and node +1 s over 2 s, 512M + 100M + 8M + 8M.
    assert_match(%r{\Aclaude 200 · repo\s+4\s+150\.0%\s+628M\s+628M\s+15\.6s\s+5\.0M\s+56m 42s\z}, out[1])
    assert_equal ["claude 200 · repo", "Claude 300", "claude 303 · web"], out[1..].map { |l| l[/\A.+?(?=\s{2})/] }
    assert_equal 4, out.size
    refute_includes result.out, "Finder"
    refute_includes result.out, "\e[" # plain in a pipe
  end

  def test_a_terminal_gets_a_boxed_table
    result = sessions(tty: true, width: 120)

    assert result.success?, result.err
    assert_includes result.out, "╭"
    assert_includes result.out, "claude 200 · repo"
  end

  # Runs the block with Claude session files naming pid => name.
  def with_names(names)
    Dir.mktmpdir do |dir|
      names.each { |pid, name| File.write(File.join(dir, "#{pid}.json"), JSON.generate({ pid:, name: })) }
      Agentmon::Metrics::SessionNames.claude_dir = dir
      yield
    ensure
      Agentmon::Metrics::SessionNames.claude_dir = NO_NAMES_DIR
    end
  end

  def test_a_long_name_is_cut_at_a_word_to_fit_the_width
    name = "Agentmon r2ui integration with a much longer human session name"
    plain, boxed = with_names(200 => name, 303 => "Web") do
      [sessions(width: 100), sessions(tty: true, width: 100)]
    end

    assert plain.success?, plain.err
    [plain, boxed].each do |result|
      assert result.out.lines.all? { |l| R2UI::CLI::Ext::Tabulate.width(l.chomp) <= 100 }, result.out
    end
    label = lines(plain)[1][/\A.+?(?=\s{2})/]

    kept = label.delete_suffix("…")

    assert label.end_with?("…"), label
    assert name.start_with?(kept), label
    assert_operator kept.size, :>=, "Agentmon r2ui".size
    assert_equal " ", name[kept.size], "cut after a whole word: #{label}"
    assert_includes plain.out, "Web · claude 303 · web" # short enough: whole
    assert_includes boxed.out, "Agentmon r2ui"
  end

  def test_json_carries_the_name
    record = with_names(200 => "Named") { JSON.parse(sessions("--json").out.lines.first) }

    assert_equal ["Named", "Named · claude 200 · repo", []], record.values_at("title", "label", "threads")
  end

  def test_ended_sessions_only_with_all
    live = sessions(samples: [machine(0), ended_303])
    all = sessions("--all", samples: [machine(0), ended_303])

    refute_includes live.out, "claude 303"
    assert_match(/^claude 303 · web · ended 2\.0s ago\s+0\s+0\.0%\s+0B\s+150M\s+5\.0s\s+0B\s+/, all.out)
    assert_equal 4, lines(all).size
  end

  def test_json_prints_one_object_per_line_in_raw_units
    result = sessions("--json")
    records = result.out.lines.map { |l| JSON.parse(l) }

    assert result.success?, result.err
    assert_equal [200, 300, 303], records.map { |r| r["root_pid"] }
    claude = records.first
    assert_equal "claude-200-#{(T0 - 3600 + 200).to_i}", claude["id"]
    assert_equal "cli", claude["kind"]
    assert_equal 628 * MB, claude["footprint"]
    assert_equal (5 * MB) + 2000, claude["bytes_written"]
    assert_in_delta 15.6, claude["cpu_seconds"]
    assert_in_delta 150.0, claude["cpu"]
    assert_nil claude["ended_at"]
  end

  def test_json_with_all_includes_ended_sessions
    records = sessions("--json", "--all", samples: [machine(0), ended_303]).out.lines.map { |l| JSON.parse(l) }

    ended = records.find { |r| r["root_pid"] == 303 }
    assert_in_delta T0, ended["ended_at"] # the last sample it was seen alive in
  end

  def test_no_sessions_says_so_and_succeeds
    quiet = Fixtures.sample(0, processes: [process(pid: 400, name: "Finder")])
    result = sessions(samples: [quiet])

    assert result.success?
    assert_equal "No agent sessions running.\n", result.out
    assert_equal "", sessions("--json", samples: [quiet]).out
  end

  def test_a_missing_ledger_is_no_sessions_not_a_crash
    registry = Agentmon::Registry.new
    Agentmon.registry.metrics.reject { |m| m.name == :session_ledger }.each { |m| registry.add(:metric, m) }
    engine = Agentmon::Engine.new(sampler: Sampler.new(machine(0), machine(2)), registry:, prime_gap: 0)
    result = with_engine(engine) { run_cli(Agentmon::Program.build, "sessions") }

    assert result.success?, result.err
    assert_equal "No agent sessions running.\n", result.out
  end
end
