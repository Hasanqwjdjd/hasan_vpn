import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'connection_log_service.dart';

/// Health monitor برای endpoint انتخاب‌شده WARP/WARP+/MASQUE.
///
/// هر [intervalSec] ثانیه (پیش‌فرض ۳۰) یه بار یه TCP-connect سریع به
/// endpoint فعلی می‌زنه. اگه N بار متوالی fail شد، flag می‌ذاره که UI
/// بتونه هشدار بده یا auto-rescan کنه.
class WarpEndpointHealthMonitor {
  WarpEndpointHealthMonitor._();
  static final WarpEndpointHealthMonitor instance =
      WarpEndpointHealthMonitor._();

  static const int defaultIntervalSec = 30;
  static const int consecutiveFailsToWarn = 3;

  Timer? _timer;
  String? _endpoint;
  String? _serverId;
  int _consecutiveFails = 0;
  bool _lastOk = true;

  /// callback ها برای UI.
  void Function(String serverId)? onDegraded;
  void Function(String serverId)? onRecovered;

  final ValueNotifier<WarpHealthState> state =
      ValueNotifier(const WarpHealthState());

  bool get isRunning => _timer != null;

  void start({
    required String serverId,
    required String endpoint,
    int intervalSec = defaultIntervalSec,
  }) {
    stop();
    _serverId = serverId;
    _endpoint = endpoint;
    _consecutiveFails = 0;
    _lastOk = true;
    state.value = WarpHealthState(
      running: true,
      endpoint: endpoint,
      lastCheckAt: DateTime.now(),
      ok: true,
      consecutiveFails: 0,
    );
    _timer = Timer.periodic(
      Duration(seconds: intervalSec),
      (_) => _check(),
    );
    Timer(const Duration(seconds: 2), _check);
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
    _endpoint = null;
    _serverId = null;
    _consecutiveFails = 0;
    state.value = const WarpHealthState();
  }

  Future<void> _check() async {
    final ep = _endpoint;
    final id = _serverId;
    if (ep == null || id == null) return;

    final parts = ep.split(':');
    if (parts.length < 2) return;
    final host = parts[0];
    final port = int.tryParse(parts[1]);
    if (port == null || port < 1 || port > 65535) return;

    final sw = Stopwatch()..start();
    var ok = false;
    Socket? sock;
    try {
      sock = await Socket.connect(
        host,
        port,
        timeout: const Duration(milliseconds: 2500),
      );
      ok = true;
    } catch (_) {
      ok = false;
    } finally {
      sw.stop();
      try { sock?.destroy(); } catch (_) {}
    }

    if (ok) {
      _consecutiveFails = 0;
      final wasDegraded = !_lastOk;
      _lastOk = true;
      state.value = WarpHealthState(
        running: true,
        endpoint: ep,
        lastCheckAt: DateTime.now(),
        lastLatencyMs: sw.elapsedMilliseconds,
        ok: true,
        consecutiveFails: 0,
      );
      if (wasDegraded) {
        onRecovered?.call(id);
        // ignore: unawaited_futures
        ConnectionLogService.logWarpScan(
          server: 'health-monitor',
          endpoint: ep,
          ms: sw.elapsedMilliseconds,
        );
      }
    } else {
      _consecutiveFails++;
      _lastOk = false;
      state.value = WarpHealthState(
        running: true,
        endpoint: ep,
        lastCheckAt: DateTime.now(),
        lastLatencyMs: sw.elapsedMilliseconds,
        ok: false,
        consecutiveFails: _consecutiveFails,
      );
      if (_consecutiveFails == consecutiveFailsToWarn) {
        onDegraded?.call(id);
        // ignore: unawaited_futures
        ConnectionLogService.logWarpScan(
          server: 'health-monitor',
          endpoint: ep,
          reason: 'degraded after $_consecutiveFails fails',
        );
      }
    }
  }

  /// چک سریع یه endpoint (بدون مانیتور).
  static Future<bool> quickCheck(String endpoint, {int timeoutMs = 2500}) async {
    final parts = endpoint.split(':');
    if (parts.length < 2) return false;
    final port = int.tryParse(parts[1]);
    if (port == null || port < 1 || port > 65535) return false;
    Socket? sock;
    try {
      sock = await Socket.connect(
        parts[0],
        port,
        timeout: Duration(milliseconds: timeoutMs),
      );
      return true;
    } catch (_) {
      return false;
    } finally {
      try { sock?.destroy(); } catch (_) {}
    }
  }
}

class WarpHealthState {
  final bool running;
  final String endpoint;
  final DateTime? lastCheckAt;
  final int? lastLatencyMs;
  final bool ok;
  final int consecutiveFails;

  const WarpHealthState({
    this.running = false,
    this.endpoint = '',
    this.lastCheckAt,
    this.lastLatencyMs,
    this.ok = true,
    this.consecutiveFails = 0,
  });

  bool get degraded => !ok && consecutiveFails >= 3;
}
