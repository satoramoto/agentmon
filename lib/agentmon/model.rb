# frozen_string_literal: true

module Agentmon
  # The data model: every value that crosses a file boundary (a probe's output, a metric's output,
  # a store record) is one of these. Stories build against these shapes, so they can be written in
  # parallel; changing one is a contract change (docs/design.md).
  #
  # Units, everywhere:
  #   sizes and cumulative I/O   bytes (Integer)
  #   rates                      bytes per second (Float)
  #   CPU time                   seconds (Float), never Mach ticks
  #   CPU usage                  percent of one core (Float): 250.0 is two and a half cores busy
  #   instants                   epoch seconds (Float); intervals use the monotonic clock
  #   nil                        unknown (unreadable, or not measured yet), never 0

  # One probe pass: what every probe returned at one instant. `parts[:processes]` and so on.
  # `errors` maps a probe that raised to its message (its part keeps the previous value).
  Sample = Data.define(:at, :mono, :parts, :errors) do
    def initialize(at:, mono:, parts:, errors: {}) = super

    def [](name) = parts[name]
  end

  # probes/processes.rb: one process. Cumulative counters are since the process started.
  # `readable` is false for processes the kernel won't describe to us (root daemons): then only
  # the ps fields (pid, ppid, path, resident, ps_cpu) are set and the rest are nil.
  ProcessStat = Data.define(
    :pid, :ppid,
    :name,            # basename of the executable
    :path,            # executable path as ps reports it (comm)
    :readable,        # rusage was readable
    :start_ticks,     # Mach ticks at start: [pid, start_ticks] survives pid reuse (nil if unreadable)
    :started_at,      # epoch seconds (nil if unreadable)
    :cpu_time,        # own user+system seconds
    :child_cpu_time,  # user+system seconds of children it has reaped
    :resident,        # bytes (rusage, or ps rss when unreadable)
    :footprint,       # physical footprint, bytes: what Activity Monitor calls Memory
    :peak_footprint,  # lifetime max footprint, bytes
    :disk_read,       # cumulative bytes
    :disk_written,    # cumulative bytes
    :ps_cpu           # ps %cpu (a decaying average): the fallback when rusage is unreadable
  ) do
    def identity = [pid, start_ticks]
  end

  # metrics/process_rates.rb output, per pid: rates between the previous sample and this one.
  # A process seen for the first time (or unreadable) has ps's %cpu and nil disk rates.
  ProcessRates = Data.define(:cpu, :read_rate, :write_rate)

  # metrics/sessions.rb: who an agent session is. `kind` is :cli (an outermost claude/codex CLI
  # process) or :app (a desktop app and all its helpers). `id` is stable across agentmon runs:
  # "claude-4242-1790711088" (name, root pid, root start second).
  SessionInfo = Data.define(:id, :kind, :name, :root_pid, :label, :cwd, :started_at)

  # metrics/sessions.rb output: the sessions alive in this sample and which one each pid is in.
  SessionMap = Data.define(:sessions, :by_pid) do
    def of(pid) = (id = by_pid[pid]) && sessions.find { |s| s.id == id }
  end

  # metrics/session_ledger.rb output (one per session, alive or ended in the last
  # SessionLedger::KEEP_ENDED seconds). Current values are 0 once it has ended.
  Session = Data.define(
    :id, :kind, :name, :root_pid, :label, :cwd,
    :started_at,      # the root process's start (epoch), or first_seen_at when unknown
    :first_seen_at,   # when agentmon first saw it
    :last_seen_at,    # last sample it was alive in
    :ended_at,        # nil while alive
    :processes,       # live member processes
    :cpu,             # percent, now
    :footprint,       # bytes, now (readable members only)
    :resident,        # bytes, now
    :read_rate,       # bytes/s, now
    :write_rate,      # bytes/s, now
    :peak_footprint,  # max footprint seen over its life (bytes)
    :cpu_seconds,     # CPU seconds over its life, reaped children included (see design.md)
    :bytes_read,      # disk bytes read by members while observed (a lower bound)
    :bytes_written    # disk bytes written by members while observed (a lower bound)
  ) do
    def alive? = ended_at.nil?

    def duration = (ended_at || last_seen_at) - (started_at || first_seen_at)

    # The store line for kind "sessions" (docs/design.md, "Store").
    def to_record = to_h.merge(kind: kind.to_s)
  end

  # metrics/process_rows.rb output: one row per process for tables (dashboard and CLI).
  ProcessRow = Data.define(
    :pid, :ppid, :name, :path, :cwd,
    :session,         # session label, nil when it isn't in an agent session
    :session_id,
    :cpu,             # percent (rusage delta, or ps %cpu when unreadable or first seen)
    :footprint, :resident, :peak_footprint,  # bytes
    :read_rate, :write_rate,                 # bytes/s, nil until two samples
    :cpu_time, :disk_written,                # seconds, bytes (cumulative)
    :started_at, :readable
  )

  # probes/memory.rb (story a01): the machine's memory counters. Sizes in bytes; the counters
  # (swapins .. pageins) are cumulative bytes since boot (pages x page size).
  MemoryStat = Data.define(
    :total,              # hw.memsize
    :free,
    :app,                # anonymous (internal) pages minus purgeable
    :wired,
    :compressed,         # pages occupied by the compressor
    :compressor_stored,  # uncompressed bytes held in the compressor
    :cached,             # file-backed + purgeable
    :purgeable,
    :swap_total, :swap_used,
    :swapins, :swapouts, :compressions, :decompressions, :pageins,
    :memorystatus_level  # kern.memorystatus_level: percent of memory available (100 = no pressure)
  )

  # metrics/memory.rb (story a02): Activity Monitor's breakdown plus rates and pressure.
  MemoryView = Data.define(
    :total, :used, :app, :wired, :compressed, :cached, :free, :swap_used, :swap_total,
    :compression_ratio,  # compressor_stored / compressed (e.g. 3.1)
    :swapin_rate, :swapout_rate, :compression_rate, :decompression_rate,  # bytes/s
    :pressure,           # percent: 100 - memorystatus_level
    :pressure_trend      # recent pressure values, oldest first (Array of Float)
  )

  # metrics/pressure_drivers.rb (story a03): sessions ranked by how much they push memory.
  PressureDriver = Data.define(
    :session_id, :label,
    :footprint,     # bytes now
    :share,         # percent of used memory
    :growth_rate    # bytes/s of footprint change over the last minute
  )
end
