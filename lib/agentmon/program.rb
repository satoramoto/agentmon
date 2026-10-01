# frozen_string_literal: true

module Agentmon
  # The `agentmon` command line, an r2ui CLI program: the root (no command) opens the dashboard,
  # and every registered command is a subcommand.
  module Program
    module_function

    def build(registry: Agentmon.registry)
      R2UI.cli("agentmon") do
        summary "What AI coding agents (Claude, Codex) cost this Mac"
        description <<~TEXT.chomp
          With no command, opens the dashboard: agent sessions, processes with real memory
          (footprint) and disk I/O, and memory pressure. Off a terminal it prints one frame.
        TEXT
        registry.cli_blocks.each { |b| instance_exec(&b) }
        registry.commands.each { |c| command(c.name, &c.block) }

        run do
          engine = Agentmon.engine
          engine.recording = shell.interactive? # history is written while the dashboard is open
          UI.install(engine:)
          dashboard UI::DASHBOARD
        end
      end
    end

    def start(argv = ARGV) = build.start(argv)
  end
end
