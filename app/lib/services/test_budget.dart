import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// بخش ۲.۲ — تنظیمات «تست و رتبه‌بندی» (بازگشت صفحه به برنامه).
///
/// حالت تست:
///   turbo    → فقط TCP connect (بدون تست واقعی). برای ۱۰۰۰+ سرور در چند ثانیه.
///   balanced → TCP برای همه + تست واقعی فقط برای ۲۴ پاسخ‌دهنده‌ی برتر.
///   accurate → TCP برای همه + تست واقعی برای همه‌ی پاسخ‌دهنده‌ها (پیش‌فرض).
///
/// مقادیر پیش‌فرض = مقادیر هاردکد قبلی (بخش ۷ نسخه قبل):
///   TCP: تایم‌اوت ۱۵۰۰ms، هم‌زمانی ۶۴
///   Real: تایم‌اوت ۴s، هم‌زمانی ۸، ۳ نمونه، آدرس gstatic generate_204
enum TestMode { turbo, balanced, accurate }

class TestBudget {
  static const String storageKey = 'test_settings_v2';

  /// گزینه‌های UI — همان بازه‌های MarbleNG/PingNG.
  static const List<int> tcpTimeoutOptions = <int>[1000, 1500, 2000, 3000];
  static const List<int> tcpConcurrencyOptions = <int>[16, 32, 64, 96];
  static const List<int> realTimeoutOptions = <int>[2, 3, 4, 5, 8, 10];
  static const List<int> realConcurrencyOptions = <int>[1, 2, 4, 8, 16, 32];
  static const List<int> sampleOptions = <int>[1, 2, 3, 5];

  /// هم‌زمانی TCP در واقعیت بیشتر از این بی‌معناست (limit امنیتی).
  static const int tcpConcurrencyMax = 96;

  /// حالت balanced — حداکثر سرورهایی که تست واقعی می‌گیرند.
  static const int balancedRealLimit = 24;

  final TestMode mode;
  final int tcpTimeoutMs;
  final int tcpConcurrency;
  final int realTimeoutSec;
  final int realConcurrency;
  final int realSamples;
  final String delayUrl;

  const TestBudget({
    this.mode = TestMode.accurate,
    this.tcpTimeoutMs = 1500,
    this.tcpConcurrency = 64,
    this.realTimeoutSec = 4,
    this.realConcurrency = 8,
    this.realSamples = 3,
    this.delayUrl = 'https://www.gstatic.com/generate_204',
  });

  static TestBudget _defaults = const TestBudget();
  static TestBudget? _cached;

  /// مقادیر پیش‌فرض (برای نمایش در UI).
  static TestBudget get defaults => _defaults;

  static int _clamp(dynamic v, int min, int max, int fallback) {
    final n = v is int ? v : int.tryParse(v?.toString() ?? '');
    if (n == null) return fallback;
    return n.clamp(min, max);
  }

  static Future<TestBudget> load() async {
    if (_cached != null) return _cached!;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(storageKey);
      if (raw == null || raw.isEmpty) {
        _cached = _defaults;
        return _cached!;
      }
      final m = jsonDecode(raw);
      if (m is! Map) {
        _cached = _defaults;
        return _cached!;
      }
      final modeName = m['mode']?.toString() ?? 'accurate';
      final mode = TestMode.values.firstWhere(
        (e) => e.name == modeName,
        orElse: () => TestMode.accurate,
      );
      _cached = TestBudget(
        mode: mode,
        tcpTimeoutMs: _clamp(m['tcpTimeoutMs'], 500, 10000,
            _defaults.tcpTimeoutMs),
        tcpConcurrency: _clamp(m['tcpConcurrency'], 1, tcpConcurrencyMax,
            _defaults.tcpConcurrency),
        realTimeoutSec: _clamp(m['realTimeoutSec'], 1, 30,
            _defaults.realTimeoutSec),
        realConcurrency: _clamp(m['realConcurrency'], 1, 64,
            _defaults.realConcurrency),
        realSamples: _clamp(m['realSamples'], 1, 10, _defaults.realSamples),
        delayUrl: (m['delayUrl']?.toString() ?? '').trim().isEmpty
            ? _defaults.delayUrl
            : m['delayUrl'].toString().trim(),
      );
      return _cached!;
    } catch (e) {
      debugPrint('[TestBudget] load failed: $e');
      _cached = _defaults;
      return _cached!;
    }
  }

  static Future<void> save(TestBudget b) async {
    _cached = b;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        storageKey,
        jsonEncode(<String, dynamic>{
          'mode': b.mode.name,
          'tcpTimeoutMs': b.tcpTimeoutMs,
          'tcpConcurrency': b.tcpConcurrency,
          'realTimeoutSec': b.realTimeoutSec,
          'realConcurrency': b.realConcurrency,
          'realSamples': b.realSamples,
          'delayUrl': b.delayUrl,
        }),
      );
      debugPrint('[TestBudget] saved: mode=${b.mode.name} '
          'tcp=${b.tcpTimeoutMs}ms/${b.tcpConcurrency} '
          'real=${b.realTimeoutSec}s/${b.realConcurrency}x${b.realSamples} '
          'url=${b.delayUrl}');
    } catch (e) {
      debugPrint('[TestBudget] save failed: $e');
    }
  }

  /// هم‌زمانی فاز Real:
  ///   turbo    → 0 (اجرا نمی‌شود)
  ///   balanced → همان realConcurrency (سقف ۱۲ برای جلوگیری از فشار)
  ///   accurate → همان realConcurrency
  int get effectiveRealConcurrency {
    switch (mode) {
      case TestMode.turbo:
        return 0;
      case TestMode.balanced:
        return realConcurrency.clamp(1, 12);
      case TestMode.accurate:
        return realConcurrency;
    }
  }
}
