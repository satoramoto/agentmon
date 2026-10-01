# frozen_string_literal: true

# Quick filters on the Processes table, after Agents and All (cycle with `]`, back with `[`):
#
#   Busy     CPU above 5% of one core
#   Heavy    footprint above 500 MiB
#   Writing  writing to disk now (write rate above 0 B/s)
#
# They look at every process, not just agent ones, and `/` search still narrows inside them
# (Busy, then `/node`: the busy node processes). A process whose value is unknown (unreadable
# without root, or not yet sampled twice) is left out of that scope.
module Agentmon
  module UI
    # The thresholds, in the units of ProcessRow: percent of one core, bytes.
    module ProcessScopes
      BUSY_CPU = 5.0
      HEAVY_FOOTPRINT = 500 * 1024 * 1024

      module_function

      def busy?(row) = !row.cpu.nil? && row.cpu > BUSY_CPU
      def heavy?(row) = !row.footprint.nil? && row.footprint > HEAVY_FOOTPRINT
      def writing?(row) = !row.write_rate.nil? && row.write_rate.positive?
    end
  end

  extend_resource :process do |_engine|
    scope(:busy) { |row| UI::ProcessScopes.busy?(row) }
    scope(:heavy) { |row| UI::ProcessScopes.heavy?(row) }
    scope(:writing) { |row| UI::ProcessScopes.writing?(row) }
  end
end
