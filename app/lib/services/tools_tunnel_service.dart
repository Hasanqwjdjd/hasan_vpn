import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/server.dart';
import 'link_parser.dart';
import 'settings_service.dart';
import 'v2ray_engine.dart';

/// نتیجه‌ی آماده‌سازی پروکسی محلی برای ابزارهای تشخیصی.
class ToolsProxy {
  /// پورت SOCKS5 واقعاً زنده (تأییدشده با handshake) — 0 یعنی پیدا نشد.
  final int socksPort;

  /// پورت HTTP proxy واقعاً زنده (تأییدشده با درخواست واقعی) — 0 = پیدا نشد.
  final int httpPort;

  /// true = VPN سیستم از قبل روشن بود و از تونل فعال استفاده کردیم؛
  /// false = تونل موقت proxy-only توسط همین سرویس بالا آمد.
  final bool reusedVpn;

  final VpnServer? server;

  const ToolsProxy({
    required this.socksPort,
    required this.httpPort,
    required this.reusedVpn,
    this.server,
  });
}

/// بخش ۱.۲ — تونل موقت ابزارها (IP خروجی / تست سرعت / نشت DNS).
///
/// مشکل قبلی: ابزارها فقط پورت 10808/9050 را TCP-check می‌کردند در حالی که
/// در بیلد فعلی SOCKS واقعی هسته روی 10807 بالا می‌آید و HTTP proxy روی
/// 10808؛ ضمن اینکه وقتی VPN روشن نبود هیچ مسیری برای تست وجود نداشت و
/// کاربر خطای «no SOCKS port listening» می‌گرفت.
///
/// راه‌حل:
///   1. اگر VPN روشن است → پورت‌های واقعی را با handshake واقعی پیدا کن.
///   2. اگر VPN خاموش است → با همان مسیر connect یک تونل proxy-only موقت
///      (بدون مجوز VPN و بدون TUN) از «سرور انتخابی/آخر» بالا بیاور.
///   3. هر دو حالت لاگ اجباری [Tools] دارند.
class ToolsTunnelService {
  ToolsTunnelService._();

  static bool _ownedByTools = false;
  static VpnServer? _ownedServer;
  static ToolsProxy? _last;

  static ToolsProxy? get last => _last;

  /// فقط تونلی که خود ابزارها بالا آورده‌اند را پایین بکش.
  static Future<void> releaseOwned() async {
    if (!_ownedByTools) return;
    debugPrint('[Tools] releasing temporary proxy-only tunnel');
    try {
      await V2RayEngine.disconnect();
    } catch (_) {}
    _ownedByTools = false;
    _ownedServer = null;
  }

  /// پورت SOCKS5 زنده را بین کاندیدها با handshake واقعی پیدا می‌کند.
  static Future<int> findSocksPort() async {
    final candidates = <int>[
      V2RayEngine.localSocksPort,
      10807, // پورت واقعی fork (LOCAL_SOCKS5_PORT پیش‌فرض)
      10808, // inbound کانفیگ‌های استاندارد / HTTP proxy در fork
      1080,
      9050, // Tor
      1819, // WARP MASQUE
      18000, // MasterDNS
    ];
    for (final port in candidates) {
      if (port <= 0) continue;
      if (await _socksGreetingOk(port)) {
        debugPrint('[Tools] live SOCKS5 found on 127.0.0.1:$port');
        return port;
      }
    }
    debugPrint('[Tools] no live SOCKS5 port among: '
        '${candidates.where((p) => p > 0).join(", ")}');
    return 0;
  }

  /// پورت HTTP proxy زنده را با یک درخواست واقعی (CONNECT) تأیید می‌کند.
  static Future<int> findHttpPort() async {
    final candidates = <int>[10808, 10809, 10807];
    for (final port in candidates) {
      if (port <= 0) continue;
      if (await _httpProxyOk(port)) {
        debugPrint('[Tools] live HTTP proxy found on 127.0.0.1:$port');
        return port;
      }
    }
    debugPrint('[Tools] no live HTTP proxy among: $candidates');
    return 0;
  }

  /// تأیید عمومی اینکه یک پورت SOCKS5 زنده است (برای پورت‌های پاس‌داده‌شده).
  static Future<bool> verifySocks(int port) => _socksGreetingOk(port);

  /// SOCKS5 greeting واقعی: 05 01 00 → 05 00
  static Future<bool> _socksGreetingOk(int port) async {
    Socket? socket;
    try {
      socket = await Socket.connect(
        InternetAddress.loopbackIPv4,
        port,
        timeout: const Duration(milliseconds: 800),
      );
      socket.add(const <int>[0x05, 0x01, 0x00]);
      await socket.flush();
      final reply = await socket.first.timeout(
        const Duration(milliseconds: 800),
        onTimeout: () => throw TimeoutException('greeting'),
      );
      final ok = reply.length >= 2 && reply[0] == 0x05 && reply[1] == 0x00;
      if (!ok) {
        debugPrint('[Tools] port $port is not a SOCKS5 (greeting rejected)');
      }
      return ok;
    } catch (e) {
      debugPrint('[Tools] port $port probe failed: ${e.toString()}');
      return false;
    } finally {
      try {
        socket?.destroy();
      } catch (_) {}
    }
  }

