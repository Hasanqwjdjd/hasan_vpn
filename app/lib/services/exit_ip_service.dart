import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'socks_probe.dart';
import 'v2ray_engine.dart';
import 'xray_settings.dart';

/// اطلاعات IP خروجی از داخل تونل (الهام از ZedSecure).
class ExitIpInfo {
  final String ip;
  final String? country;
  final String? city;
  final String? org;
  final int? latencyMs;

  const ExitIpInfo({
    required this.ip,
    this.country,
    this.city,
    this.org,
    this.latencyMs,
  });

  String get summary {
    final parts = <String>[ip];
    if (country != null && country!.isNotEmpty) parts.add(country!);
    if (city != null && city!.isNotEmpty) parts.add(city!);
    if (org != null && org!.isNotEmpty) parts.add(org!);
    return parts.join(' · ');
  }
}

class ExitIpService {
  ExitIpService._();

  static ExitIpInfo? last;

  /// از داخل تونل فعلی (SOCKS محلی) IP خروجی را می‌گیرد.
  static Future<ExitIpInfo?> fetch({
    int? socksPort,
    Duration timeout = const Duration(seconds: 10),
  }) async {
    final port = socksPort ?? V2RayEngine.localSocksPort;
    try {
      // اول از طریق SOCKS اگر تونل بالا باشد
      final viaSocks = await _viaSocks(port, timeout);
      if (viaSocks != null) {
        last = viaSocks;
        return viaSocks;
      }
    } catch (e) {
      debugPrint('ExitIp via SOCKS: $e');
    }

    // اگر SOCKS جواب نداد، مستقیم (بدون تونل) — فقط برای تشخیص
    try {
      final direct = await _direct(timeout);
      if (direct != null) {
        last = direct;
        return direct;
      }
    } catch (e) {
      debugPrint('ExitIp direct: $e');
    }
    return null;
  }

  static Future<(String, int, String)> _connInfoTarget() async {
    try {
      final xs = await XraySettings.load();
      final raw = xs['connInfoUrl']?.toString() ?? '';
      if (raw.isNotEmpty) {
        final uri = Uri.tryParse(raw);
        if (uri != null && uri.host.isNotEmpty) {
          final p = uri.hasPort ? uri.port : (uri.scheme == 'https' ? 443 : 80);
          final path = uri.path.isEmpty ? '/' : uri.path;
          return (uri.host, p, path);
        }
      }
    } catch (_) {}
    return ('api.ipify.org', 80, '/?format=json');
  }

  static Future<ExitIpInfo?> _viaSocks(int port, Duration timeout) async {
    // از SocksProbe برای اطمینان از بالا بودن تونل استفاده می‌کنیم
    final probe = await SocksProbe.measure(port: port, samples: 1)
        .timeout(timeout, onTimeout: () => const ProbeResult(error: 'timeout'));
    if (!probe.ok) return null;

    Socket? socket;
    try {
      socket = await Socket.connect(
        InternetAddress.loopbackIPv4,
        port,
        timeout: timeout,
      );
      // SOCKS5 handshake no-auth
      socket.add([0x05, 0x01, 0x00]);
      await socket.flush();
      final h = await _read(socket, 2, timeout);
      if (h[0] != 0x05 || h[1] != 0x00) return null;

      // CONNECT to connInfoUrl host:port over SOCKS
      final target = await _connInfoTarget();
      final host = target.$1;
      final tport = target.$2;
      final hostBytes = utf8.encode(host);
      final req = <int>[
        0x05, 0x01, 0x00, 0x03,
        hostBytes.length,
        ...hostBytes,
        (tport >> 8) & 0xff, tport & 0xff,
      ];
      socket.add(req);
      await socket.flush();
      final rep = await _read(socket, 4, timeout);
      if (rep[1] != 0x00) return null;
      // skip bind addr
      if (rep[3] == 0x01) {
        await _read(socket, 4 + 2, timeout);
      } else if (rep[3] == 0x03) {
        final l = (await _read(socket, 1, timeout))[0];
        await _read(socket, l + 2, timeout);
      } else if (rep[3] == 0x04) {
        await _read(socket, 16 + 2, timeout);
      }

      final http =
          'GET ${target.$3} HTTP/1.1\r\nHost: $host\r\nConnection: close\r\n\r\n';
      socket.write(http);
      await socket.flush();

      final body = await _readBody(socket, timeout);
      final ipMatch = RegExp(r'"?ip"?\s*:\s*"?([0-9.]+)"?').firstMatch(body) ??
          RegExp(r'\b(\d{1,3}(?:\.\d{1,3}){3})\b').firstMatch(body);
      if (ipMatch == null) return null;
      final ip = ipMatch.group(1)!;

      // جزئیات بیشتر (کشور) از ip-api — اختیاری
      String? country;
      String? city;
      String? org;
      try {
        final detail = await _detailViaSocks(port, ip, timeout);
        country = detail['country'];
        city = detail['city'];
        org = detail['org'] ?? detail['isp'];
      } catch (_) {}

      return ExitIpInfo(
        ip: ip,
        country: country,
        city: city,
        org: org,
        latencyMs: probe.ms,
      );
    } finally {
      try {
        await socket?.close();
      } catch (_) {}
    }
  }

  static Future<Map<String, String>> _detailViaSocks(
    int socksPort,
    String ip,
    Duration timeout,
  ) async {
    // ساده‌سازی: بدون جزئیات اضافه اگر شکست خورد
    return {};
  }

  static Future<ExitIpInfo?> _direct(Duration timeout) async {
    try {
      final client = HttpClient();
      client.connectionTimeout = timeout;
      final req = await client
          .getUrl(Uri.parse('https://api.ipify.org?format=json'))
          .timeout(timeout);
      final res = await req.close().timeout(timeout);
      final body = await res.transform(utf8.decoder).join();
      client.close(force: true);
      final m = RegExp(r'"ip"\s*:\s*"([^"]+)"').firstMatch(body);
      if (m == null) return null;
      return ExitIpInfo(ip: m.group(1)!);
    } catch (_) {
      return null;
    }
  }

  static Future<List<int>> _read(Socket s, int n, Duration t) async {
    final out = <int>[];
    final deadline = DateTime.now().add(t);
    await for (final chunk in s) {
      out.addAll(chunk);
      if (out.length >= n) return out.sublist(0, n);
      if (DateTime.now().isAfter(deadline)) {
        throw TimeoutException('read');
      }
    }
    throw const SocketException('closed');
  }

  static Future<String> _readBody(Socket s, Duration t) async {
    final buf = <int>[];
    final deadline = DateTime.now().add(t);
    await for (final chunk in s) {
      buf.addAll(chunk);
      if (buf.length > 8192) break;
      if (DateTime.now().isAfter(deadline)) break;
      final text = utf8.decode(buf, allowMalformed: true);
      if (text.contains('\r\n\r\n') &&
          (text.contains('}') || text.contains('\n'))) {
        break;
      }
    }
    return utf8.decode(buf, allowMalformed: true);
  }
}
