import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/server.dart';
import 'v2ray_engine.dart';

/// یک candidate برای تست — متن args به فرمت ciadpi.
class DesyncCandidate {
  final String label;
  final String method; // Split / Disorder / Fake SNI / OOB / Disoob
  final String args;
  const DesyncCandidate({
    required this.label,
    required this.method,
    required this.args,
  });
}

class DesyncResult {
  final DesyncCandidate candidate;
  final int ms;
  final bool ok;
  final String? error;
  const DesyncResult({
    required this.candidate,
    required this.ms,
    required this.ok,
    this.error,
  });
}

/// اسکنر خودکار PingNG Desync — پورت Dart از `PingNgDesyncTuner.kt`.
///
/// هر candidate رو روی سرور فعلی با `dialerProxy` فعال تست می‌کنه و
/// سریع‌ترین/موفق‌ترین رو انتخاب می‌کنه. برنده‌ها برای سرور ذخیره می‌شن
/// تا اجرای بعدی سریع‌تر باشه.
class DesyncTuner {
  DesyncTuner._();

  static bool _running = false;
  static bool get isRunning => _running;

  // ── پارامترهای search space (نمونه‌گیری محدود از Tuner اصلی) ──
  static const List<int> _splitPositions = [1, 2, 3, 4, 5, 6, 8, 12, 16, 24];
  static const List<int> _disorderPositions = [1, 2, 3, 4, 5, 6, 8, 12];
  static const List<int> _recordPositions = [1, 2, 3, 4, 6, 8, 12];
  static const List<int> _fakeTtls = [5, 7, 8, 10, 12];
  static const List<int> _oobPositions = [1, 2, 4, 8];
  static const List<String> _fakeSnis = [
    'www.wikipedia.org',
    'www.microsoft.com',
    'www.cloudflare.com',
    'www.apple.com',
  ];

  /// Preset های کوتاه — همیشه امتحان می‌شن قبل از search.
  static List<DesyncCandidate> _priorityPresets() => const <DesyncCandidate>[
        DesyncCandidate(
          label: 'Light',
          method: 'Split',
          args: '--proto=tls --split 1+s --tlsrec 1+s --delay-range 0-1',
        ),
        DesyncCandidate(
          label: 'Balanced',
          method: 'Split',
          args:
              '--proto=tls --split-range 1-3+s --tlsrec 1-3+s --delay-range 1-3',
        ),
        DesyncCandidate(
          label: 'Severe',
          method: 'Fake SNI',
          args:
              '--proto=tls --split 1+s --tlsrec 1+s --disorder 3+s --fake -1 --ttl 8 --fake-jitter --delay-range 1-5',
        ),
      ];

  /// لیست candidate ها — basic + (اختیاری) advanced.
  static List<DesyncCandidate> generateCandidates({bool advanced = false}) {
    final out = <DesyncCandidate>[];
    final seen = <String>{};

    void add(DesyncCandidate c) {
      if (seen.add(c.args)) out.add(c);
    }

    // 1) preset های برنده اول
    for (final c in _priorityPresets()) {
      add(c);
    }

    // 2) Split: 10×7 = 70 نمونه کوچک
    for (final split in _splitPositions) {
      for (final record in _recordPositions) {
        add(DesyncCandidate(
          label: 'Split $split / tlsrec $record',
          method: 'Split',
          args:
              '--proto=tls --split $split+s --tlsrec $record+s --delay-range 1-5',
        ));
      }
    }

    // 3) Disorder: 8×7 = 56
    for (final disorder in _disorderPositions) {
      for (final record in _recordPositions) {
        add(DesyncCandidate(
          label: 'Disorder $disorder / tlsrec $record',
          method: 'Disorder',
          args:
              '--proto=tls --disorder $disorder+s --tlsrec $record+s --delay-range 1-5',
        ));
      }
    }

    // 4) Fake SNI: 4 SNIs × 3 TTLs = 12
    for (final sni in _fakeSnis.take(3)) {
      for (final ttl in _fakeTtls.take(3)) {
        add(DesyncCandidate(
          label: 'Fake $ttl / $sni',
          method: 'Fake SNI',
          args:
              '--proto=tls --fake -1 --ttl $ttl --tls-sni $sni --fake-jitter --delay-range 1-5',
        ));
      }
    }

    // 5) OOB: 4×2
    for (final pos in _oobPositions) {
      add(DesyncCandidate(
        label: 'OOB $pos',
        method: 'OOB',
        args:
            '--proto=tls --oob $pos+s --tlsrec 1,3+s --delay-range 1-5',
      ));
      add(DesyncCandidate(
        label: 'Disoob $pos',
        method: 'Disoob',
        args:
            '--proto=tls --disoob $pos+s --oob-ttl 1 --tlsrec 1,3+s --delay-range 1-5',
      ));
    }

    if (advanced) {
      // 6) Split-range
      for (final range in ['1-3', '1-5', '2-4', '3-6']) {
        add(DesyncCandidate(
          label: 'Split-range $range',
          method: 'Split',
          args:
              '--proto=tls --split-range $range+s --tlsrec 1+s --delay-range 1-5',
        ));
      }
      // 7) Adaptive auto-fallback
      add(const DesyncCandidate(
        label: 'Adaptive auto',
        method: 'Split',
        args:
            '--proto=tls --split-range 1-3+s --tlsrec 1-3+s --auto=torst,redirect,ssl_err --disorder 1 --fake -1 --ttl-range 7-10 --fake-jitter --cache-ttl 3600 --delay-range 1-5 --timeout 3',
      ));
      // 8) Fake with ttl-range
      for (final sni in _fakeSnis.take(2)) {
        add(DesyncCandidate(
          label: 'Fake range / $sni',
          method: 'Fake SNI',
          args:
              '--proto=tls --fake -1 --ttl-range 7-10 --tls-sni $sni --fake-jitter --delay-range 1-5',
        ));
      }
    }

    return out;
  }

