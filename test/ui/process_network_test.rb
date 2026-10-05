# frozen_string_literal: true

require "test_helper"

# The :process network columns: on performance views only.
class ProcessNetworkTest < Minitest::Test
  include Fixtures

  def process_columns(view)
    with_engine(Fixtures.engine(machine(0), machine(2))) do
      Agentmon::UI.install(engine: Agentmon.engine, view:)
      R2UI.registry.resource(:process).columns.to_h { |c| [c.key, [c.label, c.format]] }
    end
  end

  def test_default_dashboard_has_no_network_columns
    cols = process_columns(nil)

    refute_includes cols.keys, :net_in_rate
    refute_includes cols.keys, :net_out_rate
  end

  def test_a_view_adds_net_in_and_out_rates
    cols = process_columns(:dense)

    assert_equal ["Net in", :bytes_per_sec], cols[:net_in_rate]
    assert_equal ["Net out", :bytes_per_sec], cols[:net_out_rate]
  end
end
