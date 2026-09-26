import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'xray_settings.dart';

/// حالت تست پینگ:
///   turbo    → فقط TCP connect (بدون Xray). برای ۱۰۰۰+ سرور در چند ثانیه.
///   balanced → TCP برای همه + real HTTP فقط برای چند سرور برتر (پیش‌فرض).
///   accurate → TCP + real HTTP برای همه‌ی سرورهای آنلاین (کندترین، دقیق‌ترین).
enum TestMode { turbo, balanced, accurate }

/// بودجه پینگ — هم‌راستا با MarbleNG PingBudget (Models.kt):
/// timeout default 5s, samples default 3, concurrency default 16 (1..64),
/// TCP gate 1s, SAMPLE_SPACING_MS=60. turbo/balanced/accurate hasan-specific modes kept.
class TestBudget {
  static const String storageKey = 'test_settings_v1';
  /// MarbleNG TIMEOUT_CHOICES plus a few extras for hasan UI compatibility.
  static const List<int> timeoutOptions = [2, 3, 5, 8, 10, 15];
  static const List<int> directOptions = [1, 2, 4, 8, 16, 32, 64];
  /// MarbleNG SAMPLE_CHOICES subset that fits mobile UX (full set is 1..10).
  static const List<int> sampleOptions = [1, 2, 3, 5];

  final int timeoutSec;
  final int direct;
  final int samples;
  final bool tcpFallback;
  final bool tcpPrecheck;

  final TestMode mode;

  const TestBudget({
    this.timeoutSec = 5,
    this.direct = 32,
    this.samples = 3,
    this.tcpFallback = true,
    this.tcpPrecheck = true,
    this.mode = TestMode.accurate,
  });

  /// Concurrency برای تست‌های real HTTP.
  /// - turbo: 0 (اصلاً اجرا نمی‌شود)
  /// - balanced: 8 (فقط برای سرورهای برتر)
  /// - accurate: مقدار direct کاربر
  int get realConcurrency {
    switch (mode) {
      case TestMode.turbo:
        return 0;
      case TestMode.balanced:
        return direct.clamp(1, 12).toInt();
      case TestMode.accurate:
        return direct.clamp(1, 64).toInt();
    }
  }

  /// حداکثر تعداد سرورهایی که در حالت balanced تست real می‌شوند.
  int get realTestLimit {
    switch (mode) {
      case TestMode.turbo:
        return 0;
      case TestMode.balanced:
        return 40;
      case TestMode.accurate:
        return 100000;
    }
  }

  bool get isTurbo => mode == TestMode.turbo;

  /// TCP pre-check pool (can be higher; cheap)
  int get tcpConcurrency => (realConcurrency * 2).clamp(2, 128).toInt();

  /// Aether native process — keep low
  int get aetherConcurrency => 2;

  int get worstCaseSec => timeoutSec * samples;

  static int _pick(dynamic raw, List<int> options, int fallback) {
    final v = raw is num ? raw.toInt() : int.tryParse('$raw');
    if (v != null && options.contains(v)) return v;
    return fallback;
  }

  static Future<TestBudget> load() async {
    try {
      // اول xray_settings.concurrentDelayTests را چک کن (PattNG-style)
      try {
        final xs = await XraySettings.load();
        final c = (xs['concurrentDelayTests'] as num?)?.toInt();
        if (c != null && c >= 1 && c <= 64) {
          final prefs0 = await SharedPreferences.getInstance();
          final raw0 = prefs0.getString(storageKey);
          if (raw0 == null) {
            return TestBudget(direct: c);
          }
        }
      } catch (_) {}

      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(storageKey);
      if (raw == null) return const TestBudget();
      final m = jsonDecode(raw);
      if (m is! Map) return const TestBudget();
      final modeStr = (m['mode'] ?? 'balanced').toString();
      final mode = TestMode.values.firstWhere(
        (e) => e.name == modeStr,
        orElse: () => TestMode.balanced,
      );
      return TestBudget(
        timeoutSec: _pick(m['timeoutSec'], timeoutOptions, 5),
        direct: _pick(m['directConcurrency'], directOptions, 16),
        samples: _pick(m['samples'], sampleOptions, 3),
        tcpFallback: m['tcpFallback'] != false,
        tcpPrecheck: m['tcpPrecheck'] != false,
        mode: mode,
      );
    } catch (_) {
      return const TestBudget();
    }
  }
}
