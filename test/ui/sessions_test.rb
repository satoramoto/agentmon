# frozen_string_literal: true

require "test_helper"

# The Sessions panel (story a05) on fixture engines, through r2ui as a user sees it.
class SessionsPanelTest < Minitest::Test
  include Fixtures

  # The fixture machine with claude 303 (the CLI session under the desktop app) gone.
  def without_303(t) = Fixtures.sample(t, processes: machine(t).parts[:processes].reject { |p| p.pid == 303 },
                                          cwd: machine(t).parts[:cwd])

  # Primes the engine (two samples), then takes `more` further samples.
  def prime(engine, more: 0)
    engine.current
    more.times { engine.tick! }
    engine
  end

  # The dashboard with the Sessions panel focused and zoomed (z), so it has the whole frame however
  # many panels share its row.
  def app = dashboard_app(focus: :session).tap { |a| a.press("z") }

  def frame(app) = dashboard_frame(app, focus: :session).lines(chomp: true)

  def line_of(lines, text) = lines.find { |l| l.include?(text) } || flunk("no line with #{text.inspect}:\n#{lines.join("\n")}")

  def test_a_sessions_sums_equal_its_members
    with_engine(prime(Fixtures.engine(machine(0), machine(2)))) do |engine|
      rows = engine.current[:process_rows].select { |r| r.session == "claude 200 · repo" }
      session = engine.current[:session_ledger].find { |s| s.root_pid == 200 }
      line = line_of(frame(app), "claude 200 · repo")

      cpu = R2UI::Format.call(:percent, rows.sum(&:cpu))
      footprint = R2UI::Format.bytes(rows.sum(&:footprint))
      write = R2UI::Format.call(:bytes_per_sec, rows.sum { |r| r.write_rate || 0 })

      assert_equal ["150.0%", "628M", "1000B/s"], [cpu, footprint, write] # the members' sums
      assert_in_delta 15.6, session.cpu_seconds
      # processes, CPU and footprint (each after its sparkline), peak, CPU s, written (git's 5 MB +
      # claude's 2000 B), read/write rates, age (root started 3402 s before the sample)
      assert_match(/claude 200 · repo\s+#{rows.size}\s+\S+\s+#{cpu}\s+\S+\s+#{footprint}\s+628M\s+15\.6\s+5\.0M\s+0B\/s\s+#{write}\s+56m/,
                   line)
    end
  end

  def test_sorted_by_cpu
    with_engine(prime(Fixtures.engine(machine(0), machine(2), machine(4, 301 => { cpu_time: 24.0 })), more: 1)) do
      lines = frame(app)
      app_at = lines.index { |l| l.include?("Claude 300") }
      cli_at = lines.index { |l| l.include?("claude 200 · repo") }
      web_at = lines.index { |l| l.include?("claude 303") }

      assert_operator app_at, :<, cli_at # 200% (helper +4 s in 2 s) before 150%
      assert_operator cli_at, :<, web_at # 150% before 0%
    end
  end

  def test_an_ended_session_shows_only_under_all
    engine = prime(Fixtures.engine(machine(0), machine(2), without_303(182)), more: 1)
    with_engine(engine) do
      a = app
      live = frame(a).join("\n")

      assert_includes live, "Live"
      assert_includes live, "claude 200 · repo"
      refute_includes live, "claude 303"

      a.press("]")
      all = frame(a).join("\n")

      assert_includes all, "claude 303 · web · ended 3m ago" # last seen at t=2, now t=182
      assert_includes all, "claude 200 · repo"
    end
  end

  def test_no_ledger_shows_an_empty_panel
    registry = Agentmon::Registry.new
    Agentmon.registry.metrics.reject { |m| m.name == :session_ledger }.each { |m| registry.add(:metric, m) }
    engine = Agentmon::Engine.new(sampler: Fixtures::Sampler.new(machine(0), machine(2)), registry:, prime_gap: 0)
    with_engine(engine) do
      text = frame(app).join("\n") # zoomed: only the Sessions panel, though Processes still has sessions

      assert_includes text, "Sessions"
      refute_includes text, "claude 200"
    end
  end

  def test_processes_keeps_focus_with_sessions_above_it
    with_engine(prime(Fixtures.engine(machine(0), machine(2)))) do
      assert_equal :process, dashboard_app(focus: nil).focus.name # r2ui's choice plus agentmon's default
    end
  end

  # Stand-in with SessionNetwork's members (model.rb's Data class when it exists).
  Net = Struct.new(:session_id, :label, :in_rate, :out_rate, :bytes_in, :bytes_out, :in_trend, :out_trend,
                   :connections, :remote_hosts, :flags, keyword_init: true)

  NET_KEYS = %i[net_in_rate net_out_rate bytes_in bytes_out connections remote_hosts].freeze

  def session_rows(network)
    ledger = prime(Fixtures.engine(machine(0), machine(2))).current[:session_ledger]
    reading = Fixtures.reading(machine(2), previous: machine(0), values: { session_ledger: ledger, session_network: network })
    [ledger, Agentmon::UI::SessionsPanel.rows(reading)]
  end

  def test_rows_carry_their_sessions_network
    ledger, = session_rows(nil)
    repo = ledger.find { |s| s.root_pid == 200 }
    net = Net.new(session_id: repo.id, label: repo.label, in_rate: 2048.0, out_rate: 512.0, bytes_in: 10_000,
                  bytes_out: 4000, connections: 3, remote_hosts: 2, flags: [:out_spike])
    _, rows = session_rows([net])
    row = rows.find { |r| r[:id] == repo.id }
    other = rows.find { |r| r[:id] != repo.id }

    assert_equal [2048.0, 512.0, 10_000, 4000, 3, 2, [:out_spike]], row.values_at(*NET_KEYS, :net_flags)
    assert_equal [nil] * 6 + [[]], other.values_at(*NET_KEYS, :net_flags) # no entry: unknown
  end

  def test_unknown_network_leaves_rows_blank
    _, rows = session_rows(nil)

    refute_empty rows
    rows.each { |r| assert_equal [nil] * 6 + [[]], r.values_at(*NET_KEYS, :net_flags) }
  end

  def test_network_columns_only_on_a_view
    with_engine(prime(Fixtures.engine(machine(0), machine(2)))) do
      dashboard_app
      default = R2UI.registry.resource(:session).columns.map(&:key)

      assert_equal %i[label processes cpu footprint peak_footprint cpu_seconds bytes_written read_rate write_rate age],
                   default
      R2UI.reset!
      dashboard_app(view: :dense, focus: nil) # dense opens on Sessions; :process is a drill-down
      cols = R2UI.registry.resource(:session).columns.to_h { |c| [c.key, [c.label, c.format]] }

      assert_equal({ net_in_rate: ["Net in", :bytes_per_sec], net_out_rate: ["Net out", :bytes_per_sec],
                     bytes_in: ["Recv", :bytes], bytes_out: ["Sent", :bytes], connections: ["Conns", :integer],
                     remote_hosts: ["Hosts", :integer] }, cols.slice(*NET_KEYS))
    end
  end

  def test_age_formats
    age = Agentmon::UI::SessionsPanel.method(:age)

    assert_equal "45s", age.call(45)
    assert_equal "12m", age.call(12 * 60 + 30)
    assert_equal "3h 5m", age.call((3 * 3600) + 300)
    assert_equal "2d 4h", age.call((2 * 86_400) + (4 * 3600))
    assert_equal "", age.call(nil)
  end
end
