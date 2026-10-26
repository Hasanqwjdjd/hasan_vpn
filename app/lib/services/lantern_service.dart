import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

import '../models/server.dart';
import 'app_log.dart';
import 'connection_log_service.dart';
import 'v2ray_engine.dart';

/// Lantern — پل Flutter به SDK رسمی (getlantern/lanternsdk-android v1.0.1).
///
/// هستهٔ Lantern یک پروکسی HTTP محلی بالا می‌آورد (proxyAllTraffic=false)
/// و Xray با outbound پروتکل http ترافیک TUN را از آن عبور می‌دهد —
/// همان الگوی زنجیرهٔ Psiphon/Tor/Geph.
class LanternServiceDart {
  LanternServiceDart._();

  static const MethodChannel _ch =
      MethodChannel('com.hasan.hasan_vpn/lantern');

  static String? lastError;
  static bool _connected = false;
  static int _port = 0;

  static bool get isConnected => _connected;
  static int get port => _port;

  static Future<int> _freePort() async {
    final s = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final p = s.port;
    await s.close();
    return p;
  }

  static Future<bool> connect({
    void Function(String msg)? onProgress,
    bool Function()? isCancelled,
  }) async {
    lastError = null;
    _connected = false;
    try {
      final allowed = await V2RayEngine.requestPermission();
      if (!allowed) {
        lastError = 'VPN permission denied';
        return false;
      }

      onProgress?.call('Lantern · راه‌اندازی هسته…');
      final port = await _freePort();
      AppLog.i('LANTERN', 'starting core on :$port');
      final started = await _ch.invokeMethod<bool>(
        'start',
        {'port': port, 'app': 'HasanVPN'},
      );
      if (started != true) {
        lastError = 'Lantern service could not be started';
        return false;
      }
      _port = port;

      // آمادگی واقعی: CONNECT از پورت HTTP پروکسی (مثل SocksProbe ولی http).
      final deadline = DateTime.now().add(const Duration(seconds: 90));
      var ready = false;
      while (DateTime.now().isBefore(deadline)) {
        if (isCancelled?.call() ?? false) {
          await stop();
          return false;
        }
        await Future<void>.delayed(const Duration(milliseconds: 700));
        ready = await _httpProxyReady(port);
      if (ready) AppLog.i('LANTERN', 'http proxy ready on :$port');
        if (ready) break;
        final st = await status();
        if (st['running'] != true) {
          lastError =
              st['error']?.toString() ?? 'Lantern stopped early';
          return false;
        }
      }
      if (!ready) {
        lastError = 'Timed out — Lantern proxy did not answer';
        await stop();
        return false;
      }

      onProgress?.call('Lantern · بستن مسیر با Xray');
      final cfgXray = _buildLanternXrayConfig(port);
      final fake = VpnServer(
        id: 'lantern_fake_${DateTime.now().millisecondsSinceEpoch}',
        name: 'Lantern',
        flag: '🏮',
        shareLink: 'xrayjson://lantern',
        protocol: VpnProtocol.xrayJson,
        host: '127.0.0.1',
        port: port,
        isDeletable: false,
      );
      final ok = await V2RayEngine.startConfig(
        remark: 'Lantern',
        config: cfgXray,
        server: fake,
      );
      if (!ok) {
        lastError = V2RayEngine.lastError ?? 'VPN routing failed';
        await stop();
        return false;
      }
      _connected = true;
      ConnectionLogService.logConnect('Lantern');
      return true;
    } catch (e) {
      lastError = e.toString();
      return false;
    }
  }

  static Future<void> stop() async {
    try {
      await V2RayEngine.disconnect();
    } catch (_) {}
    try {
      await _ch.invokeMethod('stop');
    } catch (_) {}
    _connected = false;
    _port = 0;
  }

  static Future<Map<String, dynamic>> status() async {
    try {
      final r = await _ch.invokeMapMethod<String, dynamic>('status');
      return r ?? {'running': false};
    } catch (_) {
      return {'running': false};
    }
  }

  /// تست واقعی پروکسی HTTP: GET از طریق CONNECT.
  static Future<bool> _httpProxyReady(int port) async {
    Socket? sock;
    try {
      sock = await Socket.connect('127.0.0.1', port,
          timeout: const Duration(seconds: 2));
      sock.add(utf8.encode(
          'GET http://www.gstatic.com/generate_204 HTTP/1.1\r\n'
          'Host: www.gstatic.com\r\n'
          'Connection: close\r\n\r\n'));
      final reply = await sock
          .map(utf8.decode)
          .take(1)
          .first
          .timeout(const Duration(seconds: 8));
      return reply.contains('204') || reply.contains('302') ||
          reply.startsWith('HTTP/');
    } catch (_) {
      return false;
    } finally {
      try {
        sock?.destroy();
      } catch (_) {}
    }
  }

  /// پیکربندی Xray زنجیره — outbound پروتکل http به هستهٔ Lantern.
  static String _buildLanternXrayConfig(int port) {
    final cfg = <String, dynamic>{
      'inbounds': [
        {
          'tag': 'socks-in',
          'port': 10808,
          'listen': '127.0.0.1',
          'protocol': 'socks',
          'settings': {'auth': 'noauth', 'udp': true},
          'sniffing': {
            'enabled': true,
            'destOverride': ['http', 'tls'],
          },
        },
      ],
      'outbounds': [
        {
          'tag': 'lantern-out',
          'protocol': 'http',
          'settings': {
            'servers': [
              {'address': '127.0.0.1', 'port': port},
            ],
          },
        },
        {'tag': 'direct', 'protocol': 'freedom'},
        {'tag': 'dns-out', 'protocol': 'dns'},
        {'tag': 'block', 'protocol': 'blackhole'},
      ],
      'routing': {
        'domainStrategy': 'AsIs',
        'rules': <Map<String, dynamic>>[
          {
            'type': 'field',
            'inboundTag': ['socks-in'],
            'port': 53,
            'outboundTag': 'lantern-out',
          },
          {
            'type': 'field',
            'inboundTag': ['socks-in'],
            'network': 'udp',
            'outboundTag': 'block',
          },
        ],
      },
    };
    return jsonEncode(cfg);
  }
}

// jsonEncode از dart:convert
