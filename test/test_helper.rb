# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require "agentmon"
require "r2ui/cli/testing"
require_relative "support/fixtures"
require_relative "support/dashboard"

# Session names never come from this Mac's real ~/.claude or ~/.codex in tests: an empty dir and
# no open files, for the whole run (session_names tests set their own).
NO_NAMES_DIR = Dir.mktmpdir("agentmon-names")
Agentmon::Metrics::SessionNames.claude_dir = Agentmon::Metrics::SessionNames.codex_home = NO_NAMES_DIR
Agentmon::Metrics::SessionNames.open_paths = ->(_pid) {}
Minitest.after_run { FileUtils.remove_entry(NO_NAMES_DIR) }

module Minitest
  class Test
    include DashboardFrames

    # Runs the block with Agentmon.engine swapped (and R2UI's dashboards cleared), restoring both.
    def with_engine(engine)
      previous = Agentmon.instance_variable_get(:@engine)
      Agentmon.engine = engine
      R2UI.reset!
      yield engine
    ensure
      Agentmon.engine = previous
      R2UI.reset!
    end

    # Live macOS tests run only on macOS.
    def macos!
      skip "macOS only" unless Agentmon::Darwin.available?
    end
  end
end
