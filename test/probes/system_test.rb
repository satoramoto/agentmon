# frozen_string_literal: true

require "test_helper"
require "minitest/mock"

class SystemProbeTest < Minitest::Test
  # Captured from `netstat -ibn` on an Apple Silicon Mac (trimmed): lo0 and en0 have several
  # address rows repeating the Link row's counters; utun0 has no Address column on its Link row.
  NETSTAT = <<~TEXT
    Name       Mtu   Network       Address            Ipkts Ierrs     Ibytes    Opkts Oerrs     Obytes  Coll
    lo0        16384 <Link#1>                       3969900     0 3043054611  3969900     0 3043054611     0
    lo0        16384 127           127.0.0.1        3969900     - 3043054611  3969900     - 3043054611     -
    lo0        16384 ::1/128     ::1                3969900     - 3043054611  3969900     - 3043054611     -
    gif0*      1280  <Link#2>                             0     0          0        0     0          0     0
    anpi1      1500  <Link#4>    a6:f7:8f:af:39:e5        0     0          0        0     0          0     0
    utun0      1500  <Link#18>                            0     0          0        1     0        100     0
    utun0      1500  fe80::d941: fe80:12::d941:251        0     -          0        1     -        100     -
    en0        1500  <Link#14>   c2:4b:51:3e:50:8a 266689137     0 283325209934 371420752     0 475365507890     0
    en0        1500  fe80::65:49 fe80:e::65:49b9:c 266689137     - 283325209934 371420752     - 475365507890     -
    en0        1500  192.168.1     192.168.1.118   266689137     - 283325209934 371420752     - 475365507890     -
    awdl0      1500  <Link#16>   fa:ec:18:ae:ed:c0    18855     0   13710683    12220     0    4708877     0
    awdl0      1500  fe80::f8ec: fe80:10::f8ec:18f    18855     -   13710683    12220     -    4708877     -
  TEXT

  def parse(text) = Agentmon::Probes::System.parse_netstat(text)

  def test_sums_link_rows_only_without_lo0
    net_in, net_out = parse(NETSTAT)

    assert_equal 283_325_209_934 + 13_710_683, net_in
    assert_equal 100 + 475_365_507_890 + 4_708_877, net_out
  end

  def test_not_netstat_output_is_nil
    assert_nil parse("")
    assert_nil parse("netstat: command not found\n")
  end

  def test_only_lo0_is_zero_not_nil
    assert_equal [0, 0], parse(NETSTAT.lines.first(2).join + NETSTAT.lines[4])
  end

  def test_probe_is_nil_off_macos
    probe = Agentmon.registry[:probe, :system]

    Agentmon::Darwin.stub(:available?, false) { assert_nil probe.block.call({}) }
  end

  # Runs System.read with every source replaced (no real machine); pass a lambda that raises to
  # make one part fail.
  def read(netstat: -> { NETSTAT }, cpu_ticks: -> { [100, 50, 800, 10] }, ncpu: -> { 10 },
           load: -> { [1.5, 2.0, 2.5] })
    system = Agentmon::Probes::System
    native = system::Native
    system.stub(:netstat, netstat) do
      native.stub(:cpu_ticks, cpu_ticks) do
        native.stub(:ncpu, ncpu) { native.stub(:load_average, load) { system.read } }
      end
    end
  end

  def test_read_builds_a_system_stat
    stat = read

    assert_kind_of Agentmon::SystemStat, stat
    assert_equal [100, 50, 800, 10], stat.cpu_ticks
    assert_equal 10, stat.ncpu
    assert_equal [1.5, 2.0, 2.5], stat.load
    assert_equal 283_325_209_934 + 13_710_683, stat.net_in
    assert_kind_of Float, stat.at_mono
  end

  def test_missing_netstat_leaves_only_network_nil
    stat = read(netstat: -> { raise Errno::ENOENT, "netstat" })

    assert_nil stat.net_in
    assert_nil stat.net_out
    assert_equal [100, 50, 800, 10], stat.cpu_ticks
    assert_equal [1.5, 2.0, 2.5], stat.load
  end

  def test_failing_host_statistics_leaves_only_cpu_nil
    stat = read(cpu_ticks: -> { raise Agentmon::Error, "host_statistics failed" })

    assert_nil stat.cpu_ticks
    assert_equal 10, stat.ncpu
    refute_nil stat.net_in
  end
end
