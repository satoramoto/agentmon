# frozen_string_literal: true

# visual: gauges, areas and heat.
module Agentmon
  view :visual, title: "agentmon" do
    row height: 10 do
      panel :cpu, title: "CPU" do
        meter "system.cpu"
        trend "system.cpu", height: 5, label: "last 4 min"
        stat "system.load1", "system.load5", "system.load15", columns: 3
      end
      panel :memory, title: "Memory" do
        meter "memory.used"
        meter "memory.pressure"
        meter "memory.swap_used"
        stat "memory.app", "memory.wired", "memory.compressed", "memory.cached", columns: 2
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
      top :process, span: 3, by: :cpu, limit: 14, columns: %i[name session cpu footprint],
                    widths: { name: 16, session: 22 }
      top :session, span: 2, by: :cpu, columns: %i[label cpu footprint], widths: { label: 22 }
    end
  end
end
