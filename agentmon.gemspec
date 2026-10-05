# frozen_string_literal: true

require_relative "lib/agentmon/version"

# A plain `ruby` platform gem, not a darwin one: agentmon has no native extension (it reaches the
# kernel through Fiddle at run time), so there is nothing per-platform to build, and a darwin
# platform gem would have to name every arch/OS-version pair. macOS-only is stated in the
# description and the `platforms` metadata; on another OS it installs, and `agentmon` exits with a "macOS only" message.
Gem::Specification.new do |spec|
  spec.name = "agentmon"
  spec.version = Agentmon::VERSION
  spec.authors = ["Ryan Gavin"]
  spec.email = ["ryan.michael.gavin@gmail.com"]

  spec.summary = "What AI coding agents (Claude, Codex) cost your Mac"
  spec.description = "A terminal monitor for AI coding agents (Claude, Codex) on macOS: per-session CPU, " \
                     "real memory (footprint), disk and network I/O, memory pressure, and a history of runs. " \
                     "macOS only."
  spec.homepage = "https://github.com/satoramoto/agentmon"
  spec.license = "MIT"
  spec.metadata = {
    "source_code_uri" => spec.homepage,
    "changelog_uri" => "#{spec.homepage}/blob/main/CHANGELOG.md",
    "rubygems_mfa_required" => "true",
    "platforms" => "macOS only"
  }
  spec.required_ruby_version = ">= 3.3"

  spec.files = Dir["lib/**/*.rb", "exe/*", "README.md", "LICENSE.txt", "CHANGELOG.md"]
  spec.bindir = "exe"
  spec.executables = ["agentmon"]
  spec.require_paths = ["lib"]

  spec.add_dependency "fiddle", "~> 1.1" # a default gem until Ruby 3.5, which drops it
  spec.add_dependency "r2ui", "~> 0.2"
end