  /// تست همه‌ی candidate ها روی سرور فعلی. مثل FinalMaskFinder.
  ///
  /// نکته: `V2RayEngine.connect` خودش desync رو راه می‌ندازه چون
  /// `server.pingNgProfile = 'Custom'` و `server.pingNgArgs = candidate.args`
  /// ست شده. پس نیازی به start جداگانه DesyncService نیست.
  static Future<DesyncResult?> findBest(
    VpnServer server, {
    void Function(int index, int total, DesyncCandidate c)? onProgress,
    void Function(DesyncResult r)? onResult,
    bool stopOnFirstWorking = false,
    bool Function()? advancedProvider,
    bool Function()? isCancelled,
  }) async {
    if (_running) return null;
    _running = true;

    final results = <DesyncResult>[];
    // basic همیشه اجرا می‌شه. advanced فقط اگه provider در طول اسکن true بشه.
    final basicCandidates = generateCandidates(advanced: false);
    final advancedOnly = <DesyncCandidate>[];
    {
      final seen = basicCandidates.map((c) => c.args).toSet();
      for (final c in generateCandidates(advanced: true)) {
        if (!seen.contains(c.args)) advancedOnly.add(c);
      }
    }
    final totalHint = basicCandidates.length + advancedOnly.length;

    try {
      for (var i = 0; i < totalHint; i++) {
        if (isCancelled?.call() == true) break;
        final bool isAdvancedPhase = i >= basicCandidates.length;
        // در فاز advanced، اگه کاربر تیک رو نزد، رد کن
        if (isAdvancedPhase && (advancedProvider?.call() != true)) {
          continue;
        }
        final c = isAdvancedPhase
            ? advancedOnly[i - basicCandidates.length]
            : basicCandidates[i];
        onProgress?.call(i + 1, totalHint, c);

        final testServer = server.copyWith(
          pingNgProfile: 'Custom',
          pingNgArgs: c.args,
        );

        try {
          await V2RayEngine.disconnect();
          await Future<void>.delayed(const Duration(milliseconds: 350));

          if (isCancelled?.call() == true) break;

          final ok = await V2RayEngine.connect(testServer);
          if (!ok) {
            final r = DesyncResult(
              candidate: c,
              ms: 999999,
              ok: false,
              error: V2RayEngine.lastError ?? 'connect failed',
            );
            results.add(r);
            onResult?.call(r);
            continue;
          }

          final ms = await V2RayEngine.connectedDelay(
            timeout: const Duration(seconds: 6),
          );
          final r = DesyncResult(
            candidate: c,
            ms: ms > 0 ? ms : 999999,
            ok: ms > 0,
            error: ms > 0 ? null : 'no response',
          );
          results.add(r);
          onResult?.call(r);

          if (stopOnFirstWorking && r.ok) break;
        } catch (e) {
          final r = DesyncResult(
            candidate: c,
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
          await Future<void>.delayed(const Duration(milliseconds: 250));
        }
      }

      final working = results.where((r) => r.ok).toList()
        ..sort((a, b) => a.ms.compareTo(b.ms));
      if (working.isEmpty) return null;
      debugPrint('DesyncTuner: ${results.length} tested, ${working.length} ok, '
          'best=${working.first.candidate.label} ${working.first.ms}ms');
      return working.first;
    } finally {
      _running = false;
    }
  }

  static void cancel() {
    _running = false;
  }
}
