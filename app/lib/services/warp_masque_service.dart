import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Wrapper for `WarpMasqueService.kt` — runs `libwarpmasque.so` (usque)
/// as a foreground service and exposes a local SOCKS5 on 127.0.0.1:1819.
/// وضعیت زنده اسکن MASQUE — قابل listen در UI.
class WarpMasqueScanState {
  final String phase;
  final int tested;
  final int total;
  final String endpoint;
  final int ms;
  final bool done;
  final String error;

  const WarpMasqueScanState({
    this.phase = '',
    this.tested = 0,
    this.total = 0,
    this.endpoint = '',
    this.ms = 0,
    this.done = false,
    this.error = '',
  });

  WarpMasqueScanState fromMap(Map<dynamic, dynamic> m) => WarpMasqueScanState(
        phase: m['phase']?.toString() ?? '',
        tested: (m['tested'] as num?)?.toInt() ?? 0,
        total: (m['total'] as num?)?.toInt() ?? 0,
        endpoint: m['endpoint']?.toString() ?? '',
        ms: (m['ms'] as num?)?.toInt() ?? 0,
        done: m['done'] == true,
        error: m['error']?.toString() ?? '',
      );

  double get progress => total > 0 ? tested / total : 0.0;
  bool get active => !done && phase.isNotEmpty;
}

class WarpMasqueService {
  WarpMasqueService._();

  /// وضعیت زنده اسکن — از MethodChannel پر می‌شه.
  static final ValueNotifier<WarpMasqueScanState> scanProgress =
      ValueNotifier(const WarpMasqueScanState());

  static const MethodChannel _ch =
      MethodChannel('com.hasan.hasan_vpn/warpmasque');

  static const int socksPort = 1819;

  static const String defaultEndpoint = '162.159.198.238:443';
  static const String defaultSni = 'soft98.ir';
  static const String defaultDns = '1.1.1.1,1.0.0.1';

  /// لیست پیش‌فرض candidate برای parallel fallback scan.
  /// هر توکن می‌تونه `host:port` یا `subnet/24:port` باشه.
  static const String defaultEndpointCandidates =
      '162.159.198.0/24:443,162.159.199.0/24:443,'
      '162.159.192.0/24:443,162.159.193.0/24:443,'
      '162.159.195.0/24:443,188.114.96.0/24:443,'
      '188.114.97.0/24:443,188.114.98.0/24:443,'
      '188.114.99.0/24:443';

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
        case 'onProgress':
          try {
            final args = call.arguments;
            if (args is Map) {
              scanProgress.value =
                  const WarpMasqueScanState().fromMap(args);
            }
          } catch (_) {}
          return null;
      }
      return null;
    });
  }

  static Future<bool> start({
    String endpoint = defaultEndpoint,
    String? endpointCandidates,
    String sni = defaultSni,
    String dns = defaultDns,
    bool http2 = true,
    bool desyncEnabled = false,
    int desyncSocksPort = 0,
    String deviceName = 'Hasan-VPN',
    Duration timeout = const Duration(seconds: 90),
  }) async {
    _ensureListener();
    lastError = null;
    scanProgress.value = const WarpMasqueScanState();

    try {
      final ok = await _ch.invokeMethod<bool>('start', {
        'endpoint': endpoint.trim(),
        'endpointCandidates': endpointCandidates?.trim(),
        'sni': sni.trim(),
        'dns': dns.trim(),
        'http2': http2,
        'desyncEnabled': desyncEnabled,
        'desyncSocksPort': desyncSocksPort,
        'deviceName': deviceName.trim(),
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

  /// Rescan MASQUE endpoints — با زیرساخت Kotlin parallel scanner.
  ///
  /// فرآیند:
  ///   1. config موقت با candidates داده‌شده می‌سازیم
  ///   2. WarpMasqueService.start() رو صدا می‌زنیم
  ///   3. منتظر می‌مونیم که scanProgress به "Connected" برسه
  ///   4. winning endpoint رو از آخرین progress می‌خونیم
  ///   5. سرویس رو stop می‌کنیم
  ///   6. endpoint رو برمی‌گردونیم
  ///
  /// [timeoutSec] — چقدر منتظر اسکن بمونیم (پیش‌فرض ۶۰ ثانیه).
  static Future<({String? endpoint, int ms, String? error})> rescanEndpoints({
    required String endpoint,
    String? endpointCandidates,
    String sni = defaultSni,
    String dns = defaultDns,
    bool http2 = true,
    int timeoutSec = 60,
  }) async {
    try {
      // ریست progress
      scanProgress.value = const WarpMasqueScanState();

      // تبدیل به Completer
      final completer = Completer<({String? endpoint, int ms, String? error})>();

      void listener() {
        final s = scanProgress.value;
        if (s.done) {
          if (s.error.isNotEmpty) {
            if (!completer.isCompleted) {
              completer.complete(
                (endpoint: null, ms: 0, error: s.error),
              );
            }
          } else if (s.endpoint.isNotEmpty) {
            if (!completer.isCompleted) {
              completer.complete(
                (endpoint: s.endpoint, ms: s.ms, error: null),
              );
            }
          }
        }
      }

      scanProgress.addListener(listener);

      // شروع اسکن (foreground service در پروسه جدا)
      final ok = await start(
        endpoint: endpoint,
        endpointCandidates: endpointCandidates,
        sni: sni,
        dns: dns,
        http2: http2,
        timeout: Duration(seconds: timeoutSec),
      );

      if (!ok) {
        scanProgress.removeListener(listener);
        final s = scanProgress.value;
        return (
          endpoint: null,
          ms: 0,
          error: s.error.isNotEmpty
              ? s.error
              : (lastError ?? 'scan failed'),
        );
      }

      // اگه reach شد، منتظر completer می‌مونیم یا مستقیم از progress می‌خونیم
      final result = completer.isCompleted
          ? await completer.future
          : await completer.future.timeout(
              Duration(seconds: timeoutSec),
              onTimeout: () {
                final s = scanProgress.value;
                if (s.endpoint.isNotEmpty) {
                  return (endpoint: s.endpoint, ms: s.ms, error: null);
                }
                return (
                  endpoint: null,
                  ms: 0,
                  error: 'timeout waiting for scan result'
                );
              },
            );

      scanProgress.removeListener(listener);

      // سرویس رو ببند (چون فقط برای اسکن باز شده بود)
      await stop();

      return result;
    } catch (e) {
      return (endpoint: null, ms: 0, error: e.toString());
    }
  }

  static Future<void> stop() async {
    _running = false;
    scanProgress.value = const WarpMasqueScanState();
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