  /// HTTP proxy واقعی: یک GET به generate_204 از طریق proxy.
  static Future<bool> _httpProxyOk(int port) async {
    try {
      final client = HttpClient();
      client.findProxy = (uri) => 'PROXY 127.0.0.1:$port';
      client.connectionTimeout = const Duration(seconds: 4);
      final req = await client
          .getUrl(Uri.parse('http://www.gstatic.com/generate_204'))
          .timeout(const Duration(seconds: 5));
      final res = await req.close().timeout(const Duration(seconds: 5));
      await res.drain<void>().timeout(const Duration(seconds: 5));
      client.close(force: true);
      return res.statusCode > 0;
    } catch (e) {
      debugPrint('[Tools] http proxy probe on $port failed: ${e.toString()}');
      return false;
    }
  }

  /// بازیابی سرور هدف: سرور متصل فعلی → آخرین سرور انتخابی (custom یا
  /// کش اشتراک‌ها). اگر هیچ‌کدام نبود null.
  static Future<VpnServer?> _resolveTarget() async {
    final current = V2RayEngine.current;
    if (current != null) return current;

    final lastId = await SettingsService.getLastServer();
    if (lastId == null || lastId.isEmpty) return null;

    // 1) سرورهای custom ذخیره‌شده (custom_servers_v1 — همان فرمت home_screen)
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('custom_servers_v1');
      if (raw != null) {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          for (final item in decoded) {
            if (item is! Map) continue;
            final map = Map<String, dynamic>.from(item);
            if (map['id']?.toString() != lastId) continue;
            final protocolName = map['protocol']?.toString() ?? 'custom';
            final protocol = VpnProtocol.values.firstWhere(
              (value) => value.name == protocolName,
              orElse: () => VpnProtocol.custom,
            );
            final port = int.tryParse(map['port']?.toString() ?? '') ?? 443;
            return VpnServer(
              id: lastId,
              name: map['name']?.toString() ?? 'server',
              flag: map['flag']?.toString() ?? '🔧',
              shareLink: map['shareLink']?.toString() ?? '',
              protocol: protocol,
              host: map['host']?.toString() ?? '',
              port: port > 0 ? port : 443,
            );
          }
        }
      }
    } catch (e) {
      debugPrint('[Tools] custom server lookup failed: $e');
    }

    // 2) کش اشتراک‌ها — لینک‌ها با همان stableId بازسازی می‌شوند.
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('subscriptions_v3');
      if (raw != null) {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          for (final subItem in decoded) {
            if (subItem is! Map) continue;
            final links = subItem['cachedLinks'];
            if (links is! List) continue;
            for (final link in links) {
              final l = link?.toString() ?? '';
              if (l.trim().isEmpty) continue;
              try {
                final id = LinkParser.stableId('sub', l);
                if (id != lastId) continue;
                final server = LinkParser.parse(l, id: id);
                if (server != null) return server;
              } catch (_) {}
            }
          }
        }
      }
    } catch (e) {
      debugPrint('[Tools] subscription cache lookup failed: $e');
    }
    return null;
  }

  /// آماده‌سازی پروکسی برای ابزارها. هرگز null خطای throw نمی‌کند؛
  /// null = آماده نشد (پیام در لاگ).
  static Future<ToolsProxy?> ensure() async {
    // ─── حالت ۱: VPN روشن است — از تونل فعال استفاده کن ───
    if (V2RayEngine.isConnected) {
      final socks = await findSocksPort();
      final http = await findHttpPort();
      if (socks > 0) {
        debugPrint('[Tools] reusing active VPN tunnel '
            '(socks=$socks http=$http)');
        _last = ToolsProxy(
          socksPort: socks,
          httpPort: http,
          reusedVpn: true,
          server: V2RayEngine.current,
        );
        return _last;
      }
      debugPrint('[Tools] VPN is connected but no local SOCKS is reachable');
    }

    // ─── حالت ۲: تونل موقت proxy-only ───
    final server = await _resolveTarget();
    if (server == null) {
      debugPrint('[Tools] no target server to open a temporary tunnel');
      return null;
    }

    // اتصال قبلیِOwned را ببند تا پورت‌ها تازه شوند.
    await releaseOwned();

    debugPrint('[Tools] starting temporary proxy-only tunnel for '
        '${server.displayName} (${server.protocol.name})');
    final built = await V2RayEngine.buildConfigFor(server);
    if (built == null) {
      debugPrint('[Tools] buildConfigFor failed: ${V2RayEngine.lastError}');
      return null;
    }
    final (config, remark) = built;
    final ok = await V2RayEngine.startConfig(
      remark: remark,
      config: config,
      server: server,
      forceProxyOnly: true,
    );
    if (!ok) {
      debugPrint('[Tools] proxy-only start failed: ${V2RayEngine.lastError}');
      return null;
    }
    _ownedByTools = true;
    _ownedServer = server;

    // صبر کوتاه تا Xray listener ها بالا بیایند.
    int socks = 0;
    int http = 0;
    for (var i = 0; i < 10; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 400));
      socks = await findSocksPort();
      if (socks > 0) {
        http = await findHttpPort();
        break;
      }
    }
    if (socks <= 0) {
      debugPrint('[Tools] temporary tunnel did not open a SOCKS port');
      return null;
    }
    debugPrint('[Tools] temporary tunnel ready '
        '(socks=$socks http=$http server=${server.displayName})');
    _last = ToolsProxy(
      socksPort: socks,
      httpPort: http,
      reusedVpn: false,
      server: server,
    );
    return _last;
  }
}
