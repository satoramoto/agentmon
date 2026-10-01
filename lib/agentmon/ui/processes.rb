# frozen_string_literal: true

# The :process resource and the Processes panel (the main row): every process with its session,
# directory, CPU %, footprint (what Activity Monitor calls Memory), resident size and disk rates.
# Scope "Agents" (default) shows processes in agent sessions; "All" shows everything. Group by
# session, directory, name, or as a tree (g); search with / (`footprint>500M`, `session~repo`).
#
# Other stories add to the resource with `Agentmon.extend_resource(:process) { ... }` (actions,
# scopes, columns) instead of editing this file.
module Agentmon
  resource :process do |engine|
    title "Processes"
    source { engine.current[:process_rows] }
    refresh every: engine.interval
    key :pid, parent: :ppid

    scope :agents, default: true, &:session
    scope :all

    group_by :session, label: "Session"
    group_by :cwd, label: "Directory"
    group_by :name
    group_by :parent, tree: true

    index do
      column :pid, format: :id
      column :name
      column :session, label: "Session"
      column :cwd, label: "Directory", format: :short_path
      column :cpu, label: "CPU", format: :percent, sparkline: true, sort: :desc
      column :footprint, label: "Footprint", format: :bytes
      column :resident, label: "Resident", format: :bytes
      column :read_rate, label: "Read", format: :bytes_per_sec
      column :write_rate, label: "Write", format: :bytes_per_sec
    end

    filter :name, :cwd, :session, :path
  end

  # span 3: a detail pane beside it (span 1) takes a quarter of the row.
  panel :process, row: :main, order: 100, span: 3
end
