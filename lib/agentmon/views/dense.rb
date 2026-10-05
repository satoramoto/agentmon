# frozen_string_literal: true

# dense: htop-like, sessions first (docs/views.md). FRAME
module Agentmon
  view :dense, title: "agentmon" do
    # Home: the machine strip, every agent session with its breakdown, all agents together.
    row height: 6 do
      panel :cpu, title: "CPU", span: 3 do
        spark "system.cpu"
        spark "system.user"
        stat "system.load1", "system.load5", "system.load15", "system.ncpu", columns: 2
      end
      panel :memory, title: "Memory", span: 2 do
        spark "memory.used"
        spark "memory.pressure"
        spark "memory.swap_used"
        spark "memory.compressed", label: "compr"
      end
      panel :io, title: "I/O", span: 2 do
        spark "system.net_in_rate", label: "net in"
        spark "system.net_out_rate", label: "net out"
        spark "system.disk_read_rate", label: "disk rd"
        spark "system.disk_write_rate", label: "disk wr"
      end
    end
    row do
      top :session, title: "Sessions", by: :cpu, spark: %i[cpu net_out_rate],
                    columns: %i[label processes cpu footprint read_rate write_rate net_in_rate net_out_rate],
                    widths: { label: 20 }
    end
    row height: 5 do
      panel :agents, title: "All agents" do
        spark "focus.cpu"
        spark "focus.footprint"
        spark "focus.processes"
      end
      panel :agents_io, title: "Agents I/O" do
        spark "focus.net_in_rate"
        spark "focus.net_out_rate"
        stat "focus.remote_hosts", "focus.connections", columns: 2
      end
    end

    # Drilled into one session (Enter on Sessions, F on a process; Escape returns).
    focused do
      row height: 7 do
        panel :s_cpu, title: "CPU" do
          spark "focus.cpu"
          spark "focus.read_rate", label: "disk rd"
          spark "focus.write_rate", label: "disk wr"
          stat "focus.processes", "system.ncpu", columns: 2
        end
        panel :s_memory, title: "Memory" do
          meter "focus.footprint"
          spark "focus.footprint", label: "trend"
          stat "focus.resident", "focus.wired", "focus.growth_rate", "focus.pagein_rate", columns: 2
        end
        panel :s_net, title: "Network" do
          spark "focus.net_in_rate"
          spark "focus.net_out_rate"
          stat "focus.bytes_in", "focus.bytes_out", "focus.remote_hosts", "focus.connections", columns: 2
        end
      end
      row do
        top :process, title: "Processes", by: :cpu, spark: false,
                      columns: %i[pid name cpu footprint run_wait read_rate write_rate net_in_rate net_out_rate],
                      widths: { name: 22 }
      end
      row height: 9 do
        top :connection, title: "Connections", by: :out_rate, spark: false, widths: { process: 18 },
                         columns: %i[process protocol remote_text state in_rate out_rate bytes_in bytes_out]
      end
      row height: 7 do
        detail :process, columns: 3
      end
    end
  end
end
