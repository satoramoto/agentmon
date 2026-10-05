# frozen_string_literal: true

require "test_helper"
require "agentmon/views/widgets"

class WidgetsViewTest < Minitest::Test
  W = Agentmon::Views::Widgets
  G = R2UI::Widgets::Glyphs

  def plain(str) = str.gsub(/\e\[[0-9;?]*[ -\/]*[@-~]/, "")

  def assert_width(width, line, msg = nil)
    assert_equal width, W.visible_width(line), msg || "#{line.inspect} is not #{width} cells"
  end

  # --- measure, pad, cut ---

  def test_visible_width_ignores_sgr
    assert_equal 3, W.visible_width("\e[38;2;1;2;3mabc\e[0m")
    assert_equal 4, W.visible_width("⣀⣠ab")
  end

  def test_pad_aligns_and_never_cuts
    assert_equal "ab  ", W.pad("ab", 4)
    assert_equal "  ab", W.pad("ab", 4, align: :right)
    assert_equal "abcdef", W.pad("abcdef", 3)
  end

  def test_cut_at_word_boundary_with_separators_stripped
    assert_equal "claude 74432…", W.cut("claude 74432 · agentmon", 15)
    assert_equal "claude…", W.cut("claude 74432 · agentmon", 12)
    assert_equal "load, cpu…", W.cut("load, cpu: other things", 12)
  end

  def test_cut_fits_unchanged_and_degenerate_widths
    assert_equal "short", W.cut("short", 5)
    assert_equal "", W.cut("short", 0)
    assert_equal "", W.cut("short", -3)
    assert_equal "…", W.cut("short", 1)
  end

  def test_cut_without_boundary_cuts_the_word
    assert_equal "superca…", W.cut("supercalifragilistic", 8)
    assert_equal "memor…", W.cut("memory used", 6)
  end

  def test_cut_from_left_keeps_the_path_tail
    assert_equal "…/long/repo", W.cut("~/src/very/long/repo", 12, from: :left)
    assert_equal "…/repo", W.cut("~/src/very/long/repo", 8, from: :left)
    assert_equal "…ilistic", W.cut("a/b/supercalifragilistic", 8, from: :left)
    assert_equal "…two three", W.cut("one two three", 10, from: :left)
  end

  def test_cut_never_exceeds_width
    ["claude 74432 · agentmon", "~/src/very/long/repo", "x", "a b c d e f", "日本語のテキスト"].each do |text|
      (0..30).each do |w|
        assert_operator W.visible_width(W.cut(text, w)), :<=, w
        assert_operator W.visible_width(W.cut(text, w, from: :left)), :<=, w
      end
    end
  end

  # --- value_sgr ---

  def test_value_sgr_by_unit
    assert_equal G.heat(0.5), W.value_sgr(unit: :percent, fraction: 0.5)
    assert_nil W.value_sgr(unit: :percent)
    assert_equal G.fg(W::ACCENT), W.value_sgr(unit: :bytes)
    assert_equal G.fg(W::ACCENT), W.value_sgr(unit: :bytes_per_sec)
    assert_equal G.fg(W::ACCENT), W.value_sgr(unit: :signed_bytes_per_sec)
    assert_nil W.value_sgr(unit: :count)
    assert_equal G.fg(W::DIM), W.value_sgr(unit: :percent, fraction: 0.5, known: false)
  end

  def test_value_sgr_pulse
    assert_equal W.value_sgr(unit: :bytes), W.value_sgr(unit: :bytes, pulse: 0.0)
    assert_equal G.fg(R2UI::Motion.mix_hex(W::ACCENT, W::PULSE, 0.2)), W.value_sgr(unit: :bytes, pulse: 0.2)
    assert_equal "#{G.fg(R2UI::Motion.mix_hex(W::ACCENT, W::PULSE, 0.5))};1", W.value_sgr(unit: :bytes, pulse: 0.5)
    heat = G.gradient(G::HEAT, 0.9)
    assert_equal "#{G.fg(R2UI::Motion.mix_hex(heat, W::PULSE, 1.0))};1",
                 W.value_sgr(unit: :percent, fraction: 0.9, pulse: 1.0)
    assert_equal G.fg(R2UI::Motion.mix_hex(W::PLAIN, W::PULSE, 0.1)), W.value_sgr(unit: :count, pulse: 0.1)
  end

  # --- meter ---

  def test_meter_exact
    line = W.meter(label: "busy", text: "42%", fraction: 0.42, width: 20)
    assert_equal "busy ▕███▊     ▏ 42%", plain(line)
    assert_includes line, "#{G.heat(0.42)};#{G.bg(W::TROUGH)}"
    assert_includes line, "38;2;"
  end

  def test_meter_label_and_text_widths
    line = W.meter(label: "used", text: "71%", fraction: 1.5, width: 24, label_width: 6, text_width: 5)
    assert_equal "used   ▕█████████▏   71%", plain(line)
    assert_includes line, G.paint("71%", nil)
  end

  def test_meter_text_sgr_and_bar_sgr
    line = W.meter(label: "m", text: "2G", fraction: 0.5, width: 12, bar_sgr: G.fg(W::ACCENT), text_sgr: G.fg(W::ACCENT))
    assert_includes line, "#{G.fg(W::ACCENT)};#{G.bg(W::TROUGH)}"
    assert_includes line, G.paint("2G", G.fg(W::ACCENT))
  end

  def test_meter_unknown
    [[nil, "42%"], [0.4, nil], [nil, nil]].each do |fraction, text|
      line = W.meter(label: "busy", text: text, fraction: fraction, width: 16)
      assert_equal "busy ▕       ▏ –", plain(line)
      assert_includes line, G.paint(W::UNKNOWN, G.fg(W::DIM))
    end
  end

  def test_meter_drops_the_bar_when_narrow
    assert_equal "memor… 42%", plain(W.meter(label: "memory used", text: "42%", fraction: 0.42, width: 10))
    assert_equal "busy    42%", plain(W.meter(label: "busy", text: "42%", fraction: 0.42, width: 11))
    assert_equal "42%", plain(W.meter(label: "busy", text: "42%", fraction: 0.42, width: 3))
  end

  # --- spark ---

  def test_spark_exact
    line = W.spark(label: "cpu", values: [1, 2, 3, 4], text: "4%", width: 12)
    assert_equal "cpu ⠀⠀⠀⣠⣾ 4%", plain(line)
    assert_includes line, G.paint("⠀⠀⠀⣠⣾", G.fg(W::ACCENT))
  end

  def test_spark_few_values_is_baseline_and_unknown_text
    line = W.spark(label: "cpu", values: [7], text: nil, width: 12)
    assert_equal "cpu ⣀⣀⣀⣀⣀⣀ –", plain(line)
    assert_includes line, G.paint(W::UNKNOWN, G.fg(W::DIM))
    assert_equal "cpu ⣀⣀⣀⣀⣀⣀ –", plain(W.spark(label: "cpu", values: nil, text: nil, width: 12))
  end

  def test_spark_drops_the_chart_when_narrow
    assert_equal "cpu   4%", plain(W.spark(label: "cpu", values: [1, 2], text: "4%", width: 8))
  end

  # --- trend ---

  def test_trend_header_and_area
    lines = W.trend(label: "CPU", text: "42%", values: [1, 2, 3, 4], width: 10, height: 1, text_sgr: G.heat(0.42))
    assert_equal ["CPU    42%", "⠀⠀⠀⠀⠀⠀⠀⠀⣠⣾"], lines.map { plain(_1) }
    assert_includes lines[0], G.paint("CPU", G.fg("#8A8A8A"))
    assert_includes lines[0], G.paint("42%", G.heat(0.42))
    assert_includes lines[1], G.fg(W::ACCENT)
    assert_equal 4, W.trend(label: "CPU", text: "1%", values: [1], width: 10, height: 3).size
  end

  def test_trend_without_height_and_unknown
    lines = W.trend(label: "load average now", text: nil, values: [], width: 10, height: 0)
    assert_equal ["load…    –"], lines.map { plain(_1) }
  end

  # --- stat ---

  def test_stat_exact
    pairs = [["load1", "2.1", nil], ["load5", nil, nil], ["load15", "1.0", G.heat(0.2)]]
    lines = W.stat(pairs: pairs, width: 24)
    assert_equal ["load1   2.1  load5     –", "load15  1.0             "], lines.map { plain(_1) }
    assert_includes lines[0], G.paint(W::UNKNOWN, G.fg(W::DIM))
    assert_includes lines[1], G.paint("1.0", G.heat(0.2))
  end

  def test_stat_cuts_labels_and_values
    lines = W.stat(pairs: [["compressed memory", "1.5G", nil], ["swap", "123456789012", nil]], width: 22)
    assert_equal ["comp… 1.5G  123456789…"], lines.map { plain(_1) }
    assert_equal ["a  1", "b  2"], W.stat(pairs: [["a", "1", nil], ["b", "2", nil]], width: 4, columns: 1).map { plain(_1) }
  end

  # --- tile ---

  def test_tile_borders
    lines = W.tile(title: "claude 4242", body: ["cpu 12%"], width: 18, height: 4, border_sgr: G.fg(W::ACCENT))
    assert_equal ["╭─ claude 4242 ──╮", "│cpu 12%         │", "│                │", "╰────────────────╯"],
                 lines.map { plain(_1) }
    assert_includes lines[0], G.fg(W::ACCENT)
  end

  def test_tile_cuts_title_by_word
    assert_equal "╭─ claude… ─╮", plain(W.tile(title: "claude 74432 · repo", body: [], width: 13, height: 2)[0])
  end

  def test_tile_truncates_ansi_body
    line = W.tile(title: "x", body: ["\e[31mhello world long\e[0m"], width: 8, height: 3)[1]
    assert_equal "│\e[31mhello \e[0m│", line
  end

  def test_tile_degenerate
    assert_equal [], W.tile(title: "t", body: [], width: 10, height: 1)
    assert_equal ["   ", "   "], W.tile(title: "t", body: [], width: 3, height: 2)
    assert_equal ["", ""], W.tile(title: "t", body: [], width: 0, height: 2)
  end

  # --- width exactness ---

  def test_every_function_is_exactly_its_width
    long = "claude 74432 · agentmon session"
    (0..60).each do |w|
      [W.meter(label: long, text: "23G / 32G 71%", fraction: 0.71, width: w),
       W.meter(label: "busy", text: nil, fraction: nil, width: w, label_width: 6, text_width: 4),
       W.spark(label: long, values: (1..40).to_a, text: "512M", width: w),
       W.spark(label: "cpu", values: [], text: nil, width: w, label_width: 5)].each do |line|
        assert_width [w, 0].max, line
      end
      W.trend(label: long, text: "42%", values: (1..80).to_a, width: w, height: 2).each { assert_width w, _1 }
      W.stat(pairs: [[long, "1.5G", nil], ["swap", nil, nil], ["x", "123456789012345", nil]], width: w, columns: 2)
       .each { assert_width w, _1 }
      W.stat(pairs: [["a", "1", nil]] * 4, width: w, columns: 3).each { assert_width w, _1 }
      tile = W.tile(title: long, body: ["\e[1m#{long * 3}\e[0m", "short"], width: w, height: 5)
      assert_equal 5, tile.size
      tile.each { assert_width w, _1 }
    end
  end
end
