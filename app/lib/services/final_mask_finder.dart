import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/server.dart';
import 'v2ray_engine.dart';

/// Preset FinalMask/fragment profiles برای تست.
class FinalMaskPreset {
  final String label;
  final String finalMask;
  const FinalMaskPreset({required this.label, required this.finalMask});
}

class FinalMaskResult {
  final FinalMaskPreset preset;
  final int ms;
  final bool ok;
  final String? error;
  const FinalMaskResult({
    required this.preset,
    required this.ms,
    required this.ok,
    this.error,
  });
}

/// اسکن FinalMask — چند preset رو با یه سرور امتحان می‌کنه و
/// سریع‌ترین رو انتخاب می‌کنه. هر تست شامل: start Xray → probe → stop.
class FinalMaskFinder {
  FinalMaskFinder._();

  /// Preset ها بر اساس الگوهای رایج PingNG/PattNG برای کلاودفلر.
  static const List<FinalMaskPreset> presets = [
    FinalMaskPreset(
      label: 'None (baseline)',
      finalMask: '',
    ),
    FinalMaskPreset(
      label: 'tlshello / 100-200 / 10-20',
      finalMask:
          '{"tcp":[{"type":"fragment","settings":{"packets":"tlshello","lengths":["100","200"],"delays":["10","20"],"maxSplit":"0"}}]}',
    ),
    FinalMaskPreset(
      label: 'tlshello / 0-104-1 / 0',
      finalMask:
          '{"tcp":[{"type":"fragment","settings":{"packets":"tlshello","lengths":["0","104","1"],"delays":["0"],"maxSplit":"0"}},{"type":"fragment","settings":{"packets":"1-1","lengths":["114","1"],"delays":["1"],"maxSplit":"11"}}]}',
    ),
    FinalMaskPreset(
      label: '1-1 / 5-94 / 0 / split 355',
      finalMask:
          '{"tcp":[{"type":"fragment","settings":{"packets":"1-1","lengths":["5","94","1"],"delays":["0"],"maxSplit":"355"}}]}',
    ),
    FinalMaskPreset(
      label: 'tlshello / 20-40 / 5-10',
      finalMask:
          '{"tcp":[{"type":"fragment","settings":{"packets":"tlshello","lengths":["20","40"],"delays":["5","10"],"maxSplit":"0"}}]}',
    ),
    FinalMaskPreset(
      label: '1-3 / 1-2 (aggressive)',
      finalMask:
          '{"tcp":[{"type":"fragment","settings":{"packets":"1-3","lengths":["1","2"],"delays":["1","2"],"maxSplit":"0"}}]}',
    ),
    FinalMaskPreset(
      label: 'tlshello / 50-100 / 1-2',
      finalMask:
          '{"tcp":[{"type":"fragment","settings":{"packets":"tlshello","lengths":["50","100"],"delays":["1","2"],"maxSplit":"0"}}]}',
    ),
    FinalMaskPreset(
      label: 'tlshello / 5-10 / 5-10 (conservative)',
      finalMask:
          '{"tcp":[{"type":"fragment","settings":{"packets":"tlshello","lengths":["5","10"],"delays":["5","10"],"maxSplit":"0"}}]}',
    ),
  ];

  static bool _running = false;
  static bool get isRunning => _running;

  /// تست همه‌ی preset ها روی یه سرور.
  /// callbacks:
  ///   onProgress(index, total, preset)
  ///   onResult(FinalMaskResult)
  static Future<FinalMaskResult?> findBest(
    VpnServer server, {
    void Function(int index, int total, FinalMaskPreset preset)? onProgress,
    void Function(FinalMaskResult result)? onResult,
    bool stopOnFirstWorking = false,
  }) async {
    if (_running) return null;
    _running = true;

    final results = <FinalMaskResult>[];

    try {
      for (var i = 0; i < presets.length; i++) {
        final preset = presets[i];
        onProgress?.call(i + 1, presets.length, preset);

        final testServer = server.copyWith(
          tls: server.tls.copyWith(finalMask: preset.finalMask.isEmpty
              ? null
              : preset.finalMask),
        );

        try {
          await V2RayEngine.disconnect();
          await Future.delayed(const Duration(milliseconds: 400));

          final ok = await V2RayEngine.connect(testServer);
          if (!ok) {
            final r = FinalMaskResult(
              preset: preset,
              ms: 999999,
              ok: false,
              error: V2RayEngine.lastError ?? 'connect failed',
            );
            results.add(r);
            onResult?.call(r);
            continue;
          }

          // probe delay
          final sw = Stopwatch()..start();
          final ms = await V2RayEngine.connectedDelay(
            timeout: const Duration(seconds: 6),
          );
          sw.stop();

          final r = FinalMaskResult(
            preset: preset,
            ms: ms > 0 ? ms : 999999,
            ok: ms > 0,
            error: ms > 0 ? null : 'no response',
          );
          results.add(r);
          onResult?.call(r);

          if (stopOnFirstWorking && r.ok) break;
        } catch (e) {
          final r = FinalMaskResult(
            preset: preset,
            ms: 999999,
            ok: false,
            error: e.toString(),
          );
          results.add(r);
          onResult?.call(r);
        } finally {
          try {
            await V2RayEngine.disconnect();
          } catch (_) {}
          await Future.delayed(const Duration(milliseconds: 300));
        }
      }

      // انتخاب سریع‌ترین با ok=true
      final working =
          results.where((r) => r.ok).toList()..sort((a, b) => a.ms.compareTo(b.ms));
      if (working.isEmpty) return null;
      return working.first;
    } finally {
      _running = false;
    }
  }

  static void cancel() {
    _running = false;
  }
}
