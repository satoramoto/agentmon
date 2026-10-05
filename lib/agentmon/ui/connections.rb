# frozen_string_literal: true

# The :connection resource: the network flows of agent-session processes that have a concrete
# remote end, one line each, busiest upload first. No panel of its own: layouts place it with
# `top :connection`. Follows session focus (the reading is already narrowed).
#
#   Process          Proto  Remote                         State         In     Out   Recv   Sent
#   claude 4242      tcp4   api.anthropic.com:443          ESTABLISHED  2.0K/s 12K/s   1.5M   9.0M
#   node 4310        tcp6   …ample-long-host.internal:8443 ESTABLISHED  0B/s    0B/s   10K    2K
#
# Remote is the host and port as the probe printed them, cut from the left when long (the port and
# domain matter more than a subdomain). Search with / (`remote~anthropic`, `state~CLOSE`).
module Agentmon
  module UI
    module ConnectionsPanel
      REMOTE_WIDTH = 30

      module_function

      # reading[:connections] as rows; none while network data is unavailable.
      def rows(reading)
        (reading[:connections] || []).map { |c| row(c) }
      end

      def row(conn)
        {
          id: key(conn),
          pid: conn.pid,
          name: conn.name,
          process: "#{conn.name} #{conn.pid}",
          session_id: conn.session_id,
          session: conn.session,
          protocol: conn.protocol,
          local: conn.local,
          remote: conn.remote,
          remote_text: cut_left(conn.remote.to_s, REMOTE_WIDTH),
          interface: conn.interface,
          state: conn.state,
          in_rate: conn.in_rate,
          out_rate: conn.out_rate,
          bytes_in: conn.bytes_in,
          bytes_out: conn.bytes_out
        }
      end

      # Stable across samples while the flow lives: "pid|protocol|local|remote".
      def key(conn) = [conn.pid, conn.protocol, conn.local, conn.remote].join("|")

      # `text` fitted to `width` columns, dropping its start ("…" marks the cut).
      def cut_left(text, width)
        text.length > width ? "…#{text[-(width - 1)..]}" : text
      end
    end
  end

  resource :connection do |engine|
    title "Connections"
    source { UI::ConnectionsPanel.rows(engine.current) }
    refresh every: engine.interval
    key :id

    index do
      column :process, label: "Process"
      column :protocol, label: "Proto", width: 5
      column :remote_text, label: "Remote", width: UI::ConnectionsPanel::REMOTE_WIDTH
      column :state, label: "State", width: 11
      column :in_rate, label: "In", format: :bytes_per_sec
      column :out_rate, label: "Out", format: :bytes_per_sec, sort: :desc
      column :bytes_in, label: "Recv", format: :bytes
      column :bytes_out, label: "Sent", format: :bytes
    end

    filter :name, :remote, :state
  end
end
