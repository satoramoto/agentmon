# frozen_string_literal: true

require "r2ui"

module Agentmon
  module Views
    # The drawing layer of the performance-view DSL (docs/views.md, "The DSL"): pure functions,
    # Strings in, Strings out, no app, engine or state. Every line returned is exactly `width`
    # visible cells (SGR escapes count zero, wide characters two), padded with spaces, never more.
    # Colour is 24-bit SGR through R2UI's Glyphs: percents take heat, bytes the accent, unknown
    # values show "–" in dim.
    #
    # The examples below are the plain text (escapes stripped).
    #
    #   cut("claude 74432 · agentmon", 15)              # => "claude 74432…"
    #   cut("~/src/very/long/repo", 12, from: :left)    # => "…/long/repo"
    #   meter(label: "busy", text: "42%", fraction: 0.42, width: 20)
    #                                                   # => "busy ▕███▊     ▏ 42%"
    #   meter(label: "busy", text: nil, fraction: nil, width: 16)
    #                                                   # => "busy ▕       ▏ –"
    #   spark(label: "cpu", values: [1, 2, 3, 4], text: "4%", width: 12)
    #                                                   # => "cpu ⠀⠀⠀⣠⣾ 4%"
    #   trend(label: "CPU", text: "42%", values: [1, 2, 3, 4], width: 10, height: 1)
    #                                                   # => ["CPU    42%", "⠀⠀⠀⠀⠀⠀⠀⠀⣠⣾"]
    #   stat(pairs: [["load1", "2.1", nil], ["load5", nil, nil]], width: 24)
    #                                                   # => ["load1   2.1  load5     –"]
    #   tile(title: "claude 4242", body: ["cpu 12%"], width: 18, height: 3)
    #                                                   # => ["╭─ claude 4242 ──╮",
    #                                                   #     "│cpu 12%         │",
    #                                                   #     "╰────────────────╯"]
    #
    # value_sgr picks the SGR params for a value: heat for a percent with a fraction, the accent
    # for bytes and byte rates, nil otherwise, dim when unknown; a pulse (0..1) mixes the colour
    # toward PULSE and turns bold above 0.3.
    module Widgets
      G = R2UI::Widgets::Glyphs
      ACCENT = "#D97757"
      DIM = "#555555"
      TROUGH = "#303030"
      PULSE = "#FFE0C2"
      PLAIN = "#BCBCBC"
      MUTED = "#8A8A8A"
      UNKNOWN = "–"
      ELLIPSIS = "…"
      SEPARATORS = [" ", "·", "-", ",", ":", "/"].freeze
      BYTE_UNITS = %i[bytes bytes_per_sec signed_bytes_per_sec].freeze
      SGR = /\e\[[0-9;?]*[ -\/]*[@-~]/
      TOKEN = /\e\[[0-9;?]*[ -\/]*[@-~]|\X/

      module_function

      # Visible cells of `str`: SGR escapes are zero-width, wide characters two.
      def visible_width(str)
        R2UI::Compat::Tea::ANSI.string_width(str.to_s.gsub(SGR, ""))
      end

      # `str` padded with spaces to `width` cells (right-aligned with align: :right). Never cuts.
      def pad(str, width, align: :left)
        str = str.to_s
        gap = width - visible_width(str)
        return str if gap <= 0

        align == :right ? (" " * gap) + str : str + (" " * gap)
      end

      # Plain `text` cut to at most `width` cells, the ellipsis at a word boundary when one exists.
      def cut(text, width, from: :right)
        text = text.to_s
        return "" if width <= 0
        return text if visible_width(text) <= width
        return ELLIPSIS if width == 1

        from == :left ? cut_left(text, width) : cut_right(text, width)
      end

      # SGR params (or nil) for a value of `unit`; see the module comment.
      def value_sgr(unit:, fraction: nil, pulse: 0.0, known: true)
        return G.fg(DIM) unless known

        heat = unit == :percent && !fraction.nil?
        bytes = BYTE_UNITS.include?(unit)
        pulse = pulse.to_f.clamp(0.0, 1.0)
        if pulse.positive?
          base = if heat then G.gradient(G::HEAT, fraction.to_f.clamp(0.0, 1.0))
                 elsif bytes then ACCENT
                 else PLAIN
                 end
          sgr = G.fg(R2UI::Motion.mix_hex(base, PULSE, pulse))
          return pulse > 0.3 ? "#{sgr};1" : sgr
        end
        return G.heat(fraction) if heat
        return G.fg(ACCENT) if bytes

        nil
      end

      # One line: `label ▕bar▏ text`; without room for a 3-cell bar, label left and text right.
      def meter(label:, text:, fraction:, width:, label_width: nil, text_width: nil, bar_sgr: nil, text_sgr: nil)
        return "" if width <= 0

        known = !fraction.nil? && !text.nil?
        text, text_sgr = UNKNOWN, G.fg(DIM) unless known
        label = label.to_s
        text = text.to_s
        label_w = label_width || visible_width(label)
        text_w = text_width || visible_width(text)
        bw = width - label_w - text_w - 4
        return sides(label, nil, text, text_sgr, width) if bw < 3

        fraction = known ? fraction.to_f.clamp(0.0, 1.0) : 0.0
        bar_sgr ||= known ? G.heat(fraction) : G.fg(DIM)
        line = pad(cut(label, label_w), label_w) + " " + G.paint("▕", G.fg(DIM)) +
               G.paint(G.bar(fraction, bw), "#{bar_sgr};#{G.bg(TROUGH)}") + G.paint("▏", G.fg(DIM)) +
               " " + pad(G.paint(text, text_sgr), text_w, align: :right)
        fit(line, width)
      end

      # One line: `label ⣀⣠⣴⣾ text` (braille sparkline, newest at the right).
      def spark(label:, values:, text:, width:, max: nil, label_width: nil, text_width: nil, chart_sgr: nil, text_sgr: nil)
        return "" if width <= 0

        text, text_sgr = UNKNOWN, G.fg(DIM) if text.nil?
        label = label.to_s
        text = text.to_s
        label_w = label_width || visible_width(label)
        text_w = text_width || visible_width(text)
        sw = width - label_w - text_w - 2
        return sides(label, nil, text, text_sgr, width) if sw < 2

        values = Array(values)
        values = Array.new(sw * 2, 0) if values.size < 2
        chart = G.braille_line(values, sw, max: max)
        line = pad(cut(label, label_w), label_w) + " " + G.paint(chart, chart_sgr || G.fg(ACCENT)) +
               " " + pad(G.paint(text, text_sgr), text_w, align: :right)
        fit(line, width)
      end

      # height + 1 lines: a header (label left, text right) then a braille area chart.
      def trend(label:, text:, values:, width:, height:, max: nil, chart_sgr: nil, text_sgr: nil)
        return [] if width <= 0

        text, text_sgr = UNKNOWN, G.fg(DIM) if text.nil?
        header = sides(label.to_s, G.fg(MUTED), text.to_s, text_sgr, width)
        return [header] if height <= 0

        area = G.braille_area(Array(values), width, height, max: max)
        [header] + area.map { |row| fit(G.paint(row, chart_sgr || G.fg(ACCENT)), width) }
      end

      # A label/value grid, `columns` cells per line; pairs are [label, text_or_nil, sgr_or_nil].
      def stat(pairs:, width:, columns: 2, gap: 2)
        return [] if width <= 0 || pairs.nil? || pairs.empty?

        columns = [columns.to_i, 1].max
        gap = [gap.to_i, 0].max
        cell_w = (width - (gap * (columns - 1))) / columns
        pairs.each_slice(columns).map do |row|
          next " " * width if cell_w <= 0

          cells = row.map do |label, text, sgr|
            text, sgr = UNKNOWN, G.fg(DIM) if text.nil?
            sides(label.to_s, G.fg(MUTED), text.to_s, sgr, cell_w)
          end
          fit(cells.join(" " * gap), width)
        end
      end

      # Exactly `height` lines: a rounded border with `title` in the top edge around `body`.
      def tile(title:, body:, width:, height:, border_sgr: nil, title_sgr: nil)
        return [] if height < 2
        return Array.new(height, " " * [width, 0].max) if width < 4

        inner = width - 2
        room = inner - 3
        title = room.positive? ? cut(title.to_s, room) : ""
        top = if title.empty?
                G.paint("╭#{"─" * inner}╮", border_sgr)
              else
                G.paint("╭─ ", border_sgr) + G.paint(title, title_sgr) +
                  G.paint(" #{"─" * (room - visible_width(title))}╮", border_sgr)
              end
        body = Array(body)
        rows = Array.new(height - 2) do |i|
          G.paint("│", border_sgr) + fit(body[i].to_s, inner) + G.paint("│", border_sgr)
        end
        [top, *rows, G.paint("╰#{"─" * inner}╯", border_sgr)]
      end

      # ANSI-aware: the first `width` visible cells of `str`, SGR runs kept, re-closed with a reset.
      def truncate(str, width)
        str = str.to_s
        return str if visible_width(str) <= width

        out = +""
        used = 0
        styled = false
        str.scan(TOKEN) do |tok|
          if tok.start_with?("\e[")
            out << tok
            styled = true
            next
          end
          w = R2UI::Compat::Tea::ANSI.string_width(tok)
          break if used + w > width

          out << tok
          used += w
        end
        styled ? out << "\e[0m" : out
      end

      # `str` truncated then padded to exactly `width` cells.
      def fit(str, width)
        return "" if width <= 0

        pad(truncate(str, width), width)
      end

      # `left` and `right` on one `width`-cell line; the right side always shows (cut only when it
      # alone is wider than the line), the left is cut by the word rule to fit beside it.
      def sides(left, left_sgr, right, right_sgr, width)
        return "" if width <= 0

        right = cut(right, width)
        rw = visible_width(right)
        left = cut(left, width - rw - 1)
        lw = visible_width(left)
        gap = width - lw - rw
        fit(G.paint(left, left.empty? ? nil : left_sgr) + (" " * gap) + G.paint(right, right_sgr), width)
      end

      def cut_right(text, width)
        best = nil
        text.each_char.with_index do |ch, i|
          next unless ch == " "

          prefix = strip_tail(text[0, i])
          best = prefix if !prefix.empty? && visible_width(prefix) + 1 <= width
        end
        (best || take(text, width - 1)) + ELLIPSIS
      end

      def cut_left(text, width)
        best = nil
        text.each_char.with_index do |ch, i|
          next unless ch == "/" || ch == " "

          suffix = ch == "/" ? text[i..] : strip_head(text[i..])
          next if suffix.empty? || visible_width(suffix) + 1 > width

          best = suffix
          break
        end
        ELLIPSIS + (best || take(text.reverse, width - 1).reverse)
      end

      def strip_tail(str)
        str = str.chop while !str.empty? && SEPARATORS.include?(str[-1])
        str
      end

      def strip_head(str)
        str = str[1..] while !str.empty? && SEPARATORS.include?(str[0])
        str
      end

      # The longest leading run of grapheme clusters of plain `str` within `width` cells.
      def take(str, width)
        out = +""
        used = 0
        str.each_grapheme_cluster do |g|
          w = R2UI::Compat::Tea::ANSI.string_width(g)
          break if used + w > width

          out << g
          used += w
        end
        out
      end
    end
  end
end
