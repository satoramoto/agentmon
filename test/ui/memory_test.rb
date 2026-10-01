# frozen_string_literal: true

require "test_helper"

# The Memory panel (story a04) on preset `memory` and `pressure_drivers` values, drawn through
# r2ui as a user sees it.
class MemoryPanelTest < Minitest::Test
  include Fixtures

  GB = 1024 * MB
  KB = 1024

  VIEW = Agentmon::MemoryView.new(
    total: 16 * GB, used: 12 * GB, app: 8 * GB, wired: 2 * GB, compressed: 2 * GB, cached: 3 * GB,
    free: 1 * GB, swap_used: 512 * MB, swap_total: 2 * GB, compression_ratio: 3.1,
    swapin_rate: 1.0 * MB, swapout_rate: 256.0 * KB, compression_rate: 4.0 * MB, decompression_rate: 3.0 * MB,
    pressure: 42.0, pressure_trend: [10.0, 20.0, 30.0, 42.0]
  )

  DRIVERS = [
    Agentmon::PressureDriver.new(session_id: "claude-200-1", label: "claude 200 · repo", footprint: 1536 * MB,
                                 share: 12.5, growth_rate: 2.0 * MB),
    Agentmon::PressureDriver.new(session_id: "Claude-300-1", label: "Claude 300", footprint: 1 * GB, share: 8.3,
                                 growth_rate: -512.0 * KB),
    Agentmon::PressureDriver.new(session_id: "codex-77-1", label: "codex 77 · web", footprint: 512 * MB, share: nil,
                                 growth_rate: 0.0),
    Agentmon::PressureDriver.new(session_id: "claude-88-1", label: "claude 88 · fourth", footprint: 100 * MB,
                                 share: 0.8, growth_rate: 0.0)
  ].freeze

  # An engine over the fixture machine whose `memory` and `pressure_drivers` metrics return
  # preset values (nil to leave a metric unregistered), whatever the producing stories register.
  def engine_with(memory:, drivers:)
    registry = Agentmon::Registry.new
    Agentmon.registry.metrics.reject { |m| %i[memory pressure_drivers].include?(m.name) }
            .each { |m| registry.add(:metric, m) }
    registry.add(:metric, Agentmon::Metric.new(name: :memory, block: ->(_r, _s) { memory })) if memory
    registry.add(:metric, Agentmon::Metric.new(name: :pressure_drivers, block: ->(_r, _s) { drivers })) if drivers
    Agentmon::Engine.new(sampler: Sampler.new(machine(0), machine(2)), registry:, prime_gap: 0)
  end

  # The top row's lines (the Memory panel and whatever shares the row) of the full dashboard.
  def top_row = dashboard_frame(dashboard_app).lines.first(14).join

  def test_shows_each_number_in_its_unit
    with_engine(engine_with(memory: VIEW, drivers: DRIVERS)) do
      text = top_row

      assert_includes text, "Memory"
      assert_match(/Used\s+▕█+░+▏\s*12G \/ 16G 75%/, text)
      assert_match(/App\s+8\.0G/, text)
      assert_match(/Wired\s+2\.0G/, text)
      assert_match(/Compressed\s+2\.0G/, text)
      assert_match(/Ratio\s+3\.1x/, text)
      assert_match(/Cached\s+3\.0G/, text)
      assert_match(/Swap used\s+512M/, text)
      assert_match(/Swap in\s+1\.0M\/s/, text)
      assert_match(/Swap out\s+256K\/s/, text)
      assert_match(/Compress\s+4\.0M\/s/, text)
      assert_match(/Decompress\s+3\.0M\/s/, text)
    end
  end

  def test_shows_a_pressure_sparkline_of_the_trend
    with_engine(engine_with(memory: VIEW, drivers: DRIVERS)) do
      line = top_row.lines.find { |l| l.include?("Pressure") }

      refute_nil line
      assert_match(/Pressure\s+[▁▂▃▄▅▆▇█]{4}\s+42\.0%/, line) # four trend points, scaled to 100%
    end
  end

  def test_shows_the_top_three_pressure_drivers
    with_engine(engine_with(memory: VIEW, drivers: DRIVERS)) do
      text = top_row

      assert_match(/claude 200 · repo\s+1\.5G\s+12\.5%\s+\+2\.0M\/s/, text)
      assert_match(/Claude 300\s+1\.0G\s+8\.3%\s+-512K\/s/, text)
      assert_match(/codex 77 · web\s+512M\s+\+0B\/s/, text) # share unknown: left blank
      refute_includes text, "fourth"
    end
  end

  # A dashboard holding only the Memory panel in a 14-line row, so its width doesn't depend on
  # which other panels share the :top row.
  def memory_only(width:)
    engine = Agentmon.engine
    Agentmon::UI.install(engine:)
    items = Agentmon.registry[:panel, :memory].block
    R2UI.registry.add_dashboard(R2UI::DSL::Dashboard.build(:memory_only) do
      row(height: 14) { panel(:memory) { instance_exec(engine, &items) } }
    end)
    R2UI::App.new(R2UI.registry, :memory_only).tap { |a| a.feeds.each_value(&:refresh!) }
             .frame(width, 15).plain_lines.first(14).join("\n")
  end

  def test_fits_a_third_of_a_150_column_screen
    with_engine(engine_with(memory: VIEW, drivers: DRIVERS)) do
      text = memory_only(width: 50)

      assert_match(/12G \/ 16G 75%/, text)
      assert_match(/Decompress\s+3\.0M\/s/, text)
      assert_match(/Pressure.*42\.0%/, text)
      assert_match(/codex 77 · web\s+512M/, text) # the third driver still fits the 14-line row
    end
  end

  def test_without_a_memory_value_shows_no_numbers
    with_engine(engine_with(memory: nil, drivers: DRIVERS)) do
      text = top_row
      panel = text.lines.map { |l| l[/│([^│]*)│/, 1] }.compact.join("\n") # inside the panel's box

      assert_includes text, "Memory"
      assert_includes panel, "not available"
      refute_match(/\d/, panel)
    end
  end

  def test_without_drivers_still_shows_memory
    with_engine(engine_with(memory: VIEW, drivers: nil)) do
      text = top_row

      assert_match(/12G \/ 16G 75%/, text)
      assert_match(/Pressure.*42\.0%/, text)
    end
  end
end
