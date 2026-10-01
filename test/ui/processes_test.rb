# frozen_string_literal: true

require "test_helper"

# The Processes panel on fixture data, through r2ui as a user sees it.
class ProcessesPanelTest < Minitest::Test
  include Fixtures

  def test_shows_agent_processes_with_footprint_and_rates_by_default
    with_engine(Fixtures.engine(machine(0), machine(2))) do
      text = dashboard_frame(dashboard_app)

      assert_includes text, "claude 200 · repo"
      assert_match(/claude\s+claude 200 · repo\s+~?\S*\s+.*100\.0%\s+512M\s+600M\s+0B\/s\s+1000B\/s/, text)
      refute_includes text, "Finder" # not an agent process
    end
  end

  def test_all_scope_shows_unreadable_processes_with_ps_values
    with_engine(Fixtures.engine(machine(0), machine(2))) do
      a = dashboard_app
      a.press("]")
      text = dashboard_frame(a)

      assert_includes text, "Finder"
      assert_match(/WindowServer.*11\.2%\s+134M/, text) # footprint blank: unreadable
    end
  end

  def test_a_broken_metric_shows_in_the_status_bar
    registry = Agentmon::Registry.new
    Agentmon.registry.metrics.each { |m| registry.add(:metric, m) }
    registry.add(:metric, Agentmon::Metric.new(name: :broken, block: ->(_r, _s) { raise "no swap info" }))
    engine = Agentmon::Engine.new(sampler: Sampler.new(machine(0), machine(2)), registry:, prime_gap: 0)
    with_engine(engine) do
      text = dashboard_frame(dashboard_app)

      assert_includes text.lines.last, "⚠ metric broken: RuntimeError: no swap info"
      assert_includes text, "claude 200 · repo" # the rest still draws
    end
  end

  def test_keys_go_to_processes_even_with_a_table_panel_before_it
    registry = Agentmon::Registry.new
    %i[probe metric row panel].each { |kind| Agentmon.registry.all(kind).each { |item| registry.add(kind, item) } }
    Agentmon.registry.resources.each { |name, (block, *)| registry.define_resource(name, block) }
    registry.define_resource(:early, proc do
      source { [{ id: 1, name: "early" }] }
      index { column :name }
    end)
    registry.add(:panel, Agentmon::Panel.new(name: :early, row: :top, order: 0, resource: :early, span: 1,
                                             title: nil, options: {}, block: nil))
    with_engine(Fixtures.engine(machine(0), machine(2))) do |engine|
      Agentmon::UI.install(engine:, registry:)
      a = R2UI::App.new(R2UI.registry, Agentmon::UI::DASHBOARD)

      assert_equal :early, a.dashboard.panels.first.name
      assert_equal :process, a.focus.name
    end
  end

  def test_grouping_by_session_sums_members
    with_engine(Fixtures.engine(machine(0), machine(2))) do
      a = dashboard_app
      a.press("g") # first grouping: Session
      text = dashboard_frame(a)

      assert_match(/claude 200 · repo.*150\.0%\s+628M/, text) # 512 + 100 + 8 + 8 MB footprint
    end
  end
end
