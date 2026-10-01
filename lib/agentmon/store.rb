# frozen_string_literal: true

require "json"
require "fileutils"

module Agentmon
  # Append-only history in plain files: one JSON object per line, one file per kind per local day.
  #
  #   ~/.local/state/agentmon/sessions/2026-10-01.jsonl
  #   ~/.local/state/agentmon/memory/2026-10-01.jsonl
  #
  # The directory is $AGENTMON_STATE_DIR, else $XDG_STATE_HOME/agentmon, else
  # ~/.local/state/agentmon. Every record gets `t` (epoch seconds) when it has none. Reading
  # tolerates a torn last line (a crash mid-write) by skipping lines that don't parse.
  class Store
    def self.default_dir(env = ENV)
      return File.expand_path(env["AGENTMON_STATE_DIR"]) if env["AGENTMON_STATE_DIR"].to_s != ""

      base = env["XDG_STATE_HOME"].to_s == "" ? File.join(Dir.home, ".local", "state") : env["XDG_STATE_HOME"]
      File.join(File.expand_path(base), "agentmon")
    end

    attr_reader :dir

    def initialize(dir: Store.default_dir, clock: Clock)
      @dir = dir
      @clock = clock
      @lock = Mutex.new
    end

    # Appends one record (a Hash) under `kind`. Returns the record as written.
    def append(kind, record)
      record = { t: @clock.now }.merge(record)
      path = file_for(kind, record[:t] || record["t"])
      line = "#{JSON.generate(record)}\n"
      @lock.synchronize do
        FileUtils.mkdir_p(File.dirname(path))
        File.open(path, "a") { |f| f.write(line) }
      end
      record
    end

    # Records of `kind` with `since <= t < till` (epoch seconds or Time), oldest first, keys as
    # Symbols. Without a block, an Enumerator.
    def each(kind, since: nil, till: nil, &block)
      return enum_for(:each, kind, since:, till:) unless block

      since = since&.to_f
      till = till&.to_f
      files(kind, since).each do |path|
        File.foreach(path) do |line|
          record = parse(line) or next
          t = record[:t].to_f
          next if (since && t < since) || (till && t >= till)

          yield record
        end
      end
    end

    # Deletes day files older than `days` days. Returns the paths removed.
    def prune(days:)
      cutoff = day(@clock.now - (days * 86_400))
      old = Dir[File.join(dir, "*", "*.jsonl")].select { |p| File.basename(p, ".jsonl") < cutoff }
      old.each { |p| File.delete(p) }
    end

    private

    def file_for(kind, t) = File.join(dir, kind.to_s, "#{day(t)}.jsonl")

    def day(t) = Time.at(t.to_f).strftime("%Y-%m-%d")

    def files(kind, since)
      all = Dir[File.join(dir, kind.to_s, "*.jsonl")].sort
      # A record at `since` lives in that local day's file or a later one.
      since ? all.select { |p| File.basename(p, ".jsonl") >= day(since) } : all
    end

    def parse(line)
      JSON.parse(line, symbolize_names: true)
    rescue JSON::ParserError
      nil
    end
  end
end
