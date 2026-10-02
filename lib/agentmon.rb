# frozen_string_literal: true

require "r2ui"
require "r2ui/cli"

require_relative "agentmon/version"
require_relative "agentmon/model"
require_relative "agentmon/registry"
require_relative "agentmon/darwin"
require_relative "agentmon/sampler"
require_relative "agentmon/reading"
require_relative "agentmon/focus"
require_relative "agentmon/engine"
require_relative "agentmon/store"
require_relative "agentmon/ui"
require_relative "agentmon/program"

# agentmon: what AI coding agents cost this Mac. docs/design.md is the architecture and the story
# list. Probes read the machine into a Sample; metrics derive values from samples (a Reading);
# recorders append to the Store; the dashboard's panels and the CLI's commands read the Engine.
# Each of those is one self-registering file under lib/agentmon/{probes,metrics,recorders,ui,commands}.
module Agentmon
  class << self
    # The one Engine the dashboard and commands share. Tests assign their own (fixture sampler,
    # temp store) and reset it with `Agentmon.engine = nil`.
    def engine = @engine ||= Engine.new(store: Store.new)

    attr_writer :engine

    # Engine#errors, or {} when nothing has built an engine yet (e.g. `agentmon --help`).
    def engine_errors = @engine ? @engine.errors : {}
  end
end

Agentmon.load_extensions
