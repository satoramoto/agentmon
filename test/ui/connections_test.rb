# frozen_string_literal: true

require "test_helper"

# The :connection resource on fixture readings.
class ConnectionsTest < Minitest::Test
  include Fixtures

  # Stand-in with ConnectionRow's members (model.rb's Data class when it exists).
  Conn = Struct.new(:pid, :name, :session_id, :session, :protocol, :local, :remote, :remote_host, :remote_port,
                    :interface, :state, :bytes_in, :bytes_out, :in_rate, :out_rate, keyword_init: true)

  def conn(**over)
    Conn.new(pid: 200, name: "claude", session_id: "s200", session: "claude 200 · repo", protocol: "tcp4",
             local: "192.168.1.5:50123", remote: "api.anthropic.com:443", remote_host: "api.anthropic.com",
             remote_port: 443, interface: "en0", state: "ESTABLISHED", bytes_in: 1_500_000, bytes_out: 9_000_000,
             in_rate: 2048.0, out_rate: 12_288.0, **over)
  end

  def rows(conns) = Agentmon::UI::ConnectionsPanel.rows(Fixtures.reading(machine(0), values: { connections: conns }))

  def test_rows_and_stable_key
    row = rows([conn]).first

    assert_equal "200|tcp4|192.168.1.5:50123|api.anthropic.com:443", row[:id]
    assert_equal "claude 200", row[:process]
    assert_equal "api.anthropic.com:443", row[:remote_text]
    assert_equal [2048.0, 12_288.0, 1_500_000, 9_000_000], row.values_at(:in_rate, :out_rate, :bytes_in, :bytes_out)
    assert_equal row[:id], rows([conn(bytes_in: 1, in_rate: nil)]).first[:id] # same flow, new numbers
  end

  def test_long_remote_is_cut_from_the_left
    remote = "a-very-long-subdomain.example-long-host.internal:8443"
    text = rows([conn(remote:)]).first[:remote_text]

    assert_equal Agentmon::UI::ConnectionsPanel::REMOTE_WIDTH, text.length
    assert text.start_with?("…")
    assert text.end_with?("host.internal:8443")
  end

  def test_no_network_data_means_no_rows
    assert_empty rows(nil)
  end

  def test_resource_sorts_by_upload_and_filters
    with_engine(Fixtures.engine(machine(0), machine(2))) do
      Agentmon::UI.install(engine: Agentmon.engine)
      resource = R2UI.registry.resource(:connection)

      assert_equal "Connections", resource.title
      assert_equal [:out_rate, :desc], resource.default_sort
      assert_equal %i[process protocol remote_text state in_rate out_rate bytes_in bytes_out], resource.columns.map(&:key)
      assert_equal %i[name remote state], resource.searchable
      assert_equal [], resource.fetch # the fixture engine has no network data
    end
  end
end
