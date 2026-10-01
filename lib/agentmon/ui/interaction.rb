# frozen_string_literal: true

# Mouse and help. A left click focuses the panel under the pointer and selects the table row
# there; the wheel moves the selection of the table under the pointer. `?` opens a full-screen
# help listing every key (r2ui's, those other stories bind, and agentmon's own) and what each
# panel shows; any key closes it.
#
#   ?   help                        click  focus a panel, select a row
#   K   terminate the selection     wheel  move the selection
#
# The overlay is the r2ui extension `agentmon_help` (a `view_override`); it draws only for the
# agentmon dashboard, since r2ui's hooks are process-wide.
module Agentmon
  module UI
    # Not `Help` or `Interaction` alone: named after the story so it can't hide a core constant.
    module MouseAndHelp
      STORE = :agentmon_help

      # agentmon's own keys, shown even before the stories that bind them have merged.
      KEYS = [
        ["K", "terminate the selected process (TERM, asks y/n)"],
        ["X", "kill the selected process (KILL, asks y/n)"],
        ["?", "this help (any key closes it)"]
      ].freeze

      # r2ui's selection keys, which its status bar doesn't list.
      MOVE = [["↑ ↓ j k", "move the selection"]].freeze

      MOUSE = [
        ["click", "focus the panel, select the row under the pointer"],
        ["wheel", "move the selection of the table under the pointer"]
      ].freeze

      # What each panel shows, by panel name; panels not listed show their title only.
      PANELS = {
        memory: "RAM: used/total, app, wired, compressed, cached, swap, pressure and its drivers",
        session: "agent sessions: CPU, footprint, peak, CPU seconds, disk written, age",
        process: "every process with its session, directory, CPU, footprint, resident size, disk rates",
        detail: "the selected process: command line, cwd, memory, CPU time, files, start time"
      }.freeze

      module_function

      def open?(store) = store[:open] == true

      def toggle(store) = store[:open] = !open?(store)

      # The overlay text, at most `width` x `height`. `hints` are app.hint_pairs ([key, label]);
      # agentmon's own labels win for the keys it describes itself.
      def render(app, hints, width, height)
        ours = KEYS.map(&:first)
        keys = hints.map { |k, l| [k.to_s, l.to_s] }.reject { |k, _| ours.include?(k) } + MOVE + KEYS
        pad = (keys + MOUSE).map { |k, _| k.length }.max
        lines = ["agentmon help", "", "Keys"]
        lines += keys.map { |k, l| "  #{k.ljust(pad)}  #{l}" }
        lines += ["", "Mouse"] + MOUSE.map { |k, l| "  #{k.ljust(pad)}  #{l}" }
        lines += ["", "Panels"]
        lines += app.dashboard.panels.map do |p|
          "  #{panel_title(app, p)}#{"  #{PANELS[p.name]}" if PANELS[p.name]}"
        end
        lines += ["", "Press any key to close."]
        lines.first([height, 1].max).map { |line| line[0, [width, 0].max] }.join("\n")
      end

      # The title the panel's border shows: its own, else its resource's, else its name.
      def panel_title(app, panel)
        resource = panel.resource && app.registry.resource(panel.resource)
        (panel.title || resource&.title || panel.name.to_s.capitalize).to_s
      end
    end
  end

  dashboard do
    mouse :cell
    on_key("?", help: "help") { UI::MouseAndHelp.toggle(store(UI::MouseAndHelp::STORE)) }
  end

  R2UI.extension :agentmon_help do
    # While the help is open it takes every key (closing it) and every mouse message.
    on(->(m) { m.is_a?(Bubbletea::KeyMessage) || m.is_a?(Bubbletea::MouseMessage) }, priority: 100) do |message|
      help = store(UI::MouseAndHelp::STORE)
      pass unless UI::MouseAndHelp.open?(help)

      help[:open] = false if message.is_a?(Bubbletea::KeyMessage)
      nil
    end

    view_override do
      if dashboard.name == UI::DASHBOARD && UI::MouseAndHelp.open?(store(UI::MouseAndHelp::STORE))
        UI::MouseAndHelp.render(app, app.hint_pairs(self), width, height)
      end
    end
  end
end
