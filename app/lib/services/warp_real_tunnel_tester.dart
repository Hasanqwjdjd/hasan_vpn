import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../models/server.dart';
import 'v2ray_engine.dart';
import 'warp_endpoint_scanner.dart';

/// Real-tunnel verify: بعد از UDP scan، هر candidate رو با یک تونل کامل
/// WARP تست می‌کنه و یه درخواست HTTP واقعی می‌زنه.
///
/// چرا لازمه: UDP handshake نشون می‌ده endpoint مسیر باز داره، ولی تضمین
/// نمی‌کنه data-plane کار کنه. بعضی endpoint ها handshake رو قبول می‌کنن
/// ولی packet رو drop می‌کنن. این تست اون‌ها رو حذف می‌کنه.
///
/// الگو: مثل FinalMaskFinder و DesyncTuner — VpnServer موقت می‌سازیم،
/// V2RayEngine.connect می‌کنیم، delay می‌گیریم، disconnect می‌کنیم.
class WarpRealTunnelTester {
  WarpRealTunnelTester._();

  /// حداکثر تعداد candidate که verify می‌شن.
  static const int defaultMaxCandidates = 12;

  /// timeout هر تست کامل (connect + delay).
  static const Duration defaultTimeout = Duration(seconds: 10);

  static bool _running = false;
  static bool get isRunning => _running;

  /// ورودی: لیست endpoint های hit شده از UDP scan (مرتب‌شده).
  /// خروجی: سریع‌ترین endpoint که واقعاً تونل می‌ده.
  ///
  /// [makeServerFromEndpoint] مسئول ساخت VpnServer واقعی از یه
  /// endpoint + finalMask هست (WARP یا WARP Plus chain).
  static Future<WarpEndpointHit?> findFirstWorking({
    required List<WarpEndpointHit> hits,
    required VpnServer Function(WarpEndpoint) makeServerFromEndpoint,
    int maxCandidates = defaultMaxCandidates,
    Duration perCandidateTimeout = defaultTimeout,
    bool Function()? isCancelled,
    void Function(int tested, int total, WarpEndpoint endpoint, int ms)?
        onProgress,
  }) async {
    if (_running) return null;
    _running = true;

    final candidates = hits.take(maxCandidates).toList();
    if (candidates.isEmpty) {
      _running = false;
      return null;
    }

    try {
      for (var i = 0; i < candidates.length; i++) {
        if (isCancelled?.call() == true) return null;
        final hit = candidates[i];

        final testServer = makeServerFromEndpoint(hit.endpoint);
        final sw = Stopwatch()..start();

        try {
          await V2RayEngine.disconnect();
          await Future<void>.delayed(const Duration(milliseconds: 250));

          if (isCancelled?.call() == true) return null;

          final ok = await V2RayEngine
              .connect(testServer)
              .timeout(perCandidateTimeout,
                  onTimeout: () => false);

          if (!ok) {
            debugPrint('warp-verify: ${hit.endpoint} connect failed: '
                '${V2RayEngine.lastError}');
            onProgress?.call(i + 1, candidates.length, hit.endpoint, -1);
            continue;
          }

          // real HTTP probe از داخل تونل
          final ms = await V2RayEngine
              .connectedDelay(timeout: const Duration(seconds: 6))
              .timeout(const Duration(seconds: 8), onTimeout: () => -1);

          sw.stop();
          if (ms > 0) {
            debugPrint('warp-verify: ${hit.endpoint} WORKS in $ms ms');
            onProgress?.call(i + 1, candidates.length, hit.endpoint, ms);
            return WarpEndpointHit(
              endpoint: hit.endpoint,
              latencyMs: ms,
              discoveryOrder: hit.discoveryOrder,
            );
          }

          debugPrint('warp-verify: ${hit.endpoint} no data-plane response');
          onProgress?.call(i + 1, candidates.length, hit.endpoint, -1);
        } catch (e) {
          debugPrint('warp-verify: ${hit.endpoint} exception: $e');
          onProgress?.call(i + 1, candidates.length, hit.endpoint, -1);
        } finally {
          try {
            await V2RayEngine.disconnect();
          } catch (_) {}
          await Future<void>.delayed(const Duration(milliseconds: 200));
        }
      }
      return null;
    } finally {
      _running = false;
    }
  }

  static void cancel() {
    _running = false;
  }
}
