# frozen_string_literal: true

# visual: gauges, areas and heat, sessions first (docs/views.md). FRAME
module Agentmon
  view :visual, title: "agentmon" do
    # Home: the machine's breakdown, then every agent session.
    row height: 11 do
      panel :cpu, title: "CPU" do
        meter "system.cpu"
        trend "system.cpu", height: 6, label: "last 4 min"
        stat "system.load1", "system.load5", "system.load15", columns: 3
      end
      panel :memory, title: "Memory" do
        meter "memory.used"
        meter "memory.pressure"
        meter "memory.swap_used"
        stat "memory.app", "memory.wired", "memory.compressed", "memory.cached", columns: 2
        trend "memory.used", height: nil, label: "used, last 4 min"
      end
    end
    row height: 8 do
      panel :network, title: "Network" do
        trend "system.net_in_rate", "system.net_out_rate", height: nil
      end
      panel :disk, title: "Disk" do
        trend "system.disk_read_rate", "system.disk_write_rate", height: nil
      end
    end
    row do
      top :session, title: "Sessions", by: :cpu, spark: %i[cpu net_out_rate],
                    columns: %i[label cpu footprint read_rate write_rate net_in_rate net_out_rate],
                    widths: { label: 22 }
    end

    # Drilled into one session: its CPU, memory, network and disk, processes, connections.
    focused do
      row height: 11 do
        panel :s_cpu, title: "CPU" do
          meter "focus.cpu"
          trend "focus.cpu", height: nil, label: "last 4 min"
          stat "focus.processes", "focus.read_rate", "focus.write_rate", columns: 3
        end
        panel :s_memory, title: "Memory" do
          meter "focus.footprint"
          stat "focus.resident", "focus.wired", "focus.growth_rate", "focus.pagein_rate", columns: 2
          trend "focus.footprint", height: nil, label: "footprint, last 4 min"
        end
      end
      row height: 8 do
        panel :s_net, title: "Network" do
          trend "focus.net_in_rate", "focus.net_out_rate", height: nil
        end
        panel :s_disk, title: "Disk" do
          trend "focus.read_rate", "focus.write_rate", height: nil
        end
      end
      row do
        top :process, span: 3, by: :cpu, columns: %i[name cpu footprint net_out_rate], widths: { name: 20 }
        detail :process, span: 2
      end
      row height: 8 do
        top :connection, title: "Connections", by: :out_rate, spark: false, widths: { process: 18 },
                         columns: %i[process remote_text state in_rate out_rate bytes_in bytes_out]
      end
    end
  end
end
