import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

  /// Presets که با مشخصات سرور فعلی سازگارتر هستند و اول امتحان می‌شن.
  ///
  /// - اگه SNI/Host دومین کوتاه باشه → fragment کوچک‌تر با priority
  /// - اگه سرور CDN باشه (cloudflare/amazon/...) → tlshello aggressive
  /// - preset هایی که قبلاً روی همین سرور برنده شدن → اول لیست
  static Future<List<FinalMaskPreset>> dynamicPresetsFor(VpnServer server) async {
    final dynamic = <FinalMaskPreset>[];
    final sni = (server.sniOrHost ?? '').toLowerCase();
    final host = server.host.toLowerCase();
    final target = sni.isNotEmpty ? sni : host;
    final isCdn = host.contains('cloudflare') ||
        host.contains('amazonaws') ||
        host.contains('fastly') ||
        host.contains('akamai') ||
        host.contains('cdn') ||
        host.endsWith('.workers.dev') ||
        host.endsWith('.pages.dev');

    // CDN: بسته‌های TLS بزرگ → split در موقعیت کوچک
    if (isCdn) {
      dynamic.add(const FinalMaskPreset(
        label: 'CDN adaptive: tlshello / 1-20 / 0-1',
        finalMask:
            '{"tcp":[{"type":"fragment","settings":{"packets":"tlshello","lengths":["1","20"],"delays":["0","1"],"maxSplit":"0"}}]}',
      ));
      dynamic.add(const FinalMaskPreset(
        label: 'CDN adaptive: 1-3 / 100-300 / 1-2',
        finalMask:
            '{"tcp":[{"type":"fragment","settings":{"packets":"1-3","lengths":["100","300"],"delays":["1","2"],"maxSplit":"0"}}]}',
      ));
    }

    // دامنه‌های کوتاه یا تک‌برچسبی → split دقیق‌تر در بایت اول SNI
    if (target.isNotEmpty && target.split('.').length <= 2) {
      dynamic.add(const FinalMaskPreset(
        label: 'short-SNI: tlshello / 0-40 / 0',
        finalMask:
            '{"tcp":[{"type":"fragment","settings":{"packets":"tlshello","lengths":["0","40"],"delays":["0"],"maxSplit":"0"}}]}',
      ));
    }

    // سرور ایران یا دامنه‌های خاص → fragment شدید
    final iran = host.endsWith('.ir') || target.endsWith('.ir');
    if (iran) {
      dynamic.add(const FinalMaskPreset(
        label: 'IR-adaptive: tlshello / 0-104-1 / 0 + 1-1 / 114',
        finalMask:
            '{"tcp":[{"type":"fragment","settings":{"packets":"tlshello","lengths":["0","104","1"],"delays":["0"],"maxSplit":"0"}},{"type":"fragment","settings":{"packets":"1-1","lengths":["114","1"],"delays":["1"],"maxSplit":"11"}}]}',
      ));
      dynamic.add(const FinalMaskPreset(
        label: 'IR-adaptive: 1-1 / 200-400 / 5',
        finalMask:
            '{"tcp":[{"type":"fragment","settings":{"packets":"1-1","lengths":["200","400"],"delays":["5"],"maxSplit":"0"}}]}',
      ));
    }

    // preset هایی که قبلاً روی همین سرور برنده شدن → با اولویت
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getStringList('final_mask_winners_${server.id}');
      if (saved != null && saved.isNotEmpty) {
        for (final raw in saved.take(3)) {
          if (raw.isEmpty) continue;
          dynamic.insert(
            0,
            FinalMaskPreset(label: 'remembered (server)', finalMask: raw),
          );
        }
      }
    } catch (_) {}

    return dynamic;
  }

  /// بعد از انتخاب بهترین preset، اون رو برای این سرور یادداشت می‌کنه
  /// تا در اجراهای بعدی اول امتحان بشه.
  static Future<void> rememberWinner(
      VpnServer server, FinalMaskPreset preset) async {
    if (preset.finalMask.isEmpty) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = 'final_mask_winners_${server.id}';
      final list = prefs.getStringList(key) ?? <String>[];
      list.remove(preset.finalMask);
      list.insert(0, preset.finalMask);
      // فقط ۵ تا رو نگه دار
      if (list.length > 5) list.removeRange(5, list.length);
      await prefs.setStringList(key, list);
    } catch (_) {}
  }

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

    // Presets سفارشی این سرور (CDN/IR/short-SNI + remembered) + لیست ثابت
    List<FinalMaskPreset> effective = presets;
    try {
      final dyn = await dynamicPresetsFor(server);
      final seen = <String>{};
      final merged = <FinalMaskPreset>[];
      for (final p in [...dyn, ...presets]) {
        if (seen.add(p.finalMask)) merged.add(p);
      }
      if (merged.isNotEmpty) effective = merged;
    } catch (_) {}

    try {
      for (var i = 0; i < effective.length; i++) {
        final preset = effective[i];
        onProgress?.call(i + 1, effective.length, preset);

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
      final best = working.first;
      // یادداشت برنده برای اجرای بعدی
      // ignore: unawaited_futures
      rememberWinner(server, best.preset);
      return best;
    } finally {
      _running = false;
    }
  }

  static void cancel() {
    _running = false;
  }
}
