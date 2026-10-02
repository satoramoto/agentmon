# frozen_string_literal: true

require "test_helper"
require "json"

class FootprintCommandTest < Minitest::Test
  include Fixtures
  include R2UI::CLI::Testing

  GB = 1024 * MB

  VIEW = Agentmon::MemoryView.new(
    total: 16 * GB, used: 12 * GB, app: 8 * GB, wired: 2 * GB, compressed: 2 * GB, cached: 3 * GB,
    free: 1 * GB, swap_used: 512 * MB, swap_total: 2 * GB, compression_ratio: 3.1, swapin_rate: 0.0,
    swapout_rate: 0.0, compression_rate: 0.0, decompression_rate: 0.0, pressure: 42.0, pressure_trend: []
  )

  # An engine over `samples` whose `memory` metric returns `memory` (nil: unregistered) and, with
  # `rows`, whose `session_memory` returns them; otherwise the real session_memory runs.
  def engine_with(samples: [machine(0), machine(2)], memory: VIEW, rows: :real)
    replaced = [:memory, (:session_memory unless rows == :real)].compact
    registry = Agentmon::Registry.new
    Agentmon.registry.metrics.reject { |m| replaced.include?(m.name) }.each { |m| registry.add(:metric, m) }
    registry.add(:metric, Agentmon::Metric.new(name: :memory, block: ->(_r, _s) { memory })) if memory
    registry.add(:metric, Agentmon::Metric.new(name: :session_memory, block: ->(_r, _s) { rows })) unless rows == :real
    Agentmon::Engine.new(sampler: Sampler.new(*samples), registry:, prime_gap: 0)
  end

  def footprint(*argv, engine: engine_with, **shell)
    with_engine(engine) { run_cli(Agentmon::Program.build, "footprint", *argv, **shell) }
  end

  def lines(result) = result.out.lines.map(&:rstrip)

  def test_lists_sessions_largest_first_as_plain_columns
    result = footprint
    out = lines(result)

    assert result.success?, result.err
    assert_match(/\ASession\s+Processes\s+Footprint\s+Share\s+Resident\s+Wired\s+Peak\s+Growth\s+Pageins\/s\z/, out.first)
    # claude 200: 512M + 100M + 8M + 8M of 12G used; resident 600M + 3 x 10M; 1M wired; 10 pageins/s.
    assert_match(%r{\Aclaude 200 · repo\s+4\s+628M\s+5\.1%\s+630M\s+1\.0M\s+628M\s+\+0B/s\s+10\.0\z}, out[1])
    assert_match(%r{\AClaude 300\s+3\s+501M\s+4\.1%\s+30M\s+0B\s+501M\s+\+0B/s\s+0\.0\z}, out[2])
    assert_match(/\Aclaude 303 · web\s+1\s+150M/, out[3])
    assert_equal "", out[4]
    assert_equal "compressed 2.0G · swap 512M (per-process compressed/swap needs root)", out[5]
    assert_equal 6, out.size
    refute_includes result.out, "Finder"
    refute_includes result.out, "\e[" # plain in a pipe
  end

  def test_a_terminal_gets_a_boxed_table
    result = footprint(tty: true, width: 140)

    assert result.success?, result.err
    assert_includes result.out, "╭"
    assert_includes result.out, "claude 200 · repo"
  end

  def test_without_memory_share_is_blank_and_no_machine_line
    result = footprint(engine: engine_with(memory: nil))

    assert result.success?, result.err
    assert_match(%r{\Aclaude 200 · repo\s+4\s+628M\s+630M\s+1\.0M\s+628M}, lines(result)[1])
    refute_includes result.out, "compressed"
  end

  def test_json_prints_one_object_per_line_in_raw_units
    result = footprint("--json")
    records = result.out.lines.map { |l| JSON.parse(l) }

    assert result.success?, result.err
    assert_equal ["claude 200 · repo", "Claude 300", "claude 303 · web"], records.map { |r| r["label"] }
    claude = records.first
    assert_equal "claude-200-#{(T0 - 3600 + 200).to_i}", claude["session_id"]
    assert_equal 4, claude["processes"]
    assert_equal 628 * MB, claude["footprint"]
    assert_equal 630 * MB, claude["resident"]
    assert_equal 1 * MB, claude["wired"]
    assert_equal 20, claude["pageins"]
    assert_in_delta 10.0, claude["pagein_rate"]
    assert_in_delta 1000.0, claude["fault_rate"]
    assert_in_delta 628.0 * 100 / (12 * 1024), claude["share"]
    assert_in_delta 0.0, claude["growth_rate"]
  end

  def test_unknown_values_are_blank_in_the_table_and_null_in_json
    rows = [Fixtures.session_memory(session_id: "x", label: "codex 7", footprint: nil, resident: nil, share: nil,
                                    peak_footprint: 0, growth_rate: nil)]
    engine = -> { engine_with(rows:) }

    # Only processes, wired and peak known: the rest blank.
    assert_match(/\Acodex 7\s+1\s+0B\s+0B\z/, lines(footprint(engine: engine.call))[1])
    record = JSON.parse(footprint("--json", engine: engine.call).out)
    assert_nil record["footprint"]
    assert_nil record["share"]
  end

  def test_no_sessions_says_so_and_succeeds
    quiet = Fixtures.sample(0, processes: [process(pid: 400, name: "Finder")])

    result = footprint(engine: engine_with(samples: [quiet]))
    assert result.success?
    assert_equal "No agent sessions running.\n", result.out
    assert_equal "", footprint("--json", engine: engine_with(samples: [quiet])).out
  end

  def test_a_missing_metric_is_no_sessions_not_a_crash
    result = footprint(engine: engine_with(rows: nil))

    assert result.success?, result.err
    assert_equal "No agent sessions running.\n", result.out
  end

  def test_without_process_rows_the_sessions_are_still_listed
    registry = Agentmon::Registry.new
    Agentmon.registry.metrics.reject { |m| m.name == :process_rows }.each { |m| registry.add(:metric, m) }
    registry.add(:metric, Agentmon::Metric.new(name: :process_rows, block: ->(_r, _s) {}))
    result = footprint(engine: Agentmon::Engine.new(sampler: Sampler.new(machine(0), machine(2)), registry:, prime_gap: 0))

    assert result.success?, result.err
    refute_includes result.out, "No agent sessions running."
    assert_includes result.out, "claude 200 · repo"
  end
end
