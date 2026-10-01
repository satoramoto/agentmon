# frozen_string_literal: true

# sample[:processes]: every process, as ProcessStat (lib/agentmon/model.rb).
#
# One `ps` for the whole table (pid, ppid, rss, %cpu, executable path: what rusage lacks), then
# proc_pid_rusage and proc_pidinfo through Fiddle for each pid: no subprocess per process.
# ~700 processes take ~30 ms on an M-series Mac.
#
# Processes the kernel won't describe (other users', EPERM) and ones that exit between ps and
# rusage (ESRCH) keep their ps values: `readable: false`, resident from ps rss, ps %cpu, and nil
# footprint, CPU time and disk I/O.
module Agentmon
  module Probes
    module Processes
      PS = %w[ps -axo pid=,ppid=,rss=,pcpu=,comm=].freeze

      module_function

      # `ps_text` and `reader` (anything with Darwin's `rusage(pid)` and `started_at(pid)`) are
      # injectable for tests.
      def read(ps_text: IO.popen(PS, err: File::NULL, &:read), reader: Darwin)
        parse_ps(ps_text).map do |row|
          usage = reader.rusage(row[:pid])
          build(row, usage, usage && reader.started_at(row[:pid]))
        end
      end

      # ps lines -> Hashes. comm is last and may contain spaces.
      def parse_ps(text)
        text.each_line.filter_map do |line|
          pid, ppid, rss, pcpu, path = line.strip.split(nil, 5)
          next unless path

          { pid: pid.to_i, ppid: ppid.to_i, rss: rss.to_i * 1024, pcpu: pcpu.to_f, path: }
        end
      end

      def build(row, usage, started_at)
        ProcessStat.new(
          pid: row[:pid], ppid: row[:ppid], name: File.basename(row[:path]), path: row[:path],
          readable: !usage.nil?,
          start_ticks: usage&.start_ticks,
          started_at:,
          cpu_time: usage&.cpu_time,
          child_cpu_time: usage&.child_cpu_time,
          resident: usage ? usage.resident : row[:rss],
          footprint: usage&.footprint,
          peak_footprint: usage&.peak_footprint,
          disk_read: usage&.disk_read,
          disk_written: usage&.disk_written,
          ps_cpu: row[:pcpu]
        )
      end
    end
  end

  probe(:processes) { Probes::Processes.read }
end
