# frozen_string_literal: true

require "test_helper"

class SessionsRecorderTest < Minitest::Test
  include Fixtures

  def setup
    @dir = Dir.mktmpdir
    @clock = Clock.new
    @store = Agentmon::Store.new(dir: @dir, clock: @clock)
  end

  def teardown = FileUtils.rm_rf(@dir)

  # The fixture machine at t, without claude 303 (its session ended) when `ended`. disclaimer 302
  # reaps it, so its child time grows by 303's 5 s.
  def machine_at(t, ended: false)
    sample = machine(t, 302 => ended ? { child_cpu_time: 5.0 } : {})
    return sample unless ended

    Fixtures.sample(t, processes: sample.parts[:processes].reject { |p| p.pid == 303 }, cwd: sample.parts[:cwd])
  end

  # A recording engine over `samples`, ticked once per sample, its clock moving with them. Returns
  # the engine and its last reading.
  def record(samples, registry: Agentmon.registry, store: @store, clock: @clock)
    engine = Agentmon::Engine.new(sampler: Sampler.new(*samples), registry:, store:, recording: true, prime_gap: 0,
                                  clock:)
    reading = nil
    samples.each_with_index do |sample, i|
      clock.advance(sample.mono - samples[i - 1].mono) if i.positive?
      reading = engine.tick!
    end
    [engine, reading]
  end

  def lines = @store.each(:sessions).to_a

  def test_one_line_per_alive_session_every_ten_seconds
    engine, = record((0..12).step(2).map { |t| machine_at(t) }) # ticks at 0..12: recorded at 0 and 10

    assert_equal 6, lines.size
    assert_equal({ T0 => [200, 300, 303], T0 + 10 => [200, 300, 303] },
                 lines.group_by { |l| l[:t] }.transform_values { |group| group.map { |l| l[:root_pid] }.sort })
    assert(lines.all? { |l| l[:run] == engine.run_id && l[:ended_at].nil? })
    assert_empty engine.errors
  end

  def test_fields_and_units_round_trip
    _, reading = record([machine_at(0)])
    expected = reading[:session_ledger].map(&:to_record)

    assert_equal expected, lines.map { |l| l.except(:t, :run) }
    claude = lines.find { |l| l[:root_pid] == 200 }
    assert_equal "cli", claude[:kind]
    assert_kind_of Float, claude[:cpu_seconds]
    assert_in_delta 12.6, claude[:cpu_seconds] # seconds, not ticks
    assert_equal (512 + 100 + 8 + 8) * MB, claude[:peak_footprint] # bytes
    assert_kind_of Integer, claude[:bytes_written]
    assert_kind_of Float, claude[:started_at] # epoch seconds
  end

  def test_an_ended_session_gets_exactly_one_final_line
    samples = (0..30).step(2).map { |t| machine_at(t, ended: t >= 12) } # 303 ends at 12; records at 0, 10, 20, 30
    record(samples)

    mine = lines.select { |l| l[:root_pid] == 303 }
    assert_equal [T0, T0 + 10, T0 + 20], mine.map { |l| l[:t] }
    final = mine.last
    assert_in_delta T0 + 10, final[:ended_at] # last seen alive at 10
    assert_equal final[:last_seen_at], final[:ended_at]
    assert_in_delta 5.0, final[:cpu_seconds]
    assert_equal 0, final[:footprint]
    assert_equal 2, lines.count { |l| l[:t] == T0 + 30 } # the two alive sessions only
  end

  def test_each_engine_writes_its_own_final_line
    samples = [machine_at(0), machine_at(10, ended: true)]
    record(samples)
    record(samples, clock: Clock.new(now: T0 + 1)) # a later start: another run id

    finals = lines.select { |l| l[:root_pid] == 303 && l[:ended_at] }
    assert_equal 2, finals.size
    refute_equal finals.first[:run], finals.last[:run]
  end

  def test_nothing_is_recorded_without_a_session_ledger
    registry = Agentmon::Registry.new
    registry.add(:recorder, Agentmon.registry[:recorder, :sessions])
    engine, = record([machine_at(0)], registry:)

    assert_empty lines
    assert_empty engine.errors
  end
end
