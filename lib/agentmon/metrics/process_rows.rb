# frozen_string_literal: true

# reading[:process_rows]: one ProcessRow per process, joining the probe's counters with rates,
# working directories and session labels. What the dashboard's process table and the CLI print.
module Agentmon
  module Metrics
    module ProcessRows
      module_function

      def call(processes, rates, cwds, sessions)
        cwds ||= {}
        labels = sessions.sessions.to_h { |s| [s.id, s.label] }
        (processes || []).map do |p|
          rate = rates[p.pid]
          session_id = sessions.by_pid[p.pid]
          ProcessRow.new(
            pid: p.pid, ppid: p.ppid, name: p.name, path: p.path, cwd: cwds[p.pid],
            session: session_id && labels[session_id], session_id:,
            cpu: rate&.cpu, footprint: p.footprint, resident: p.resident, peak_footprint: p.peak_footprint,
            read_rate: rate&.read_rate, write_rate: rate&.write_rate,
            cpu_time: p.cpu_time, disk_written: p.disk_written, started_at: p.started_at, readable: p.readable
          )
        end
      end
    end
  end

  metric(:process_rows) do |reading|
    Metrics::ProcessRows.call(reading.sample[:processes], reading[:process_rates], reading.sample[:cwd], reading[:sessions])
  end
end
