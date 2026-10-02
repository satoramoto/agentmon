# frozen_string_literal: true

# What the selected process waits on: memory and scheduling detail in the Detail panel, two compact
# columns in the Processes table, and a Waiting scope.
#
# Detail panel lines, under the process's own (Detail follows the Processes selection):
#
#   Threads    12 (1 running)
#   CPU wait   25.0% now, 3m 2s total    runnable but waiting for a CPU (% of one core)
#   Page-ins   10/s, 20 total            each one waited for the disk
#   Faults     1000/s (COW 100/s)
#   Switches   500/s                     context switches
#   Wired      1.0M
#   Read       512B/s, 1.2G total        from disk
#
# A value that isn't known yet (rates need two samples) is left out of its line, and a line with
# nothing known says "unknown". Root's processes say "not readable without root".
#
# Processes table: Wait (`run_wait`, percent of one core spent waiting for a CPU) and Pgin/s
# (page-ins per second); blank when unknown. Scope Waiting (after Busy, Heavy, Writing): processes
# waiting for a CPU more than 10% of a core, or paging in at all. macOS has no per-process I/O wait
# without root; page-ins and disk rates are the closest signals.
module Agentmon
  module UI
    module ProcessWaits
      UNREADABLE = "not readable without root"
      # Scope Waiting: percent of one core spent runnable but not running.
      WAITING_RUN_WAIT = 10.0
      # Fixed widths for the two table columns (r2ui has no optional columns, so keep them narrow).
      WAIT_WIDTH = 6
      PAGEIN_WIDTH = 6

      module_function

      def waiting?(row)
        (!row.run_wait.nil? && row.run_wait > WAITING_RUN_WAIT) || (!row.pagein_rate.nil? && row.pagein_rate.positive?)
      end

      # The Detail panel lines for `row`: [[label, value or nil], ...].
      def lines(row)
        labels = ["Threads", "CPU wait", "Page-ins", "Faults", "Switches", "Wired", "Read"]
        return labels.map { |l| [l, UNREADABLE] } unless row.readable

        labels.zip([threads(row), cpu_wait(row), pageins(row), faults(row), rate(row.context_switch_rate),
                    row.wired && R2UI::Format.bytes(row.wired), read(row)])
      end

      def threads(row)
        return nil unless row.threads

        row.running_threads ? "#{row.threads} (#{row.running_threads} running)" : row.threads.to_s
      end

      # "25.0% now, 3m 2s total": total is runnable time minus time on a CPU.
      def cpu_wait(row)
        total = row.runnable_time && row.cpu_time && [row.runnable_time - row.cpu_time, 0.0].max
        join(row.run_wait && "#{format('%.1f%%', row.run_wait)} now",
             total && "#{R2UI::CLI::Ext::HumanFormat.duration(total)} total")
      end

      def pageins(row) = join(rate(row.pagein_rate), row.pageins && "#{row.pageins} total")

      def faults(row)
        cow = rate(row.cow_fault_rate)
        base = rate(row.fault_rate)
        return base && "#{base} (COW #{cow})" if cow

        base
      end

      def read(row)
        join(row.read_rate && "#{R2UI::Format.bytes(row.read_rate)}/s",
             row.disk_read && "#{R2UI::Format.bytes(row.disk_read)} total")
      end

      # Events per second: whole numbers from 10/s up, one decimal below.
      def rate(value)
        return nil unless value

        value >= 10 || value.zero? ? "#{value.round}/s" : format("%.1f/s", value)
      end

      def join(*parts)
        known = parts.compact
        known.empty? ? nil : known.join(", ")
      end
    end
  end

  detail_section :waits, order: 10 do |row, _reading|
    UI::ProcessWaits.lines(row)
  end

  extend_resource :process do |_engine|
    column :run_wait, label: "Wait", format: :percent, width: UI::ProcessWaits::WAIT_WIDTH
    column :pagein_rate, label: "Pgin/s", format: :number, width: UI::ProcessWaits::PAGEIN_WIDTH
    scope(:waiting) { |row| UI::ProcessWaits.waiting?(row) }
  end
end
