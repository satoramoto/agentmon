# frozen_string_literal: true

module Agentmon
  class Error < StandardError; end

  # A probe reads the machine. Its block gets a private state Hash (kept between samples) and
  # returns one value, stored as `sample[name]`. With `every:`, the previous value is reused until
  # that many seconds have passed (slow probes such as lsof).
  Probe = Data.define(:name, :every, :block)
  # A metric derives a value from samples. Its block gets the Reading and a private state Hash
  # (kept between samples, so it can accumulate) and returns `reading[name]`. Every metric runs on
  # every sample, so stateful ones see each one.
  Metric = Data.define(:name, :block)
  # A recorder turns a Reading into store records (Hashes) appended under its name, at most once
  # every `every` seconds, while the engine records (the dashboard, `agentmon record`).
  Recorder = Data.define(:name, :every, :block)
  # A dashboard row. Panels name the row they go in; rows without panels are left out.
  Row = Data.define(:name, :order, :height)
  # A dashboard panel: r2ui's `panel` arguments plus where it goes. `block` holds r2ui panel items
  # (table, gauge, stat, sparkline, view, ...); nil shows the resource's full index.
  Panel = Data.define(:name, :row, :order, :resource, :span, :title, :options, :block)
  # A CLI command: the block is an r2ui CLI command body (summary, option, run, ...).
  Command = Data.define(:name, :block)

  # Everything the extension files registered. One per process (Agentmon.registry); tests build
  # their own to try a registration in isolation.
  class Registry
    KINDS = %i[probe metric recorder row panel command].freeze

    def initialize
      @items = KINDS.to_h { |k| [k, {}] }
      @resources = {}
      @resource_extensions = Hash.new { |h, k| h[k] = [] }
      @dashboard_blocks = []
      @cli_blocks = []
    end

    attr_reader :resource_extensions, :dashboard_blocks, :cli_blocks

    # Adds a named item; a name already taken in its kind raises, so two stories can't silently
    # register the same probe, metric, panel or command.
    def add(kind, item)
      items = @items.fetch(kind) { raise Error, "unknown kind #{kind.inspect}" }
      raise Error, "#{kind} #{item.name} is already registered" if items.key?(item.name)

      items[item.name] = item
    end

    def all(kind) = @items.fetch(kind).values

    def [](kind, name) = @items.fetch(kind)[name.to_sym]

    def probes = all(:probe)
    def metrics = all(:metric)
    def recorders = all(:recorder)
    def commands = all(:command)

    # Rows in order, each with its panels in order; empty rows left out.
    def layout
      panels = all(:panel).group_by(&:row)
      unknown = panels.keys - @items[:row].keys
      raise Error, "panel #{panels[unknown.first].first.name} names unknown row #{unknown.first}" if unknown.any?

      all(:row).sort_by(&:order).filter_map do |row|
        members = panels[row.name]
        members && [row, members.sort_by { |p| [p.order, p.name.to_s] }]
      end
    end

    def define_resource(name, block)
      raise Error, "resource #{name} is already defined" if @resources.key?(name)

      @resources[name] = block
    end

    # name => [definition block, *extension blocks in load order]
    def resources
      extra = @resource_extensions.keys - @resources.keys
      raise Error, "extend_resource #{extra.first}: no resource defines it" if extra.any?

      @resources.to_h { |name, block| [name, [block, *@resource_extensions[name]]] }
    end
  end

  class << self
    def registry = @registry ||= Registry.new

    # --- the extension points (docs/design.md); each story's file calls these at load ---

    def probe(name, every: nil, &block) = registry.add(:probe, Probe.new(name: name.to_sym, every:, block: need(block)))

    def metric(name, &block) = registry.add(:metric, Metric.new(name: name.to_sym, block: need(block)))

    def recorder(name, every: 10, &block)
      registry.add(:recorder, Recorder.new(name: name.to_sym, every:, block: need(block)))
    end

    def row(name, order:, height: nil) = registry.add(:row, Row.new(name: name.to_sym, order:, height:))

    # `resource:` defaults to the panel's name, as in r2ui; `resource: nil` for extension items only.
    def panel(name, row:, order: 100, resource: name, span: 1, title: nil, **options, &block)
      registry.add(:panel, Panel.new(name: name.to_sym, row: row.to_sym, order:, resource:, span:, title:, options:, block:))
    end

    # An r2ui resource (R2UI.resource's DSL). The block runs on r2ui's resource builder and gets
    # the Engine: `source { engine.current[:process_rows] }`. Defined once; see extend_resource.
    def resource(name, &block) = registry.define_resource(name.to_sym, need(block))

    # More DSL for a resource another file defines: columns, scopes, actions. Runs after the
    # definition, in load order.
    def extend_resource(name, &block) = registry.resource_extensions[name.to_sym] << need(block)

    # Dashboard-level r2ui DSL (keys, mouse, theme, title, ...), run on r2ui's dashboard builder
    # with the Engine, before the rows.
    def dashboard(&block) = registry.dashboard_blocks << need(block)

    # An `agentmon <name>` command; the block is an r2ui CLI command body.
    def command(name, &block) = registry.add(:command, Command.new(name: name.to_sym, block: need(block)))

    # Root-level r2ui CLI DSL (version, completion, global flags), run on the root builder.
    def cli(&block) = registry.cli_blocks << need(block)

    # Loads every extension file, kind by kind, each directory in name order.
    def load_extensions(root = __dir__)
      %w[probes metrics recorders ui commands].each do |dir|
        Dir[File.join(root, dir, "*.rb")].sort.each { |file| require file }
      end
    end

    private

    def need(block) = block || raise(ArgumentError, "a block is required")
  end
end
