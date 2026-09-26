import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';

import '../models/tunnel_profile.dart';

/// کلاینت MethodChannel برای TunnelService.kt — اجرای باینری‌های
/// DNSTT / NoizDNS / VayDNS / Slipstream و انتظار برای باز شدن SOCKS.
class TunnelService {
  TunnelService._();

  static const MethodChannel _channel =
      MethodChannel('com.hasan.hasan_vpn/tunnel');

  /// یک پورت آزاد محلی انتخاب می‌کند.
  static Future<int> _freePort() async {
    final s = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final p = s.port;
    await s.close();
    return p;
  }

  /// شروع تونل. اگر پورت مشخص نشده باشد، پورت آزاد انتخاب می‌شود.
  /// پس از بازگشت موفق، SOCKS5 روی `127.0.0.1:<socksPort>` آماده است.
  static Future<Map<String, dynamic>> start(
    TunnelProfile profile, {
    void Function(String msg)? onProgress,
  }) async {
    if (profile.domain.isEmpty) {
      return <String, dynamic>{'ok': false, 'error': 'domain required'};
    }

    final port = profile.listenPort > 0 ? profile.listenPort : await _freePort();
    final args = profile.buildArgs(port);
    final env = profile.buildEnv();

    onProgress?.call('Starting ${profile.kind} on port $port…');

    try {
      final ok = await _channel.invokeMethod<bool>('start', <String, dynamic>{
        'binary': profile.binary,
        'args': args,
        'env': env,
        'remark': profile.name.isNotEmpty ? profile.name : profile.summary,
      });

      if (ok != true) {
        final st = await status();
        return <String, dynamic>{
          'ok': false,
          'error': st['error']?.toString() ?? 'start failed',
        };
      }
    } catch (e) {
      return <String, dynamic>{'ok': false, 'error': e.toString()};
    }

    // انتظار برای باز شدن SOCKS — تا ۲۰ ثانیه
    final deadline = DateTime.now().add(const Duration(seconds: 20));
    while (DateTime.now().isBefore(deadline)) {
      await Future.delayed(const Duration(milliseconds: 500));
      if (await _isPortOpen(port)) {
        return <String, dynamic>{
          'ok': true,
          'socksPort': port,
        };
      }
      final st = await status();
      if (st['exited'] == true) {
        return <String, dynamic>{
          'ok': false,
          'error': '${profile.kind} exited: ${st['lastLine'] ?? st['error'] ?? 'unknown'}',
        };
      }
    }

    // آخرین تلاش
    await stop();
    return <String, dynamic>{
      'ok': false,
      'error': 'SOCKS port $port never opened (timeout)',
    };
  }

  static Future<bool> _isPortOpen(int port) async {
    try {
      final s = await Socket.connect(
        '127.0.0.1',
        port,
        timeout: const Duration(milliseconds: 700),
      );
      s.destroy();
      return true;
    } catch (_) {
      return false;
    }
  }

  static Future<void> stop() async {
    try {
      await _channel.invokeMethod<bool>('stop');
    } catch (_) {}
  }

  static Future<Map<String, dynamic>> status() async {
    try {
      final r = await _channel.invokeMapMethod<String, dynamic>('status');
      return r ?? <String, dynamic>{};
    } catch (_) {
      return <String, dynamic>{};
    }
  }

  static Future<String> log() async {
    final s = await status();
    return s['log']?.toString() ?? '';
  }

  static Future<bool> isRunning() async {
    final s = await status();
    return s['running'] == true && s['exited'] != true;
  }
}
