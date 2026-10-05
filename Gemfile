# frozen_string_literal: true

source "https://rubygems.org"

# Runtime dependencies (r2ui, fiddle) come from agentmon.gemspec.
gemspec

# r2ui from a sibling checkout when there is one (local work on both), otherwise main on GitHub (CI).
# `../r2ui` from the main checkout, `../../r2ui` from a worktree in agentmon-wt/<id>/.
# Once r2ui 0.2.0 is on RubyGems, drop the GitHub fallback so CI tests against the released gem
# the gemspec names (keep the sibling path for local work on both).
r2ui_path = %w[../r2ui ../../r2ui].find { |p| File.exist?(File.expand_path("#{p}/r2ui.gemspec", __dir__)) }
if r2ui_path
  gem "r2ui", path: r2ui_path
else
  gem "r2ui", github: "satoramoto/r2ui", branch: "main"
end

gem "minitest", "~> 5.25"
gem "rake", "~> 13.0"
