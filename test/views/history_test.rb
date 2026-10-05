# frozen_string_literal: true

require "test_helper"
require "agentmon/views/history"

class HistoryViewTest < Minitest::Test
  History = Agentmon::Views::History

  def test_appends_once_per_at
    history = History.new
    history.record("system.cpu", 1.0, 10)
    history.record("system.cpu", 1.0, 20)
    history.record("system.cpu", 3.0, 30)

    assert_equal [10.0, 30.0], history["system.cpu"]
  end

  def test_nil_is_skipped_but_its_at_is_remembered
    history = History.new
    history.record("memory.used", 1.0, nil)
    history.record("memory.used", 1.0, 5)

    assert_equal [], history["memory.used"]
    history.record("memory.used", 2.0, 5)

    assert_equal [5.0], history["memory.used"]
    assert_equal ["memory.used"], history.keys
  end

  def test_caps_at_capacity_dropping_the_oldest
    history = History.new
    assert_equal 120, History::CAPACITY
    125.times { |i| history.record("k", i.to_f, i) }

    assert_equal 120, history["k"].size
    assert_in_delta 5.0, history["k"].first
    assert_in_delta 124.0, history["k"].last

    small = History.new(capacity: 3)
    5.times { |i| small.record("k", i, i) }

    assert_equal [2.0, 3.0, 4.0], small["k"]
  end

  def test_keys_are_independent
    history = History.new
    history.record("a", 1.0, 1)
    history.record("b", 1.0, 2)
    history.record("b", 2.0, 3)

    assert_equal [1.0], history["a"]
    assert_equal [2.0, 3.0], history["b"]
    assert_equal %w[a b], history.keys
    history.forget("a")

    assert_equal [], history["a"]
    assert_equal ["b"], history.keys
  end

  def test_results_are_frozen_and_not_shared
    history = History.new
    returned = history.record("a", 1.0, 1)

    assert_predicate returned, :frozen?
    assert_predicate history["a"], :frozen?
    assert_predicate history["unknown"], :frozen?
    assert_raises(FrozenError) { history["a"] << 9 }
    history.record("a", 2.0, 2)

    assert_equal [1.0], returned
    assert_equal [1.0, 2.0], history["a"]
    assert_equal [], History.new["a"]
  end

  def test_rejects_a_bad_capacity
    assert_raises(ArgumentError) { History.new(capacity: 0) }
  end
end
