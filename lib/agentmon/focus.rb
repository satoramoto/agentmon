# frozen_string_literal: true

module Agentmon
  # Session focus: one agent session the whole dashboard (or a command) narrows to.
  #
  # The Engine holds the focus (`engine.focus = session_id`, `engine.focus = nil` clears it), and
  # while it is set `engine.current` returns a FocusedReading: the same reading with every
  # per-session value narrowed to that session. Panels and commands keep reading
  # `engine.current[:process_rows]` and so on, and show only the focused session's processes,
  # sessions, drivers and memory without knowing focus exists. Machine-wide values (`:memory`,
  # anything not in FILTERS) pass through unchanged.
  #
  #   engine.focus = "claude-4242-1790711088"
  #   engine.current[:process_rows]        # only that session's processes
  #   engine.current.focus                 # => "claude-4242-1790711088" (nil when unfocused)
  #   engine.current(focused: false)       # the whole machine, e.g. a picker listing every session
  #   engine.focused_session               # its Session from the ledger, nil when unfocused or gone
  #   engine.focus = nil                   # everything again
  #
  # The filters are per shape in model.rb, so a new per-session shape (a contract change) adds its
  # filter here in the same PR. `reading.sample` is never filtered: code that reads raw probe
  # values sees the whole machine.
  module Focus
    # metric name => ->(value, session_id, unfocused_reading) { narrowed value }. Values are never
    # nil here (nil passes through).
    FILTERS = {
      process_rows: ->(rows, id, _) { rows.select { |r| r.session_id == id } },
      process_rates: lambda do |rates, id, reading|
        by_pid = reading[:sessions]&.by_pid || {}
        rates.select { |pid, _| by_pid[pid] == id }
      end,
      sessions: lambda do |map, id, _|
        SessionMap.new(sessions: map.sessions.select { |s| s.id == id }, by_pid: map.by_pid.select { |_, s| s == id })
      end,
      session_ledger: ->(sessions, id, _) { sessions.select { |s| s.id == id } },
      pressure_drivers: ->(drivers, id, _) { drivers.select { |d| d.session_id == id } },
      session_memory: ->(rows, id, _) { rows.select { |r| r.session_id == id } }
    }.freeze

    module_function

    # `reading` narrowed to `session_id`; the reading itself when nil.
    def apply(reading, session_id) = session_id ? FocusedReading.new(reading, session_id) : reading

    # Sessions a user's query names (CLI `--session`, a typed filter): an exact id or root pid
    # first, else every session whose label contains it (case-insensitive). [] when none.
    def find(sessions, query)
      query = query.to_s
      exact = sessions.select { |s| s.id == query || s.root_pid.to_s == query }
      return exact unless exact.empty?

      sessions.select { |s| s.label.downcase.include?(query.downcase) }
    end
  end

  # A Reading narrowed to one session (see Focus). Every filtered value is computed once, when
  # the Engine builds it under its lock, so feed threads only look values up.
  class FocusedReading
    attr_reader :focus, :unfocused

    def initialize(reading, session_id)
      @unfocused = reading
      @focus = session_id
      @values = Focus::FILTERS.each_with_object({}) do |(name, filter), values|
        value = reading[name]
        values[name] = value.nil? ? nil : filter.call(value, session_id, reading)
      end
    end

    def [](name)
      name = name.to_sym
      @values.key?(name) ? @values[name] : @unfocused[name]
    end

    def sample = @unfocused.sample
    def previous = @unfocused.previous
    def errors = @unfocused.errors
    def at = @unfocused.at
    def interval = @unfocused.interval
    def key?(name) = @unfocused.key?(name)
  end
end
