# frozen_string_literal: true

require "test_helper"

class StoreCoreTest < Minitest::Test
  DAY = 86_400

  def setup
    @dir = Dir.mktmpdir
    @clock = Fixtures::Clock.new
    @store = Agentmon::Store.new(dir: @dir, clock: @clock)
  end

  def teardown = FileUtils.rm_rf(@dir)

  def test_appends_json_lines_per_kind_and_local_day
    @store.append(:sessions, id: "a", cpu_seconds: 1.5)
    path = File.join(@dir, "sessions", "#{Time.at(@clock.now).strftime("%Y-%m-%d")}.jsonl")

    assert_equal 1, File.readlines(path).size
    assert_equal [{ t: @clock.now, id: "a", cpu_seconds: 1.5 }], @store.each(:sessions).to_a
  end

  def test_each_filters_by_time_across_days
    @store.append(:memory, n: 1)
    @clock.advance(DAY)
    @store.append(:memory, n: 2)
    @clock.advance(DAY)
    @store.append(:memory, n: 3)

    assert_equal [2, 3], @store.each(:memory, since: @clock.now - DAY).map { |r| r[:n] }
    assert_equal [1, 2], @store.each(:memory, till: @clock.now).map { |r| r[:n] }
  end

  def test_a_torn_last_line_is_skipped
    @store.append(:sessions, id: "a")
    File.write(Dir[File.join(@dir, "sessions", "*")].first, "{\"t\": 1, \"id\"", mode: "a")

    assert_equal ["a"], @store.each(:sessions).map { |r| r[:id] }
  end

  def test_prune_deletes_old_days
    @store.append(:sessions, id: "old")
    @clock.advance(10 * DAY)
    @store.append(:sessions, id: "new")

    assert_equal 1, @store.prune(days: 7).size
    assert_equal ["new"], @store.each(:sessions).map { |r| r[:id] }
  end

  # launchd, cron and `env -i` start Ruby with no locale: default external encoding US-ASCII.
  def test_reads_and_writes_utf8_without_a_locale
    previous = Encoding.default_external
    silence_warnings { Encoding.default_external = Encoding::US_ASCII }
    @store.append(:sessions, id: "a", name: "café · ✓")

    assert_equal ["café · ✓"], @store.each(:sessions).map { |r| r[:name] }
  ensure
    silence_warnings { Encoding.default_external = previous }
  end

  def silence_warnings
    verbose = $VERBOSE
    $VERBOSE = nil
    yield
  ensure
    $VERBOSE = verbose
  end

  def test_default_dir_follows_the_environment
    assert_equal "/tmp/x", Agentmon::Store.default_dir("AGENTMON_STATE_DIR" => "/tmp/x")
    assert_equal "/tmp/state/agentmon", Agentmon::Store.default_dir("XDG_STATE_HOME" => "/tmp/state")
    assert_equal File.join(Dir.home, ".local/state/agentmon"), Agentmon::Store.default_dir({})
  end
end
