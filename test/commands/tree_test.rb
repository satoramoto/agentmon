# frozen_string_literal: true

require "test_helper"

class TreeCommandTest < Minitest::Test
  include Fixtures
  include R2UI::CLI::Testing

  CLAUDE_200 = "claude-200-#{(Fixtures::T0 - 3600 + 200).to_i}".freeze

  def tree(*argv, engine: Fixtures.engine(machine(0), machine(2)))
    with_engine(engine) { run_cli(Agentmon::Program.build, "tree", *argv) }
  end

  def lines(result) = result.out.lines.map(&:rstrip)

  def test_prints_each_session_as_a_tree_rooted_at_its_label
    result = tree

    assert result.success?, result.err
    roots = lines(result).reject { |l| l.empty? || l.start_with?(" ", "│", "├", "└") }
    assert_equal ["claude 200 · repo", "Claude 300", "claude 303 · web"], roots
    refute_includes result.out, "Finder"
    refute_includes result.out, "WindowServer"
    refute_includes result.out, "\e[" # plain in a pipe
  end

  def test_tree_nests_by_parent_with_pid_name_footprint_and_cpu
    result = tree("repo")

    assert result.success?, result.err
    assert_equal [
      "claude 200 · repo",
      "└── 200 claude · 512M · 100.0%",
      "    ├── 201 node · 100M · 50.0%",
      "    └── 202 zsh · 8.0M · 0.0%",
      "        └── 203 git · 8.0M · 0.0%"
    ], lines(result)
  end

  def test_an_app_session_leaves_out_the_cli_session_it_launched
    result = tree("300")

    assert result.success?, result.err
    assert_equal "Claude 300", lines(result).first
    assert_includes result.out, "301 Claude Helper · 200M"
    assert_includes result.out, "302 disclaimer · 1.0M"
    refute_includes result.out, "303 claude"
  end

  def test_argument_matches_id_root_pid_or_label_substring
    assert_equal "claude 200 · repo", lines(tree(CLAUDE_200)).first
    assert_equal "claude 303 · web", lines(tree("303")).first
    assert_equal "claude 303 · web", lines(tree("WEB")).first
    assert_equal 1, lines(tree("web")).count { |l| !l.start_with?(" ", "│", "├", "└") }
  end

  def test_unknown_session_exits_1_with_the_list_of_sessions
    result = tree("nope")

    assert_equal 1, result.code
    assert_empty result.out
    assert_includes result.err, "nope"
    ["claude 200 · repo", "Claude 300", "claude 303 · web", CLAUDE_200].each { |s| assert_includes result.err, s }
  end

  def test_an_ambiguous_label_exits_1_with_the_matches
    result = tree("claude")

    assert_equal 1, result.code
    assert_empty result.out
    assert_includes result.err, "claude 200 · repo"
    assert_includes result.err, "claude 303 · web"
  end

  def test_unknown_footprint_is_shown_as_not_available
    engine = Fixtures.engine(machine(0, 202 => { footprint: nil }), machine(2, 202 => { footprint: nil }))
    result = tree("repo", engine:)

    assert result.success?, result.err
    assert_includes result.out, "202 zsh · n/a · 0.0%"
  end

  def test_no_sessions_says_so_and_exits_0
    idle = ->(t) { sample(t, processes: [process(pid: 1, ppid: 0, name: "launchd"), process(pid: 400, name: "Finder")]) }
    result = tree(engine: Fixtures.engine(idle.call(0), idle.call(2)))

    assert result.success?, result.err
    assert_equal "No agent sessions running.\n", result.out

    named = tree("repo", engine: Fixtures.engine(idle.call(0), idle.call(2)))
    assert_equal 1, named.code
    assert_includes named.err, "No agent sessions running."
  end

  def test_missing_sessions_metric_is_handled_as_no_sessions
    registry = Agentmon::Registry.new
    Agentmon.registry.metrics.reject { |m| m.name == :sessions }.each { |m| registry.add(:metric, m) }
    engine = Agentmon::Engine.new(sampler: Sampler.new(machine(0), machine(2)), registry:, prime_gap: 0)
    result = tree(engine:)

    assert result.success?, result.err
    assert_equal "No agent sessions running.\n", result.out
  end
end
