import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'v2ray_engine.dart';

/// تست سرعت دانلود از طریق SOCKS محلی (تونل فعال).
class SpeedTestResult {
  final double mbps;
  final int bytes;
  final Duration elapsed;
  final String? error;

  const SpeedTestResult({
    this.mbps = 0,
    this.bytes = 0,
    this.elapsed = Duration.zero,
    this.error,
  });

  String get summary =>
      error != null ? 'خطا: $error' : '${mbps.toStringAsFixed(2)} Mbps';
}

class SpeedTestService {
  SpeedTestService._();

  /// URL های تست به ترتیب اولویت — اگه اولی fail داد، بعدی.
  /// هم HTTPS هم HTTP (بعضی تونل‌ها HTTP رو سریع‌تر رد می‌کنن)، و
  /// چند endpoint مختلف تا اگه یکی مسدود بود، بعدی جواب بده.
  static const List<String> _testUrls = <String>[
    'https://speed.cloudflare.com/__down?bytes=20000000',
    'http://speedtest.tele2.net/10MB.zip',
    'https://proof.ovh.net/files/10Mb.dat',
    'http://ipv4.download.thinkbroadband.com/10MB.zip',
    'https://cachefly.cachefly.net/10mb.test',
    'http://cachefly.cachefly.net/10mb.test',
    'https://ash-speed.hetzner.com/10MB.bin',
  ];

  /// pre-check: SOCKS پورت واقعاً listener داره؟
  static Future<bool> _socksAlive(int port) async {
    try {
      final s = await Socket.connect('127.0.0.1', port,
          timeout: const Duration(seconds: 3));
      s.destroy();
      return true;
    } catch (_) {
      return false;
    }
  }

  /// دانلود از طریق SOCKS محلی روی 10808.
  static Future<SpeedTestResult> run({
    int? socksPort,
    Duration timeout = const Duration(seconds: 20),
    void Function(int bytes, double mbps)? onProgress,
  }) async {
    final port = socksPort ?? V2RayEngine.localSocksPort;
    if (port <= 0) {
      return const SpeedTestResult(error: 'no active tunnel');
    }
    // FIX: قبل از هر تلاشی، چک کن SOCKS پورت واقعاً بازه. اگه نباشه،
    // error معنادار برگردون نه "all test urls failed".
    if (!await _socksAlive(port)) {
      return SpeedTestResult(
          error: 'SOCKS port $port not listening — reconnect');
    }

    final errors = <String>[];
    for (final url in _testUrls) {
      try {
        final r = await _tryDownload(url, port, timeout, onProgress);
        if (r.error == null && r.bytes > 0) return r;
        if (r.error != null) errors.add('${Uri.parse(url).host}: ${r.error}');
      } catch (e) {
        errors.add('${Uri.parse(url).host}: $e');
        debugPrint('SpeedTest $url: $e');
      }
    }
    // پیام خطا شامل ۲ تا خطای آخر
    final tail = errors.length > 2
        ? errors.sublist(errors.length - 2).join(' | ')
        : errors.join(' | ');
    return SpeedTestResult(error: 'all urls failed — $tail');
  }

  static Future<SpeedTestResult> _tryDownload(
    String url,
    int socksPort,
    Duration timeout,
    void Function(int bytes, double mbps)? onProgress,
  ) async {
    final uri = Uri.parse(url);
    final sw = Stopwatch()..start();
    HttpClient? client;
    try {
      client = HttpClient();
      client.findProxy = (u) => 'SOCKS 127.0.0.1:$socksPort';
      client.connectionTimeout = const Duration(seconds: 15);
      client.badCertificateCallback = (_, __, ___) => true;

      final req = await client.getUrl(uri).timeout(timeout);
      final res = await req.close().timeout(timeout);

      int bytes = 0;
      final completer = Completer<void>();
      final sub = res.listen(
        (chunk) {
          bytes += chunk.length;
          final secs = sw.elapsedMilliseconds / 1000.0;
          if (secs > 0.5) {
            final mbps = (bytes * 8) / secs / 1000000;
            onProgress?.call(bytes, mbps);
          }
          // بعد از ۱۰ مگابایت قطع کن
          if (bytes >= 10000000) {
            if (!completer.isCompleted) completer.complete();
          }
        },
        onDone: () {
          if (!completer.isCompleted) completer.complete();
        },
        onError: (e) {
          if (!completer.isCompleted) completer.completeError(e);
        },
        cancelOnError: true,
      );

      await completer.future.timeout(timeout, onTimeout: () {
        sub.cancel();
      });
      sw.stop();

      final secs = sw.elapsedMilliseconds / 1000.0;
      final mbps = secs > 0 ? (bytes * 8) / secs / 1000000 : 0.0;
      client.close(force: true);

      return SpeedTestResult(
        mbps: mbps,
        bytes: bytes,
        elapsed: sw.elapsed,
      );
    } catch (e) {
      try {
        client?.close(force: true);
      } catch (_) {}
      return SpeedTestResult(error: e.toString());
    }
  }
}
