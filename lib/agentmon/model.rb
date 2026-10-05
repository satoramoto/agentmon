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
    :ps_cpu,          # ps %cpu (a decaying average): the fallback when rusage is unreadable
    # Paging and scheduling, from the same two calls per process (rusage, PROC_PIDTASKALLINFO).
    # nil when unreadable. Counts are cumulative event counts (Integer), not bytes.
    :wired,           # wired (unpageable) bytes now
    :pageins,         # count of faults that had to read a page from disk (rusage ri_pageins)
    :faults,          # count of page faults of any kind (pti_faults: a 32-bit kernel counter, wraps)
    :cow_faults,      # count of copy-on-write faults (pti_cow_faults: 32-bit, wraps)
    :context_switches, # count (pti_csw: 32-bit, wraps)
    :runnable_time,   # seconds its threads were runnable: on a CPU *or waiting for one*
                      # (ri_runnable_time). Time spent waiting to run = runnable_time - cpu_time
    :threads,         # threads now
    :running_threads  # threads running now
  ) do
    # The paging and scheduling fields default to nil (unknown), so code written before they
    # existed, and fixtures that don't care, still build ProcessStats.
    def initialize(wired: nil, pageins: nil, faults: nil, cow_faults: nil, context_switches: nil, runnable_time: nil,
                   threads: nil, running_threads: nil, **) = super

    def identity = [pid, start_ticks]
  end

  # metrics/process_rates.rb output, per pid: rates between the previous sample and this one.
  # A process seen for the first time (or unreadable) has ps's %cpu and nil for every other rate.
  ProcessRates = Data.define(
    :cpu,                    # percent of one core
    :read_rate, :write_rate, # disk bytes/s
    :pagein_rate,            # pageins/s: each one waited for the disk (the closest thing to I/O wait)
    :fault_rate,             # page faults/s
    :cow_fault_rate,         # copy-on-write faults/s
    :context_switch_rate,    # context switches/s
    :run_wait                # percent of one core spent runnable but not running, i.e. waiting for
                             # a CPU: (Δrunnable_time - Δcpu_time) / interval x 100
  ) do
    def initialize(pagein_rate: nil, fault_rate: nil, cow_fault_rate: nil, context_switch_rate: nil, run_wait: nil,
                   **) = super
  end

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
    :started_at, :readable,
    # Paging and scheduling (from ProcessStat and ProcessRates); nil when unreadable or before two
    # samples. Optional, so rows built without them still work.
    :disk_read,                              # bytes (cumulative)
    :wired,                                  # bytes now
    :pageins, :faults, :cow_faults, :context_switches, # counts (cumulative)
    :runnable_time,                          # seconds (cumulative), time on a CPU included
    :threads, :running_threads,              # counts now
    :pagein_rate, :fault_rate, :cow_fault_rate, :context_switch_rate, # per second
    :run_wait,                               # percent of one core spent waiting for a CPU
    # Network (metrics/network.rb, from nettop); nil when unknown (no snapshot yet, first sighting).
    :net_in_rate, :net_out_rate              # bytes/s received / sent over all its sockets
  ) do
    def initialize(disk_read: nil, wired: nil, pageins: nil, faults: nil, cow_faults: nil, context_switches: nil,
                   runnable_time: nil, threads: nil, running_threads: nil, pagein_rate: nil, fault_rate: nil,
                   cow_fault_rate: nil, context_switch_rate: nil, run_wait: nil, net_in_rate: nil,
                   net_out_rate: nil, **) = super
  end

  # probes/network.rb: one socket (flow) of a process as one `nettop -x -L 0` line prints it.
  NetFlow = Data.define(
    :protocol,     # "tcp4", "udp6", "quic4", ...
    :local,        # local endpoint as nettop prints it: "192.0.2.5:55584" (IPv4 `:` port),
    :remote,       # "2001:db8::1.443" (IPv6 `.` port), "*:*" / "*.*" wildcards
    :remote_host,  # remote address or name without the port; nil for the `*` wildcard
    :remote_port,  # Integer, nil for `*`
    :interface,    # "en0", "lo0"; nil when nettop leaves it empty
    :state,        # "Established", "Listen", ...; nil for stateless (UDP) or empty
    :bytes_in,     # cumulative bytes received on this flow; nil when nettop leaves it empty
    :bytes_out     # cumulative bytes sent, likewise
  )

  # probes/network.rb: one process's sockets in one nettop block.
  NetProcess = Data.define(
    :pid,
    :name,         # nettop's (truncated) process name
    :bytes_in,     # cumulative bytes received, as nettop counts them for the process
    :bytes_out,    # cumulative bytes sent
    :flows         # Array of NetFlow
  )

  # probes/network.rb: one complete nettop block (sample[:network]).
  NetSnapshot = Data.define(
    :at_mono,      # monotonic seconds when the block's header arrived (rates use these)
    :processes     # { pid => NetProcess }; a process without sockets has no entry
  )

  # metrics/network.rb reading[:net_rates], per pid: between the two latest nettop snapshots.
  NetRates = Data.define(:in_rate, :out_rate) # bytes/s; nil when unknown

  # metrics/network.rb reading[:session_network]: one alive session's network, each pid once.
  SessionNetwork = Data.define(
    :session_id, :label,
    :in_rate, :out_rate,   # bytes/s now, summed over members (nil when no member's rate is known)
    :bytes_in, :bytes_out, # cumulative bytes received / sent by members while agentmon observed them
    :in_trend, :out_trend, # the last 120 known rates (bytes/s), oldest first
    :connections,          # count of member flows with a concrete remote (not `*`)
    :remote_hosts,         # count of distinct remote hosts, loopback and link-local left out
    :flags                 # Array of Symbols from the anomaly rule (:out_spike, :in_spike, :many_hosts); [] normal
  )

  # metrics/network.rb reading[:connections]: one flow of a process in an agent session with a
  # concrete remote (no `*`, no Listen). Fields as NetFlow; rates bytes/s, nil the first time.
  ConnectionRow = Data.define(
    :pid, :name, :session_id,
    :session,              # session label
    :protocol, :local, :remote, :remote_host, :remote_port, :interface, :state,
    :bytes_in, :bytes_out, # cumulative bytes on this flow
    :in_rate, :out_rate    # bytes/s between the two latest snapshots
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

  # metrics/session_memory.rb (story a20): one alive session's memory, largest footprint first.
  # Sums over the session's live readable members, each process once. Compressed and swapped
  # bytes per process need task_for_pid (root), so they aren't here; MemoryView has the machine's.
  SessionMemory = Data.define(
    :session_id, :label,
    :processes,       # live members
    :footprint,       # bytes now (Activity Monitor's Memory; includes the session's compressed pages)
    :resident,        # bytes now
    :wired,           # bytes now
    :peak_footprint,  # bytes: largest footprint sum over its life (Session#peak_footprint)
    :share,           # percent of MemoryView#used (nil while memory is unknown)
    :growth_rate,     # bytes/s of footprint change over the last minute (0.0 until two samples)
    :pageins,         # count, cumulative over live members
    :pagein_rate,     # pageins/s now (nil until two samples)
    :fault_rate       # page faults/s now (nil until two samples)
  )
end
