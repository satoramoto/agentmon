# frozen_string_literal: true

# Drill into one agent session: every panel narrows to it.
#
#   enter   on a Sessions row: focus that session (anywhere else enter still toggles a group)
#   F       focus the session of the row selected in Processes ("not in an agent session" if none)
#   escape  back to every session
#
# Focus lives in the core (`engine.focus=`, lib/agentmon/focus.rb): panels keep reading
# `engine.current[...]`, which narrows itself, so Processes, Sessions and the pressure drivers show
# only the focused session once their feeds refresh. Each change refreshes every feed at once, so
# the next frame is already narrowed. While focused the status bar says
#
#   focus: claude 4242 · repo (esc: all)
#
# and a focused session that has left the ledger clears itself (and refreshes) on the next frame.
module Agentmon
  module UI
    module SessionFocus
      SESSIONS = :session
      PROCESSES = :process
      NO_SESSION = "not in an agent session"
      SEVERAL = "rows span several sessions: ungroup (g) to pick one"

      module_function

      # Sets the engine's focus (nil clears it) and refreshes every feed, so the next frame shows it.
      def focus!(app, engine, session_id)
        engine.focus = session_id
        app.feeds.each_value(&:refresh!)
      end

      # The session id of the line selected in the Sessions panel; nil on a group line or none.
      def selected_session(app)
        line = selected_line(app, SESSIONS)
        return nil if line.nil? || line.id.is_a?(Array) # [:group, by, key]: enter toggles it

        line.id
      end

      # The session of the line selected in Processes: [session_id, nil] or [nil, message to flash].
      # A group line focuses its session when every process in it is in that one session.
      def process_session(app)
        line = selected_line(app, PROCESSES) or return [nil, nil]

        row = line.rows.find { |r| r.pid == line.id }
        ids = (row ? [row] : line.rows).map(&:session_id).uniq
        return [ids.first, nil] if ids.size == 1 && ids.first
        return [nil, NO_SESSION] if ids.compact.empty?

        [nil, SEVERAL]
      end

      # The status bar text while focused; nil when unfocused.
      def status(engine)
        session = engine.focused_session
        session && "focus: #{session.label} (esc: all)"
      end

      # Clears a focus whose session has left the ledger (and refreshes). True when it did. A
      # reading without a ledger (that metric failed this sample) keeps the focus.
      def clear_if_gone(app, engine)
        id = engine.focus or return false
        ledger = engine.current(focused: false)[:session_ledger]
        return false if ledger.nil? || ledger.any? { |s| s.id == id }

        focus!(app, engine, nil)
        true
      end

      def selected_line(app, name)
        panel = app.dashboard.panels.find { |p| p.name == name }
        state = panel && app.panel_state(panel)
        state && app.panel_lines(panel)[state.selected]
      end
    end
  end

  # Hands the engine to the extension below through the dashboard, so only a dashboard built by
  # UI.install (with its own engine) gets these keys.
  R2UI.extension :agentmon_session_focus do
    dsl :dashboard do
      def agentmon_session_focus(engine) = declare(:agentmon_session_focus, engine)
    end

    helpers do
      # The engine of the dashboard drawing, nil on dashboards that aren't agentmon's.
      def session_focus_engine = dashboard.declared(:agentmon_session_focus).first
    end

    on(->(m) { m.is_a?(Bubbletea::KeyMessage) && [:enter, "F", :escape].include?(R2UI::Keys.name(m)) }) do |message|
      engine = session_focus_engine or pass
      focus = UI::SessionFocus
      case R2UI::Keys.name(message)
      when :enter
        pass unless app.focus&.name == focus::SESSIONS
        id = focus.selected_session(app) or pass
        focus.focus!(app, engine, id)
      when "F"
        id, problem = focus.process_session(app)
        id ? focus.focus!(app, engine, id) : (problem && flash(problem))
      when :escape
        pass unless engine.focus
        focus.focus!(app, engine, nil)
      end
      nil
    end

    # Feeds' own refreshes arrive as updates too: a session that left the ledger clears here even
    # while a flash hides the status bar.
    after_update do
      engine = session_focus_engine
      UI::SessionFocus.clear_if_gone(app, engine) if engine
    end

    status do
      engine = session_focus_engine
      next nil unless engine

      UI::SessionFocus.clear_if_gone(app, engine)
      UI::SessionFocus.status(engine)
    end
  end

  dashboard { |engine| agentmon_session_focus(engine) }
end
