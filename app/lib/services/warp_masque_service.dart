import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';

/// Wrapper for `WarpMasqueService.kt` — runs `libwarpmasque.so` (usque)
/// as a foreground service and exposes a local SOCKS5 on 127.0.0.1:1819.
class WarpMasqueService {
  WarpMasqueService._();

  static const MethodChannel _ch =
      MethodChannel('com.hasan.hasan_vpn/warpmasque');

  static const int socksPort = 1819;

  static const String defaultEndpoint = '162.159.198.238:443';
  static const String defaultSni = 'soft98.ir';
  static const String defaultDns = '1.1.1.1,1.0.0.1';

  static bool _running = false;
  static bool get isRunning => _running;

  static String? lastError;

  static void Function()? onReady;
  static void Function(String msg)? onError;

  static bool _listening = false;

  static void _ensureListener() {
    if (_listening) return;
    _listening = true;
    _ch.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'onReady':
          onReady?.call();
          return null;
        case 'onError':
          lastError = call.arguments?.toString();
          onError?.call(lastError ?? 'unknown');
          return null;
      }
      return null;
    });
  }

  static Future<bool> start({
    String endpoint = defaultEndpoint,
    String sni = defaultSni,
    String dns = defaultDns,
    bool http2 = true,
    Duration timeout = const Duration(seconds: 90),
  }) async {
    _ensureListener();
    lastError = null;

    try {
      final ok = await _ch.invokeMethod<bool>('start', {
        'endpoint': endpoint.trim(),
        'sni': sni.trim(),
        'dns': dns.trim(),
        'http2': http2,
      });
      if (ok != true) {
        lastError = 'start() returned false';
        return false;
      }
      _running = true;

      final deadline = DateTime.now().add(timeout);
      while (DateTime.now().isBefore(deadline)) {
        if (!_running) {
          lastError ??= 'MASQUE exited during startup';
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
