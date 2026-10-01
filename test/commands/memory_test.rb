# frozen_string_literal: true

require "test_helper"
require "json"

class MemoryCommandTest < Minitest::Test
  include Fixtures
  include R2UI::CLI::Testing

  GB = 1024**3

  # An engine whose reading carries preset `memory` and `pressure_drivers` values (stories a02
  # and a03 produce them; this one only consumes their shapes).
  class PresetEngine
    def initialize(values) = @reading = Fixtures.reading(Fixtures.machine(0), values:)

    def current(**) = @reading

    def errors = {}
  end

  def view(**overrides)
    Agentmon::MemoryView.new(
      total: 16 * GB, used: 12 * GB, app: 8 * GB, wired: 2 * GB, compressed: 2 * GB, cached: 3 * GB, free: 1 * GB,
      swap_used: 1 * GB, swap_total: 2 * GB, compression_ratio: 3.1,
      swapin_rate: 1024.0, swapout_rate: 0.0, compression_rate: 2.0 * MB, decompression_rate: 512.0 * 1024,
      pressure: 35.0, pressure_trend: [30.0, 35.0], **overrides
    )
  end

  def driver(label, footprint, share, growth)
    Agentmon::PressureDriver.new(session_id: label.tr(" ·", "-"), label:, footprint:, share:, growth_rate: growth)
  end

  def drivers
    [driver("claude 200 · repo", 512 * MB, 4.2, 1.0 * MB), driver("claude 303 · web", 150 * MB, nil, -2048.0),
     *(1..4).map { |i| driver("codex #{i}", (10 - i) * MB, 0.1, 0.0) }]
  end

  def memory(*argv, values: { memory: view, pressure_drivers: drivers })
    with_engine(PresetEngine.new(values)) { run_cli(Agentmon::Program.build, "memory", *argv) }
  end

  def test_prints_the_breakdown_as_aligned_pairs_in_binary_units
    result = memory
    lines = result.out.lines.map(&:rstrip)

    assert result.success?, result.err
    assert_equal "Memory", lines.first
    {
      "Total" => "16G", "Used" => "12G", "App" => "8.0G", "Wired" => "2.0G", "Compressed" => "2.0G (3.1x)",
      "Cached" => "3.0G", "Swap" => "1.0G / 2.0G", "Swap in" => "1.0K/s", "Swap out" => "0B/s",
      "Compression" => "2.0M/s", "Decompression" => "512K/s", "Pressure" => "35.0%"
    }.each { |key, value| assert_includes lines, "  #{key.ljust(13)}  #{value}" }
    refute_includes result.out, "\e[" # plain in a pipe
  end

  def test_then_the_top_pressure_drivers_in_their_order
    lines = memory.out.lines.map(&:rstrip)
    start = lines.index("Pressure drivers")

    refute_nil start
    assert_match(/\ASession\s+Footprint\s+Share\s+Growth\z/, lines[start + 1])
    assert_match(/\Aclaude 200 · repo\s+512M\s+4\.2%\s+\+1\.0M\/s\z/, lines[start + 2])
    assert_match(/\Aclaude 303 · web\s+150M\s+-2\.0K\/s\z/, lines[start + 3]) # unknown share is blank
    assert_match(/\Acodex 3\s+7\.0M\s+0\.1%\s+0B\/s\z/, lines.last)
    assert_equal Agentmon::Commands::MemoryReport::DRIVERS, lines.size - start - 2
  end

  def test_json_prints_the_raw_values
    result = memory("--json")
    data = JSON.parse(result.out)

    assert result.success?, result.err
    assert_equal 16 * GB, data["memory"]["total"]
    assert_in_delta 3.1, data["memory"]["compression_ratio"]
    assert_equal [30.0, 35.0], data["memory"]["pressure_trend"]
    assert_equal 6, data["pressure_drivers"].size
    assert_equal({ "session_id" => "claude-200---repo", "label" => "claude 200 · repo", "footprint" => 512 * MB,
                   "share" => 4.2, "growth_rate" => 1.0 * MB }, data["pressure_drivers"].first)
  end

  def test_unknown_values_show_a_dash
    lines = memory(values: { memory: view(compression_ratio: nil, swap_total: nil, pressure: nil) }).out.lines.map(&:rstrip)

    assert_includes lines, "  Compressed     2.0G"
    assert_includes lines, "  Swap           1.0G / —"
    assert_includes lines, "  Pressure       —"
  end

  def test_without_pressure_drivers_only_the_breakdown_prints
    result = memory(values: { memory: view })

    assert result.success?, result.err
    assert_includes result.out, "Total"
    refute_includes result.out, "Pressure drivers"
  end

  def test_no_sessions_says_so
    assert_includes memory(values: { memory: view, pressure_drivers: [] }).out, "No agent sessions are using memory."
  end

  def test_without_memory_it_fails_with_a_reason_on_stderr
    result = memory(values: {})

    assert_equal 1, result.code
    assert_empty result.out
    assert_includes result.err, "Memory isn't available"
  end

  def test_json_without_memory_fails_too
    result = memory("--json", values: {})

    assert_equal 1, result.code
    assert_empty result.out
  end

  def test_a_broken_memory_metric_is_reported_on_stderr
    registry = Agentmon::Registry.new
    Agentmon.registry.metrics.reject { |m| %i[memory pressure_drivers].include?(m.name) }.each { |m| registry.add(:metric, m) }
    registry.add(:metric, Agentmon::Metric.new(name: :memory, block: ->(_r, _s) { raise "no vm stats" }))
    engine = Agentmon::Engine.new(sampler: Sampler.new(machine(0), machine(2)), registry:, prime_gap: 0)
    result = with_engine(engine) { run_cli(Agentmon::Program.build, "memory") }

    assert_equal 1, result.code
    assert_includes result.err, "metric memory: RuntimeError: no vm stats"
  end
end
