# frozen_string_literal: true

# Dashboard tests draw the whole agentmon dashboard, with every story's panels in it. These helpers
# make those tests independent of which other panels exist and in what order:
#
#   with_engine(Fixtures.engine(machine(0), machine(2))) do
#     a = dashboard_app             # installed, feeds refreshed, keys on the Processes panel
#     a.press("]")                  # goes to the :process panel
#     text = dashboard_frame(a)     # 200x50 plain text, every row on screen
#     text = dashboard_frame(a, focus: :session) # keys on another panel
#   end
module DashboardFrames
  WIDTH = 200
  HEIGHT = 50

  # A fresh agentmon dashboard over `Agentmon.engine` with its feeds refreshed and key focus on
  # the `focus` panel (nil keeps r2ui's choice).
  def dashboard_app(focus: Agentmon::UI::FOCUS, view: nil)
    Agentmon::UI.install(engine: Agentmon.engine, view:)
    app = R2UI::App.new(R2UI.registry, Agentmon::UI::DASHBOARD)
    app.feeds.each_value(&:refresh!)
    focus_panel(app, focus) if focus
    app
  end

  # One plain frame as text, big enough for the full dashboard. Focus moves to the `focus` panel
  # first (nil keeps the current one, e.g. after a test pressed tab).
  def dashboard_frame(app, width: WIDTH, height: HEIGHT, focus: Agentmon::UI::FOCUS)
    focus_panel(app, focus) if focus
    app.frame(width, height).plain_lines.join("\n")
  end

  # A performance view's frame at the owner's window size, 100x50 (docs/views.md).
  def view_frame(app, width: 100, height: 50, focus: nil)
    dashboard_frame(app, width:, height:, focus:)
  end

  # Gives key focus to the panel named `name`.
  def focus_panel(app, name)
    panel = app.dashboard.panels.find { |p| p.name == name }
    raise ArgumentError, "no panel #{name.inspect} on the dashboard" unless panel

    app.focus = panel
  end
end
