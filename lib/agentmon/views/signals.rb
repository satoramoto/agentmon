# frozen_string_literal: true

module Agentmon
  module Views
    # A named number on the machine with a unit (docs/views.md, "Vocabulary"): "system.cpu" is
    # reading[:system].cpu. `max` is its natural maximum (percent: 100), `of` another signal's name
    # that is its whole ("memory.used" of "memory.total"). Either may be nil.
    Signal = Data.define(:name, :metric, :member, :label, :unit, :max, :of)

    # Signals: parse a name into a Signal (defaults, then inference from the member name, then
    # overrides), read its value from a Reading (nil is unknown, never 0) and format it.
    #
    #   s = Signals.parse("memory.used")      # label "used", unit :bytes, of "memory.total"
    #   Signals.value(s, reading)             # => 23.1e9, or nil
    #   Signals.fraction(s, reading)          # => 0.71 (value / total, or / max), or nil
    #   Signals.format(Signals.value(s, reading), s.unit) # => "21G"
    #
    # The virtual metric :focus is the focused session, else every agent session together
    # (Signals::Focus.value).
    module Signals
      PART = /\A[a-z_][a-z0-9_]*\z/
      EVENT_STEMS = %w[pagein fault cow_fault context_switch].freeze
      PERCENT_MEMBERS = %w[cpu pressure share user system run_wait].freeze
      INTEGER_MEMBERS = %w[processes threads ncpu count].freeze

      def self.entry(label, unit, max: nil, of: nil) = { label:, unit:, max:, of: }.freeze
      private_class_method :entry

      DEFAULTS = {
        "system.cpu" => entry("CPU", :percent, max: 100),
        "system.user" => entry("user", :percent, max: 100),
        "system.system" => entry("system", :percent, max: 100),
        "system.ncpu" => entry("cores", :integer),
        "system.load1" => entry("load 1m", :number),
        "system.load5" => entry("load 5m", :number),
        "system.load15" => entry("load 15m", :number),
        "system.net_in_rate" => entry("net in", :bytes_per_sec),
        "system.net_out_rate" => entry("net out", :bytes_per_sec),
        "system.disk_read_rate" => entry("disk read", :bytes_per_sec),
        "system.disk_write_rate" => entry("disk write", :bytes_per_sec),
        "memory.used" => entry("used", :bytes, of: "memory.total"),
        "memory.total" => entry("total", :bytes),
        "memory.app" => entry("app", :bytes),
        "memory.wired" => entry("wired", :bytes),
        "memory.compressed" => entry("compressed", :bytes),
        "memory.cached" => entry("cached", :bytes),
        "memory.free" => entry("free", :bytes),
        "memory.swap_used" => entry("swap", :bytes, of: "memory.swap_total"),
        "memory.swap_total" => entry("swap total", :bytes),
        "memory.compression_ratio" => entry("ratio", :ratio),
        "memory.pressure" => entry("pressure", :percent, max: 100),
        "memory.swapin_rate" => entry("swap in", :bytes_per_sec),
        "memory.swapout_rate" => entry("swap out", :bytes_per_sec),
        "memory.compression_rate" => entry("compress", :bytes_per_sec),
        "memory.decompression_rate" => entry("decompress", :bytes_per_sec),
        "focus.cpu" => entry("CPU", :percent, max: 100),
        "focus.footprint" => entry("footprint", :bytes, of: "memory.used"),
        "focus.resident" => entry("resident", :bytes),
        "focus.wired" => entry("wired", :bytes),
        "focus.peak_footprint" => entry("peak", :bytes),
        "focus.growth_rate" => entry("growth", :signed_bytes_per_sec),
        "focus.pagein_rate" => entry("pageins", :per_sec),
        "focus.processes" => entry("procs", :integer),
        "focus.read_rate" => entry("read", :bytes_per_sec),
        "focus.write_rate" => entry("write", :bytes_per_sec),
        "focus.net_in_rate" => entry("net in", :bytes_per_sec),
        "focus.net_out_rate" => entry("net out", :bytes_per_sec),
        "focus.bytes_in" => entry("received", :bytes),
        "focus.bytes_out" => entry("sent", :bytes),
        "focus.connections" => entry("conns", :integer),
        "focus.remote_hosts" => entry("hosts", :integer)
      }.freeze

      module_function

      # A Signal for "metric.member"; ArgumentError when the name isn't one.
      def parse(name, label: nil, unit: nil, max: nil, of: nil)
        name = name.to_s
        parts = name.split(".", -1)
        unless parts.size == 2 && parts.all? { |part| PART.match?(part) }
          raise ArgumentError, "bad signal #{name.inspect}: expected \"metric.member\" (e.g. \"system.cpu\")"
        end

        metric, member = parts
        defaults = DEFAULTS.fetch(name, {})
        inferred = infer(member)
        pick = ->(key, override) { override.nil? ? (defaults[key].nil? ? inferred[key] : defaults[key]) : override }
        Signal.new(name:, metric: metric.to_sym, member: member.to_sym, label: pick[:label, label],
                   unit: pick[:unit, unit]&.to_sym, max: pick[:max, max], of: pick[:of, of]&.to_s)
      end

      # Label, unit and max guessed from a member name.
      def infer(member)
        member = member.to_s
        rate = member.end_with?("_rate")
        stem = rate ? member.delete_suffix("_rate") : member
        label = stem.tr("_", " ")
        unit, max =
          if rate
            [EVENT_STEMS.include?(stem) ? :per_sec : :bytes_per_sec, nil]
          elsif PERCENT_MEMBERS.include?(member) || member.end_with?("_pct", "_percent")
            [:percent, 100]
          elsif member.start_with?("load")
            [:number, nil]
          elsif INTEGER_MEMBERS.include?(member) || member.end_with?("_count")
            [:integer, nil]
          elsif member.end_with?("ratio")
            [:ratio, nil]
          else
            [:bytes, nil]
          end
        { label:, unit:, max: }
      end

      # The metric's value in `reading` (the virtual :focus is Focus.value); nil when missing or
      # when the reading raises.
      def metric_value(reading, metric)
        return nil if reading.nil?

        metric = metric.to_sym
        metric == :focus ? Focus.value(reading) : reading[metric]
      rescue StandardError
        nil
      end

      # A member of a Data/Struct or Hash (symbol or string key); only Numeric results count.
      def read(object, member)
        value = fetch(object, member)
        value.is_a?(Numeric) ? value : nil
      end

      def value(signal, reading) = read(metric_value(reading, signal.metric), signal.member)

      # The `of` signal's value, nil when there is none or it is unknown.
      def total(signal, reading)
        return nil unless signal.of

        value(parse(signal.of), reading)
      end

      # value / (total || max) clamped to 0..1; nil when the value or the scale is unknown.
      def fraction(signal, reading)
        current = value(signal, reading) or return nil
        scale = total(signal, reading) || signal.max
        return nil if scale.nil? || !scale.positive?

        (current.to_f / scale).clamp(0.0, 1.0)
      end

      # A trend the metric already keeps (`member_trend`, else the member without `_rate`), or nil.
      def trend(signal, reading)
        object = metric_value(reading, signal.metric) or return nil
        member = signal.member.to_s
        [member, member.delete_suffix("_rate")].uniq.each do |base|
          series = fetch(object, :"#{base}_trend")
          return series if series.is_a?(Array)
        end
        nil
      end

      # `value` as text in `unit`; nil for nil.
      def format(value, unit)
        return nil if value.nil?

        case unit
        when :integer then value.round.to_s
        when :percent, :bytes, :bytes_per_sec, :number, :ratio then R2UI::Format.call(unit, value)
        when :per_sec then per_sec(value)
        when :signed_bytes_per_sec then signed_bytes_per_sec(value)
        else value.to_s
        end
      end

      def per_sec(value)
        return "0/s" if value.zero?

        value.abs >= 10 ? "#{value.round}/s" : Kernel.format("%.1f/s", value)
      end

      def signed_bytes_per_sec(value)
        return "0B/s" if value.zero?

        "#{value.positive? ? "+" : "-"}#{R2UI::Format.bytes(value.abs)}/s"
      end

      def fetch(object, member)
        case object
        when nil then nil
        when Hash
          key = member.to_sym
          object.key?(key) ? object[key] : object[member.to_s]
        when Data then object.to_h[member.to_sym]
        when Struct then object.members.include?(member.to_sym) ? object[member.to_sym] : nil
        else
          name = member.to_sym
          object.respond_to?(name) && object.method(name).arity.zero? ? object.public_send(name) : nil
        end
      rescue StandardError
        nil
      end

      # The virtual metric :focus: the focused session, else every agent session together.
      # FocusedReading already narrows :session_ledger and :session_memory to the focused session,
      # so this only aggregates what the reading gives (:session_network too).
      module Focus
        LEDGER_SUMS = %i[processes read_rate write_rate].freeze
        MEMORY_SUMS = %i[footprint resident wired peak_footprint growth_rate pagein_rate].freeze
        # focus member => SessionNetwork member summed into it.
        NETWORK_SUMS = { net_in_rate: :in_rate, net_out_rate: :out_rate, bytes_in: :bytes_in, bytes_out: :bytes_out,
                         connections: :connections, remote_hosts: :remote_hosts }.freeze
        # focus trend => SessionNetwork trend, used when focused on one session (else History).
        NETWORK_TRENDS = { net_in_trend: :in_trend, net_out_trend: :out_trend }.freeze

        module_function

        # A Hash: cpu (percent of the machine), processes, read_rate, write_rate (alive sessions),
        # footprint .. pagein_rate (session memory), net_in_rate .. remote_hosts (session network;
        # remote_hosts sums each session's count, so a host two sessions share counts twice),
        # label, focused, and when focused the session's net_in_trend/net_out_trend. Unknown sums
        # are nil; an empty list sums to 0.
        def value(reading)
          ledger = safe(reading, :session_ledger)
          alive = ledger&.select { |s| s.ended_at.nil? }
          memory = safe(reading, :session_memory)
          network = safe(reading, :session_network)
          focus = reading.respond_to?(:focus) ? reading.focus : nil

          result = { cpu: cpu(alive, safe(reading, :system)) }
          LEDGER_SUMS.each { |key| result[key] = sum(alive, key) }
          MEMORY_SUMS.each { |key| result[key] = sum(memory, key) }
          NETWORK_SUMS.each { |key, member| result[key] = sum(network, member) }
          trends(network).each { |key, series| result[key] = series } if focus && network&.size == 1
          result[:label] = focus ? label(focus, ledger, memory) : "all agents"
          result[:focused] = !focus.nil?
          result
        end

        # The one session's own rate trends (Arrays only).
        def trends(network)
          NETWORK_TRENDS.filter_map do |key, member|
            series = Signals.fetch(network.first, member)
            [key, series] if series.is_a?(Array)
          end
        end

        # Sum of alive sessions' CPU (percent of one core) / ncpu: percent of the machine.
        def cpu(alive, system)
          ncpu = system.respond_to?(:ncpu) ? system.ncpu : nil
          return nil if alive.nil? || !ncpu.is_a?(Numeric) || !ncpu.positive?
          return 0.0 if alive.empty?

          total = sum(alive, :cpu)
          total && (total.to_f / ncpu)
        end

        # nil for an unknown list; 0 for an empty one; nil when no item knows the member.
        def sum(items, member)
          return nil if items.nil?
          return 0 if items.empty?

          known = items.filter_map { |item| Signals.read(item, member) }
          known.empty? ? nil : known.sum
        end

        def label(focus, ledger, memory)
          session = ledger&.find { |s| s.id == focus }
          row = memory&.find { |m| m.session_id == focus }
          session&.label || row&.label || focus.to_s
        end

        def safe(reading, name)
          reading[name]
        rescue StandardError
          nil
        end
      end
    end
  end
end
