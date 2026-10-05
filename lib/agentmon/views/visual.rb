# frozen_string_literal: true

# visual: gauges, areas and heat (docs/views.md). FRAME
module Agentmon
  view :visual, title: "agentmon" do
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
    row height: 9 do
      panel :network, title: "Network" do
        trend "system.net_in_rate", "system.net_out_rate", height: nil
      end
      panel :disk, title: "Disk" do
        trend "system.disk_read_rate", "system.disk_write_rate", height: nil
      end
    end
    row do
      top :process, span: 3, by: :cpu, columns: %i[name session cpu footprint], widths: { name: 16, session: 14 }
      panel :session, title: "Sessions", span: 2 do
        trend "focus.cpu", "focus.footprint", height: 0.65
        top :session, by: :cpu, columns: %i[label cpu footprint], widths: { label: 14 }, spark: false
      end
    end
  end
end
