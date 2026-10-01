# frozen_string_literal: true

module Agentmon
  # Builds the r2ui dashboard from the registered pieces: each resource (its definition, then its
  # extensions), the dashboard-level blocks, then the rows with their panels in order. Every block
  # gets the Engine, so sources read `engine.current[...]`.
  #
  #   Agentmon::UI.install(engine:)            # into R2UI.registry, as the :agentmon dashboard
  #   R2UI.snapshot(:agentmon, width: 140, height: 40)
  module UI
    DASHBOARD = :agentmon

    module_function

    def install(engine:, registry: Agentmon.registry, into: R2UI.registry)
      registry.resources.each do |name, blocks|
        into.add_resource(R2UI::DSL::Resource.build(name) { blocks.each { |b| instance_exec(engine, &b) } })
      end
      into.add_dashboard(build_dashboard(engine, registry))
    end

    def build_dashboard(engine, registry)
      layout = registry.layout
      extras = registry.dashboard_blocks
      R2UI::DSL::Dashboard.build(DASHBOARD) do
        title "agentmon"
        extras.each { |b| instance_exec(engine, &b) }
        layout.each do |spec, panels|
          row(height: spec.height) do
            panels.each do |p|
              items = p.block && proc { instance_exec(engine, &p.block) }
              panel(p.name, resource: p.resource, span: p.span, title: p.title, **p.options, &items)
            end
          end
        end
      end
    end
  end

  # The rows panels go in. Stories add panels to these (or register rows of their own).
  row :top, order: 10, height: 14
  row :main, order: 100
end
