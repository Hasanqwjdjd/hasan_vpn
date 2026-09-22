import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class TestBudget {
  static const String storageKey = 'test_settings_v1';
  static const List<int> timeoutOptions = [2, 3, 5, 10, 15];
  static const List<int> directOptions = [1, 2, 4, 8, 16, 32];
  static const List<int> sampleOptions = [1, 2, 3, 5, 8];

  final int timeoutSec;
  final int direct;
  final int samples;
  final bool tcpFallback;

  const TestBudget({
    this.timeoutSec = 10,
    this.direct = 16,
    this.samples = 1,
    this.tcpFallback = true,
  });

  /// هم‌زمانی بالاتر = تست سریع‌تر؛ سقف ۸ برای حفظ دقت پینگ واقعی
  int get realConcurrency => direct.clamp(4, 8).toInt();
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
        timeoutSec: _pick(m['timeoutSec'], timeoutOptions, 10),
        direct: _pick(m['directConcurrency'], directOptions, 16),
        samples: _pick(m['samples'], sampleOptions, 1),
        tcpFallback: m['tcpFallback'] != false,
      );
    } catch (_) {
      return const TestBudget();
    }
  }
}
