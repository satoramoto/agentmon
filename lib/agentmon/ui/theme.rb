# frozen_string_literal: true

# The dashboard's look and the terminal window title.
#
# Theme (r2ui's `theme`, lipgloss colours): panel titles and the focused border in agentmon's
# orange accent, which also draws session sparklines and the active scope ("[Agents]"); memory
# pressure (gauges, percent cells) goes green under 70%, amber, then red from 90%.
#
# Window title, kept current as sessions start and end and pressure moves:
#
#   agentmon · 3 sessions · 42% pressure
#   agentmon · 1 session                    (pressure left out until memory data is available)
module Agentmon
  module UI
    # The title text for a Reading (nil before the first one).
    module ThemeTitle
      ACCENT = "#D97757"

      module_function

      def title(reading)
        parts = ["agentmon"]
        return parts.first unless reading

        alive = (reading[:session_ledger] || []).count { |s| s.ended_at.nil? }
        parts << "#{alive} #{alive == 1 ? "session" : "sessions"}"
        pressure = reading[:memory]&.pressure
        parts << "#{pressure.round}% pressure" if pressure
        parts.join(" · ")
      end
    end
  end

  dashboard do |engine|
    theme do
      title foreground: UI::ThemeTitle::ACCENT, bold: true
      focus foreground: UI::ThemeTitle::ACCENT
      accent foreground: UI::ThemeTitle::ACCENT
      selected reverse: true, foreground: UI::ThemeTitle::ACCENT
      ok foreground: "#5FAF5F"
      warn foreground: "#E5A50A"
      alert foreground: "#E5484D", bold: true
    end

    # Runs after every update; reads the latest reading without sampling (the panels' feeds keep it
    # fresh), so a keypress never waits on `ps`.
    window_title { UI::ThemeTitle.title(engine.current(max_age: Float::INFINITY)) }
  end
end
