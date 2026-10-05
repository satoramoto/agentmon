# frozen_string_literal: true

require "pty"

module Agentmon
  # sample[:network]: every process's sockets and byte counters, as a NetSnapshot (model.rb), from
  # ONE long-lived `nettop` child. Nil until its first block arrives, when the latest block is older
  # than STALE seconds (nettop stalled), and off macOS.
  #
  # nettop in connection mode (`-x -L 0 -s 1 -J interface,state,bytes_in,bytes_out`, no -P) prints
  # one block a second: a header line `,interface,state,bytes_in,bytes_out,`, then per process a
  # line `Name With Spaces.PID,,,BYTES_IN,BYTES_OUT,` followed by its flows:
  #
  #   tcp4 192.0.2.5:55584<->198.51.100.11:5223,en0,Established,3177530,7189392,
  #   udp4 *:5353<->*:*,en0,,4823549,2970949,
  #   tcp6 fe80::1%lo0.53<->*.*,lo0,Listen,,,
  #
  # IPv6 endpoints put `.` before the port, IPv4 (and host names) `:`; `*` is a wildcard; empty byte
  # fields are unknown (nil). Byte counts are cumulative. A one-shot `nettop -L 1` takes ~5 s, so it
  # is never run per sample or per process.
  #
  # Piped, nettop block-buffers its output (nothing for many seconds), so the child runs under a pty
  # (PTY.spawn), where each block arrives at once. A reader thread parses lines and publishes each
  # complete block, frozen, as soon as the next header arrives or the pty has been idle for IDLE
  # seconds. `at_mono` is when the block's header arrived, so rates come from the snapshots' own
  # clock whatever the engine's interval. The child starts on the first probe call, restarts at most
  # once every RESTART_EVERY seconds when it dies (MISSING_RETRY when nettop is missing), and is
  # stopped (TERM, KILL after KILL_AFTER, then reaped) by an at_exit hook or Stream#stop.
  module Probes
    module Network
      COMMAND = %w[/usr/bin/nettop -x -L 0 -s 1 -J interface,state,bytes_in,bytes_out].freeze

      module_function

      # Every block in captured nettop text, as NetSnapshots (the last one even when its block is
      # cut short). Block i gets at_mono `at_mono + i * every`. Pure; tests feed it fixtures.
      def parse(text, at_mono: 0.0, every: 1.0)
        parser = Parser.new
        blocks = -1
        snapshots = text.each_line.filter_map do |line|
          blocks += 1 if Parser.header?(line)
          parser.feed(line, at_mono + (blocks * every))
        end
        last = parser.flush
        last ? snapshots << last : snapshots
      end

      # The process's one stream.
      def stream = @stream ||= Stream.new

      # The probe: the latest snapshot, starting nettop when needed. Never raises into the sampler.
      def read
        Darwin.available? ? stream.snapshot : nil
      rescue StandardError
        nil
      end

      # Turns nettop lines into NetSnapshots, one block at a time. Not thread-safe: one feeder.
      class Parser
        HEADER = /\A,interface,/

        def self.header?(line) = HEADER.match?(line)

        def initialize
          @block = nil   # { at_mono:, processes: { pid => builder Hash } }
          @current = nil # the process the next flow lines belong to
          @dirty = false # changed since the last snapshot handed out
        end

        # Feeds one line; returns the previous block's snapshot when this line is the header that
        # closes it (and it changed since it was last handed out), else nil. Lines before the first
        # header (a block we joined midway) are dropped.
        def feed(line, at_mono)
          line = line.delete("\r\n")
          return nil if line.empty?

          if self.class.header?(line)
            done = flush
            @block = { at_mono:, processes: {} }
            @current = nil
            @dirty = true
            return done
          end
          return nil unless @block

          add(line)
          nil
        end

        # The block so far as a snapshot, if it changed since the last one handed out; else nil.
        def flush
          return nil unless @block && @dirty

          @dirty = false
          snapshot
        end

        private

        def add(line)
          head, interface, state, bytes_in, bytes_out = fields(line)
          return unless head

          if head.include?("<->")
            return unless @current

            @current[:flows] << flow(head, interface, state, bytes_in, bytes_out)
          else
            name, dot, pid = head.rpartition(".")
            pid = Integer(pid, 10, exception: false)
            return if dot.empty? || pid.nil?

            @current = @block[:processes][pid] = { pid:, name:, bytes_in: count(bytes_in),
                                                   bytes_out: count(bytes_out), flows: [] }
          end
          @dirty = true
        end

        # [first field, interface, state, bytes_in, bytes_out]; the first field may hold commas.
        def fields(line)
          parts = line.split(",", -1)
          parts.pop if line.end_with?(",")
          return nil if parts.size < 5

          [parts[0...-4].join(","), *parts[-4..]]
        end

        def flow(head, interface, state, bytes_in, bytes_out)
          protocol, endpoints = head.split(" ", 2)
          local, remote = endpoints.to_s.split("<->", 2)
          host, port = Network.endpoint(remote, protocol)
          NetFlow.new(protocol:, local:, remote:, remote_host: host, remote_port: port,
                      interface: blank(interface), state: blank(state), bytes_in: count(bytes_in),
                      bytes_out: count(bytes_out))
        end

        def snapshot
          processes = @block[:processes].transform_values do |p|
            NetProcess.new(**p.except(:flows), flows: p[:flows].dup.freeze)
          end
          NetSnapshot.new(at_mono: @block[:at_mono], processes: processes.freeze)
        end

        def count(text) = text.nil? || text.empty? ? nil : Integer(text, 10, exception: false)

        def blank(text) = text.nil? || text.empty? ? nil : text
      end

      # [host, port] of an endpoint as nettop prints it: IPv6 (`protocol` ending in 6) separates the
      # port with the last `.`, IPv4 and names with `:`. `*` (either part) is nil.
      def endpoint(text, protocol)
        return [nil, nil] if text.nil? || text.empty?

        separators = protocol.to_s.end_with?("6") ? [".", ":"] : [":", "."]
        host, port = nil
        separators.each do |sep|
          h, s, p = text.rpartition(sep)
          next if s.empty?

          host = h
          port = p
          break
        end
        host ||= text
        host = nil if host == "*"
        port = port.nil? || port == "*" ? nil : Integer(port, 10, exception: false)
        [host, port]
      end

      # The nettop child and its reader thread. `feed`/`idle` are the reader's entry points, public
      # so tests drive publishing without spawning.
      class Stream
        IDLE = 0.05           # seconds of pty silence that end a block
        STALE = 5.0           # a snapshot older than this is not returned
        RESTART_EVERY = 10.0  # seconds between starts when the child keeps dying
        MISSING_RETRY = 60.0  # seconds between tries when nettop is missing
        KILL_AFTER = 1.0      # seconds between TERM and KILL on stop

        attr_reader :pid

        def initialize(command: COMMAND, clock: -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) })
          @command = command
          @clock = clock
          @parser = Parser.new
          @latest = nil
          @next_start = nil
          @lock = Mutex.new
        end

        # The probe's call: starts (or restarts) nettop when due, returns the latest fresh snapshot.
        def snapshot
          @lock.synchronize { ensure_running }
          latest
        end

        # The latest published snapshot, or nil when none yet or it is older than STALE.
        def latest
          snap = @latest
          snap if snap && @clock.call - snap.at_mono <= STALE
        end

        # One line from nettop (the reader thread, or a test).
        def feed(line) = publish(@parser.feed(line, @clock.call))

        # The pty went quiet: the block so far is complete.
        def idle = publish(@parser.flush)

        def running? = !@pid.nil? && !reaped?(@pid)

        def start
          now = @clock.call
          unless File.executable?(@command.first)
            @next_start = now + MISSING_RETRY
            return false
          end

          @next_start = now + RESTART_EVERY
          @parser = Parser.new
          reader, writer, @pid = PTY.spawn(*@command)
          writer.close
          @reader = reader
          @thread = Thread.new { read_loop(reader) }
          @thread.report_on_exception = false
          register_exit_hook
          true
        rescue SystemCallError
          @next_start = now + MISSING_RETRY
          false
        end

        # Stops the child (TERM, then KILL after KILL_AFTER) and reaps it; safe to call twice.
        def stop
          @lock.synchronize do
            pid = @pid
            @pid = nil
            terminate(pid) if pid
            begin
              @reader&.close
            rescue IOError
              nil
            end
            @thread&.join(1)
            @thread = nil
            @reader = nil
            @next_start = nil
          end
        end

        private

        def ensure_running
          return if running?
          return if @next_start && @clock.call < @next_start

          start
        end

        def publish(snap)
          @latest = snap if snap
          snap
        end

        def read_loop(io)
          buffer = String.new(encoding: Encoding::BINARY)
          loop do
            unless io.wait_readable(IDLE)
              idle
              next
            end
            chunk = io.read_nonblock(65_536, exception: false)
            next if chunk == :wait_readable
            break if chunk.nil?

            buffer << chunk
            while (i = buffer.index("\n"))
              feed(buffer.slice!(0..i).force_encoding(Encoding::UTF_8).scrub)
            end
          end
        rescue IOError, SystemCallError # Errno::EIO when the child exits; IOError when stop closes it
          nil
        ensure
          idle
        end

        # True when `pid` has exited (and is now reaped).
        def reaped?(pid)
          !Process.waitpid(pid, Process::WNOHANG).nil?
        rescue Errno::ECHILD
          true
        end

        def terminate(pid)
          signal(:TERM, pid)
          deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + KILL_AFTER
          until reaped?(pid)
            if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline
              signal(:KILL, pid)
              begin
                Process.waitpid(pid)
              rescue Errno::ECHILD
                nil
              end
              break
            end
            sleep 0.01
          end
        end

        def signal(name, pid)
          Process.kill(name, pid)
        rescue Errno::ESRCH, Errno::EPERM
          nil
        end

        def register_exit_hook
          return if @exit_hook

          @exit_hook = true
          at_exit { stop }
        end
      end
    end
  end

  probe(:network) { Probes::Network.read }
end
