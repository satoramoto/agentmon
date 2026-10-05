# frozen_string_literal: true

require "ipaddr"

# Per-process and per-session network, from the nettop snapshots in sample[:network]
# (probes/network.rb). Every metric here is nil while sample[:network] is nil (no snapshot yet,
# nettop stalled or missing, off macOS): unknown, never 0.
#
# reading[:net_rates]: { pid => NetRates or nil }, bytes/s between the previous nettop snapshot and
#   this one, over the snapshots' own at_mono (nettop runs at 1 s, the engine at 2 s). A pid's rate
#   needs the same process as before: the same start_ticks in sample[:processes] and the same
#   nettop name; a reused pid, a first sighting, or a counter that went down is nil. A process in
#   the sample with no nettop line has no sockets: 0.0. When the sample carries the very snapshot
#   the previous one did (nettop hasn't printed since), the previous rates are kept.
#
# reading[:session_network]: one SessionNetwork per session in reading[:sessions], each pid counted
#   once (SessionMap#by_pid). Rates sum the members' known rates (members without sockets add
#   0.0; nil when none is known). bytes_in/bytes_out add each member's positive counter growth while
#   agentmon watched it (a first sighting adds 0, so these are lower bounds). Trends keep the last
#   TREND known rates. connections counts member flows with a concrete remote; remote_hosts counts
#   distinct remote hosts, loopback and link-local left out.
#
# Anomaly rule (flags; [] is normal), checked each time a new snapshot arrives:
#   :out_spike   out_rate >= SPIKE_FACTOR (8) x the median of the session's previous BASELINE (30)
#                known out_rate values, and >= SPIKE_FLOOR (1 MiB/s), with at least BASELINE_MIN (5)
#                previous values
#   :in_spike    the same for in_rate
#   :many_hosts  remote_hosts >= MANY_HOSTS (20)
#
# reading[:connections]: one ConnectionRow per flow of a process in an agent session with a
#   concrete remote (no `*` wildcard, not Listen), in nettop's order, with per-flow rates matched on
#   (process identity, protocol, local, remote) between snapshots (nil the first time).
module Agentmon
  module Metrics
    module Network
      TREND = 120
      SPIKE_FACTOR = 8.0
      SPIKE_FLOOR = 1024.0 * 1024 # bytes/s
      BASELINE = 30
      BASELINE_MIN = 5
      MANY_HOSTS = 20
      NO_SOCKETS = NetRates.new(in_rate: 0.0, out_rate: 0.0)

      module_function

      # --- reading[:net_rates] ---

      def rates(snap, processes, state)
        return nil unless snap

        ids = identities(processes)
        prev = state[:snap]
        if prev && prev.at_mono == snap.at_mono && state[:rates]
          rates = state[:rates].dup
        else
          rates = between(snap, prev, ids, state[:ids] || {})
          state.merge!(snap:, ids:, rates:)
          rates = rates.dup
        end
        ids.each_key { |pid| rates[pid] = NO_SOCKETS unless rates.key?(pid) || snap.processes.key?(pid) }
        rates.freeze
      end

      def between(snap, prev, ids, prev_ids)
        seconds = prev && (snap.at_mono - prev.at_mono)
        snap.processes.to_h do |pid, now|
          was = prev&.processes&.[](pid)
          same = was && seconds&.positive? && was.name == now.name && ids[pid] == prev_ids[pid]
          next [pid, nil] unless same

          in_rate = rate(now.bytes_in, was.bytes_in, seconds)
          out_rate = rate(now.bytes_out, was.bytes_out, seconds)
          [pid, in_rate.nil? && out_rate.nil? ? nil : NetRates.new(in_rate:, out_rate:)]
        end
      end

      # --- reading[:session_network] ---

      def sessions(snap, map, rates, processes, state)
        return nil unless snap && map

        rates ||= {}
        ids = identities(processes)
        fresh = state[:at] != snap.at_mono
        state[:at] = snap.at_mono
        members = map.by_pid.each_with_object(Hash.new { |h, k| h[k] = [] }) { |(pid, id), m| m[id] << pid }
        seen = state[:seen] || {}
        next_seen = seen.select { |(pid, ticks, _), _| ids.key?(pid) && ids[pid] == ticks }
        totals = state[:totals] ||= {}
        trends = state[:trends] ||= {}
        spikes = state[:spikes] ||= {}

        rows = map.sessions.map do |info|
          pids = members[info.id]
          procs = pids.filter_map { |pid| snap.processes[pid] }
          total = totals[info.id] ||= [0, 0]
          count_bytes(procs, ids, seen, next_seen, total) if fresh
          in_rate = sum(pids, :in_rate, rates, snap)
          out_rate = sum(pids, :out_rate, rates, snap)
          trend = trends[info.id] ||= { in: [], out: [] }
          if fresh
            spikes[info.id] = [(:out_spike if spike?(out_rate, trend[:out])),
                               (:in_spike if spike?(in_rate, trend[:in]))].compact
            push(trend[:in], in_rate)
            push(trend[:out], out_rate)
          end
          flows = procs.flat_map(&:flows).select(&:remote_host)
          hosts = flows.map(&:remote_host).reject { |h| local_host?(h) }.uniq.size
          flags = [*spikes[info.id], (:many_hosts if hosts >= MANY_HOSTS)].compact
          SessionNetwork.new(session_id: info.id, label: info.label, in_rate:, out_rate:,
                             bytes_in: total[0], bytes_out: total[1], in_trend: trend[:in].dup.freeze,
                             out_trend: trend[:out].dup.freeze, connections: flows.size, remote_hosts: hosts,
                             flags: flags.freeze)
        end

        state[:seen] = next_seen if fresh
        alive = map.sessions.to_h { |s| [s.id, true] }
        [totals, trends, spikes].each { |h| h.select! { |id, _| alive[id] } }
        rows
      end

      # Adds each member's counter growth since it was last seen (first sighting: 0) to `total`.
      def count_bytes(procs, ids, seen, next_seen, total)
        procs.each do |np|
          key = [np.pid, ids[np.pid], np.name]
          was = seen[key]
          if was
            total[0] += growth(np.bytes_in, was[0])
            total[1] += growth(np.bytes_out, was[1])
          end
          next_seen[key] = [np.bytes_in || was&.[](0), np.bytes_out || was&.[](1)]
        end
      end

      # Sum of the members' known rates; a member with no nettop line has no sockets (0.0).
      def sum(pids, field, rates, snap)
        known = pids.filter_map do |pid|
          if rates.key?(pid) then rates[pid]&.public_send(field)
          elsif !snap.processes.key?(pid) then 0.0
          end
        end
        known.empty? ? nil : known.sum.to_f
      end

      def spike?(value, history)
        return false if value.nil?

        base = history.last(BASELINE)
        base.size >= BASELINE_MIN && value >= SPIKE_FLOOR && value >= SPIKE_FACTOR * median(base)
      end

      def median(values)
        sorted = values.sort
        mid = sorted.size / 2
        sorted.size.odd? ? sorted[mid] : (sorted[mid - 1] + sorted[mid]) / 2.0
      end

      # --- reading[:connections] ---

      def connections(snap, map, processes, state)
        return nil unless snap && map

        ids = identities(processes)
        labels = map.sessions.to_h { |s| [s.id, s.label] }
        prev = state[:snap]
        same = prev && prev.at_mono == snap.at_mono
        seconds = prev && !same ? snap.at_mono - prev.at_mono : nil
        prev_bytes = state[:bytes] || {}
        prev_rates = state[:rates] || {}
        bytes = {}
        new_rates = {}

        rows = snap.processes.flat_map do |pid, np|
          session_id = map.by_pid[pid] or next []
          np.flows.filter_map do |f|
            next unless f.remote_host && f.state != "Listen"

            key = [pid, ids[pid], np.name, f.protocol, f.local, f.remote]
            bytes[key] = [f.bytes_in, f.bytes_out]
            in_rate, out_rate = new_rates[key] =
              if same
                prev_rates[key] || [nil, nil]
              elsif (was = prev_bytes[key]) && seconds&.positive?
                [rate(f.bytes_in, was[0], seconds), rate(f.bytes_out, was[1], seconds)]
              else
                [nil, nil]
              end
            ConnectionRow.new(pid:, name: np.name, session_id:, session: labels[session_id], protocol: f.protocol,
                              local: f.local, remote: f.remote, remote_host: f.remote_host,
                              remote_port: f.remote_port, interface: f.interface, state: f.state,
                              bytes_in: f.bytes_in, bytes_out: f.bytes_out, in_rate:, out_rate:)
          end
        end

        state.merge!(snap:, bytes:, rates: new_rates) unless same
        rows
      end

      # --- shared ---

      # pid => start_ticks (nil for unreadable processes: then the nettop name has to match alone).
      def identities(processes) = (processes || []).to_h { |p| [p.pid, p.start_ticks] }

      # Bytes/s between two cumulative counts; nil when either is unknown or it went down.
      def rate(now, was, seconds)
        return nil if now.nil? || was.nil? || now < was

        (now - was) / seconds.to_f
      end

      def growth(now, was) = now && was && now > was ? now - was : 0

      def push(trend, value)
        return if value.nil?

        trend << value
        trend.shift while trend.size > TREND
      end

      # Loopback (127/8, ::1, localhost) or link-local (169.254/16, fe80::/10) hosts.
      def local_host?(host)
        address = host.sub(/%.*\z/, "")
        return true if address == "localhost"

        ip = IPAddr.new(address)
        ip.loopback? || ip.link_local?
      rescue IPAddr::Error
        false
      end
    end
  end

  metric(:net_rates) do |reading, state|
    Metrics::Network.rates(reading.sample[:network], reading.sample[:processes], state)
  end

  metric(:session_network) do |reading, state|
    Metrics::Network.sessions(reading.sample[:network], reading[:sessions], reading[:net_rates],
                              reading.sample[:processes], state)
  end

  metric(:connections) do |reading, state|
    Metrics::Network.connections(reading.sample[:network], reading[:sessions], reading.sample[:processes], state)
  end
end
