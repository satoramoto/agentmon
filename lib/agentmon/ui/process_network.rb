# frozen_string_literal: true

# Network columns on the :process resource ("Net in", "Net out": each process's bytes per second
# received and sent, blank while unknown), on performance views only (--layout): the default
# dashboard keeps its columns.
module Agentmon
  extend_resource :process do |_engine|
    next unless Agentmon::Views.installing

    column :net_in_rate, label: "Net in", format: :bytes_per_sec
    column :net_out_rate, label: "Net out", format: :bytes_per_sec
  end
end
