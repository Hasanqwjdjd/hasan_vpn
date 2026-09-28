import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'connection_log_service.dart';
import 'warp_endpoint_scanner.dart';

/// Health monitor برای endpoint انتخاب‌شده WARP/WARP+/MASQUE.
///
/// برای WARP/WARP+ از UDP handshake واقعی (کلید لازم) و برای MASQUE
/// از TCP استفاده می‌کنه. هر intervalSec یه بار چک می‌کنه.
class WarpEndpointHealthMonitor {
  WarpEndpointHealthMonitor._();
  static final WarpEndpointHealthMonitor instance =
      WarpEndpointHealthMonitor._();

  static const int defaultIntervalSec = 45;
  static const int consecutiveFailsToWarn = 3;
  static const String _prefKeyPrefix = 'warp_health_endpoint_v1_';

  Timer? _timer;
  String? _endpoint;
  String? _serverId;
  String? _privateKeyB64;
  String? _peerPublicKeyB64;
  int _consecutiveFails = 0;
  bool _lastOk = true;
  bool _checking = false;

  void Function(String serverId)? onDegraded;
  void Function(String serverId)? onRecovered;

  final ValueNotifier<WarpHealthState> state =
      ValueNotifier(const WarpHealthState());

  bool get isRunning => _timer != null;

  void start({
    required String serverId,
    required String endpoint,
    String? privateKeyB64,
    String? peerPublicKeyB64,
    int intervalSec = defaultIntervalSec,
  }) {
    stop();
    _serverId = serverId;
    _endpoint = endpoint;
    _privateKeyB64 = privateKeyB64;
    _peerPublicKeyB64 = peerPublicKeyB64;
    _consecutiveFails = 0;
    _lastOk = true;
    state.value = WarpHealthState(
      running: true,
      endpoint: endpoint,
      lastCheckAt: DateTime.now(),
      ok: true,
      consecutiveFails: 0,
    );
    // ignore: unawaited_futures
    _persist(serverId, endpoint);
    _timer = Timer.periodic(
      Duration(seconds: intervalSec),
      (_) => _check(),
    );
    Timer(const Duration(seconds: 3), _check);
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
    _endpoint = null;
    _serverId = null;
    _privateKeyB64 = null;
    _peerPublicKeyB64 = null;
    _consecutiveFails = 0;
    state.value = const WarpHealthState();
  }

  Future<void> _check() async {
    if (_checking) return;
    final ep = _endpoint;
    final id = _serverId;
    if (ep == null || id == null) return;

    _checking = true;
    final sw = Stopwatch()..start();
    var ok = false;

    try {
      if (_privateKeyB64 != null && _peerPublicKeyB64 != null) {
        ok = await _udpHandshakeProbe(
          ep,
          _privateKeyB64!,
          _peerPublicKeyB64!,
        );
      } else {
        ok = await _tcpProbe(ep);
      }
    } catch (_) {
      ok = false;
    } finally {
      sw.stop();
      _checking = false;
    }

    _applyResult(id, ep, ok, sw.elapsedMilliseconds);
  }

  void _applyResult(String id, String ep, bool ok, int latencyMs) {
    if (ok) {
      final wasDegraded = !_lastOk;
      _consecutiveFails = 0;
      _lastOk = true;
      state.value = WarpHealthState(
        running: true,
        endpoint: ep,
        lastCheckAt: DateTime.now(),
        lastLatencyMs: latencyMs,
        ok: true,
        consecutiveFails: 0,
      );
      if (wasDegraded) {
        onRecovered?.call(id);
        // ignore: unawaited_futures
        ConnectionLogService.logWarpScan(
          server: 'health-monitor',
          endpoint: ep,
          ms: latencyMs,
        );
      }
    } else {
      _consecutiveFails++;
      _lastOk = false;
      state.value = WarpHealthState(
        running: true,
        endpoint: ep,
        lastCheckAt: DateTime.now(),
        lastLatencyMs: latencyMs,
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

  static Future<bool> _udpHandshakeProbe(
    String endpoint,
    String privateKeyB64,
    String peerPublicKeyB64,
  ) async {
    final parts = endpoint.split(':');
    if (parts.length < 2) return false;
    final port = int.tryParse(parts[1]);
    if (port == null || port < 1 || port > 65535) return false;

    try {
      final ep = WarpEndpoint(parts[0], port);
      final priv = _tryDecodeB64(privateKeyB64);
      final peer = _tryDecodeB64(peerPublicKeyB64);
      if (priv == null || peer == null) return false;
      final hits = await WarpEndpointScanner.scan(
        endpoints: [ep],
        privateKey: priv,
        peerPublicKey: peer,
        ratePerSecond: 0,
        workers: 1,
        timeoutMs: 1500,
        maxHits: 1,
        acceptCookieReplies: true,
      );
      return hits.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> _tcpProbe(String endpoint) async {
    final parts = endpoint.split(':');
    if (parts.length < 2) return false;
    final port = int.tryParse(parts[1]);
    if (port == null || port < 1 || port > 65535) return false;
    Socket? sock;
    try {
      sock = await Socket.connect(
        parts[0],
        port,
        timeout: const Duration(milliseconds: 2500),
      );
      return true;
    } catch (_) {
      return false;
    } finally {
      try { sock?.destroy(); } catch (_) {}
    }
  }

  static Future<void> _persist(String serverId, String endpoint) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('$_prefKeyPrefix$serverId', endpoint);
    } catch (_) {}
  }

  static Future<String?> restored(String serverId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString('$_prefKeyPrefix$serverId');
    } catch (_) {
      return null;
    }
  }

  /// چک سریع یه endpoint (بدون مانیتور) — TCP probe.
  static Future<bool> quickCheck(
    String endpoint, {
    int timeoutMs = 2500,
  }) async {
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

  static Uint8List? _tryDecodeB64(String value) {
    try {
      final normalized = value.replaceAll('-', '+').replaceAll('_', '/');
      final padded = normalized.padRight((normalized.length + 3) & ~3, '=');
      final out = base64.decode(padded);
      return out.length == 32 ? out : null;
    } catch (_) {
      return null;
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

  String get shortStatus {
    if (!running) return 'off';
    if (ok) return lastLatencyMs != null ? '${lastLatencyMs}ms' : 'ok';
    return 'fails: $consecutiveFails';
  }
}
