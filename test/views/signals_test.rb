# frozen_string_literal: true

require "test_helper"
require "agentmon/views/signals"

class SignalsViewTest < Minitest::Test
  Signals = Agentmon::Views::Signals
  Signal = Agentmon::Views::Signal
  MB = Fixtures::MB
  GB = 1024 * MB

  def system_view(**overrides)
    Agentmon::SystemView.new(
      cpu: 42.0, user: 30.0, system: 12.0, ncpu: 4, load1: 1.5, load5: 1.2, load15: 1.0,
      net_in_rate: 1000.0, net_out_rate: 500.0, disk_read_rate: 2.0 * MB, disk_write_rate: 1.0 * MB,
      cpu_trend: [40.0, 42.0], net_in_trend: [900.0, 1000.0], net_out_trend: [], disk_trend: [3.0 * MB],
      **overrides
    )
  end

  def memory_view(**overrides)
    Agentmon::MemoryView.new(
      total: 32 * GB, used: 24 * GB, app: 12 * GB, wired: 4 * GB, compressed: 2 * GB, cached: 6 * GB,
      free: 2 * GB, swap_used: 1 * GB, swap_total: 4 * GB, compression_ratio: 3.1,
      swapin_rate: 0.0, swapout_rate: 10.0, compression_rate: 0.0, decompression_rate: 0.0,
      pressure: 25.0, pressure_trend: [20.0, 25.0], **overrides
    )
  end

  def session(id, cpu:, processes: 2, read_rate: 100.0, write_rate: 50.0, ended_at: nil, label: id)
    Agentmon::Session.new(
      id:, kind: :cli, name: "claude", root_pid: 200, label:, cwd: "/", started_at: Fixtures::T0,
      first_seen_at: Fixtures::T0, last_seen_at: Fixtures::T0, ended_at:, processes:, cpu:,
      footprint: 100 * MB, resident: 100 * MB, read_rate:, write_rate:, peak_footprint: 100 * MB,
      cpu_seconds: 1.0, bytes_read: 0, bytes_written: 0
    )
  end

  def reading(**values)
    Fixtures.reading(Fixtures.machine(0), values:)
  end

  def full_reading
    reading(
      system: system_view, memory: memory_view,
      session_ledger: [session("a", cpu: 100.0, label: "repo"), session("b", cpu: 60.0, processes: 3),
                       session("gone", cpu: 0.0, ended_at: Fixtures::T0)],
      session_memory: [Fixtures.session_memory(session_id: "a", label: "repo", footprint: 300 * MB, wired: MB,
                                               growth_rate: 1000.0, pagein_rate: 2.0),
                       Fixtures.session_memory(session_id: "b", footprint: 100 * MB, growth_rate: -200.0)]
    )
  end

  # Parsing

  def test_parse_splits_metric_and_member
    signal = Signals.parse("system.cpu")

    assert_instance_of Signal, signal
    assert_equal "system.cpu", signal.name
    assert_equal :system, signal.metric
    assert_equal :cpu, signal.member
  end

  def test_parse_rejects_bad_names
    ["cpu", "a.b.c", "System.cpu", "system.", ".cpu", "system.cpu-x", "", "1x.cpu"].each do |bad|
      error = assert_raises(ArgumentError) { Signals.parse(bad) }

      assert_includes error.message, bad.inspect
    end
  end

  # Defaults

  def test_defaults
    cpu = Signals.parse("system.cpu")

    assert_equal ["CPU", :percent, 100, nil], [cpu.label, cpu.unit, cpu.max, cpu.of]
    used = Signals.parse("memory.used")

    assert_equal ["used", :bytes, nil, "memory.total"], [used.label, used.unit, used.max, used.of]
    assert_equal "memory.swap_total", Signals.parse("memory.swap_used").of
    assert_equal [:ratio, "ratio"], [Signals.parse("memory.compression_ratio").unit,
                                     Signals.parse("memory.compression_ratio").label]
    assert_equal ["load 1m", :number], [Signals.parse("system.load1").label, Signals.parse("system.load1").unit]
    assert_equal ["net in", :bytes_per_sec], [Signals.parse("system.net_in_rate").label,
                                              Signals.parse("system.net_in_rate").unit]
    assert_equal ["growth", :signed_bytes_per_sec], [Signals.parse("focus.growth_rate").label,
                                                     Signals.parse("focus.growth_rate").unit]
    assert_equal :per_sec, Signals.parse("focus.pagein_rate").unit
    assert_equal ["procs", :integer], [Signals.parse("focus.processes").label, Signals.parse("focus.processes").unit]
    assert_equal "memory.used", Signals.parse("focus.footprint").of
    assert_predicate Signals::DEFAULTS, :frozen?
  end

  # Inference

  def test_inference_rules
    {
      "pagein_rate" => ["pagein", :per_sec, nil],
      "fault_rate" => ["fault", :per_sec, nil],
      "cow_fault_rate" => ["cow fault", :per_sec, nil],
      "context_switch_rate" => ["context switch", :per_sec, nil],
      "read_rate" => ["read", :bytes_per_sec, nil],
      "cpu" => ["cpu", :percent, 100],
      "share" => ["share", :percent, 100],
      "run_wait" => ["run wait", :percent, 100],
      "idle_pct" => ["idle pct", :percent, 100],
      "busy_percent" => ["busy percent", :percent, 100],
      "load_avg" => ["load avg", :number, nil],
      "threads" => ["threads", :integer, nil],
      "open_count" => ["open count", :integer, nil],
      "hit_ratio" => ["hit ratio", :ratio, nil],
      "footprint" => ["footprint", :bytes, nil]
    }.each do |member, (label, unit, max)|
      assert_equal({ label:, unit:, max: }, Signals.infer(member), member)
    end
    signal = Signals.parse("process.fault_rate")

    assert_equal ["fault", :per_sec, nil, nil], [signal.label, signal.unit, signal.max, signal.of]
  end

  def test_overrides_win
    signal = Signals.parse("memory.used", label: "RAM", unit: :percent, max: 50, of: "memory.app")

    assert_equal ["RAM", :percent, 50, "memory.app"], [signal.label, signal.unit, signal.max, signal.of]
    assert_equal "used", Signals.parse("memory.used", label: nil).label
  end

  # Values

  def test_value_reads_data_and_hash_members
    r = full_reading

    assert_in_delta 42.0, Signals.value(Signals.parse("system.cpu"), r)
    assert_equal 24 * GB, Signals.value(Signals.parse("memory.used"), r)
    assert_equal 3, Signals.read({ "n" => 3 }, :n)
    assert_equal 3, Signals.read({ n: 3 }, "n")
    assert_nil Signals.read({ n: "3" }, :n)
    assert_nil Signals.read(memory_view, :pressure_trend)
    assert_nil Signals.read(memory_view, :nope)
  end

  def test_unknown_stays_nil
    r = reading(memory: memory_view(used: nil))
    used = Signals.parse("memory.used")

    assert_nil Signals.value(used, r)
    assert_nil Signals.fraction(used, r)
    assert_nil Signals.format(Signals.value(used, r), used.unit)
    missing = Signals.parse("nosuch.cpu")

    assert_nil Signals.value(missing, r)
    assert_nil Signals.fraction(missing, r)
    assert_nil Signals.metric_value(nil, :system)
  end

  def test_metric_value_is_nil_when_the_reading_raises
    broken = Object.new
    def broken.[](_) = raise("boom")

    assert_nil Signals.metric_value(broken, :system)
  end

  def test_fraction_uses_of_then_max
    r = full_reading

    assert_in_delta 0.75, Signals.fraction(Signals.parse("memory.used"), r)
    assert_in_delta 0.25, Signals.fraction(Signals.parse("memory.swap_used"), r)
    assert_in_delta 0.42, Signals.fraction(Signals.parse("system.cpu"), r)
    assert_nil Signals.fraction(Signals.parse("memory.app"), r) # no scale
    assert_in_delta 0.5, Signals.fraction(Signals.parse("memory.app", max: 24 * GB), r)
    assert_in_delta 1.0, Signals.fraction(Signals.parse("memory.used", of: "memory.app"), r) # clamped
    assert_equal 32 * GB, Signals.total(Signals.parse("memory.used"), r)
    assert_nil Signals.total(Signals.parse("system.cpu"), r)
    # An unknown total falls back to max (none here), so the fraction is unknown.
    assert_nil Signals.fraction(Signals.parse("memory.used"), reading(memory: memory_view(total: nil)))
  end

  def test_trend_lookup
    r = full_reading

    assert_equal [40.0, 42.0], Signals.trend(Signals.parse("system.cpu"), r)
    assert_equal [900.0, 1000.0], Signals.trend(Signals.parse("system.net_in_rate"), r)
    assert_equal [20.0, 25.0], Signals.trend(Signals.parse("memory.pressure"), r)
    assert_nil Signals.trend(Signals.parse("system.disk_read_rate"), r)
    assert_nil Signals.trend(Signals.parse("memory.used"), r)
    assert_nil Signals.trend(Signals.parse("system.cpu"), reading(system: nil))
  end

  # Formats

  def test_formats_for_every_unit
    assert_equal "42.0%", Signals.format(42.0, :percent)
    assert_equal "1.5G", Signals.format(1.5 * GB, :bytes)
    assert_equal "3.2M/s", Signals.format(3.2 * MB, :bytes_per_sec)
    assert_equal "1.5", Signals.format(1.52, :number)
    assert_equal "10", Signals.format(9.6, :integer)
    assert_equal "2.0x", Signals.format(2.0, :ratio)
    assert_equal "12/s", Signals.format(12.4, :per_sec)
    assert_equal "2.5/s", Signals.format(2.5, :per_sec)
    assert_equal "0/s", Signals.format(0.0, :per_sec)
    assert_equal "+1.5M/s", Signals.format(1.5 * MB, :signed_bytes_per_sec)
    assert_equal "-200K/s", Signals.format(-200.0 * 1024, :signed_bytes_per_sec)
    assert_equal "0B/s", Signals.format(0.0, :signed_bytes_per_sec)
    assert_nil Signals.format(nil, :bytes)
  end

  # Focus

  def test_focus_aggregates_every_alive_session
    focus = Signals::Focus.value(full_reading)

    assert_in_delta 40.0, focus[:cpu] # (100 + 60) % of one core over 4 cores
    assert_equal 5, focus[:processes] # the ended session is not counted
    assert_in_delta 200.0, focus[:read_rate]
    assert_in_delta 100.0, focus[:write_rate]
    assert_equal 400 * MB, focus[:footprint]
    assert_equal MB, focus[:wired]
    assert_in_delta 800.0, focus[:growth_rate]
    assert_in_delta 2.0, focus[:pagein_rate] # nil members are skipped
    assert_equal "all agents", focus[:label]
    refute focus[:focused]
    assert_in_delta 40.0, Signals.value(Signals.parse("focus.cpu"), full_reading)
    assert_in_delta 0.4, Signals.fraction(Signals.parse("focus.cpu"), full_reading)
  end

  def test_focus_narrows_to_the_focused_session
    focused = Agentmon::FocusedReading.new(full_reading, "a")
    focus = Signals::Focus.value(focused)

    assert_in_delta 25.0, focus[:cpu]
    assert_equal 2, focus[:processes]
    assert_equal 300 * MB, focus[:footprint]
    assert_equal "repo", focus[:label]
    assert focus[:focused]
    assert_in_delta 300.0 / (24 * 1024), Signals.fraction(Signals.parse("focus.footprint"), focused)
  end

  def test_focus_unknowns_and_empties
    empty = Signals::Focus.value(reading(system: system_view, session_ledger: [], session_memory: []))

    assert_in_delta 0.0, empty[:cpu]
    assert_equal 0, empty[:processes]
    assert_equal 0, empty[:footprint]
    unknown = Signals::Focus.value(reading(system: nil, session_ledger: [session("a", cpu: 10.0)],
                                           session_memory: nil))

    assert_nil unknown[:cpu] # no ncpu
    assert_equal 2, unknown[:processes]
    assert_nil unknown[:footprint] # no session memory
    no_pageins = Signals::Focus.value(reading(session_memory: [Fixtures.session_memory(session_id: "a")]))

    assert_nil no_pageins[:pagein_rate]
    assert_nil Signals::Focus.value(reading(session_ledger: nil))[:processes]
  end
end
