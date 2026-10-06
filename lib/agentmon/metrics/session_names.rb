# frozen_string_literal: true

require "json"

# reading[:session_names]: { root pid => SessionName } for the agent CLI processes whose human
# name (or status) is known. Metrics::Sessions puts the name at the front of the session label.
#
# Where names come from (no subprocess, ever):
#
# - Claude Code writes ~/.claude/sessions/<pid>.json for each CLI session ("name", "status"
#   busy/idle, "startedAt" ms, ...). Re-parsed only when its mtime changes.
# - One codex process (the ChatGPT app's `codex app-server`, or the codex CLI) hosts threads and
#   keeps each one's rollout file open: $CODEX_HOME/sessions/YYYY/MM/DD/rollout-<time>-<uuid>.jsonl.
#   $CODEX_HOME/session_index.jsonl maps thread id => thread_name (later lines win); it is
#   append-only, so it is read incrementally from the last byte offset (from 0 if it shrank).
#   The open files come from Darwin.open_paths, once per live codex pid. The title is the newest
#   (rollout mtime) named open thread, plus " +N" for its N other open threads.
#
# Cost: nothing per sample. It refreshes at most every REFRESH seconds (monotonic); in between
# it returns its last value. Unreadable, missing or garbled files mean no name, never an error.
module Agentmon
  module Metrics
    module SessionNames
      REFRESH = 10.0
      CLI = /\A(claude|codex)\z/
      ROLLOUT = /rollout-.*-(\h{8}-\h{4}-\h{4}-\h{4}-\h{12})\.jsonl\z/
      # A Claude session file written before this process started belongs to an earlier process
      # that had the same pid (seconds of slack for clock rounding).
      STALE_SLACK = 60

      class << self
        # Injectable for tests (test_helper points them at an empty dir and a nil reader).
        attr_writer :claude_dir, :codex_home, :open_paths

        def claude_dir = @claude_dir || File.join(Dir.home, ".claude", "sessions")
        def codex_home = @codex_home || ENV["CODEX_HOME"] || File.join(Dir.home, ".codex")
        def open_paths = @open_paths || Darwin.method(:open_paths)

        # The metric: the last value until REFRESH seconds have passed, then a refresh.
        def call(reading, state)
          mono = reading.sample.mono
          return state[:value] if state[:at] && mono - state[:at] < REFRESH

          state[:at] = mono
          state[:value] = refresh(reading.sample[:processes] || [], state)
        end

        # { pid => SessionName } for the live claude/codex roots in `processes`.
        def refresh(processes, state)
          by_pid = processes.to_h { |p| [p.pid, p] }
          cli = ->(p) { p && p.name.to_s.match?(CLI) }
          roots = processes.select { |p| cli[p] && !cli[by_pid[p.ppid]] } # under another CLI: not a root
          names = {}
          claude(roots.select { |p| p.name == "claude" }, state, names)
          codex = roots.select { |p| p.name == "codex" }
          codex(codex, state, names) unless codex.empty?
          names
        end

        private

        def claude(processes, state, names)
          cache = (state[:claude] ||= {}) # path => [mtime, SessionName or nil, startedAt seconds]
          live = {}
          processes.each do |p|
            path = File.join(claude_dir, "#{p.pid}.json")
            live[path] = true
            entry = claude_file(path, cache)
            next unless entry

            _, name, started = entry
            next if started && p.started_at && started < p.started_at - STALE_SLACK

            names[p.pid] = name if name
          end
          cache.select! { |path, _| live[path] }
        end

        def claude_file(path, cache)
          mtime = File.mtime(path)
          return cache[path] if cache[path] && cache[path][0] == mtime

          cache[path] = [mtime, *parse_claude(File.read(path, encoding: Encoding::UTF_8))]
        rescue SystemCallError, IOError
          cache.delete(path)
          nil
        end

        # [SessionName or nil, startedAt in epoch seconds or nil]
        def parse_claude(text)
          json = JSON.parse(text)
          return [nil, nil] unless json.is_a?(Hash)

          title = json["name"].is_a?(String) && !json["name"].strip.empty? ? json["name"].strip : nil
          status = json["status"].is_a?(String) ? json["status"] : nil
          started = json["startedAt"].is_a?(Numeric) ? json["startedAt"] / 1000.0 : nil
          [title || status ? SessionName.new(title:, status:, threads: []) : nil, started]
        rescue JSON::ParserError, EncodingError
          [nil, nil]
        end

        def codex(processes, state, names)
          index = read_index(state)
          reader = open_paths
          processes.each do |p|
            paths = begin
              reader.call(p.pid)
            rescue StandardError
              nil
            end
            name = codex_name(paths || [], index)
            names[p.pid] = name if name
          end
        end

        # The open rollout files' threads, newest first, named from the index.
        def codex_name(paths, index)
          threads = paths.filter_map { |path| (m = ROLLOUT.match(path)) && [m[1], path] }.uniq(&:first)
          dated = threads.filter_map do |id, path|
            [id, File.mtime(path)]
          rescue SystemCallError
            nil
          end
          return nil if dated.empty?

          named = dated.sort_by { |_, mtime| -mtime.to_f }.filter_map { |id, _| index[id] }
          return nil if named.empty?

          more = dated.size - 1
          SessionName.new(title: more.positive? ? "#{named.first} +#{more}" : named.first, status: nil, threads: named)
        end

        # The thread id => name map, after reading what was appended since the last refresh.
        def read_index(state)
          index = (state[:index] ||= { offset: 0, names: {} })
          path = File.join(codex_home, "session_index.jsonl")
          size = File.size(path)
          index.merge!(offset: 0, names: {}) if size < index[:offset]
          return index[:names] if size == index[:offset]

          chunk = File.open(path, "rb") do |f|
            f.seek(index[:offset])
            f.read(size - index[:offset])
          end.to_s
          complete = chunk.rindex("\n")
          return index[:names] unless complete # a line still being written: next time

          chunk.byteslice(0, complete + 1).each_line { |line| index_line(line, index[:names]) }
          index[:offset] += complete + 1
          index[:names]
        rescue SystemCallError, IOError
          index[:names]
        end

        def index_line(line, names)
          json = JSON.parse(line.force_encoding(Encoding::UTF_8))
          return unless json.is_a?(Hash) && json["id"].is_a?(String)

          name = json["thread_name"]
          names[json["id"]] = name.strip if name.is_a?(String) && !name.strip.empty?
        rescue JSON::ParserError, EncodingError
          nil
        end
      end
    end
  end

  metric(:session_names) { |reading, state| Metrics::SessionNames.call(reading, state) }
end
