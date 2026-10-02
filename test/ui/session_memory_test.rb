# frozen_string_literal: true

require "test_helper"

# The "Memory by session" panel (story a20) on preset `session_memory` and `memory` values, drawn
# through r2ui as a user sees it.
class SessionMemoryPanelTest < Minitest::Test
  include Fixtures

  GB = 1024 * MB
  KB = 1024

  ROWS = [
    Fixtures.session_memory(session_id: "claude-200-1", label: "claude 200 · repo", processes: 4,
                            footprint: 1536 * MB, resident: 2 * GB, share: 12.5, growth_rate: 2.0 * MB,
                            pagein_rate: 10.0),
    Fixtures.session_memory(session_id: "Claude-300-1", label: "Claude 300", processes: 3, footprint: 1 * GB,
                            resident: 900 * MB, share: 8.3, growth_rate: -512.0 * KB, pagein_rate: 0.0),
    Fixtures.session_memory(session_id: "codex-77-1", label: "codex 77 · web", footprint: 512 * MB, share: nil,
                            growth_rate: 0.0)
  ].freeze

  VIEW = Agentmon::MemoryView.new(
    total: 16 * GB, used: 12 * GB, app: 8 * GB, wired: 2 * GB, compressed: 2 * GB, cached: 3 * GB,
    free: 1 * GB, swap_used: 512 * MB, swap_total: 2 * GB, compression_ratio: 3.1, swapin_rate: 0.0,
    swapout_rate: 0.0, compression_rate: 0.0, decompression_rate: 0.0, pressure: 42.0, pressure_trend: []
  )

  # An engine over the fixture machine whose `session_memory` and `memory` metrics return preset
  # values (nil leaves a metric unregistered), whatever the producing stories register.
  def engine_with(rows:, memory:)
    registry = Agentmon::Registry.new
    Agentmon.registry.metrics.reject { |m| %i[session_memory memory].include?(m.name) }
            .each { |m| registry.add(:metric, m) }
    registry.add(:metric, Agentmon::Metric.new(name: :session_memory, block: ->(_r, _s) { rows })) if rows
    registry.add(:metric, Agentmon::Metric.new(name: :memory, block: ->(_r, _s) { memory })) if memory
    Agentmon::Engine.new(sampler: Sampler.new(machine(0), machine(2)), registry:, prime_gap: 0)
  end

  # The top row's lines of the full dashboard.
  def top_row = dashboard_frame(dashboard_app).lines.first(14).join

  # The panel's own lines (inside its box) on the full dashboard: the rightmost box of the top row.
  def panel_text = top_row.lines.map { |l| l.split("│").reject(&:empty?)[-2].to_s }.join("\n")

  # A dashboard holding only this panel, so every column fits whatever shares the :top row.
  def panel_only(width: 100)
    engine = Agentmon.engine
    Agentmon::UI.install(engine:)
    items = Agentmon.registry[:panel, :session_memory].block
    R2UI.registry.add_dashboard(R2UI::DSL::Dashboard.build(:session_memory_only) do
      row(height: 14) { panel(:session_memory, title: "Memory by session") { instance_exec(engine, &items) } }
    end)
    R2UI::App.new(R2UI.registry, :session_memory_only).tap { |a| a.feeds.each_value(&:refresh!) }
             .frame(width, 15).plain_lines.first(14).join("\n")
  end

  def test_sits_in_the_top_row_with_its_title
    with_engine(engine_with(rows: ROWS, memory: VIEW)) do
      text = top_row

      assert_includes text, "Memory by session"
      assert_match(/claude .*1\.5G\s+12\.5%/, panel_text) # labels shrink to fit a quarter of 200 columns
    end
  end

  def test_shows_each_session_with_its_numbers_in_their_units
    with_engine(engine_with(rows: ROWS, memory: VIEW)) do
      text = panel_only

      assert_match(/Session\s+Footprint▼\s+Share\s+Resident\s+Growth\s+Pgin\/s/, text)
      assert_match(/claude 200 · repo\s+\S*\s+1\.5G\s+12\.5%\s+2\.0G\s+\+2\.0M\/s\s+10\.0/, text)
      assert_match(/Claude 300\s+\S*\s+1\.0G\s+8\.3%\s+900M\s+-512K\/s\s+0\.0/, text)
      assert_match(/codex 77 · web\s+\S*\s+512M\s+512M\s+\+0B\/s\s*│/, text) # share and pageins unknown: blank
      rows = text.lines.grep(/claude 200|Claude 300|codex 77/)
      assert_equal ["claude 200", "Claude 300", "codex 77"], rows.map { |l| l[/claude 200|Claude 300|codex 77/] }
    end
  end

  def test_shows_the_machines_compressed_and_swap
    with_engine(engine_with(rows: ROWS, memory: VIEW)) do
      assert_includes panel_only, "compressed 2.0G · swap 512M (per-process compressed/swap needs root)"
    end
  end

  def test_without_memory_the_machine_line_is_blank
    with_engine(engine_with(rows: ROWS, memory: nil)) do
      text = panel_only

      refute_includes text, "compressed"
      assert_match(/claude 200 · repo\s+\S*\s+1\.5G/, text)
    end
  end

  def test_without_session_memory_shows_no_rows_and_does_not_raise
    with_engine(engine_with(rows: nil, memory: VIEW)) do
      assert_includes top_row, "Memory by session"
      text = panel_only

      refute_includes text, "claude 200"
      refute_match(/\d/, text.lines[3..12].join) # no rows below the machine line and the header
    end
  end

  def test_follows_session_focus
    with_engine(engine_with(rows: ROWS, memory: VIEW)) do |engine|
      engine.focus = "Claude-300-1"
      text = panel_only

      assert_includes text, "Claude 300"
      refute_includes text, "claude 200"
      refute_includes text, "codex 77"
    end
  end

  def test_growth_is_signed
    ui = Agentmon::UI::SessionMemoryPanel

    assert_equal "+1.5M/s", ui.growth(1.5 * MB)
    assert_equal "-12K/s", ui.growth(-12.0 * KB)
    assert_equal "", ui.growth(nil)
  end
end
