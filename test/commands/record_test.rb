# frozen_string_literal: true

require "test_helper"

class RecordCommandTest < Minitest::Test
  include Fixtures
  include R2UI::CLI::Testing

  def setup
    @dir = Dir.mktmpdir("agentmon-record")
  end

  def teardown
    FileUtils.rm_rf(@dir)
  end

  # Every registered metric plus a `ticks` recorder that writes on every sample and, on its
  # `signal_at`th line, sends `signal` to this process (as ctrl+c or launchd would).
  def engine(signal: nil, signal_at: 3, metrics: true)
    registry = Agentmon::Registry.new
    Agentmon.registry.metrics.each { |m| registry.add(:metric, m) } if metrics
    registry.add(:recorder, Agentmon::Recorder.new(name: :ticks, every: 0, block: lambda { |_reading, state|
      state[:n] = (state[:n] || 0) + 1
      Process.kill(signal, Process.pid) if signal && state[:n] == signal_at
      { n: state[:n] }
    }))
    Agentmon::Engine.new(sampler: Sampler.new(machine(0), machine(2)), registry:, prime_gap: 0,
                         store: Agentmon::Store.new(dir: @dir))
  end

  def record(engine, *argv, **shell)
    with_engine(engine) { run_cli(Agentmon::Program.build, "record", "--interval", "0.01", *argv, **shell) }
  end

  def ticks = Agentmon::Store.new(dir: @dir).each(:ticks).to_a

  def test_term_stops_with_0_and_every_line_is_in_the_store
    engine = engine(signal: "TERM")
    result = record(engine)

    assert_equal 0, result.code, result.err
    assert_operator ticks.size, :>=, 3
    assert_equal (1..ticks.size).to_a, ticks.map { |t| t[:n] } # read back by a fresh Store: flushed
    assert_equal [engine.run_id], ticks.map { |t| t[:run] }.uniq
    assert_match(/^recording 3 sessions to #{Regexp.escape(@dir)}$/, result.out)
    refute engine.recording, "recording is switched back off"
  end

  def test_ctrl_c_stops_with_130_and_the_store_flushed
    result = record(engine(signal: "INT"))

    assert_equal 130, result.code, result.err
    assert_operator ticks.size, :>=, 3
  end

  def test_signal_handlers_are_restored
    before = Signal.trap("TERM", "DEFAULT")
    Signal.trap("TERM", before)
    record(engine(signal: "TERM"))
    after = Signal.trap("TERM", before)

    assert_equal before, after
  end

  def test_prune_deletes_old_day_files_at_start
    old = File.join(@dir, "sessions", "2020-01-01.jsonl")
    recent = File.join(@dir, "sessions", "#{Time.at(Time.now.to_f - (3 * 86_400)).strftime("%Y-%m-%d")}.jsonl")
    FileUtils.mkdir_p(File.dirname(old))
    [old, recent].each { |p| File.write(p, "{\"t\":1}\n") }

    result = record(engine(signal: "TERM", signal_at: 1), "--prune", "14")

    assert_equal 0, result.code, result.err
    refute_path_exists old
    assert_path_exists recent
    assert_includes result.out, "pruned 1 day file"
  end

  def test_bad_interval_or_prune_is_a_usage_error
    assert_equal 2, record(engine, "--interval", "0").code
    assert_equal 2, record(engine, "--prune", "0").code
    assert_equal 2, record(engine, "--interval", "soon").code
  end

  def test_an_engine_without_a_store_is_an_error
    engine = Agentmon::Engine.new(sampler: Sampler.new(machine(0)), registry: Agentmon::Registry.new, prime_gap: 0)
    result = record(engine)

    assert_equal 1, result.code
    assert_includes result.err, "no store"
  end

  # An engine over a hand-moved clock: each sample is `step` seconds later, and the stop flag is
  # raised after `samples` samples.
  class StepEngine
    attr_accessor :recording
    attr_reader :store, :calls

    def initialize(inner, clock:, stop:, step:, samples:)
      @inner = inner
      @store = inner.store
      @clock = clock
      @stop = stop
      @step = step
      @samples = samples
      @calls = 0
    end

    def current(max_age:)
      raise "every tick samples" unless max_age.zero?

      @clock.advance(@step) if @calls.positive?
      @calls += 1
      @stop.request("TERM") if @calls == @samples
      @inner.recording = recording
      @inner.current(max_age:)
    end
  end

  def run_record(samples:, step:, tty: false, metrics: true)
    stop = Agentmon::Commands::Record::Stop.new
    clock = Fixtures::Clock.new
    stepper = StepEngine.new(engine(metrics:), clock:, stop:, step:, samples:)
    shell = test_shell(tty:, width: 300) # the live line is cut at the width; temp dirs are long
    Agentmon::Commands::Record.run(stepper, shell:, interval: 0.001, stop:, clock:)
    [stepper, shell.output.string]
  ensure
    stop&.close
  end

  def test_off_a_terminal_one_status_line_per_minute
    stepper, out = run_record(samples: 8, step: 20) # 0, 20, ..., 140 s

    assert_equal 8, stepper.calls
    assert_equal 3, out.lines.grep(/^recording 3 sessions to /).size # at 0, 60 and 120 s
    refute_includes out, "\e["
  end

  def test_on_a_terminal_a_live_line_and_the_cursor_restored
    _, out = run_record(samples: 3, step: 1, tty: true)

    assert_includes out, "recording 3 sessions to #{@dir}"
    assert out.end_with?(R2UI::CLI::Live::SHOW_CURSOR), "cursor shown again"
  end

  def test_without_the_session_ledger_the_status_has_no_count
    _, out = run_record(samples: 1, step: 1, metrics: false)

    assert_includes out, "recording to #{@dir}"
  end
end
