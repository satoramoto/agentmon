# frozen_string_literal: true

# The :session_memory resource and the "Memory by session" panel (top row, right): how much real
# memory each alive agent session holds, largest first, and whether it is growing or paging.
#
#   ╭─ Memory by session ──────────────────────────────────────────────────╮
#   │compressed 2.0G · swap 512M (per-process compressed/swap needs root)  │
#   │Session              Footprint▼       Share  Resident    Growth Pgin/s│
#   │claude 4242 · repo   ▂▃▅▇      2.1G   26.3%      2.4G   +1.5M/s   10.0│
#   │Claude 59334         ▅▅▅▅      900M   11.0%      1.1G    -12K/s    0.0│
#   ╰──────────────────────────────────────────────────────────────────────╯
#
# Footprint is what Activity Monitor calls Memory (it includes the session's compressed pages),
# summed over the session's processes, each once; Share is its percent of used memory; Growth is
# its footprint change per second over the last minute; Pgin/s counts page-ins per second (each
# one waited for the disk). The first line is the machine's compressed memory and swap used:
# macOS splits those out per process only for root. It is blank while memory is unavailable.
# A narrow panel drops columns from the right (150 columns show Session and Footprint;
# 220 add Share and Resident).
# Follows session focus (enter on a session): then only the focused session is listed.
module Agentmon
  module UI
    module SessionMemoryPanel
      NOTE = "(per-process compressed/swap needs root)"

      module_function

      # reading[:session_memory] as rows; none while it is unavailable.
      def rows(reading)
        (reading[:session_memory] || []).map do |m|
          { id: m.session_id, label: m.label, footprint: m.footprint, share: m.share, resident: m.resident,
            growth_rate: m.growth_rate, growth: growth(m.growth_rate), pagein_rate: m.pagein_rate }
        end
      end

      # "+1.5M/s", "-12K/s"; "" when unknown. (r2ui's :bytes_per_sec has no sign.)
      def growth(rate)
        return "" if rate.nil?

        "#{rate.negative? ? "-" : "+"}#{R2UI::Format.bytes(rate.abs)}/s"
      end

      # "compressed 2.0G · swap 512M (per-process compressed/swap needs root)", cut to `width`;
      # "" without a MemoryView.
      def machine_line(memory, width)
        return "" unless memory

        f = R2UI::Format
        text = "compressed #{f.bytes(memory.compressed.to_i)} · swap #{f.bytes(memory.swap_used.to_i)} #{NOTE}"
        text.length > width ? "#{text[0, [width - 1, 0].max]}…" : text
      end
    end
  end

  resource :session_memory do |engine|
    title "Memory by session"
    source { UI::SessionMemoryPanel.rows(engine.current) }
    refresh every: engine.interval
    key :id

    index do
      column :label, label: "Session"
      column :footprint, label: "Footprint", format: :bytes, sparkline: true, sort: :desc
      column :share, label: "Share", format: :percent
      column :resident, label: "Resident", format: :bytes
      column :growth, label: "Growth", width: 8, align: :right
      column :pagein_rate, label: "Pgin/s", format: :number, width: 6
    end

    filter :label
  end

  panel :session_memory, row: :top, order: 30, span: 1, title: "Memory by session" do |engine|
    # Above the table: r2ui's table takes all the height left, so nothing after it is drawn.
    view { UI::SessionMemoryPanel.machine_line(engine.current(max_age: Float::INFINITY)[:memory], width) }
    table
  end
end
