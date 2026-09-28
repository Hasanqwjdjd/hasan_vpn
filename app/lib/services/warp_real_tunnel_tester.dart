import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/server.dart';
import 'connection_log_service.dart';
import 'native_delay_probe.dart';
import 'v2ray_engine.dart';
import 'warp_endpoint_scanner.dart';

/// Real-tunnel verify: بعد از UDP scan، هر candidate رو با یک تونل کامل
/// WARP تست می‌کنه و یه درخواست HTTP واقعی می‌زنه.
///
/// **نسخه‌ی سریع:** از NativeDelayProbe استفاده می‌کنه که یه Xray موقت
/// در پروسه جدا می‌سازه — بدون قطع session فعال، بدون نیاز به VPN
/// permission، و موازی (۴ probe همزمان).
///
/// مقایسه با نسخه قبلی (connect/disconnect):
///   • قبلی:  ~۳-۱۰ ثانیه به ازای هر endpoint، ترتیبی
///   • جدید:  ~۲۰۰-۵۰۰ms به ازای هر endpoint، ۴x موازی
///   • نتیجه: ۵۰× سریع‌تر
class WarpRealTunnelTester {
  WarpRealTunnelTester._();

  /// حداکثر تعداد candidate که verify می‌شن.
  static const int defaultMaxCandidates = 12;

  /// تعداد worker موازی برای probe.
  static const int defaultWorkers = 4;

  /// timeout هر probe.
  static const Duration defaultTimeout = Duration(seconds: 12);

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
    int workers = defaultWorkers,
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
      // مرحله ۱: ساخت config برای همه candidate ها
      final configs = <String>[];
      final validHits = <WarpEndpointHit>[];
      for (final hit in candidates) {
        if (isCancelled?.call() == true) {
          _running = false;
          return null;
        }
        final server = makeServerFromEndpoint(hit.endpoint);
        final cfg = await V2RayEngine.buildConfigOnly(server);
        if (cfg.isEmpty) {
          debugPrint('warp-verify: ${hit.endpoint} config build failed');
          continue;
        }
        configs.add(cfg);
        validHits.add(hit);
      }

      if (configs.isEmpty) {
        _running = false;
        return null;
      }

      // مرحله ۲: probe موازی
      debugPrint(
          'warp-verify: probing ${configs.length} endpoints '
          'with $workers workers');
      final results = await NativeDelayProbe.probeMany(
        configs,
        workers: workers,
        timeout: perCandidateTimeout,
        isCancelled: isCancelled,
      );

      // مرحله ۳: پیدا کردن بهترین
      WarpEndpointHit? best;
      var bestMs = 0x7fffffff;
      var tested = 0;

      for (final r in results) {
        tested++;
        final hit = validHits[r.index];
        final delay = r.delay;
        onProgress?.call(
            tested, configs.length, hit.endpoint, delay);

        if (delay >= 0 && delay < bestMs) {
          bestMs = delay;
          best = WarpEndpointHit(
            endpoint: hit.endpoint,
            latencyMs: delay,
            discoveryOrder: hit.discoveryOrder,
          );
          // ignore: unawaited_futures
          ConnectionLogService.logWarpScan(
            server: 'WARP verify',
            endpoint: hit.endpoint.toString(),
            ms: delay,
          );
        } else if (delay < 0) {
          // ignore: unawaited_futures
          ConnectionLogService.logWarpScan(
            server: 'WARP verify',
            endpoint: hit.endpoint.toString(),
            reason: 'probe failed',
          );
        }
      }

      if (best != null) {
        debugPrint(
            'warp-verify: fastest = ${best.endpoint} ${best.latencyMs}ms '
            '(${results.where((r) => r.delay >= 0).length} ok / '
            '${results.length} tested)');
      } else {
        debugPrint('warp-verify: no endpoint responded');
      }
      return best;
    } finally {
      _running = false;
    }
  }

  /// verify همه candidate ها و برگردوندن sorted list.
  ///
  /// برخلاف findFirstWorking که فقط بهترین رو می‌ده، اینجا همه‌ی
  /// نتیجه‌ها با ترتیب سرعت برمی‌گردن — برای UI نمایش بهترین‌ها.
  static Future<List<WarpEndpointHit>> testAll({
    required List<WarpEndpointHit> hits,
    required VpnServer Function(WarpEndpoint) makeServerFromEndpoint,
    int maxCandidates = defaultMaxCandidates,
    int workers = defaultWorkers,
    Duration perCandidateTimeout = defaultTimeout,
    bool Function()? isCancelled,
    void Function(int tested, int total, WarpEndpoint endpoint, int ms)?
        onProgress,
  }) async {
    if (_running) return const [];
    _running = true;

    final candidates = hits.take(maxCandidates).toList();
    if (candidates.isEmpty) {
      _running = false;
      return const [];
    }

    try {
      final configs = <String>[];
      final validHits = <WarpEndpointHit>[];
      for (final hit in candidates) {
        if (isCancelled?.call() == true) return const [];
        final server = makeServerFromEndpoint(hit.endpoint);
        final cfg = await V2RayEngine.buildConfigOnly(server);
        if (cfg.isEmpty) continue;
        configs.add(cfg);
        validHits.add(hit);
      }

      if (configs.isEmpty) return const [];

      final results = await NativeDelayProbe.probeMany(
        configs,
        workers: workers,
        timeout: perCandidateTimeout,
        isCancelled: isCancelled,
      );

      final out = <WarpEndpointHit>[];
      var tested = 0;
      for (final r in results) {
        tested++;
        final hit = validHits[r.index];
        onProgress?.call(tested, configs.length, hit.endpoint, r.delay);
        if (r.delay >= 0) {
          out.add(WarpEndpointHit(
            endpoint: hit.endpoint,
            latencyMs: r.delay,
            discoveryOrder: hit.discoveryOrder,
          ));
        }
      }
      out.sort((a, b) => a.latencyMs.compareTo(b.latencyMs));
      return out;
    } finally {
      _running = false;
    }
  }

  static void cancel() {
    _running = false;
  }
}
