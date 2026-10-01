# frozen_string_literal: true

# Machine-independent inputs for tests: ProcessStats, Samples, a sampler that replays them and a
# clock you move by hand. Stories use these instead of the live machine.
module Fixtures
  MB = 1024 * 1024
  T0 = 1_790_000_000.0

  module_function

  # A ProcessStat with sensible defaults; pass only what the test is about.
  def process(pid:, ppid: 1, name: "proc", path: nil, readable: true, start_ticks: nil, started_at: nil,
              cpu_time: 0.0, child_cpu_time: 0.0, resident: 10 * MB, footprint: 8 * MB, peak_footprint: nil,
              disk_read: 0, disk_written: 0, ps_cpu: 0.0)
    Agentmon::ProcessStat.new(
      pid:, ppid:, name:, path: path || "/usr/bin/#{name}", readable:,
      start_ticks: readable ? (start_ticks || (pid * 1000)) : nil,
      started_at: readable ? (started_at || (T0 - 3600 + pid)) : nil,
      cpu_time: readable ? cpu_time : nil, child_cpu_time: readable ? child_cpu_time : nil,
      resident:, footprint: readable ? footprint : nil, peak_footprint: readable ? (peak_footprint || footprint) : nil,
      disk_read: readable ? disk_read : nil, disk_written: readable ? disk_written : nil, ps_cpu:
    )
  end

  # A Sample at `t` seconds after T0 (wall and monotonic move together).
  def sample(t, processes:, cwd: {}, **parts)
    Agentmon::Sample.new(at: T0 + t, mono: 1000.0 + t, parts: { processes:, cwd:, **parts })
  end

  # A small machine at time `t`, CPU seconds growing with t:
  #
  #   1 launchd
  #   ├─ 100 zsh ── 200 claude (~/src/repo) ─┬─ 201 node
  #   │                                       └─ 202 zsh ── 203 git
  #   ├─ 300 Claude (desktop app) ─┬─ 301 Claude Helper
  #   │                            └─ 302 disclaimer ── 303 claude (~/src/web)
  #   ├─ 400 Finder
  #   └─ 500 WindowServer (root: unreadable)
  def machine(t = 0, **overrides)
    procs = [
      process(pid: 1, ppid: 0, name: "launchd", readable: false, resident: 20 * MB, ps_cpu: 0.1),
      process(pid: 100, name: "zsh", cpu_time: 1.0),
      process(pid: 200, ppid: 100, name: "claude", cpu_time: 10.0 + t, footprint: 512 * MB, resident: 600 * MB,
              disk_written: 1000 * t.to_i),
      process(pid: 201, ppid: 200, name: "node", cpu_time: 2.0 + (t / 2.0), footprint: 100 * MB),
      process(pid: 202, ppid: 200, name: "zsh", cpu_time: 0.5),
      process(pid: 203, ppid: 202, name: "git", cpu_time: 0.1, disk_written: 5 * MB),
      process(pid: 300, name: "Claude", path: "/Applications/Claude.app/Contents/MacOS/Claude", cpu_time: 50.0,
              footprint: 300 * MB),
      process(pid: 301, ppid: 300, name: "Claude Helper", cpu_time: 20.0, footprint: 200 * MB),
      process(pid: 302, ppid: 300, name: "disclaimer", cpu_time: 0.0, footprint: 1 * MB),
      process(pid: 303, ppid: 302, name: "claude", cpu_time: 5.0, footprint: 150 * MB),
      process(pid: 400, name: "Finder", cpu_time: 30.0, footprint: 90 * MB),
      process(pid: 500, name: "WindowServer", readable: false, resident: 134 * MB, ps_cpu: 11.2)
    ]
    procs = procs.map { |p| overrides.key?(p.pid) ? p.with(**overrides[p.pid]) : p }
    sample(t, processes: procs, cwd: { 200 => "/Users/me/src/repo", 303 => "/Users/me/src/web", 300 => "/" })
  end

  # Replays samples in order, then keeps returning the last.
  class Sampler
    def initialize(*samples) = @samples = samples.flatten

    def sample = @samples.size > 1 ? @samples.shift : @samples.first
  end

  # A clock tests move by hand.
  class Clock
    attr_accessor :now, :mono

    def initialize(now: T0, mono: 1000.0)
      @now = now
      @mono = mono
    end

    def advance(seconds)
      @now += seconds
      @mono += seconds
    end
  end

  # An Engine over fixture samples that never sleeps.
  def engine(*samples, **options)
    Agentmon::Engine.new(sampler: Sampler.new(*samples), prime_gap: 0, **options)
  end

  # A Reading of `sample` after `previous`, with every registered metric.
  def reading(sample, previous: nil, values: {})
    Agentmon::Reading.new(sample, previous:, values:)
  end
end
