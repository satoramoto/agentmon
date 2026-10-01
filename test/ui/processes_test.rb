# frozen_string_literal: true

require "test_helper"

# The Processes panel on fixture data, through r2ui as a user sees it.
class ProcessesPanelTest < Minitest::Test
  include Fixtures

  def app
    Agentmon::UI.install(engine: Agentmon.engine)
    R2UI::App.new(R2UI.registry, Agentmon::UI::DASHBOARD).tap { |a| a.feeds.each_value(&:refresh!) }
  end

  def frame(app, width: 150, height: 20) = app.frame(width, height).plain_lines.join("\n")

  def test_shows_agent_processes_with_footprint_and_rates_by_default
    with_engine(Fixtures.engine(machine(0), machine(2))) do
      text = frame(app)

      assert_includes text, "claude 200 · repo"
      assert_match(/claude\s+claude 200 · repo\s+~?\S*\s+.*100\.0%\s+512M\s+600M\s+0B\/s\s+1000B\/s/, text)
      refute_includes text, "Finder" # not an agent process
    end
  end

  def test_all_scope_shows_unreadable_processes_with_ps_values
    with_engine(Fixtures.engine(machine(0), machine(2))) do
      a = app
      a.press("]")
      text = frame(a)

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
      text = frame(app)

      assert_includes text.lines.last, "⚠ metric broken: RuntimeError: no swap info"
      assert_includes text, "claude 200 · repo" # the rest still draws
    end
  end

  def test_grouping_by_session_sums_members
    with_engine(Fixtures.engine(machine(0), machine(2))) do
      a = app
      a.press("g") # first grouping: Session
      text = frame(a)

      assert_match(/claude 200 · repo.*150\.0%\s+628M/, text) # 512 + 100 + 8 + 8 MB footprint
    end
  end
end
