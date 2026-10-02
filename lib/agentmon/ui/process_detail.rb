# frozen_string_literal: true

require "fiddle"

# The Detail panel (beside Processes, a quarter of the main row): everything about the process
# selected in the Processes table, whichever panel has focus.
#
#   claude  pid 4242
#   Command    claude --resume --model opus
#   Directory  ~/src/repo
#   Session    claude 4242 · repo
#   Footprint  512M
#   Resident   600M
#   Peak       700M
#   CPU time   12m 3s
#   Written    1.2G
#   Started    2h 5m ago
#   Open files 42
#
# The full command line comes from one `ps -o args= -p PID` when the selection changes (cached
# while it stays). The open file count is `proc_pidinfo(PROC_PIDLISTFDS)` through Fiddle. Root's
# processes can't be read without root: their footprint, CPU time, disk, start and open files say
# "not readable without root"; resident size is ps's. A group line (g) shows its process count.
#
# Other stories add lines below these with `Agentmon.detail_section` (lib/agentmon/registry.rb)
# instead of editing this file.
module Agentmon
  module UI
    module ProcessDetail
      PROC_PIDLISTFDS = 1
      FDINFO_SIZE = 8 # struct proc_fdinfo: int32 fd + uint32 type
      UNREADABLE = "not readable without root"
      LABEL_WIDTH = 11
      COMMAND_LINES = 3

      class << self
        # Injection points for tests: pid -> command line String (nil if gone), pid -> Integer or nil.
        attr_writer :command_reader, :file_counter

        def command_reader = @command_reader ||= method(:read_command)
        def file_counter = @file_counter ||= method(:open_files)

        # The panel's text for the app's current selection in the :process panel.
        def render(app, engine, width)
          panel = app.dashboard.panels.find { |p| p.name == :process }
          state = panel && app.panel_state(panel)
          line = state && app.panel_lines(panel)[state.selected]
          return "No process selected" unless line

          row = line.rows.find { |r| r.pid == line.id } || (line.rows.first if line.rows.size == 1)
          return "#{line.label}\n#{line.rows.size} processes: ungroup (g) to pick one" unless row

          reading = engine.current
          lines(row, command(app, row), now: reading.at, width:, reading:).join("\n")
        end

        # The process's own lines, then each registered `Agentmon.detail_section`'s.
        def lines(row, command, now:, width:, reading: nil, sections: Agentmon.registry.detail_sections)
          [*own_lines(row, command, now:, width:), *sections.flat_map { |s| section_lines(s, row, reading) }]
        end

        # A section that raises shows its error instead of breaking the panel.
        def section_lines(section, row, reading)
          section.block.call(row, reading).map { |label, value| pair(label.to_s, value || "unknown") }
        rescue StandardError => e
          [pair(section.name.to_s, "#{e.class}: #{e.message}")]
        end

        def own_lines(row, command, now:, width:)
          readable = row.readable
          rusage = ->(value) { readable ? value : UNREADABLE }
          files = file_counter.call(row.pid)
          [
            "#{row.name}  pid #{row.pid}",
            *wrap("Command", command || row.path, width),
            pair("Directory", row.cwd ? R2UI::Format.short_path(row.cwd) : "unknown"),
            pair("Session", row.session || "none"),
            pair("Footprint", rusage[bytes(row.footprint)]),
            pair("Resident", bytes(row.resident)),
            pair("Peak", rusage[bytes(row.peak_footprint)]),
            pair("CPU time", rusage[row.cpu_time && R2UI::CLI::Ext::HumanFormat.duration(row.cpu_time)]),
            pair("Written", rusage[bytes(row.disk_written)]),
            pair("Started", rusage[row.started_at && "#{R2UI::CLI::Ext::HumanFormat.duration([now - row.started_at, 0].max)} ago"]),
            pair("Open files", files ? files.to_s : (readable ? "unknown" : UNREADABLE))
          ]
        end

        # The full command line of `pid` (one ps), or nil when it has exited.
        def read_command(pid)
          text = IO.popen(["ps", "-o", "args=", "-p", pid.to_s], err: File::NULL, &:read).strip
          text.empty? ? nil : text
        rescue SystemCallError
          nil
        end

        # How many file descriptors `pid` has open, or nil when unreadable (EPERM, exited).
        def open_files(pid)
          return nil unless Darwin.available?

          estimate = pidinfo.call(pid, PROC_PIDLISTFDS, 0, nil, 0)
          return nil unless estimate.positive?

          buffer = Fiddle::Pointer.malloc(estimate, Fiddle::RUBY_FREE)
          used = pidinfo.call(pid, PROC_PIDLISTFDS, 0, buffer, estimate)
          used.positive? ? used / FDINFO_SIZE : nil
        end

        private

        # The selected process's command line, read once per selection (pid and start time).
        def command(app, row)
          cache = app.store(:agentmon_process_detail)
          key = [row.pid, row.started_at]
          unless cache[:key] == key
            cache[:key] = key
            cache[:command] = command_reader.call(row.pid)
          end
          cache[:command]
        end

        def bytes(value) = value && R2UI::Format.bytes(value)

        def pair(label, value) = "#{label.ljust(LABEL_WIDTH)}#{value}"

        # The command line over up to COMMAND_LINES lines, indented under its value column.
        def wrap(label, text, width)
          room = [width - LABEL_WIDTH, 10].max
          chunks = text.to_s.scan(/.{1,#{room}}/).first(COMMAND_LINES)
          chunks = [""] if chunks.empty?
          chunks.each_with_index.map { |chunk, i| pair(i.zero? ? label : "", chunk) }
        end

        # proc_pidinfo, bound here: Darwin's binding is private to the core.
        def pidinfo
          @pidinfo ||= Fiddle::Function.new(
            Fiddle.dlopen(nil)["proc_pidinfo"],
            [Fiddle::TYPE_INT, Fiddle::TYPE_INT, -Fiddle::TYPE_LONG_LONG, Fiddle::TYPE_VOIDP, Fiddle::TYPE_INT],
            Fiddle::TYPE_INT
          )
        end
      end
    end
  end

  panel :detail, row: :main, order: 200, span: 1, resource: nil do |engine|
    view { UI::ProcessDetail.render(app, engine, width) }
  end
end
