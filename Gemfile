# frozen_string_literal: true

source "https://rubygems.org"

# A sibling r2ui checkout when there is one (local work on both), otherwise main on GitHub (CI).
if File.directory?(File.expand_path("../r2ui", __dir__))
  gem "r2ui", path: "../r2ui"
else
  gem "r2ui", github: "satoramoto/r2ui", branch: "main"
end

# proc_pid_rusage and friends (lib/agentmon/darwin.rb). A default gem until Ruby 3.5, which drops it.
gem "fiddle", "~> 1.1"
gem "minitest", "~> 5.25"
gem "rake", "~> 13.0"
