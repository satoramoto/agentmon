# frozen_string_literal: true

require "test_helper"

class TopCommandTest < Minitest::Test
  include Fixtures
  include R2UI::CLI::Testing

  def top(*argv)
    with_engine(Fixtures.engine(machine(0), machine(2))) { run_cli(Agentmon::Program.build, "top", *argv) }
  end

  def test_once_prints_agent_processes_busiest_first_as_plain_columns
    result = top("--once")
    lines = result.out.lines.map(&:rstrip)

    assert result.success?, result.err
    assert_match(/\APID\s+Name\s+Session\s+CPU\s+Footprint\s+Resident\s+Read\s+Write\z/, lines.first.strip)
    assert_match(/\A200\s+claude\s+claude 200 · repo\s+100\.0%\s+512M\s+600M\s+0B\/s\s+1000B\/s\z/, lines[1].strip)
    assert_equal %w[200 201 202], lines[1..3].map { |l| l.split.first } # ties at 0% by pid
    refute_includes result.out, "Finder"
    refute_includes result.out, "\e[" # plain in a pipe
  end

  def test_a_long_session_name_is_cut_at_a_word_to_fit_the_width
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, "200.json"), '{"name":"Agentmon r2ui integration with a long name"}')
      Agentmon::Metrics::SessionNames.claude_dir = dir
      result = with_engine(Fixtures.engine(machine(0), machine(2))) do
        run_cli(Agentmon::Program.build, "top", "--once", width: 100)
      end

      assert result.out.lines.all? { |l| l.chomp.size <= 100 }, result.out
      assert_match(/\A200\s+claude\s+Agentmon r2ui( \w+)*…\s+100\.0%/, result.out.lines[1])
    ensure
      Agentmon::Metrics::SessionNames.claude_dir = NO_NAMES_DIR
    end
  end

  def test_the_live_view_cuts_the_session_not_the_columns_after_it
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, "200.json"), '{"name":"Agentmon r2ui integration with a long name"}')
      Agentmon::Metrics::SessionNames.claude_dir = dir
      rows = with_engine(Fixtures.engine(machine(0), machine(2))) { |e| e.current[:process_rows].select(&:session) }
      lines = Agentmon::Commands::Top.lines(rows, 100)

      assert lines.all? { |l| l.size <= 100 }, lines.join("\n")
      assert_match(%r{Agentmon r2ui( \w+)*…\s+100\.0%\s+512M\s+600M\s+0B/s\s+1000B/s\z}, lines.find { |l| l.start_with?("200 ") })
    ensure
      Agentmon::Metrics::SessionNames.claude_dir = NO_NAMES_DIR
    end
  end

  def test_all_includes_every_process_and_unknowns_are_blank
    result = top("--once", "--all", "--limit", "20")

    assert_includes result.out, "Finder"
    assert_match(/^\s*500\s+WindowServer\s+11\.2%\s+134M\s*$/, result.out)
  end

  def test_sort_and_limit
    result = top("--once", "--sort", "footprint", "-n", "2")

    assert_equal %w[200 300], result.out.lines.drop(1).map { |l| l.split.first }
  end

  def test_session_narrows_to_one_session_by_label_id_or_root_pid
    %w[repo 200 claude-200-1789996600].each do |query|
      result = top("--once", "--session", query)

      assert result.success?, result.err
      assert_equal %w[200 201 202 203], result.out.lines.drop(1).map { |l| l.split.first }.sort, query
    end
  end

  def test_session_that_matches_nothing_or_several_exits_1_with_the_list
    none = top("--once", "--session", "nope")
    many = top("--once", "--session", "claude")

    assert_equal 1, none.code
    assert_includes none.err, "claude 200 · repo"
    assert_equal 1, many.code
    assert_match(/matches 3 sessions/, many.err)
  end

  def test_unknown_sort_is_a_usage_error
    assert_equal 2, top("--sort", "nope").code
  end

  def test_off_a_terminal_top_prints_once_without_the_flag
    assert_includes top.out, "claude 200 · repo"
  end

  # An engine whose sampler dies after the first frame.
  class DyingEngine
    def initialize(reading)
      @reading = reading
      @calls = 0
    end

    def current = (@calls += 1) > 1 ? raise("sampler died") : @reading

    def errors = {}
  end

  def test_live_top_fails_instead_of_freezing_when_the_view_dies
    reading = Fixtures.engine(machine(0), machine(2)).current
    result = with_engine(DyingEngine.new(reading)) { run_cli(Agentmon::Program.build, "top", tty: true, width: 120) }

    assert_equal 1, result.code
    assert_includes result.err, "sampler died"
    # r2ui's test shell tags `out` with the locale's encoding (US-ASCII without one).
    assert_includes result.out.dup.force_encoding(Encoding::UTF_8), "claude 200 · repo" # the first frame was drawn
    assert result.out.end_with?(R2UI::CLI::Live::SHOW_CURSOR), "cursor shown again"
  end

  def test_broken_metrics_are_reported_on_stderr_not_stdout
    registry = Agentmon::Registry.new
    Agentmon.registry.metrics.each { |m| registry.add(:metric, m) }
    registry.add(:metric, Agentmon::Metric.new(name: :broken, block: ->(_r, _s) { raise "no swap info" }))
    engine = Agentmon::Engine.new(sampler: Sampler.new(machine(0), machine(2)), registry:, prime_gap: 0)
    result = with_engine(engine) { run_cli(Agentmon::Program.build, "top", "--once") }

    assert result.success?
    assert_includes result.err, "metric broken: RuntimeError: no swap info"
    refute_includes result.out, "no swap info"
  end
end
