# frozen_string_literal: true

require "test_helper"

class RegistryCoreTest < Minitest::Test
  def setup = @registry = Agentmon::Registry.new

  def panel(name, row:, order: 100, **opts)
    Agentmon::Panel.new(name:, row:, order:, resource: opts.fetch(:resource, name), span: 1, title: nil, options: {},
                        block: opts[:block])
  end

  def test_a_name_can_be_registered_once_per_kind
    @registry.add(:command, Agentmon::Command.new(name: :top, block: proc {}))

    assert_raises(Agentmon::Error) { @registry.add(:command, Agentmon::Command.new(name: :top, block: proc {})) }
  end

  def test_detail_sections_sort_by_order_then_name_and_names_are_unique
    section = ->(name, order) { Agentmon::DetailSection.new(name:, order:, block: proc { [] }) }
    @registry.add(:detail_section, section[:b, 10])
    @registry.add(:detail_section, section[:z, 5])
    @registry.add(:detail_section, section[:a, 10])

    assert_equal %i[z a b], @registry.detail_sections.map(&:name)
    assert_raises(Agentmon::Error) { @registry.add(:detail_section, section[:a, 1]) }
  end

  def test_layout_orders_rows_and_panels_and_drops_empty_rows
    @registry.add(:row, Agentmon::Row.new(name: :main, order: 100, height: nil))
    @registry.add(:row, Agentmon::Row.new(name: :top, order: 10, height: 14))
    @registry.add(:row, Agentmon::Row.new(name: :empty, order: 50, height: 3))
    @registry.add(:panel, panel(:sessions, row: :top, order: 20))
    @registry.add(:panel, panel(:memory, row: :top, order: 10))
    @registry.add(:panel, panel(:process, row: :main))

    assert_equal [[:top, %i[memory sessions]], [:main, [:process]]],
                 @registry.layout.map { |row, panels| [row.name, panels.map(&:name)] }
  end

  def test_a_panel_in_an_unknown_row_raises
    @registry.add(:panel, panel(:x, row: :nowhere))

    assert_raises(Agentmon::Error) { @registry.layout }
  end

  def test_a_resource_is_defined_once_and_extensions_need_it
    @registry.define_resource(:thing, proc {})
    assert_raises(Agentmon::Error) { @registry.define_resource(:thing, proc {}) }

    @registry.resource_extensions[:other] << proc {}
    assert_raises(Agentmon::Error) { @registry.resources }
  end

  def test_ui_applies_definitions_then_extensions_in_order_with_the_engine
    engine = Fixtures.engine(Fixtures.machine(0))
    @registry.add(:row, Agentmon::Row.new(name: :main, order: 1, height: nil))
    @registry.define_resource(:thing, proc { |e|
      source { e.current[:process_rows].first(1) }
      column :name
    })
    @registry.resource_extensions[:thing] << proc { column :pid, format: :id }
    @registry.dashboard_blocks << proc { title "Things" }
    @registry.add(:panel, panel(:thing, row: :main))
    into = R2UI::Registry.new
    Agentmon::UI.install(engine:, registry: @registry, into:)

    assert_equal %i[name pid], into.resource(:thing).columns.map(&:key)
    assert_equal "Things", into.screen(:agentmon).title
    frame = R2UI::App.new(into, :agentmon).snapshot(width: 60, height: 6)
    assert_includes frame, "launchd"
  end
end
