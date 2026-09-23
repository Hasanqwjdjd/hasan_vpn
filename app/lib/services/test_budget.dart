import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// بودجه پینگ — مقادیر پیش‌فرض نزدیک به PattNG:
/// concurrent real-ping = 16 (1..64), TCP pre-check 1s, real budget ~12s.
class TestBudget {
  static const String storageKey = 'test_settings_v1';
  static const List<int> timeoutOptions = [5, 8, 10, 12, 15];
  static const List<int> directOptions = [1, 2, 4, 8, 16, 32, 64];
  static const List<int> sampleOptions = [1, 2, 3];

  final int timeoutSec;
  final int direct;
  final int samples;
  final bool tcpFallback;
  final bool tcpPrecheck;

  const TestBudget({
    this.timeoutSec = 12,
    this.direct = 16,
    this.samples = 1,
    this.tcpFallback = true,
    this.tcpPrecheck = true,
  });

  /// PattNG getRealPingConcurrency: default 16, clamp 1..64
  int get realConcurrency => direct.clamp(1, 64).toInt();

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
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(storageKey);
      if (raw == null) return const TestBudget();
      final m = jsonDecode(raw);
      if (m is! Map) return const TestBudget();
      return TestBudget(
        timeoutSec: _pick(m['timeoutSec'], timeoutOptions, 12),
        direct: _pick(m['directConcurrency'], directOptions, 16),
        samples: _pick(m['samples'], sampleOptions, 1),
        tcpFallback: m['tcpFallback'] != false,
        tcpPrecheck: m['tcpPrecheck'] != false,
      );
    } catch (_) {
      return const TestBudget();
    }
  }
}
