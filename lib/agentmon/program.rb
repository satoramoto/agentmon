# frozen_string_literal: true

module Agentmon
  # The `agentmon` command line, an r2ui CLI program: the root (no command) opens the dashboard
  # in a layout (`--layout`, default dense), and every registered command is a subcommand.
  module Program
    # The panel dashboard (rows and panels from Agentmon.row/panel), i.e. UI.install(view: nil).
    CLASSIC = "classic"
    DEFAULT_LAYOUT = "dense"

    module_function

    # The --layout choices: classic plus the registered views.
    def layouts(registry = Agentmon.registry) = [CLASSIC, *UI.layouts(registry).map(&:to_s)]

    # The view UI.install takes for a --layout choice (nil: the classic dashboard).
    def view(layout) = layout == CLASSIC ? nil : layout&.to_sym

    def build(registry: Agentmon.registry)
      layouts = Program.layouts(registry)
      default = layouts.include?(DEFAULT_LAYOUT) ? DEFAULT_LAYOUT : CLASSIC
      R2UI.cli("agentmon") do
        summary "What AI coding agents (Claude, Codex) cost this Mac"
        description <<~TEXT.chomp
          With no command, opens the dashboard in the #{default} layout: agent sessions with their
          CPU, real memory (footprint), disk and network, and memory pressure. --layout #{CLASSIC} is
          the panel dashboard. Off a terminal it prints one frame.
        TEXT
        registry.cli_blocks.each { |b| instance_exec(&b) }
        registry.commands.each { |c| command(c.name, &c.block) }

        option :layout, in: layouts, default:, desc: "Dashboard layout: #{CLASSIC} or a view (docs/views.md)"
        flag :motion, default: true, desc: "Animate meters, changed values and moved rows (AGENTMON_MOTION=0: off)"

        run do
          engine = Agentmon.engine
          engine.recording = shell.interactive? # history is written while the dashboard is open
          Views.motion = options[:motion] && ENV["AGENTMON_MOTION"] != "0"
          UI.install(engine:, view: Program.view(options[:layout]))
          dashboard UI::DASHBOARD
        end
      end
    end

    def start(argv = ARGV) = build.start(argv)
  end

  # After any command, a broken probe, metric or recorder is reported on stderr ("⚠ metric
  # memory: ..."), so a table with missing columns says why. stdout stays clean for scripts.
  R2UI::CLI.extension :agentmon_errors do
    after_run do
      Agentmon.engine_errors.each { |name, message| shell.err_puts("#{shell.symbol(:warn)} #{name}: #{message}") }
    end
  end
end
