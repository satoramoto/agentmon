# frozen_string_literal: true

# `agentmon record`: keeps a history of agent sessions without the dashboard open. Samples every
# `--interval` seconds with recording on, so every recorder (sessions, memory, ...) appends to the
# store (`$AGENTMON_STATE_DIR`, else `~/.local/state/agentmon`), until ctrl+c or TERM.
#
#   agentmon record                     on a terminal: one live status line, redrawn in place
#   agentmon record --interval 5        sample every 5 s instead of 2
#   agentmon record --prune 14          first delete day files older than 14 days
#   agentmon record > record.log        off a terminal: one status line a minute
#
#   recording 3 sessions to /Users/me/.local/state/agentmon
#
# TERM (launchd, `kill`) exits 0 and ctrl+c exits 130, both after the current sample: every store
# line is complete and on disk (each append closes its file). `agentmon report` reads the history.
module Agentmon
  module Commands
    module Record
      # Seconds between status lines off a terminal.
      STATUS_EVERY = 60
      # Exit code per signal that stops recording.
      SIGNALS = { "TERM" => 0, "INT" => 130 }.freeze

      # The stop flag the signal handlers raise. `request` only writes to a pipe, which is safe in a
      # trap handler; `wait` sleeps until the timeout or a request, whichever comes first.
      class Stop
        attr_reader :signal

        def initialize
          @reader, @writer = IO.pipe
        end

        def request(signal)
          @signal ||= signal
          @writer.write_nonblock(".", exception: false)
        end

        def requested? = !@signal.nil?

        def wait(seconds)
          @reader.wait_readable(seconds) if seconds.positive? && !requested?
          requested?
        end

        def close = [@reader, @writer].each(&:close)
      end

      module_function

      # "recording 3 sessions to <dir>"; without the session ledger (nil), just "recording to <dir>".
      def status(reading, store)
        sessions = reading[:session_ledger]
        count = sessions && " #{R2UI::CLI::Ext::HumanFormat.plural(sessions.count(&:alive?), "session")}"
        "recording#{count} to #{store.dir}"
      end

      # Samples every `interval` seconds with recording on until `stop` is requested: a live status
      # line on a terminal, a plain one every STATUS_EVERY seconds off it. Returns the signal.
      def run(engine, shell:, interval:, stop:, clock: Clock, status_every: STATUS_EVERY)
        was = engine.recording
        engine.recording = true
        line = "recording to #{engine.store.dir}"
        live = R2UI::CLI::Live.new(shell, fps: 2) { |frame| "#{R2UI::CLI::Live.spinner(frame)} #{line}" }
        next_status = nil
        live.run do
          until stop.requested?
            started = clock.mono
            line = status(engine.current(max_age: 0), engine.store)
            if live.live?
              live.refresh
            elsif next_status.nil? || started >= next_status
              shell.puts(line)
              next_status = started + status_every
            end
            stop.wait(interval - (clock.mono - started))
          end
        end
        stop.signal
      ensure
        engine.recording = was
      end
    end
  end

  command :record do
    summary "Record agent sessions to the history until ctrl+c or TERM"
    option :interval, :float, default: 2.0, desc: "Seconds between samples"
    option :prune, :integer, desc: "First delete day files older than this many days"

    run do
      record = Commands::Record
      usage_error!("--interval must be more than 0") unless options[:interval].positive?
      usage_error!("--prune must be at least 1 day") if options[:prune] && options[:prune] < 1
      engine = Agentmon.engine
      abort!("no store to record to") unless engine.store
      if options[:prune]
        removed = engine.store.prune(days: options[:prune])
        plural = R2UI::CLI::Ext::HumanFormat.method(:plural)
        shell.puts("pruned #{plural.call(removed.size, "day file")} older than #{plural.call(options[:prune], "day")}")
      end

      stop = record::Stop.new
      previous = record::SIGNALS.keys.to_h { |sig| [sig, Signal.trap(sig) { stop.request(sig) }] }
      begin
        signal = record.run(engine, shell:, interval: options[:interval], stop:)
      ensure
        previous.each { |sig, handler| Signal.trap(sig, handler || "DEFAULT") }
        stop.close
      end
      code = record::SIGNALS.fetch(signal, 0)
      next if code.zero?

      # halt skips the after_run hooks, so report what's broken here, as they would.
      engine.errors.each { |name, message| shell.err_puts("#{shell.symbol(:warn)} #{name}: #{message}") }
      halt(code)
    end
  end
end
