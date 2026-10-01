# frozen_string_literal: true

require "test_helper"

# K (terminate) and X (kill) on the Processes panel, with the signal sender injected so nothing
# real is signalled.
class ProcessActionsPanelTest < Minitest::Test
  include Fixtures

  def setup
    @sent = []
    @previous_sender = Agentmon::UI::ProcessActions.sender
    Agentmon::UI::ProcessActions.sender = ->(signal, pid) { @sent << [signal, pid] }
  end

  def teardown
    Agentmon::UI::ProcessActions.sender = @previous_sender
  end

  def app
    Agentmon::UI.install(engine: Agentmon.engine)
    R2UI::App.new(R2UI.registry, Agentmon::UI::DASHBOARD).tap do |a|
      a.feeds.each_value(&:refresh!)
      draw(a) # actions act on the rows of the last frame
    end
  end

  def draw(app) = app.frame(150, 20).plain_lines

  def status(app) = draw(app).last

  def press(app, *keys)
    keys.each { |k| app.press(k) }
    draw(app)
  end

  # Shows only processes named `name` (All scope, then search).
  def find(app, name) = press(app, "]", "/", *name.chars, :enter)

  def test_k_terminates_the_selected_process_after_confirm
    with_engine(Fixtures.engine(machine(0), machine(2))) do
      a = app # Agents scope, sorted by CPU: claude 200 first
      a.press("K")

      assert_includes status(a), "terminate 1 row? y/n"
      assert_empty @sent

      a.press("y")

      assert_equal [["TERM", 200]], @sent
      assert_includes status(a), "terminate: 1 done"
    end
  end

  def test_x_kills_the_selected_process_after_confirm
    with_engine(Fixtures.engine(machine(0), machine(2))) do
      a = app
      press(a, "X", "y")

      assert_equal [["KILL", 200]], @sent
    end
  end

  def test_answering_no_sends_nothing
    with_engine(Fixtures.engine(machine(0), machine(2))) do
      a = app
      press(a, "K", "n")
      press(a, "X", "n")

      assert_empty @sent
    end
  end

  def test_a_selected_group_signals_every_member
    with_engine(Fixtures.engine(machine(0), machine(2))) do
      a = app
      press(a, "g") # group by Session: "claude 200 · repo" has the most CPU
      a.press("K")

      assert_includes status(a), "terminate 4 rows? y/n"

      press(a, "y")

      assert_equal [200, 201, 202, 203], @sent.map(&:last).sort
      assert(@sent.all? { |signal, _| signal == "TERM" })
    end
  end

  def test_launchd_is_refused
    with_engine(Fixtures.engine(machine(0), machine(2))) do
      a = app
      find(a, "launchd")
      press(a, "X", "y")

      assert_empty @sent
      assert_match(/kill failed: refusing to signal pid 1 \(launchd\)/, status(a))
    end
  end

  def test_pid_0_and_agentmon_itself_are_refused
    procs = [process(pid: 0, ppid: 0, name: "kernel_task"), process(pid: Process.pid, name: "agentmonself")]
    samples = [0, 2].map { |t| Fixtures.sample(t, processes: procs) }
    with_engine(Fixtures.engine(*samples)) do
      a = app
      find(a, "kernel_task")
      press(a, "K", "y")

      assert_match(/terminate failed: refusing to signal pid 0 \(kernel_task\)/, status(a))

      press(a, "/", :escape) # clear the search
      press(a, "/", *"agentmonself".chars, :enter)
      press(a, "X", "y")

      assert_match(/kill failed: refusing to signal agentmon itself \(pid #{Process.pid}\)/, status(a))
      assert_empty @sent
    end
  end

  def test_eperm_and_esrch_show_a_failure_instead_of_raising
    with_engine(Fixtures.engine(machine(0), machine(2))) do
      a = app
      Agentmon::UI::ProcessActions.sender = ->(_signal, _pid) { raise Errno::EPERM }
      press(a, "K", "y")

      assert_match(/terminate failed: pid 200 \(claude\): Operation not permitted/, status(a))

      Agentmon::UI::ProcessActions.sender = ->(_signal, _pid) { raise Errno::ESRCH }
      press(a, "X", "y")

      assert_match(/kill failed: pid 200 \(claude\): No such process/, status(a))
    end
  end
end
