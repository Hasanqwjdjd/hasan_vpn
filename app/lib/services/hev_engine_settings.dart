import 'dart:io';

import 'package:shared_preferences/shared_preferences.dart';

/// تنظیمات HEV SOCKS5 Tunnel (heiher/hev-socks5-tunnel).
/// مقادیر در SharedPreferences ذخیره و به‌صورت YAML واقعی نوشته می‌شوند.
///
/// توجه: runtime فعلی از flutter_vless برای TUN استفاده می‌کند؛ این لایه
/// کانفیگ را برای استفادهٔ آینده / sidecar آماده نگه می‌دارد و مسیر فایل
/// را از طریق [configFilePath] در دسترس می‌گذارد.
class HevEngineSettings {
  HevEngineSettings._();

  static const String _prefix = 'hev_engine_v1_';

  // tunnel
  static const String defaultName = 'tun0';
  static const int defaultMtu = 8500;
  static const String defaultIpv4 = '198.18.0.1';
  static const String defaultIpv6 = 'fc00::1';
  static const bool defaultMultiQueue = false;
  static const String defaultIcmp = 'off'; // off | reply

  // socks5
  static const int defaultSocksPort = 1819;
  static const String defaultSocksAddress = '127.0.0.1';
  static const String defaultUdp = 'udp'; // udp | tcp
  static const bool defaultPipeline = false;
  static const int defaultMark = 0;
  static const bool defaultTcpFastopen = false;

  // mapdns
  static const String defaultMapDnsAddress = '198.18.0.2';
  static const int defaultMapDnsPort = 53;
  static const String defaultMapDnsNetwork = '100.64.0.0';
  static const String defaultMapDnsNetmask = '255.192.0.0';
  static const int defaultMapDnsCacheSize = 10000;

  // misc
  static const int defaultTaskStackSize = 86016;
  static const int defaultTcpBufferSize = 65536;
  static const int defaultUdpRecvBufferSize = 524288;
  static const int defaultUdpCopyBufferNums = 10;
  static const int defaultMaxSessionCount = 0;
  static const int defaultConnectTimeoutMs = 10000;

  static Future<SharedPreferences> get _p async =>
      SharedPreferences.getInstance();

  static Future<String> getString(String key, String def) async {
    final p = await _p;
    return p.getString('$_prefix$key') ?? def;
  }

  static Future<int> getInt(String key, int def) async {
    final p = await _p;
    return p.getInt('$_prefix$key') ?? def;
  }

  static Future<bool> getBool(String key, bool def) async {
    final p = await _p;
    return p.getBool('$_prefix$key') ?? def;
  }

  static Future<void> setString(String key, String v) async {
    final p = await _p;
    await p.setString('$_prefix$key', v);
  }

  static Future<void> setInt(String key, int v) async {
    final p = await _p;
    await p.setInt('$_prefix$key', v);
  }

  static Future<void> setBool(String key, bool v) async {
    final p = await _p;
    await p.setBool('$_prefix$key', v);
  }

  /// YAML مطابق conf/main.yml پروژهٔ heiher/hev-socks5-tunnel.
  static Future<String> buildYaml() async {
    final name = await getString('name', defaultName);
    final mtu = await getInt('mtu', defaultMtu);
    final ipv4 = await getString('ipv4', defaultIpv4);
    final ipv6 = await getString('ipv6', defaultIpv6);
    final multiQueue = await getBool('multi_queue', defaultMultiQueue);
    final icmp = await getString('icmp', defaultIcmp);

    final socksPort = await getInt('socks_port', defaultSocksPort);
    final socksAddr = await getString('socks_address', defaultSocksAddress);
    final udp = await getString('udp', defaultUdp);
    final udpAddress = await getString('udp_address', '');
    final pipeline = await getBool('pipeline', defaultPipeline);
    final username = await getString('username', '');
    final password = await getString('password', '');
    final mark = await getInt('mark', defaultMark);
    final tcpFastopen = await getBool('tcp_fastopen', defaultTcpFastopen);

    final mapAddr = await getString('mapdns_address', defaultMapDnsAddress);
    final mapPort = await getInt('mapdns_port', defaultMapDnsPort);
    final mapNet = await getString('mapdns_network', defaultMapDnsNetwork);
    final mapMask = await getString('mapdns_netmask', defaultMapDnsNetmask);
    final mapCache = await getInt('mapdns_cache_size', defaultMapDnsCacheSize);

    final taskStack = await getInt('task_stack_size', defaultTaskStackSize);
    final tcpBuf = await getInt('tcp_buffer_size', defaultTcpBufferSize);
    final udpRecv = await getInt('udp_recv_buffer_size', defaultUdpRecvBufferSize);
    final udpCopy = await getInt('udp_copy_buffer_nums', defaultUdpCopyBufferNums);
    final maxSession = await getInt('max_session_count', defaultMaxSessionCount);
    final connectTimeout =
        await getInt('connect_timeout_ms', defaultConnectTimeoutMs);

    final buf = StringBuffer();
    buf.writeln('tunnel:');
    buf.writeln('  name: $name');
    buf.writeln('  mtu: $mtu');
    buf.writeln('  multi-queue: $multiQueue');
    buf.writeln('  ipv4: $ipv4');
    buf.writeln("  ipv6: '$ipv6'");
    buf.writeln("  icmp: '$icmp'");
    buf.writeln('');
    buf.writeln('socks5:');
    buf.writeln('  port: $socksPort');
    buf.writeln('  address: $socksAddr');
    buf.writeln("  udp: '$udp'");
    if (udpAddress.isNotEmpty) {
      buf.writeln("  udp-address: '$udpAddress'");
    }
    buf.writeln('  pipeline: $pipeline');
    if (username.isNotEmpty) {
      buf.writeln("  username: '$username'");
      buf.writeln("  password: '$password'");
    }
    buf.writeln('  mark: $mark');
    buf.writeln('  tcp-fastopen: $tcpFastopen');
    buf.writeln('');
    buf.writeln('mapdns:');
    buf.writeln('  address: $mapAddr');
    buf.writeln('  port: $mapPort');
    buf.writeln('  network: $mapNet');
    buf.writeln('  netmask: $mapMask');
    buf.writeln('  cache-size: $mapCache');
    buf.writeln('');
    buf.writeln('misc:');
    buf.writeln('  task-stack-size: $taskStack');
    buf.writeln('  tcp-buffer-size: $tcpBuf');
    buf.writeln('  udp-recv-buffer-size: $udpRecv');
    buf.writeln('  udp-copy-buffer-nums: $udpCopy');
    buf.writeln('  max-session-count: $maxSession');
    buf.writeln('  connect-timeout: $connectTimeout');
    return buf.toString();
  }

  /// نوشتن YAML روی دیسک اپ و برگرداندن مسیر فایل.
  static Future<String> writeConfigFile(Directory dir) async {
    final yaml = await buildYaml();
    final file = File('${dir.path}/hev-socks5-tunnel.yml');
    await file.writeAsString(yaml, flush: true);
    return file.absolute.path;
  }

  static Future<void> resetDefaults() async {
    final p = await _p;
    final keys = p.getKeys().where((k) => k.startsWith(_prefix)).toList();
    for (final k in keys) {
      await p.remove(k);
    }
  }
}
