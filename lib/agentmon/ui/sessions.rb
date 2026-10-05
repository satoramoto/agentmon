# frozen_string_literal: true

# The :session resource and the Sessions panel (top row, beside the memory panel): one line per
# agent session with its process count, CPU % and footprint now (with sparklines), peak footprint,
# CPU seconds and bytes written over its life, disk rates now and its age. Sorted by CPU.
# Scope "Live" (default) shows running sessions; "All" (]) adds the ones that ended in the last
# 15 minutes, labelled with when:
#
#   Session                       Procs     CPU  Footprint    Peak  CPU s  Written   Read     Write  Age
#   claude 4242 · repo                4  150.0%       628M    700M   15.6     5.0M  0B/s  1000B/s  56m
#   claude 4310 · web · ended 3m ago  0    0.0%         0B    150M    5.0       0B  0B/s     0B/s  1h 2m
#
# Age is how long a session has run: since its root process started, until it ended.
# Search with / (`label~repo`, `footprint>1G`).
module Agentmon
  module UI
    # Turns the ledger's Session records into the panel's rows.
    module SessionsPanel
      module_function

      NO_NETWORK = { net_in_rate: nil, net_out_rate: nil, bytes_in: nil, bytes_out: nil, connections: nil,
                     remote_hosts: nil, net_flags: [].freeze }.freeze

      # reading[:session_ledger] as rows; none while no ledger is available. Each row also carries
      # its session's network (reading[:session_network], matched by session id): nil values and
      # no flags while network data is unknown or the session has no entry.
      def rows(reading)
        now = reading.at
        network = (reading[:session_network] || []).to_h { |n| [n.session_id, n] }
        (reading[:session_ledger] || []).map { |s| row(s, now, network[s.id]) }
      end

      def row(session, now, network = nil)
        ended = session.ended_at
        {
          id: session.id,
          alive: session.alive?,
          label: ended ? "#{session.label} · ended #{age(now - ended)} ago" : session.label,
          cwd: session.cwd,
          processes: session.processes,
          cpu: session.cpu,
          footprint: session.footprint,
          peak_footprint: session.peak_footprint,
          cpu_seconds: session.cpu_seconds,
          bytes_written: session.bytes_written,
          read_rate: session.read_rate,
          write_rate: session.write_rate,
          age: age((ended || now) - (session.started_at || session.first_seen_at)),
          **network_values(network)
        }
      end

      # A SessionNetwork as row values (NO_NETWORK for nil).
      def network_values(n)
        return NO_NETWORK unless n

        { net_in_rate: n.in_rate, net_out_rate: n.out_rate, bytes_in: n.bytes_in, bytes_out: n.bytes_out,
          connections: n.connections, remote_hosts: n.remote_hosts, net_flags: Array(n.flags) }
      end

      # "45s", "12m", "3h 5m", "2d 4h"; "" when unknown.
      def age(seconds)
        return "" if seconds.nil?

        s = [seconds.to_i, 0].max
        if s < 60 then "#{s}s"
        elsif s < 3600 then "#{s / 60}m"
        elsif s < 86_400 then "#{s / 3600}h #{s % 3600 / 60}m"
        else "#{s / 86_400}d #{s % 86_400 / 3600}h"
        end
      end
    end
  end

  resource :session do |engine|
    title "Sessions"
    source { UI::SessionsPanel.rows(engine.current) }
    refresh every: engine.interval
    key :id

    scope :live, default: true do |row|
      row[:alive]
    end
    scope :all

    index do
      column :label, label: "Session"
      column :processes, label: "Procs", format: :integer
      column :cpu, label: "CPU", format: :percent, sparkline: true, sort: :desc
      column :footprint, label: "Footprint", format: :bytes, sparkline: true
      column :peak_footprint, label: "Peak", format: :bytes
      column :cpu_seconds, label: "CPU s", format: :number
      column :bytes_written, label: "Written", format: :bytes
      column :read_rate, label: "Read", format: :bytes_per_sec
      column :write_rate, label: "Write", format: :bytes_per_sec
      column :age, label: "Age", width: 7, align: :right # fixed, so the label takes the spare width
    end

    filter :label, :cwd
  end

  # Network columns, on performance views only (--layout): the default dashboard keeps its columns.
  extend_resource :session do |_engine|
    next unless Agentmon::Views.installing

    column :net_in_rate, label: "Net in", format: :bytes_per_sec
    column :net_out_rate, label: "Net out", format: :bytes_per_sec
    column :bytes_in, label: "Recv", format: :bytes
    column :bytes_out, label: "Sent", format: :bytes
    column :connections, label: "Conns", format: :integer
    column :remote_hosts, label: "Hosts", format: :integer
  end

  panel :session, row: :top, order: 20, span: 2

  # r2ui focuses the first table panel, which is now Sessions (top row). Keys and the first
  # frame belong to Processes, so give it focus when the agentmon dashboard starts. Stopgap
  # until the core focuses :process itself.
  R2UI.extension :agentmon_sessions_focus do
    setup do
      process = dashboard.name == UI::DASHBOARD && dashboard.panels.find { |p| p.name == :process }
      app.focus = process if process
    end
  end
end
