# frozen_string_literal: true

require "test_helper"

# probes/network.rb on captured nettop text (trimmed from a real `nettop -x -L 0 -s 1` stream under
# a pty, addresses replaced with documentation ranges). No nettop is started here.
class NetworkProbeTest < Minitest::Test
  # Two whole blocks and the start of a third; `\r\n` endings as the pty delivers them, and a flow
  # line before the first header (we joined the stream midway).
  STREAM = <<~NETTOP.gsub("\n", "\r\n")
    tcp4 192.0.2.118:50000<->198.51.100.1:443,en0,Established,1,1,
    ,interface,state,bytes_in,bytes_out,
    launchd.1,,,0,0,
    tcp6 *.5900<->*.*,,Listen,,,
    tcp4 *:5900<->*:*,,Listen,,,
    apsd.404,,,3177530,7189392,
    tcp4 192.0.2.118:55584<->198.51.100.11:5223,en0,Established,3177530,7189392,
    mDNSResponder.450,,,8194353,3373607,
    udp4 *:5353<->*:*,en0,,4823549,2970949,
    udp6 *.5353<->*.*,en0,,3370804,402658,
    dnsmasq.586,,,0,0,
    udp6 fe80::1%lo0.53<->*.*,lo0,,0,0,
    tcp6 fe80::1%lo0.53<->*.*,lo0,Listen,,,
    cloudd.659,,,11736,12267,
    quic6 2001:db8:1540::4ad7.60979<->2001:db8:a41:880::13.443,en0,,5878,6788,
    Google Chrome H.1272,,,1024932,569746,
    com.docker.back.13476,,,34359684,53053063,
    Codex (Service).2409,,,13786536,8477132,
    claude.22602,,,907594,6995966,
    tcp4 192.0.2.118:52933<->203.0.113.10:443,en0,Established,12483,6976,
    tcp4 192.0.2.118:54987<->host.example.com:443,en0,Established,4292,16587,
    node.35091,,,1296,312,
    tcp4 127.0.0.1:4180<->*:*,lo0,Listen,,,
    tcp4 127.0.0.1:4180<->localhost:54968,lo0,Established,632,185,
    ,interface,state,bytes_in,bytes_out,
    launchd.1,,,0,0,
    apsd.404,,,3177600,7189500,
    tcp4 192.0.2.118:55584<->198.51.100.11:5223,en0,Established,3177600,7189500,
    claude.22602,,,909101,7078801,
    tcp4 192.0.2.118:52933<->203.0.113.10:443,en0,Established,12483,6976,
    tcp4 192.0.2.118:52937<->203.0.113.10:443,en0,Established,272924,631936,
    node.35091,,,1317,312,
    ,interface,state,bytes_in,bytes_out,
    launchd.1,,,0,0,
    apsd.404,,,3177700,7189600,
  NETTOP

  def snapshots = Agentmon::Probes::Network.parse(STREAM, at_mono: 100.0, every: 1.0)

  def test_one_snapshot_per_block_the_last_one_partial
    first, second, third = snapshots

    assert_equal 3, snapshots.size
    assert_equal [100.0, 101.0, 102.0], snapshots.map(&:at_mono)
    assert_equal [1, 404, 450, 586, 659, 1272, 13_476, 2409, 22_602, 35_091], first.processes.keys
    assert_equal [1, 404, 22_602, 35_091], second.processes.keys
    assert_equal [1, 404], third.processes.keys
    assert_equal 3_177_700, third.processes[404].bytes_in
  end

  def test_lines_before_the_first_header_are_dropped
    first = snapshots.first

    refute(first.processes.values.flat_map(&:flows).any? { |f| f.local == "192.0.2.118:50000" })
  end

  def test_process_names_with_spaces_dots_and_parentheses
    procs = snapshots.first.processes

    assert_equal "Google Chrome H", procs[1272].name
    assert_equal "com.docker.back", procs[13_476].name
    assert_equal "Codex (Service)", procs[2409].name
    assert_equal [34_359_684, 53_053_063], [procs[13_476].bytes_in, procs[13_476].bytes_out]
    assert_empty procs[1272].flows
  end

  def test_ipv4_flow
    flow = snapshots.first.processes[404].flows.first

    assert_equal Agentmon::NetFlow.new(protocol: "tcp4", local: "192.0.2.118:55584", remote: "198.51.100.11:5223",
                                       remote_host: "198.51.100.11", remote_port: 5223, interface: "en0",
                                       state: "Established", bytes_in: 3_177_530, bytes_out: 7_189_392), flow
  end

  def test_ipv6_flows_use_a_dot_before_the_port
    quic = snapshots.first.processes[659].flows.first
    dns = snapshots.first.processes[586].flows.first

    assert_equal ["quic6", "2001:db8:a41:880::13", 443], [quic.protocol, quic.remote_host, quic.remote_port]
    assert_nil quic.state
    assert_equal "fe80::1%lo0.53", dns.local
    assert_nil dns.remote_host
  end

  def test_wildcards_and_empty_fields_are_nil
    listen, v4 = snapshots.first.processes[1].flows

    assert_equal ["*.*", nil, nil, nil, "Listen", nil, nil],
                 [listen.remote, listen.remote_host, listen.remote_port, listen.interface, listen.state,
                  listen.bytes_in, listen.bytes_out]
    assert_equal "*:*", v4.remote
    assert_nil v4.remote_host
  end

  def test_host_names_as_remotes
    flows = snapshots.first.processes[22_602].flows + snapshots.first.processes[35_091].flows

    assert_includes flows.map { |f| [f.remote_host, f.remote_port] }, ["host.example.com", 443]
    assert_includes flows.map { |f| [f.remote_host, f.remote_port] }, ["localhost", 54_968]
  end

  def test_snapshots_are_frozen
    snap = snapshots.first

    assert_predicate snap.processes, :frozen?
    assert_predicate snap.processes[404].flows, :frozen?
  end

  def test_endpoint
    endpoint = Agentmon::Probes::Network.method(:endpoint)

    assert_equal ["192.0.2.1", 80], endpoint.call("192.0.2.1:80", "tcp4")
    assert_equal ["2001:db8::1", 443], endpoint.call("2001:db8::1.443", "tcp6")
    assert_equal [nil, nil], endpoint.call("*:*", "udp4")
    assert_equal [nil, nil], endpoint.call("*.*", "udp6")
    assert_equal ["192.0.2.1", nil], endpoint.call("192.0.2.1:*", "udp4")
  end

  # --- the stream's publishing, fed by hand (no child process) ---

  class FakeClock
    attr_accessor :now

    def initialize = @now = 500.0

    def to_proc = -> { @now }
  end

  def stream_with(clock) = Agentmon::Probes::Network::Stream.new(clock: clock.to_proc)

  def test_a_block_is_published_when_the_next_header_arrives
    clock = FakeClock.new
    stream = stream_with(clock)
    lines = STREAM.lines
    header = lines.index { |l| l.start_with?(",interface") }
    second = lines.index.with_index { |l, i| i > header && l.start_with?(",interface") }

    lines[0...second].each { |l| stream.feed(l) }

    assert_nil stream.latest # the first block isn't known to be complete yet

    clock.now = 501.0
    stream.feed(lines[second])

    assert_equal 500.0, stream.latest.at_mono
    assert_equal 10, stream.latest.processes.size
  end

  def test_an_idle_pty_publishes_the_block_so_far
    clock = FakeClock.new
    stream = stream_with(clock)
    stream.feed(",interface,state,bytes_in,bytes_out,\r\n")
    stream.feed("apsd.404,,,10,20,\r\n")
    stream.idle

    assert_equal [404], stream.latest.processes.keys

    stream.feed("claude.22602,,,30,40,\r\n") # a late line joins the same block
    stream.idle

    assert_equal [404, 22_602], stream.latest.processes.keys
    assert_equal 500.0, stream.latest.at_mono
  end

  def test_a_stale_snapshot_is_not_returned
    clock = FakeClock.new
    stream = stream_with(clock)
    stream.feed(",interface,state,bytes_in,bytes_out,\r\n")
    stream.idle
    clock.now = 505.0

    refute_nil stream.latest

    clock.now = 505.1

    assert_nil stream.latest
  end

  def test_missing_nettop_returns_nil_and_never_raises
    stream = Agentmon::Probes::Network::Stream.new(command: ["/nonexistent/nettop"])

    assert_nil stream.snapshot
    assert_nil stream.pid
    refute_predicate stream, :running?
    assert_nil stream.snapshot # retry is held off; still nil, still no child
    stream.stop
  end
end
