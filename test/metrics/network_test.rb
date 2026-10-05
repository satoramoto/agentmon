# frozen_string_literal: true

require "test_helper"

# metrics/network.rb: net_rates, session_network and connections over the fixture machine with
# hand-built nettop snapshots. Sessions in the fixture machine: REPO (pids 200-203), APP (300-302)
# and WEB (303, a Claude Code CLI the app launched).
class NetworkMetricTest < Minitest::Test
  include Fixtures

  REPO = "claude-200-#{(T0 - 3600 + 200).to_i}".freeze
  APP = "Claude-300-#{(T0 - 3600 + 300).to_i}".freeze
  WEB = "claude-303-#{(T0 - 3600 + 303).to_i}".freeze
  KIB = 1024

  def flow(remote, bytes_in: 0, bytes_out: 0, protocol: "tcp4", local: "192.0.2.5:50000", state: "Established")
    host, port = Agentmon::Probes::Network.endpoint(remote, protocol)
    Agentmon::NetFlow.new(protocol:, local:, remote:, remote_host: host, remote_port: port, interface: "en0", state:,
                          bytes_in:, bytes_out:)
  end

  # A NetSnapshot at monotonic `at`: pid => [name, bytes_in, bytes_out, flows].
  def snap(at, procs)
    Agentmon::NetSnapshot.new(at_mono: at, processes: procs.to_h do |pid, (name, bytes_in, bytes_out, flows)|
      [pid, Agentmon::NetProcess.new(pid:, name:, bytes_in:, bytes_out:, flows: flows || [])]
    end)
  end

  # The fixture machine at `t` carrying `network` (nil: no snapshot), with process overrides.
  def at(t, network, **overrides)
    s = machine(t, **overrides)
    Agentmon::Sample.new(at: s.at, mono: s.mono, parts: s.parts.merge(network:))
  end

  # reading[name] after each sample, through one engine (metric state kept).
  def series(name, *samples)
    engine = Fixtures.engine(*samples)
    samples.map { engine.tick![name] }
  end

  def last(name, *samples) = series(name, *samples).last

  # --- net_rates ---

  def test_rates_between_snapshots_use_their_own_clock
    rates = last(:net_rates,
                 at(0, snap(1000.0, 200 => ["claude", 1000, 0], 400 => ["Finder", 0, 0])),
                 at(2, snap(1004.0, 200 => ["claude", 9000, 2000], 400 => ["Finder", 400, 0], 300 => ["Claude", 5, 5])))

    assert_in_delta 2000.0, rates[200].in_rate # 8000 bytes over the snapshots' 4 s, not the samples' 2
    assert_in_delta 500.0, rates[200].out_rate
    assert_in_delta 100.0, rates[400].in_rate
    assert_nil rates[300] # first sighting
    assert_equal Agentmon::NetRates.new(in_rate: 0.0, out_rate: 0.0), rates[201] # no sockets
  end

  def test_first_snapshot_has_no_rates_for_processes_with_sockets
    rates = last(:net_rates, at(0, snap(1000.0, 200 => ["claude", 1000, 0])))

    assert rates.key?(200)
    assert_nil rates[200]
    assert_in_delta 0.0, rates[201].in_rate
  end

  def test_a_reused_pid_or_a_renamed_process_has_no_rate
    rates = last(:net_rates,
                 at(0, snap(1000.0, 201 => ["node", 0, 0], 400 => ["Finder", 0, 0])),
                 at(2, snap(1002.0, 201 => ["node", 900, 900], 400 => ["curl", 900, 900]),
                    201 => { start_ticks: 999 }))

    assert_nil rates[201]
    assert_nil rates[400]
  end

  def test_a_counter_that_went_down_is_unknown
    rates = last(:net_rates,
                 at(0, snap(1000.0, 200 => ["claude", 5000, 100])),
                 at(2, snap(1002.0, 200 => ["claude", 10, 300])))

    assert_nil rates[200].in_rate
    assert_in_delta 100.0, rates[200].out_rate
  end

  def test_the_same_snapshot_again_keeps_the_previous_rates
    later = snap(1002.0, 200 => ["claude", 3000, 0])
    first, second, third = series(:net_rates, at(0, snap(1000.0, 200 => ["claude", 1000, 0])), at(2, later),
                                  at(4, later))

    assert_nil first[200]
    assert_in_delta 1000.0, second[200].in_rate
    assert_in_delta 1000.0, third[200].in_rate
  end

  def test_no_snapshot_means_every_network_metric_is_unknown
    reading = Fixtures.reading(at(0, nil))

    assert_nil reading[:net_rates]
    assert_nil reading[:session_network]
    assert_nil reading[:connections]
    assert_nil(reading[:process_rows].find { |r| r.pid == 200 }.net_in_rate)
  end

  def test_process_rows_carry_network_rates
    engine = Fixtures.engine(at(0, snap(1000.0, 200 => ["claude", 0, 0])),
                             at(2, snap(1002.0, 200 => ["claude", 4000, 2000])))
    engine.tick!
    rows = engine.tick![:process_rows].to_h { |r| [r.pid, r] }

    assert_in_delta 2000.0, rows[200].net_in_rate
    assert_in_delta 1000.0, rows[200].net_out_rate
    assert_in_delta 0.0, rows[201].net_in_rate
  end

  # --- session_network ---

  def test_session_rates_sum_members_once
    repo, app, web = last(:session_network,
                          at(0, snap(1000.0, 200 => ["claude", 0, 0], 201 => ["node", 0, 0], 301 => ["Claude Helper", 0, 0],
                                     303 => ["claude", 0, 0])),
                          at(2, snap(1002.0, 200 => ["claude", 2000, 200], 201 => ["node", 1000, 0],
                                     301 => ["Claude Helper", 4000, 0], 303 => ["claude", 8000, 0])))
      .sort_by { |s| [REPO, APP, WEB].index(s.session_id) }

    assert_equal [REPO, APP, WEB], [repo.session_id, app.session_id, web.session_id]
    assert_in_delta 1500.0, repo.in_rate # 200 + 201; 202 and 203 have no sockets (0.0)
    assert_in_delta 100.0, repo.out_rate
    assert_in_delta 2000.0, app.in_rate # 303 is its own session, not counted in the app's
    assert_in_delta 4000.0, web.in_rate
  end

  def test_a_session_whose_members_are_all_unknown_stays_nil
    web = last(:session_network, at(0, snap(1000.0, 303 => ["claude", 50, 50]))).find { |s| s.session_id == WEB }

    assert_nil web.in_rate
    assert_nil web.out_rate
    assert_empty web.in_trend
    assert_equal 0, web.bytes_in
  end

  def test_cumulative_bytes_count_growth_while_observed
    rows = series(:session_network,
                  at(0, snap(1000.0, 200 => ["claude", 1_000_000, 50])),
                  at(2, snap(1002.0, 200 => ["claude", 1_000_400, 150])),
                  at(4, snap(1004.0, 200 => ["claude", 10, 250])), # in counter went down: adds 0
                  at(6, snap(1006.0, 200 => ["claude", 110, 250])))
           .map { |list| list.find { |s| s.session_id == REPO } }

    assert_equal [0, 400, 400, 500], rows.map(&:bytes_in)
    assert_equal [0, 100, 200, 200], rows.map(&:bytes_out)
  end

  def test_trends_keep_known_rates_oldest_first
    samples = (0..3).map { |i| at(i * 2, snap(1000.0 + (i * 2), 200 => ["claude", i * 2000, 0])) }
    repo = last(:session_network, *samples).find { |s| s.session_id == REPO }

    assert_equal [0.0, 1000.0, 1000.0, 1000.0], repo.in_trend # the first is 0.0: 201-203 known, 200 not
    assert_predicate repo.in_trend, :frozen?
  end

  # out_rate per sample for pid 200 (bytes/s over 1 s snapshots): a session's history.
  def outs(*rates)
    total = 0
    samples = [at(0, snap(1000.0, 200 => ["claude", 0, 0]))]
    rates.each_with_index do |r, i|
      total += r
      samples << at((i + 1) * 2, snap(1001.0 + i, 200 => ["claude", 0, total.to_i]))
    end
    last(:session_network, *samples).find { |s| s.session_id == REPO }
  end

  def test_out_spike_against_the_median_baseline
    calm = [100 * KIB] * 6

    assert_equal [:out_spike], outs(*calm, 2 * 1024 * KIB).flags
    assert_empty outs(*calm, 700 * KIB).flags # under 8x the median
    assert_empty outs(*([10 * KIB] * 6), 900 * KIB).flags # 90x, but under 1 MiB/s
  end

  def test_no_spike_without_enough_baseline
    # The first sample's rate is 0.0 (members without sockets), then three known values: four < 5.
    assert_empty outs(100 * KIB, 100 * KIB, 100 * KIB, 4 * 1024 * KIB).flags
  end

  def test_many_remote_hosts
    flows = (1..20).map { |i| flow("198.51.100.#{i}:443") } +
            [flow("127.0.0.1:5000"), flow("fe80::1%en0.80", protocol: "tcp6"), flow("*:*", state: nil)]
    repo = last(:session_network, at(0, snap(1000.0, 200 => ["claude", 0, 0, flows]))).find { |s| s.session_id == REPO }

    assert_equal 22, repo.connections # every concrete remote, loopback included
    assert_equal 20, repo.remote_hosts
    assert_equal [:many_hosts], repo.flags
  end

  # --- connections ---

  def test_connections_of_agent_sessions_with_rates
    api = "203.0.113.10:443"
    first, second = series(:connections,
                           at(0, snap(1000.0, 200 => ["claude", 0, 0, [flow(api, bytes_in: 100, bytes_out: 10),
                                                                    flow("*:*", state: nil),
                                                                    flow("*:*", local: "127.0.0.1:80", state: "Listen")]],
                                      400 => ["Finder", 0, 0, [flow(api)]])),
                           at(2, snap(1002.0, 200 => ["claude", 0, 0, [flow(api, bytes_in: 300, bytes_out: 50)]])))

    assert_equal 1, first.size # Finder is in no session; wildcards and Listen are left out
    row = first.first

    assert_equal [200, "claude", REPO, "203.0.113.10", 443], [row.pid, row.name, row.session_id, row.remote_host, row.remote_port]
    assert_nil row.in_rate
    assert_in_delta 100.0, second.first.in_rate
    assert_in_delta 20.0, second.first.out_rate
  end

  # --- focus ---

  def test_focus_narrows_network_values
    engine = Fixtures.engine(at(0, snap(1000.0, 200 => ["claude", 0, 0, [flow("203.0.113.10:443")]],
                                        301 => ["Claude Helper", 0, 0, [flow("203.0.113.11:443")]])))
    engine.tick!
    engine.focus = APP
    focused = engine.current

    assert_equal [300, 301, 302], focused[:net_rates].keys.sort
    assert_equal [APP], focused[:session_network].map(&:session_id)
    assert_equal [301], focused[:connections].map(&:pid)
  end
end
