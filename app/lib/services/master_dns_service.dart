import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';

/// Wrapper for `MasterDnsService.kt` — runs `libmasterdns.so` as a
/// foreground service and exposes a local SOCKS5 on 127.0.0.1:18000.
///
/// Flow:
///   1. dart calls `start()` with domain + key + method + resolvers
///   2. Kotlin builds config.toml + resolvers.txt and runs libmasterdns.so
///   3. Kotlin parses stdout for scan progress (Accepted/Rejected N/M)
///   4. When SOCKS5 is up (port 18000), it sends `onReady`
///   5. Xray is started with socks5-outbound → 127.0.0.1:18000
class MasterDnsService {
  MasterDnsService._();

  static const MethodChannel _ch =
      MethodChannel('com.hasan.hasan_vpn/masterdns');

  static const int socksPort = 18000;

  static bool _running = false;
  static bool get isRunning => _running;

  static String? lastError;

  static void Function(int completed, int total)? onProgress;
  static void Function(String msg)? onError;
  static void Function()? onExit;

  static bool _listening = false;

  static void _ensureListener() {
    if (_listening) return;
    _listening = true;
    _ch.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'onProgress':
          final args = call.arguments;
          if (args is Map) {
            final c = (args['completed'] as num?)?.toInt() ?? 0;
            final t = (args['total'] as num?)?.toInt() ?? 0;
            onProgress?.call(c, t);
          }
          return null;
        case 'onError':
          lastError = call.arguments?.toString();
          onError?.call(lastError ?? 'unknown');
          return null;
        case 'onExit':
          _running = false;
          onExit?.call();
          return null;
      }
      return null;
    });
  }

  static Future<bool> start({
    required String domain,
    required String key,
    int method = 1,
    String resolvers = '',
    String? advancedToml,
    Duration timeout = const Duration(seconds: 90),
  }) async {
    _ensureListener();
    lastError = null;

    if (domain.trim().isEmpty || key.trim().isEmpty) {
      lastError = 'domain/key required';
      return false;
    }

    try {
      final ok = await _ch.invokeMethod<bool>('start', {
        'domain': domain.trim(),
        'key': key.trim(),
        'method': method,
        'resolvers': resolvers,
        if (advancedToml != null && advancedToml.isNotEmpty)
          'advanced': advancedToml,
      });
      if (ok != true) {
        lastError = 'start() returned false';
        return false;
      }
      _running = true;

      // صبر کن SOCKS5 گوش بده (تا timeout)
      final deadline = DateTime.now().add(timeout);
      while (DateTime.now().isBefore(deadline)) {
        if (!_running) {
          lastError ??= 'MasterDNS exited during startup';
          return false;
        }
        if (await isSocksAlive()) return true;
        await Future.delayed(const Duration(milliseconds: 500));
      }
      lastError = 'timeout waiting for SOCKS5 on port $socksPort';
      await stop();
      return false;
    } catch (e) {
      lastError = e.toString();
      _running = false;
      return false;
    }
  }

  static Future<void> stop() async {
    _running = false;
    try {
      await _ch.invokeMethod('stop');
    } catch (_) {}
  }

  static Future<void> cancelStartup() async {
    _running = false;
    try {
      await _ch.invokeMethod('cancelStartup');
    } catch (_) {}
  }

  static Future<bool> status() async {
    try {
      final r = await _ch.invokeMethod<Map>('status');
      _running = r?['running'] == true;
      return _running;
    } catch (_) {
      return false;
    }
  }

  /// چک کن SOCKS5 روی پورت 18000 گوش می‌ده (با TCP connect از Dart).
  static Future<bool> isSocksAlive() async {
    try {
      final s = await Socket.connect(
        '127.0.0.1',
        socksPort,
        timeout: const Duration(milliseconds: 800),
      );
      s.destroy();
      return true;
    } catch (_) {
      return false;
    }
  }
}
