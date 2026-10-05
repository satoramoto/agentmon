# frozen_string_literal: true

require_relative "views/signals"
require_relative "views/history"
require_relative "views/widgets"

# Performance views: a small DSL for dashboards of the machine, a process or a session, on top of
# r2ui's rows and panels (docs/views.md is the contract). A ten-line view already looks finished:
#
#   Agentmon.view :mine, title: "agentmon" do
#     row height: 8 do
#       panel :cpu, title: "CPU" do
#         meter "system.cpu"                         # CPU ▕████▎     ▏ 42.0%
#         trend "system.cpu", height: 4              # braille area, the last four minutes
#       end
#       panel :memory, title: "Memory" do
#         meter "memory.used"                        # used ▕██████   ▏ 23G / 32G 71%
#         stat "memory.app", "memory.wired", "memory.compressed", "memory.swap_used"
#       end
#     end
#     row { top :process, by: :cpu, columns: %i[name session cpu footprint] }
#   end
#
#   agentmon --layout mine
#
# Words (all take signals, "metric.member", with defaults from views/signals.rb):
#   view-level row, focused { rows shown instead while a session is focused } (Views::Drill)
#   row-level  panel, use :name (a registered agentmon panel), top, band, detail
#   in a panel meter, trend, spark, stat, top, band, detail
#
# How it maps onto r2ui: `Agentmon.view` records a View (this file's builders; r2ui's own
# PanelBuilder already has `stat`, so the view words live on agentmon's builders, not r2ui's).
# `UI.install(engine:, view:)` turns it into the :agentmon r2ui dashboard: `top` becomes
# `table(columns:, sort:, limit:, motion: true)`, every other word a panel item drawn by the
# :agentmon_views extension below through Widgets (pure strings). Panels with only view words get
# the hidden :view_signals resource, whose feed keeps the engine sampling in the background (and
# so marks new frames due). Values are read from `engine.current(max_age: ∞)`, never sampled on
# the drawing thread.
module Agentmon
  module Views
    # --- the recorded view ---

    # `rows`: the home rows; `focused`: the rows shown instead while a session is focused
    # (`focused do ... end`; empty when the view has no drill-down).
    View = Data.define(:name, :title, :rows, :focused) do
      def initialize(name:, title:, rows:, focused: [].freeze) = super
      def drill? = !focused.empty?
      def all_rows = rows + focused
    end
    RowDef = Data.define(:height, :panels)
    PanelDef = Data.define(:name, :title, :span, :resource, :items, :options)
    UseDef = Data.define(:name, :span, :title)

    Meter = Data.define(:signal, :heat)
    Trend = Data.define(:signals, :height)
    Spark = Data.define(:signal)
    Stat = Data.define(:signals, :columns)
    # `widths`: { column => cells } fixes text columns and cuts their values at word boundaries.
    # `spark`: true puts a braille sparkline on the sort column, false on none (narrow panels), an
    # Array of column keys on those columns.
    Top = Data.define(:resource, :by, :limit, :columns, :group_by, :widths, :spark) do
      # The columns that get a sparkline.
      def spark_columns
        case spark
        when true then [by].compact.map(&:to_sym)
        when false, nil then []
        else Array(spark).map(&:to_sym)
        end
      end
    end
    Band = Data.define(:resource, :show)
    Detail = Data.define(:resource, :columns)

    SIGNALS = :view_signals
    FPS = 10
    PULSE_SECONDS = 0.5
    TWEEN_SECONDS = 0.35

    # Prepended to a view app's Motion: `hold` (r2ui's table gutter) no longer keeps frames due.
    module NoHold
      def hold(_seconds) = nil
    end
    MIN_TILE = 18 # room for a "claude 12345" title uncut

    class << self
      # The view UI.install is building (nil for the default dashboard): resource decorations
      # (heat styles, braille sort column, priorities) apply only then.
      attr_accessor :installing

      # --no-motion / AGENTMON_MOTION=0 turn animation off (R2UI::Motion#enabled).
      attr_writer :motion

      def motion? = @motion.nil? ? ENV["AGENTMON_MOTION"] != "0" : @motion

      def build(name, title:, &block)
        builder = ViewBuilder.new(title)
        builder.instance_eval(&block)
        View.new(name: name.to_sym, title: builder.title, rows: builder.rows.freeze,
                 focused: builder.focused_rows.freeze)
      end

      def signal(name, **) = Signals.parse(name.to_s, **)

      # Every Top item of `view` for `resource` (home and focused rows).
      def tops(view, resource)
        view.all_rows.flat_map(&:panels).grep(PanelDef).flat_map(&:items).grep(Top).select { |t| t.resource == resource }
      end
    end

    class ViewBuilder
      attr_reader :rows, :focused_rows

      def initialize(title)
        @title = title
        @rows = []
        @focused_rows = []
        @in_focused = false
      end

      def title(text = nil)
        @title = text if text
        @title
      end

      # Inside `focused`, rows go to the drill-down instead of the home rows.
      def row(height: nil, &block)
        builder = RowBuilder.new
        builder.instance_eval(&block)
        (@in_focused ? @focused_rows : @rows) << RowDef.new(height:, panels: builder.panels.freeze)
      end

      # The rows shown instead of the home rows while a session is focused (engine.focus): Enter on
      # the Sessions table (or the band) drills in, Escape comes back. Once per view, not nested.
      def focused(&block)
        raise ArgumentError, "focused: needs a block of rows" unless block
        raise ArgumentError, "focused: not inside another focused" if @in_focused
        raise ArgumentError, "focused: only once per view" if @focused_rows.any?

        @in_focused = true
        instance_eval(&block)
      ensure
        @in_focused = false
      end
    end

    class RowBuilder
      attr_reader :panels

      def initialize = @panels = []

      # A panel of view words. `resource:` is set by a `top` inside, else the hidden signals feed.
      def panel(name, title: nil, span: 1, resource: nil, **options, &block)
        builder = PanelBuilder.new
        builder.instance_eval(&block) if block
        items = builder.items.freeze
        resource ||= items.grep(Top).first&.resource || SIGNALS
        @panels << PanelDef.new(name: name.to_sym, title:, span:, resource:, items:, options:)
      end

      # An existing registered agentmon panel (:memory, :session, :process, :detail, ...).
      def use(name, span: nil, title: nil) = @panels << UseDef.new(name: name.to_sym, span:, title:)

      # Row-level shortcuts: one panel named after what it shows.
      def top(resource, span: 1, title: nil, **)
        panel(resource, title:, span:, resource:) { top(resource, **) }
      end

      def band(resource = :session, span: 1, title: "Sessions", **)
        panel(:band, title:, span:) { band(resource, **) }
      end

      def detail(resource = :process, span: 1, title: "Detail", **)
        panel(:detail, title:, span:) { detail(resource, **) }
      end
    end

    class PanelBuilder
      attr_reader :items

      def initialize = @items = []

      def meter(sig, of: nil, max: nil, label: nil, unit: nil, heat: true)
        @items << Meter.new(signal: Views.signal(sig, of:, max:, label:, unit:), heat:)
      end

      # Several signals stack, sharing `height` chart lines (nil: the rest of the panel; a Float
      # below 1: that share of the lines left, labels included, e.g. 0.6 above a `top`).
      def trend(*sigs, height: 3, label: nil, max: nil, unit: nil)
        @items << Trend.new(signals: sigs.map { |s| Views.signal(s, label:, max:, unit:) }.freeze, height:)
      end

      def spark(sig, label: nil, max: nil, unit: nil) = @items << Spark.new(signal: Views.signal(sig, label:, max:, unit:))

      def stat(*sigs, columns: 2) = @items << Stat.new(signals: sigs.map { |s| Views.signal(s) }.freeze, columns:)

      # `spark:` true (the `by:` column), false (none) or column keys (`%i[cpu footprint]`).
      def top(resource, by: nil, limit: nil, columns: nil, group_by: nil, widths: {}, spark: true)
        spark = Array(spark).map(&:to_sym).freeze unless [true, false, nil].include?(spark)
        @items << Top.new(resource: resource.to_sym, by:, limit:, columns: columns&.map(&:to_sym), group_by:,
                          widths: widths.transform_keys(&:to_sym).freeze, spark:)
      end

      def band(resource = :session, show: %i[cpu footprint]) = @items << Band.new(resource:, show:)

      def detail(resource = :process, columns: 1) = @items << Detail.new(resource:, columns:)
    end

    # --- per-app drawing state ---

    # The engine, signal history, last shown texts (for pulses) and a cache of drawn strings, one
    # per dashboard built from a view (declared on it, so drawers find it).
    class Runtime
      CACHE_LIMIT = 4000

      attr_reader :engine, :view, :history

      def initialize(engine:, view:)
        @engine = engine
        @view = view
        @history = History.new
        @shown = {}
        @cache = {}
      end

      # The latest reading (focused when a session is), never sampling here: feeds keep it fresh.
      def reading = @engine.current(max_age: Float::INFINITY)

      def machine = @engine.current(max_age: Float::INFINITY, focused: false)

      # The signal's recent values: the metric's own trend, else ours (appended once per reading).
      def series(signal, reading)
        Signals.trend(signal, reading) ||
          @history.record(history_key(signal), reading.at, Signals.value(signal, reading))
      end

      def history_key(signal) = signal.metric == :focus ? "#{signal.name}@#{@engine.focus}" : signal.name

      # 0..1, quantized: 1.0 on the frame `text` changed for `key`, fading over a second.
      def pulse(motion, key, text)
        before = @shown[key]
        @shown[key] = text
        level = motion.pulse(key, !before.nil? && before != text, duration: PULSE_SECONDS)
        (level * 12).round / 12.0
      end

      # A drawn string for `key`, built once per distinct key.
      def cached(key)
        @cache.clear if @cache.size > CACHE_LIMIT
        @cache.fetch(key) { @cache[key] = yield }
      end

      # --- the drill-down (`focused`): which r2ui rows are on the dashboard ---

      # Splits the r2ui dashboard's rows (built as home rows, then focused rows) into the two sets.
      def attach(dashboard)
        rows = dashboard.rows.dup
        @home_rows = rows.first(@view.rows.size).freeze
        @focused_rows = rows.drop(@view.rows.size).freeze
      end

      def drill? = @view.drill?

      def mode = @engine.focus ? :focused : :home

      # Puts the set for the current mode on the dashboard (only that set: its layout, panels, tab
      # order and drawing are exactly those of a view with only these rows).
      def show(dashboard)
        want = mode == :focused ? @focused_rows : @home_rows
        rows = dashboard.rows
        return if rows.size == want.size && rows.each_with_index.all? { |r, i| r.equal?(want[i]) }

        rows.replace(want)
      end
    end

    # --- what each word shows ---

    module Draw
      module_function

      def text(signal, value) = Signals.format(value, signal.unit)

      # "42.0%", or "23G / 32G 71%" with a total.
      def meter_text(signal, reading)
        value = Signals.value(signal, reading)
        return nil if value.nil?

        total = Signals.total(signal, reading)
        return text(signal, value) unless total&.positive?

        "#{text(signal, value)} / #{text(signal, total)} #{(value * 100.0 / total).round}%"
      end

      def max_width(texts) = texts.map { |t| Widgets.visible_width(t || Widgets::UNKNOWN) }.max || 0

      # Labels and texts of a panel's one-line words share widths, so bars and charts line up.
      def label_width(panel)
        panel.items.filter_map { |i| (i.respond_to?(:signal) && i.signal.label) || nil }.map(&:length).max
      end

      def meter(ctx, rt, item)
        reading = rt.reading
        sig = item.signal
        fraction = Signals.fraction(sig, reading)
        text = meter_text(sig, reading)
        shown = fraction && ctx.motion.tween([:agentmon_meter, ctx.panel.name, sig.name], fraction,
                                                  duration: TWEEN_SECONDS)
        pulse = rt.pulse(ctx.motion, [:agentmon_pulse, ctx.panel.name, sig.name], text)
        text_w = max_width(ctx.panel.items.grep(Meter).map { |m| meter_text(m.signal, reading) })
        label_w = label_width(ctx.panel)
        width = ctx.width
        steps = shown && (shown * width * 8).round
        rt.cached([:meter, item, width, steps, text, pulse, text_w, label_w, fraction&.round(2)]) do
          bar = item.heat && fraction ? R2UI::Widgets::Glyphs.heat(shown) : R2UI::Widgets::Glyphs.fg(Widgets::ACCENT)
          Widgets.meter(label: sig.label, text:, fraction: shown, width:, label_width: label_w, text_width: text_w,
                        bar_sgr: bar, text_sgr: value_sgr(sig, fraction, pulse, text))
        end
      end

      def value_sgr(sig, fraction, pulse, text)
        Widgets.value_sgr(unit: sig.unit, fraction: sig.unit == :percent ? fraction : nil, pulse:, known: !text.nil?)
      end

      def chart_sgr(sig, fraction)
        sig.max && fraction ? R2UI::Widgets::Glyphs.heat(fraction) : R2UI::Widgets::Glyphs.fg(Widgets::ACCENT)
      end

      def trend(ctx, rt, item)
        reading = rt.reading
        sigs = item.signals
        room = case item.height
               when nil then ctx.height - sigs.size                         # the rest of the panel
               when Float then (ctx.height * item.height).floor - sigs.size # a share of what is left
               else item.height
               end
        room = [room, sigs.size].max
        share, extra = room.divmod(sigs.size)
        sigs.each_with_index.flat_map do |sig, i|
          values = rt.series(sig, reading)
          value = Signals.value(sig, reading)
          fraction = Signals.fraction(sig, reading)
          text = text(sig, value)
          pulse = rt.pulse(ctx.motion, [:agentmon_pulse, ctx.panel.name, sig.name], text)
          height = share + (i < extra ? 1 : 0)
          # The header pulses frame by frame; the braille area changes once per sample, so it is
          # cached on the series itself (a pulse frame redraws only the header).
          header = rt.cached([:trend_head, sig.label, ctx.width, text, pulse, fraction&.round(2)]) do
            Widgets.sides(sig.label.to_s, R2UI::Widgets::Glyphs.fg(Widgets::MUTED), text || Widgets::UNKNOWN,
                          value_sgr(sig, fraction, pulse, text), ctx.width)
          end
          area = rt.cached([:trend_area, ctx.width, height, sig.max, values.hash, fraction&.round(2)]) do
            Widgets.trend(label: "", text: "", values:, width: ctx.width, height:, max: sig.max,
                          chart_sgr: chart_sgr(sig, fraction)).drop(1)
          end
          [header, *area]
        end.join("\n")
      end

      def spark(ctx, rt, item)
        reading = rt.reading
        sig = item.signal
        values = rt.series(sig, reading)
        fraction = Signals.fraction(sig, reading)
        text = text(sig, Signals.value(sig, reading))
        pulse = rt.pulse(ctx.motion, [:agentmon_pulse, ctx.panel.name, sig.name], text)
        label_w = label_width(ctx.panel)
        text_w = max_width(ctx.panel.items.grep(Spark).map { |s| text(s.signal, Signals.value(s.signal, reading)) })
        rt.cached([:spark, item, ctx.width, values.hash, text, pulse, label_w, text_w]) do
          Widgets.spark(label: sig.label, values:, text:, width: ctx.width, max: sig.max, label_width: label_w,
                        text_width: text_w, chart_sgr: chart_sgr(sig, fraction),
                        text_sgr: value_sgr(sig, fraction, pulse, text))
        end
      end

      def stat(ctx, rt, item)
        reading = rt.reading
        columns = ctx.width < 40 ? 1 : item.columns
        pairs = item.signals.map do |sig|
          text = text(sig, Signals.value(sig, reading))
          pulse = rt.pulse(ctx.motion, [:agentmon_pulse, ctx.panel.name, sig.name], text)
          [sig.label, text, value_sgr(sig, Signals.fraction(sig, reading), pulse, text)]
        end
        rt.cached([:stat, item, ctx.width, columns, pairs]) do
          Widgets.stat(pairs:, width: ctx.width, columns:).join("\n")
        end
      end

      # The Detail panel's pairs for the selected process, reflowed into `columns` columns that
      # fill the panel top to bottom. The command line (wrapped by ProcessDetail) is joined back
      # and cut at a word boundary instead.
      def detail(ctx, rt, item)
        columns = [item.columns, 1].max
        gap = 3
        col_w = (ctx.width - (gap * (columns - 1))) / columns
        text = UI::ProcessDetail.render(ctx.app, rt.engine, ctx.width)
        lines = join_wrapped(text.split("\n"))
        rt.cached([:detail, ctx.width, ctx.height, lines]) do
          # The heading (name and pid) gets its own full-width line; the pairs flow in columns.
          head, *pairs = lines
          head = R2UI::Widgets::Glyphs.paint(Widgets.cut(head.to_s, ctx.width), "1")
          rows = [(pairs.size + columns - 1) / columns, ctx.height - 1].min
          rows = 0 if rows.negative?
          cells = pairs.first(rows * columns).map { |line| fit_pair(line, col_w) }
          body = Array.new(rows) do |r|
            Array.new(columns) { |c| Widgets.pad(cells[(c * rows) + r] || "", col_w) }.join(" " * gap)
          end
          [head, *body].join("\n")
        end
      end

      LABEL = UI::ProcessDetail::LABEL_WIDTH

      def join_wrapped(lines)
        lines.each_with_object([]) do |line, out|
          if line.start_with?(" " * LABEL) && out.last&.start_with?("Command")
            out[-1] = out.last + line[LABEL..]
          else
            out << line
          end
        end
      end

      def fit_pair(line, width)
        return Widgets.cut(line, width) if line.length <= width || line.length <= LABEL

        label = line[0, LABEL]
        value = line[LABEL..]
        label + Widgets.cut(value, [width - LABEL, 0].max)
      end
    end

    # --- the band of session tiles ---

    module BandDraw
      Tile = Data.define(:id, :title, :cpu, :values, :series_key)

      module_function

      # The machine first (selected when nothing is focused), then each live session, oldest first.
      def tiles(rt, item)
        reading = rt.machine
        system = reading[:system]
        memory = reading[:memory]
        machine = Tile.new(id: nil, title: "machine", cpu: system&.cpu,
                           values: [["used", memory&.used && R2UI::Format.bytes(memory.used), :bytes]],
                           series_key: :machine)
        sessions = (reading[:session_ledger] || []).select(&:alive?).sort_by { |s| [s.started_at || 0, s.id] }
        [machine] + sessions.map do |s|
          values = (item.show - [:cpu]).map do |member|
            unit = Signals.infer(member)[:unit]
            [Signals.infer(member)[:label], Signals.format(Signals.read(s, member), unit), unit]
          end
          Tile.new(id: s.id, title: s.label, cpu: s.cpu, values:, series_key: s.id)
        end
      end

      def draw(ctx, rt, item)
        all = tiles(rt, item)
        width = ctx.width
        fit = [width / MIN_TILE, 1].max
        shown = all.size <= fit ? all : all.first(fit - 1)
        more = all.size - shown.size
        slots = shown.size + (more.positive? ? 1 : 0)
        tile_w = width / slots
        reading = rt.machine
        cursor = ctx.store(:agentmon_band)[:cursor]
        focus = rt.engine.focus
        columns = shown.each_with_index.map do |tile, i|
          w = i == slots - 1 && more.zero? ? width - (tile_w * (slots - 1)) : tile_w
          tile_lines(ctx, rt, tile, w, ctx.height, focused: tile.id == focus, cursor: cursor == i, at: reading.at)
        end
        if more.positive?
          w = width - (tile_w * shown.size)
          columns << Widgets.tile(title: "+#{more}", body: ["#{more} more", "→ to pick"], width: w,
                                  height: ctx.height, border_sgr: R2UI::Widgets::Glyphs.fg(Widgets::DIM))
        end
        Array.new(ctx.height) { |row| columns.map { |c| c[row] || "" }.join }.join("\n")
      end

      def tile_lines(ctx, rt, tile, width, height, focused:, cursor:, at:)
        glow = ctx.motion.tween([:agentmon_band, tile.series_key], focused ? 1.0 : 0.0, duration: 0.3)
        values = rt.history.record("band.cpu.#{tile.series_key}", at, tile.cpu)
        cpu_text = tile.cpu && Kernel.format("%.0f%%", tile.cpu)
        pulse = rt.pulse(ctx.motion, [:agentmon_band_pulse, tile.series_key], cpu_text)
        fraction = tile.cpu && (tile.cpu / 100.0).clamp(0.0, 1.0)
        shown = fraction && ctx.motion.tween([:agentmon_band_cpu, tile.series_key], fraction, duration: TWEEN_SECONDS)
        key = [:tile, tile, width, height, (glow * 16).round, cursor, values.hash,
               shown && (shown * width * 8).round, pulse]
        rt.cached(key) do
          inner = width - 2
          border = if cursor then "1;#{R2UI::Widgets::Glyphs.fg("#E0E0E0")}"
                   else R2UI::Widgets::Glyphs.fg(R2UI::Motion.mix_hex(Widgets::DIM, Widgets::ACCENT, glow))
                   end
          title_sgr = glow > 0.5 ? "1;#{R2UI::Widgets::Glyphs.fg(Widgets::ACCENT)}" : R2UI::Widgets::Glyphs.fg("#BCBCBC")
          text_sgr = Widgets.value_sgr(unit: :percent, fraction:, pulse:, known: !cpu_text.nil?)
          body = [Widgets.meter(label: "cpu", text: cpu_text, fraction: shown, width: inner, text_width: 4,
                                text_sgr:)]
          pairs = tile.values.map { |label, text, unit| [label, text, Widgets.value_sgr(unit:, known: !text.nil?)] }
          body.concat(Widgets.stat(pairs:, width: inner, columns: 1))
          body << Widgets.spark(label: "", values:, text: "", width: inner, max: 100,
                                chart_sgr: R2UI::Widgets::Glyphs.heat(fraction || 0))
          Widgets.tile(title: tile.title, body: body.first([height - 2, 0].max), width:, height:,
                       border_sgr: border, title_sgr:)
        end
      end

      # Key handling: ←/→ (h/l) move a cursor over the tiles, Enter focuses the tile's session
      # (the machine tile clears the focus), Escape drops the cursor (and the focus, through
      # ui/session_focus.rb).
      def key(ctx, rt, item, key)
        store = ctx.store(:agentmon_band)
        count = tiles(rt, item).size
        case key
        when :left, "h", :right, "l"
          step = %i[left].include?(key) || key == "h" ? -1 : 1
          start = store[:cursor] || tiles(rt, item).index { |t| t.id == rt.engine.focus } || 0
          store[:cursor] = (start + step) % count
          true
        when :enter
          return false unless store[:cursor]

          tile = tiles(rt, item)[store.delete(:cursor).clamp(0, count - 1)]
          UI::SessionFocus.focus!(ctx.app, rt.engine, tile.id)
          true
        when :escape
          had = store.delete(:cursor)
          !had.nil? && rt.engine.focus.nil?
        else false
        end
      end
    end

    # --- the drill-down: home rows, or the focused rows while a session is focused ---

    # r2ui has no way to hide panels or switch a dashboard's rows, so the view's r2ui dashboard is
    # built with both sets (App.new then makes feeds and table states for every panel) and the
    # Runtime swaps `dashboard.rows` to the set for engine.focus before every key and every frame.
    # Only the visible set's panels are on the dashboard: r2ui lays them out as if alone (fixed
    # heights, shared rest, the last row taking what is left), tab cycles only them, hidden panels
    # draw nothing and lookups by name (:session, :process, :detail) find the visible one.
    module Drill
      STORE = :agentmon_drill
      HOME = "sessions · ⏎ open a session"
      BACK = "esc back to sessions"

      module_function

      # Shows the set for the current mode and moves key focus when the mode changed: to the
      # first table panel of the focused set when drilling in, back to the home panel that had it
      # when coming out (the first home table panel when there is none, e.g. at start).
      def sync(app, rt)
        return unless rt&.drill?

        dashboard = app.dashboard
        rt.show(dashboard)
        store = app.store(STORE)
        mode = rt.mode
        before = store[:mode]
        panels = dashboard.panels
        return if before == mode && panels.include?(app.focus)

        store[:mode] = mode
        store[:home_focus] = app.focus if before == :home
        target = mode == :home ? store.delete(:home_focus) : nil
        target = nil unless panels.include?(target)
        target ||= panels.find(&:table) || panels.first
        app.focus = target if target
      end

      # The status bar on a view with a drill-down: where you are and how to go back.
      def status(rt)
        return nil unless rt&.drill?

        engine = rt.engine
        id = engine.focus or return HOME
        label = engine.focused_session&.label || id.to_s
        "▸ #{label} · #{BACK}"
      end
    end

    # --- resource decoration (only while a view is installed) ---

    module Decorate
      PRIORITIES = {
        process: { name: 9, cpu: 9, footprint: 8, session: 6, pid: 5, run_wait: 4, read_rate: 4, write_rate: 4,
                   pagein_rate: 3, resident: 2, cwd: 1 },
        session: { label: 9, cpu: 9, footprint: 8, processes: 6, age: 5, net_out_rate: 4, net_in_rate: 4,
                   peak_footprint: 3, remote_hosts: 3, connections: 2, read_rate: 2, write_rate: 2, cpu_seconds: 1,
                   bytes_written: 1, bytes_in: 1, bytes_out: 1 }
      }.freeze
      # The anomaly mark (docs/views.md, "Anomaly mark"): a session row whose `net_flags` is not
      # empty shows FLAG before its label, in FLAG_COLOR. The metric decides; this only marks.
      FLAG = "⚑ "
      FLAG_COLOR = "#E5484D"

      # Text columns get a fixed width in a view, so their values are cut at a word boundary here
      # (r2ui's table cuts a flexible column mid-word). `top widths:` overrides these.
      WIDTHS = {
        process: { name: 18, session: 16, cwd: 20 },
        session: { label: 18 }
      }.freeze
      FROM_LEFT = %i[cwd].freeze

      module_function

      # Heat on percent cells (a full core is red), the accent on bytes, a braille sparkline on
      # each `spark:` column (the sort column by default), priorities for dropping, fixed word-cut
      # widths (WIDTHS, then `top widths:`) and the anomaly mark on session labels. Applies to
      # every panel of the resource on a view dashboard, `use` ones too.
      def call(resource, name)
        view = Views.installing or return
        tops = Views.tops(view, name)
        sparks = tops.flat_map(&:spark_columns).uniq
        sparks = [:cpu] if tops.empty?
        widths = tops.map(&:widths).reduce(WIDTHS.fetch(name, {}), :merge)
        resource.columns.map! { |col| column(col, name, sparks, widths) }
      end

      def flagged?(row)
        flags = Signals.fetch(row, :net_flags)
        flags.respond_to?(:empty?) && !flags.empty?
      end

      # The label with the mark when `row` is flagged, cut at a word boundary to `width` cells
      # (nil: uncut).
      def flag_label(row, value, width)
        return (width ? Widgets.cut(value, width) : value) unless value.is_a?(String) && flagged?(row)

        FLAG + (width ? Widgets.cut(value, width - Widgets.visible_width(FLAG)) : value)
      end

      def column(col, name, sorts, widths)
        opts = { priority: PRIORITIES.dig(name, col.key) || 0 }
        case col.format
        when :percent
          opts[:style] = ->(value, _line) { value.is_a?(Numeric) ? R2UI::Widgets::Glyphs.heat(value / 100.0) : nil }
        when :bytes, :bytes_per_sec
          opts[:style] = ->(value, _line) { value.is_a?(Numeric) ? R2UI::Widgets::Glyphs.fg(Widgets::ACCENT) : nil }
        end
        if sorts.include?(col.key) && col.numeric?
          opts.merge!(sparkline: :braille, spark_width: 5, spark_max: col.format == :percent ? 100 : nil)
          if col.format == :percent
            opts[:spark_style] = ->(values, _line) { R2UI::Widgets::Glyphs.heat((values.last || 0) / 100.0) }
          end
        elsif col.sparkline
          opts[:sparkline] = false
        end
        reader = col.reader
        key = col.key
        w = widths[key]
        if name == :session && key == :label
          opts[:width] = w if w
          opts[:reader] = lambda do |row|
            flag_label(row, reader ? reader.call(row) : R2UI::Value.fetch(row, key), w)
          end
          red = R2UI::Widgets::Glyphs.fg(FLAG_COLOR)
          opts[:style] = ->(value, _line) { value.is_a?(String) && value.start_with?(FLAG) ? red : nil }
        elsif w
          opts[:width] = w
          opts[:reader] = lambda do |row|
            value = reader ? reader.call(row) : R2UI::Value.fetch(row, key)
            value.is_a?(String) ? Widgets.cut(value, w, from: FROM_LEFT.include?(key) ? :left : :right) : value
          end
        end
        col.with(**opts)
      end
    end

    # Reached through the resource builder: r2ui has no way to amend a column another file
    # declared (`column` with the same key appends a second one), so this edits the list.
    %i[process session].each do |name|
      Agentmon.extend_resource(name) do |_engine|
        Decorate.call(instance_variable_get(:@r), name)
      end
    end

    # --- r2ui wiring ---

    module_function

    # The r2ui dashboard (named like the default one, so every agentmon dashboard extension
    # applies) built from `view`'s rows: the home rows, then the focused ones (Drill shows one set).
    def dashboard(view, engine, registry)
      extras = registry.dashboard_blocks
      runtime = Runtime.new(engine:, view:)
      built = R2UI::DSL::Dashboard.build(UI::DASHBOARD) do
        title view.title
        extras.each { |b| instance_exec(engine, &b) }
        agentmon_view(runtime)
        view.all_rows.each do |spec|
          row(height: spec.height) do
            spec.panels.each { |p| Views.place(self, p, engine, registry, runtime) }
          end
        end
      end
      runtime.attach(built)
      built
    end

    def place(row, spec, engine, registry, runtime)
      if spec.is_a?(UseDef)
        p = registry[:panel, spec.name] or raise Error, "use #{spec.name}: no such agentmon panel"
        items = p.block && proc { instance_exec(engine, &p.block) }
        return row.panel(p.name, resource: p.resource, span: spec.span || p.span, title: spec.title || p.title,
                                 **p.options, &items)
      end

      options = spec.options
      if spec.items.any?(Band)
        options = options.merge(border_style: lambda {
          engine.focus ? R2UI::Widgets::Glyphs.fg(Widgets::ACCENT) : nil
        })
      end
      row.panel(spec.name, resource: spec.resource, span: spec.span, title: spec.title, **options) do
        spec.items.each do |item|
          if item.is_a?(Top)
            sort = item.by && [item.by, :desc]
            table(sort:, limit: item.limit, columns: item.columns, group_by: item.group_by, motion: true)
          else
            agentmon_view_item(item)
          end
        end
      end
    end

    # The hidden resource behind panels with only view words: its feed samples the engine on
    # the feed thread every interval (so drawers never do) and marks frames due.
    # When the view also shows a table (or a `use` panel), that resource's feed already samples
    # every interval and marks frames due, so this one refreshes once an hour: every feed refresh
    # is a frame, and a second feed at another phase would double the idle frames.
    def signals_resource(engine, view = Views.installing)
      tables = view && view.all_rows.flat_map(&:panels).any? { |p| p.is_a?(UseDef) || p.resource != SIGNALS }
      every = tables ? 3600 : engine.interval
      R2UI::DSL::Resource.build(SIGNALS) do
        title "Signals"
        source do
          engine.current
          []
        end
        refresh every:
      end
    end
  end

  R2UI.extension :agentmon_views do
    dsl :dashboard do
      def agentmon_view(runtime) = declare(:agentmon_view, runtime)
    end

    dsl :panel do
      def agentmon_view_item(value) = item(value)
    end

    helpers do
      # The Runtime of the view dashboard drawing; nil on other dashboards.
      def view_runtime = dashboard.declared(:agentmon_view).first
    end

    setup do
      app.motion.enabled = Views.motion?
      # Cost (docs/views.md, "Motion"): r2ui's table gutter holds the motion active for 1.5-2 s
      # after every reorder, and a process list reorders on nearly every sample, so frames would
      # never stop. On a view dashboard the gutter marks show and fade with the frames that tweens
      # and pulses already draw, and go at the next sample, instead of keeping 20 fps running.
      app.motion.singleton_class.prepend(Views::NoHold) if view_runtime
      Views::Drill.sync(app, view_runtime)
    end

    # The drill-down follows engine.focus: before any handler sees a message (so tab, Enter and
    # the name lookups see only the visible panels), after handlers changed the focus, and before
    # every frame (`styles` is the only hook App#frame runs before laying out; a focus set
    # directly, or a session that ended, shows on the next frame).
    observe { |_message| Views::Drill.sync(app, view_runtime) }
    after_update { Views::Drill.sync(app, view_runtime) }
    styles do
      rt = view_runtime
      if rt&.drill?
        UI::SessionFocus.clear_if_gone(app, rt.engine)
        Views::Drill.sync(app, rt)
      end
      nil
    end

    # Where you are and how to go back, on views with a drill-down. r2ui shows the first status
    # hook that returns text, in load order, and has no priority for them (extension.rb:87), so
    # this registers through the hook method with one above session_focus's "focus: ..." (which
    # loads first). Problems still win: with engine errors this returns nil and agentmon_errors
    # shows them.
    hook(:status, nil, proc {
      rt = view_runtime
      rt && Agentmon.engine_errors.empty? ? Views::Drill.status(rt) : nil
    }, priority: 10)

    # Animation needs fewer frames than r2ui's default 20 fps to look smooth at these durations.
    program_options do
      view_runtime && Views.motion? ? { fps: Views::FPS } : nil
    end

    panel_item(Views::Meter) { |item| Views::Draw.meter(self, view_runtime, item) }
    panel_item(Views::Trend) { |item| Views::Draw.trend(self, view_runtime, item) }
    panel_item(Views::Spark) { |item| Views::Draw.spark(self, view_runtime, item) }
    panel_item(Views::Stat) { |item| Views::Draw.stat(self, view_runtime, item) }
    panel_item(Views::Band) { |item| Views::BandDraw.draw(self, view_runtime, item) }
    panel_item(Views::Detail) { |item| Views::Draw.detail(self, view_runtime, item) }

    on(->(m) { m.is_a?(Bubbletea::KeyMessage) }, priority: 60) do |message|
      rt = view_runtime or pass
      band = dashboard.panels.flat_map(&:items).grep(Views::Band).first or pass
      Views::BandDraw.key(self, rt, band, R2UI::Keys.name(message)) or pass
      nil
    end
    # No "←→ pick" hint: r2ui's status bar drops every hint when they don't all fit beside the
    # status text (renderer.rb draw_status), and at 100 columns one more would hide them all.
  end
end

# The layouts: one file each, written only in the words above.
%w[dense focus visual].each do |name|
  path = File.join(__dir__, "views", "#{name}.rb")
  require path if File.exist?(path)
end
