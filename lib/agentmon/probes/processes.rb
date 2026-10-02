# frozen_string_literal: true

# sample[:processes]: every process, as ProcessStat (lib/agentmon/model.rb).
#
# One `ps` for the whole table (pid, ppid, rss, %cpu, executable path: what rusage lacks), then
# proc_pid_rusage and proc_pidinfo(PROC_PIDTASKALLINFO) through Fiddle for each pid: no
# subprocess per process. ~800 processes take ~50 ms on an M-series Mac: ~12 ms of Fiddle calls
# and decoding, the rest ps.
#
# Processes the kernel won't describe (other users', EPERM) and ones that exit between ps and
# rusage (ESRCH) keep their ps values: `readable: false`, resident from ps rss, ps %cpu, and nil
# footprint, CPU time, disk I/O, faults and scheduling counters.
module Agentmon
  module Probes
    module Processes
      PS = %w[ps -axo pid=,ppid=,rss=,pcpu=,comm=].freeze

      module_function

      # `ps_text` and `reader` (anything with Darwin's `rusage(pid)`, `task_info(pid)` and
      # `started_at(pid)`) are injectable for tests.
      #
      # Two calls per readable process: rusage, then task_info (start time plus fault and
      # scheduling counters, one proc_pidinfo). Only if task_info fails where rusage worked (not
      # seen on macOS 26) does a third call fetch the start time alone.
      def read(ps_text: IO.popen(PS, err: File::NULL, &:read), reader: Darwin)
        parse_ps(ps_text).map do |row|
          usage = reader.rusage(row[:pid])
          task = usage && reader.task_info(row[:pid])
          build(row, usage, task ? task.started_at : (usage && reader.started_at(row[:pid])), task)
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

      def build(row, usage, started_at, task = nil)
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
          ps_cpu: row[:pcpu],
          wired: usage&.wired,
          pageins: usage&.pageins,
          runnable_time: usage&.runnable_time,
          faults: task&.faults,
          cow_faults: task&.cow_faults,
          context_switches: task&.context_switches,
          threads: task&.threads,
          running_threads: task&.running_threads
        )
      end
    end
  end

  probe(:processes) { Probes::Processes.read }
end
