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

  def test_all_includes_every_process_and_unknowns_are_blank
    result = top("--once", "--all", "--limit", "20")

    assert_includes result.out, "Finder"
    assert_match(/^\s*500\s+WindowServer\s+11\.2%\s+134M\s*$/, result.out)
  end

  def test_sort_and_limit
    result = top("--once", "--sort", "footprint", "-n", "2")

    assert_equal %w[200 300], result.out.lines.drop(1).map { |l| l.split.first }
  end

  def test_unknown_sort_is_a_usage_error
    assert_equal 2, top("--sort", "nope").code
  end

  def test_off_a_terminal_top_prints_once_without_the_flag
    assert_includes top.out, "claude 200 · repo"
  end
end
