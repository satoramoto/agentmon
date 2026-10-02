# frozen_string_literal: true

require "test_helper"

class SessionMemoryMetricTest < Minitest::Test
  include Fixtures

  GB = 1024 * MB

  # A Session as the ledger reports it; only what session_memory reads matters.
  def session(id, ended_at: nil, peak_footprint: 0)
    Agentmon::Session.new(
      id:, kind: :cli, name: "claude", root_pid: 1, label: "claude #{id}", cwd: nil, started_at: T0,
      first_seen_at: T0, last_seen_at: T0, ended_at:, processes: 1, cpu: 0.0, footprint: 0, resident: 0,
      read_rate: 0.0, write_rate: 0.0, peak_footprint:, cpu_seconds: 0.0, bytes_read: 0, bytes_written: 0
    )
  end

  # A ProcessRow in session `id`; only the memory fields matter.
  def row(pid, id, footprint: 10 * MB, resident: nil, wired: 0, pageins: 0, pagein_rate: nil, fault_rate: nil)
    Agentmon::ProcessRow.new(
      pid:, ppid: 1, name: "p#{pid}", path: "/bin/p", cwd: nil, session: id && "claude #{id}", session_id: id,
      cpu: 0.0, footprint:, resident: resident || footprint, peak_footprint: footprint, read_rate: nil,
      write_rate: nil, cpu_time: nil, disk_written: nil, started_at: nil, readable: !footprint.nil?,
      wired:, pageins:, pagein_rate:, fault_rate:
    )
  end

  def memory(used:)
    Agentmon::MemoryView.new(
      total: 16 * GB, used:, app: used, wired: 0, compressed: 0, cached: 0, free: 0, swap_used: 0, swap_total: 0,
      compression_ratio: 0.0, swapin_rate: 0.0, swapout_rate: 0.0, compression_rate: 0.0,
      decompression_rate: 0.0, pressure: 20.0, pressure_trend: []
    )
  end

  # Readings at the given times (seconds after T0) sharing one metric state, as the Engine's are;
  # each step is [t, ledger, rows, memory]. Returns the last reading's session_memory.
  def memories(*steps)
    states = Hash.new { |h, k| h[k] = {} }
    previous = nil
    result = nil
    steps.each do |t, ledger, rows, mem|
      sample = Fixtures.sample(t, processes: [])
      values = { session_ledger: ledger, process_rows: rows, memory: mem }
      result = Agentmon::Reading.new(sample, previous:, states:, values:)[:session_memory]
      previous = sample
    end
    result
  end

  # One session "a" whose footprint is `footprint` at time t.
  def step(t, footprint) = [t, [session("a")], [row(1, "a", footprint:)], nil]

  def test_sums_each_sessions_members_largest_footprint_first
    ledger = [session("a", peak_footprint: 3 * GB), session("b")]
    rows = [row(1, "a", footprint: 100 * MB, resident: 120 * MB, wired: 1 * MB, pageins: 5, pagein_rate: 2.0,
                fault_rate: 100.0),
            row(2, "a", footprint: 50 * MB, resident: 60 * MB, wired: 2 * MB, pageins: 7, pagein_rate: 3.0,
                fault_rate: 50.0),
            row(3, "b", footprint: 500 * MB), row(4, nil, footprint: 1 * GB)]

    list = memories([0, ledger, rows, memory(used: 1 * GB)])
    assert_equal %w[b a], list.map(&:session_id)
    a = list.last
    assert_kind_of Agentmon::SessionMemory, a
    assert_equal "claude a", a.label
    assert_equal 2, a.processes
    assert_equal 150 * MB, a.footprint
    assert_equal 180 * MB, a.resident
    assert_equal 3 * MB, a.wired
    assert_equal 12, a.pageins
    assert_in_delta 5.0, a.pagein_rate
    assert_in_delta 150.0, a.fault_rate
    assert_equal 3 * GB, a.peak_footprint # the ledger's, not recomputed
    assert_in_delta 150.0 * 100 / 1024, a.share
  end

  def test_a_pid_listed_twice_counts_once
    rows = [row(1, "a", footprint: 100 * MB), row(1, "a", footprint: 100 * MB)]

    a = memories([0, [session("a")], rows, nil]).first
    assert_equal 100 * MB, a.footprint
    assert_equal 1, a.processes
  end

  def test_unknown_members_are_skipped_and_all_unknown_is_nil
    rows = [row(1, "a", footprint: nil, resident: 20 * MB, wired: nil, pageins: nil),
            row(2, "a", footprint: 30 * MB, wired: nil, pageins: nil), row(3, "b", footprint: nil, wired: nil, pageins: nil)]

    list = memories([0, [session("a"), session("b")], rows, memory(used: 1 * GB)]).to_h { |m| [m.session_id, m] }
    assert_equal 30 * MB, list["a"].footprint
    assert_equal 50 * MB, list["a"].resident # ps's resident of the unreadable one still counts
    assert_nil list["a"].wired
    assert_nil list["a"].pagein_rate # before two samples
    assert_nil list["b"].footprint
    assert_nil list["b"].share
    assert_equal %w[a b], list.keys # an unknown footprint sorts last
  end

  def test_a_session_without_rows_has_nil_sums
    m = memories([0, [session("a")], [row(1, "b")], nil]).first

    assert_equal 0, m.processes
    assert_nil m.footprint
    assert_nil m.resident
  end

  def test_without_process_rows_it_is_not_available
    assert_nil memories([0, [session("a")], nil, nil])
    assert_equal [], memories([0, [], nil, nil])
  end

  def test_share_is_nil_while_memory_is_unknown
    assert_nil memories(step(0, 1 * GB)).first.share
  end

  def test_ended_sessions_are_left_out_and_no_ledger_is_empty
    ledger = [session("a"), session("gone", ended_at: T0)]

    assert_equal %w[a], memories([0, ledger, [row(1, "a")], nil]).map(&:session_id)
    assert_equal [], memories([0, nil, [row(1, "a")], memory(used: 1 * GB)])
  end

  def test_growth_is_zero_until_two_samples
    assert_in_delta 0.0, memories(step(0, 1 * GB)).first.growth_rate
  end

  def test_growth_rate_is_bytes_per_second_over_the_samples_seen
    assert_in_delta 5.0 * MB, memories(step(0, 100 * MB), step(2, 110 * MB), step(4, 120 * MB)).first.growth_rate
  end

  def test_growth_rate_covers_only_the_last_minute
    # Flat for a minute, then +60 MB in the last 30 s: the window is t = 30..90.
    steps = (0..60).step(10).map { |t| step(t, 100 * MB) } + [step(90, 160 * MB)]

    assert_in_delta 1.0 * MB, memories(*steps).first.growth_rate
  end

  def test_shrinking_footprint_has_negative_growth
    assert_in_delta(-10.0 * MB, memories(step(0, 200 * MB), step(10, 100 * MB)).first.growth_rate)
  end

  def test_a_session_that_ends_forgets_its_history
    ended = [5, [session("a", ended_at: T0 + 5)], [], nil]

    assert_in_delta 0.0, memories(step(0, 100 * MB), ended, step(20, 300 * MB)).first.growth_rate
  end

  def test_on_the_engine_each_process_of_a_tree_counts_once
    engine = Fixtures.engine(machine(0), machine(2))
    engine.tick!
    reading = engine.tick!

    assert_empty reading.errors
    list = reading[:session_memory]
    assert_equal ["claude 200 · repo", "Claude 300", "claude 303 · web"], list.map(&:label)
    claude = list.first
    # 200 claude, 201 node, 202 zsh, 203 git: 512M + 100M + 8M + 8M; 303 under the app is its own session.
    assert_equal 4, claude.processes
    assert_equal 628 * MB, claude.footprint
    assert_equal 630 * MB, claude.resident
    assert_equal 1 * MB, claude.wired
    assert_equal 20, claude.pageins
    assert_in_delta 10.0, claude.pagein_rate
    assert_in_delta 1000.0, claude.fault_rate
    assert_equal 501 * MB, list[1].footprint # Claude 300, 301 helper, 302 disclaimer
    assert_equal 150 * MB, list[2].footprint
    assert_nil claude.share # no memory metric value on fixture samples
  end

  def test_focus_narrows_it_to_one_session
    engine = Fixtures.engine(machine(0), machine(2))
    engine.tick!
    id = engine.tick![:session_memory].last.session_id
    engine.focus = id

    assert_equal [id], engine.current(max_age: Float::INFINITY)[:session_memory].map(&:session_id)
  end
end
