# frozen_string_literal: true

require "test_helper"

class SmokeTest < Minitest::Test
  def test_r2ui_loads
    require "r2ui"
    assert defined?(R2UI::App)
  end
end
