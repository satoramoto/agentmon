# frozen_string_literal: true

source "https://rubygems.org"

# A sibling r2ui checkout when there is one (local work on both), otherwise main on GitHub (CI).
# `../r2ui` from the main checkout, `../../r2ui` from a worktree in agentmon-wt/<id>/.
r2ui_path = %w[../r2ui ../../r2ui].find { |p| File.exist?(File.expand_path("#{p}/r2ui.gemspec", __dir__)) }
if r2ui_path
  gem "r2ui", path: r2ui_path
else
  gem "r2ui", github: "satoramoto/r2ui", branch: "main"
end

# proc_pid_rusage and friends (lib/agentmon/darwin.rb). A default gem until Ruby 3.5, which drops it.
gem "fiddle", "~> 1.1"
gem "minitest", "~> 5.25"
gem "rake", "~> 13.0"
