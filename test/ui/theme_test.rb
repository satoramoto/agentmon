# frozen_string_literal: true

require "test_helper"

# a10-theme-and-title: the dashboard's theme (accent for sessions, alert colours for pressure) and
# the terminal window title "agentmon · N sessions · P% pressure".
class ThemePanelTest < Minitest::Test
  include Fixtures

  # A message that changes nothing, to drive updates.
  class Bump < Bubbletea::Message; end

  def setup
    R2UI::Ext::Theme.require_lipgloss!
    R2UI::Compat::Gloss::Renderer.color_profile = :true_color
  end

  def teardown = R2UI::Compat::Gloss::Renderer.color_profile = nil

  def app
    Agentmon::UI.install(engine: Agentmon.engine)
    R2UI::App.new(R2UI.registry, Agentmon::UI::DASHBOARD)
  end

  def titles(command)
    commands = case command
               when nil then []
               when Bubbletea::BatchCommand then command.commands
               else [command]
               end
    commands.grep(Bubbletea::SetWindowTitleCommand).map(&:title)
  end

  def memory(pressure)
    Agentmon::MemoryView.new(
      total: 16 * 1024 * MB, used: 8 * 1024 * MB, app: 5 * 1024 * MB, wired: 2 * 1024 * MB, compressed: 1024 * MB,
      cached: 4 * 1024 * MB, free: 1024 * MB, swap_used: 0, swap_total: 0, compression_ratio: 3.0,
      swapin_rate: 0.0, swapout_rate: 0.0, compression_rate: 0.0, decompression_rate: 0.0,
      pressure:, pressure_trend: [pressure]
    )
  end

  # An engine with the registered metrics plus a preset :memory value (until a02 registers one).
  def engine_with_memory(*samples, pressures:)
    registry = Agentmon::Registry.new
    Agentmon.registry.metrics.reject { |m| m.name == :memory }.each { |m| registry.add(:metric, m) }
    queue = pressures.dup
    registry.add(:metric, Agentmon::Metric.new(name: :memory, block: lambda { |_r, _s|
      memory(queue.size > 1 ? queue.shift : queue.first)
    }))
    Agentmon::Engine.new(sampler: Sampler.new(*samples), registry:, prime_gap: 0)
  end

  # machine(t) without the desktop-launched claude 303: two sessions instead of three.
  def machine_without_303(t) = machine(t).then { |s| s.with(parts: s.parts.merge(processes: s[:processes].reject { |p| p.pid == 303 })) }

  def test_title_counts_alive_sessions_and_leaves_pressure_out_without_memory
    with_engine(Fixtures.engine(machine(0), machine(2))) do
      a = app
      _, command = a.init

      assert_equal ["agentmon · 3 sessions"], titles(command)
    ensure
      a&.stop
    end
  end

  def test_title_shows_pressure_and_updates_as_it_changes
    engine = engine_with_memory(machine(0), machine(2), machine_without_303(4), pressures: [41.6, 41.6, 87.0])
    with_engine(engine) do
      a = app
      _, command = a.init
      assert_equal ["agentmon · 3 sessions · 42% pressure"], titles(command)

      _, command = a.update(Bump.new)
      assert_empty titles(command), "an unchanged title is not re-sent"

      engine.tick!
      _, command = a.update(Bump.new)
      assert_equal ["agentmon · 2 sessions · 87% pressure"], titles(command)
    ensure
      a&.stop
    end
  end

  def test_title_text_for_edge_readings
    title = Agentmon::UI::ThemeTitle.method(:title)

    assert_equal "agentmon", title.call(nil)
    assert_equal "agentmon · 0 sessions", title.call(reading(machine(0), values: { session_ledger: nil }))
    one = [Agentmon::Session.members.to_h { |m| [m, nil] }.merge(id: "x", ended_at: nil)].map { |h| Agentmon::Session.new(**h) }
    ended = one.map { |s| s.with(id: "y", ended_at: T0) }
    assert_equal "agentmon · 1 session · 5% pressure",
                 title.call(reading(machine(0), values: { session_ledger: one + ended, memory: memory(5.0) }))
    assert_equal "agentmon · 1 session",
                 title.call(reading(machine(0), values: { session_ledger: one, memory: memory(nil) }))
  end

  def test_theme_sets_accent_and_pressure_alert_styles
    with_engine(Fixtures.engine(machine(0), machine(2))) do
      a = app
      styles = R2UI.registry.dashboards.fetch(Agentmon::UI::DASHBOARD).declared(:theme).reduce({}, :merge)
      sgr = styles.transform_values { |s| R2UI::Ext::Theme.sgr(s) }

      %i[accent ok warn alert title focus].each { |name| assert_includes sgr.keys, name }
      assert_equal 4, sgr.values_at(:accent, :ok, :warn, :alert).uniq.size, "each style has its own colour"
      assert_match(/38;2;/, sgr[:accent], "accent is a truecolor foreground")

      a.feeds.each_value(&:refresh!)
      ansi = a.frame(150, 20).ansi_lines.join("\n")
      assert_includes ansi, "\e[0;#{sgr[:accent]}m[Agents]", "the active scope label is drawn in the accent"
    end
  end
end
