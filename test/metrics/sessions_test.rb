# frozen_string_literal: true

require "test_helper"

class SessionsMetricTest < Minitest::Test
  include Fixtures

  def map(sample = machine) = Fixtures.reading(sample)[:sessions]

  def test_cli_session_takes_its_whole_tree
    s = map.of(203)

    assert_equal :cli, s.kind
    assert_equal 200, s.root_pid
    assert_equal [200, 201, 202, 203], map.by_pid.select { |_, id| id == s.id }.keys.sort
  end

  def test_label_and_stable_id
    s = map.of(200)

    assert_equal "claude 200 · repo", s.label
    assert_equal "claude-200-#{(T0 - 3600 + 200).to_i}", s.id
    assert_equal "/Users/me/src/repo", s.cwd
  end

  def named(names) = Fixtures.reading(machine, values: { session_names: names })[:sessions]

  def test_a_name_leads_the_label
    name = Agentmon::SessionName.new(title: "Agentmon r2ui integration", status: "busy", threads: [])
    s = named({ 200 => name, 300 => Agentmon::SessionName.new(title: "Chat +1", status: nil, threads: %w[Chat Other]) })

    assert_equal "Agentmon r2ui integration · claude 200 · repo", s.of(200).label
    assert_equal ["Agentmon r2ui integration", "busy", []], [s.of(200).title, s.of(200).status, s.of(200).threads]
    assert_equal "Chat +1 · Claude 300", s.of(300).label
    assert_equal %w[Chat Other], s.of(300).threads
    assert_equal "claude 303 · web", s.of(303).label # no name: today's label
    assert_nil s.of(303).title
  end

  def test_a_status_without_a_name_keeps_the_label
    s = named({ 200 => Agentmon::SessionName.new(title: nil, status: "idle", threads: []) }).of(200)

    assert_equal ["claude 200 · repo", "idle"], [s.label, s.status]
  end

  def test_focus_find_and_the_sessions_filter_match_a_name
    names = { 200 => Agentmon::SessionName.new(title: "Agentmon r2ui integration", status: nil, threads: []) }
    ledger = Fixtures.reading(machine, values: { session_names: names }).then do |reading|
      Agentmon::Metrics::SessionLedger.new({}).call(reading)
    end

    assert_equal [200], Agentmon::Focus.find(ledger, "r2ui INTEG").map(&:root_pid)
    assert_empty Agentmon::Focus.find(ledger, "nothing like it")
  end

  def test_desktop_app_helpers_are_one_app_session
    app = map.of(301)

    assert_equal :app, app.kind
    assert_equal 300, app.root_pid
    assert_equal "Claude 300", app.label
    assert_equal app.id, map.by_pid[302]
  end

  def test_claude_code_under_the_app_is_its_own_session
    s = map.of(303)

    assert_equal :cli, s.kind
    assert_equal 303, s.root_pid
    assert_equal "claude 303 · web", s.label
  end

  def test_outermost_cli_wins_for_sub_agents
    sample = Fixtures.sample(0, processes: machine.parts[:processes] + [process(pid: 204, ppid: 201, name: "claude")])

    assert_equal 200, map(sample).of(204).root_pid
  end

  def test_other_processes_are_in_no_session
    assert_nil map.of(400)
    assert_nil map.of(500)
    assert_nil map.of(1)
  end

  def test_parent_cycles_terminate
    sample = Fixtures.sample(0, processes: [process(pid: 0, ppid: 0, name: "kernel_task"),
                                            process(pid: 5, ppid: 6, name: "a"), process(pid: 6, ppid: 5, name: "claude")])

    assert_equal 6, map(sample).of(5).root_pid
    assert_nil map(sample).of(0)
  end
end
