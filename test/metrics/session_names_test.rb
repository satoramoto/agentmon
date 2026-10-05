# frozen_string_literal: true

require "test_helper"
require "json"

class SessionNamesMetricTest < Minitest::Test
  include Fixtures

  Names = Agentmon::Metrics::SessionNames
  UUID1 = "01a10863-6c88-7d31-9fad-4eadc95a38ce"
  UUID2 = "01a109ad-b739-73a1-b30d-c8c2d0322663"
  UUID3 = "01a10079-5436-7243-8e62-458849c7ab30"

  def setup
    @dir = Dir.mktmpdir("agentmon-names-test")
    @claude = File.join(@dir, "claude-sessions")
    @codex = File.join(@dir, "codex")
    FileUtils.mkdir_p([@claude, File.join(@codex, "sessions", "2026", "10", "04")])
    @open = {}
    Names.claude_dir = @claude
    Names.codex_home = @codex
    Names.open_paths = ->(pid) { @open[pid] }
    @state = {}
  end

  def teardown
    Names.claude_dir = Names.codex_home = NO_NAMES_DIR
    Names.open_paths = ->(_pid) {}
    FileUtils.remove_entry(@dir)
  end

  def claude_file(pid, mtime: T0, **fields)
    path = File.join(@claude, "#{pid}.json")
    File.write(path, JSON.generate({ pid:, sessionId: "abc", cwd: "/x", entrypoint: "cli", **fields }))
    File.utime(mtime, mtime, path)
    path
  end

  def rollout(uuid, mtime)
    path = File.join(@codex, "sessions", "2026", "10", "04", "rollout-2026-10-04T15-28-16-#{uuid}.jsonl")
    File.write(path, "{}\n")
    File.utime(mtime, mtime, path)
    path
  end

  def index(*lines, mode: "a")
    File.open(File.join(@codex, "session_index.jsonl"), mode) do |f|
      lines.each { |id, name| f.write("#{JSON.generate({ id:, thread_name: name, updated_at: "2026-10-04T00:00:00Z" })}\n") }
    end
  end

  def names(t = 0, processes: [process(pid: 500, name: "claude")])
    Names.call(Fixtures.reading(Fixtures.sample(t, processes:)), @state)
  end

  def test_claude_name_and_status
    claude_file(500, name: "Agentmon r2ui integration", status: "busy")

    assert_equal Agentmon::SessionName.new(title: "Agentmon r2ui integration", status: "busy", threads: []), names[500]
  end

  def test_claude_file_is_reparsed_only_when_its_mtime_changes
    path = claude_file(500, name: "First")
    names
    File.write(path, JSON.generate({ name: "Second" }))
    File.utime(T0, T0, path) # same mtime: the cache answers

    assert_equal "First", names(10)[500].title

    File.utime(T0 + 5, T0 + 5, path)

    assert_equal "Second", names(20)[500].title
  end

  def test_missing_or_garbled_claude_file_is_no_name
    File.write(File.join(@claude, "501.json"), "{not json")
    File.write(File.join(@claude, "502.json"), "[1, 2]")
    value = names(processes: [process(pid: 500, name: "claude"), process(pid: 501, name: "claude"),
                              process(pid: 502, name: "claude")])

    assert_empty value
  end

  def test_only_live_claude_roots_are_read
    claude_file(500, name: "Root")
    claude_file(501, name: "Sub-agent")
    claude_file(600, name: "Gone")
    value = names(processes: [process(pid: 500, name: "claude"), process(pid: 501, ppid: 500, name: "claude")])

    assert_equal [500], value.keys
  end

  def test_a_session_file_older_than_the_process_belongs_to_an_earlier_pid
    started = T0 - 3600 + 500 # the fixture process's start
    claude_file(500, name: "Old", startedAt: ((started - 3600) * 1000).to_i)

    assert_empty names
  end

  def test_codex_title_is_the_newest_named_thread_plus_the_others
    index([UUID1, "Old thread"], [UUID2, "New thread"], [UUID3, "Middle"])
    @open[700] = [rollout(UUID1, T0), rollout(UUID2, T0 + 20), rollout(UUID3, T0 + 10), "/dev/null",
                  rollout(UUID2, T0 + 20)] # one thread open twice counts once
    value = names(processes: [process(pid: 700, name: "codex")])

    assert_equal "New thread +2", value[700].title
    assert_equal ["New thread", "Middle", "Old thread"], value[700].threads
    assert_nil value[700].status
  end

  def test_codex_threads_without_a_name_are_skipped_for_the_title
    index([UUID1, "Named"])
    @open[700] = [rollout(UUID1, T0), rollout(UUID2, T0 + 20)]

    assert_equal "Named +1", names(processes: [process(pid: 700, name: "codex")])[700].title
  end

  def test_codex_with_no_named_thread_or_unreadable_files_has_no_name
    index([UUID3, "Not open"])
    @open[700] = [rollout(UUID1, T0)]
    @open[701] = nil

    assert_empty names(processes: [process(pid: 700, name: "codex"), process(pid: 701, name: "codex")])
  end

  def test_codex_index_is_read_incrementally_and_later_lines_win
    index([UUID1, "Before"])
    @open[700] = [rollout(UUID1, T0)]
    codex = [process(pid: 700, name: "codex")]

    assert_equal "Before", names(0, processes: codex)[700].title
    offset = @state[:index][:offset]
    index([UUID1, "Renamed"])

    assert_equal "Renamed", names(10, processes: codex)[700].title
    assert_operator @state[:index][:offset], :>, offset
  end

  def test_codex_index_that_shrank_is_read_again
    index([UUID1, "A long name before the rewrite"], [UUID2, "Other"])
    @open[700] = [rollout(UUID1, T0)]
    codex = [process(pid: 700, name: "codex")]
    names(0, processes: codex)
    index([UUID1, "New"], mode: "w")

    assert_equal "New", names(10, processes: codex)[700].title
    assert_equal({ UUID1 => "New" }, @state[:index][:names])
  end

  def test_garbled_index_lines_are_skipped
    File.write(File.join(@codex, "session_index.jsonl"), "garbage\n#{JSON.generate({ id: UUID1, thread_name: "Ok" })}\n{\"id\":")
    @open[700] = [rollout(UUID1, T0)]

    assert_equal "Ok", names(processes: [process(pid: 700, name: "codex")])[700].title
  end

  def test_refreshes_at_most_every_ten_seconds
    path = claude_file(500, name: "First")
    names(0)
    File.write(path, JSON.generate({ name: "Second" }))
    File.utime(T0 + 5, T0 + 5, path)

    assert_equal "First", names(9.9)[500].title
    assert_equal "Second", names(10)[500].title
  end

  def test_a_reading_has_it
    claude_file(500, name: "Via reading")
    reading = Fixtures.reading(Fixtures.sample(0, processes: [process(pid: 500, name: "claude")]))

    assert_equal "Via reading", reading[:session_names][500].title
    assert_equal "Via reading · claude 500", reading[:sessions].of(500).label
  end
end
