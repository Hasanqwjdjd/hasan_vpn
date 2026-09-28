import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// تست delay سریع با Xray موقت از پلاگین flutter_vless.
///
/// از یه پروسه‌ی جداگانه Xray استفاده می‌کنه که با config داده‌شده بالا
/// میاد، HTTP probe می‌کنه، و پاک می‌شه — بدون دست زدن به Xray اصلی،
/// بدون نیاز به VPN permission.
///
/// مزیت: هر probe ~200-500ms طول می‌کشه (نه 2-5 ثانیه connect+disconnect).
class NativeDelayProbe {
  NativeDelayProbe._();

  static const MethodChannel _ch = MethodChannel('flutter_vless');

  /// URL پیش‌فرض — light-weight و معمولاً در دسترس.
  static const String defaultUrl =
      'http://cp.cloudflare.com/generate_204';

  /// Fallback URLs — اگه اولی fail شد.
  static const List<String> fallbackUrls = <String>[
    'http://connectivitycheck.gstatic.com/generate_204',
    'http://www.gstatic.com/generate_204',
  ];

  /// یک probe با config داده‌شده.
  ///
  /// برمی‌گردونه: delay به میلی‌ثانیه (>=0) یا -1 در صورت fail.
  static Future<int> probe(
    String configJson, {
    String? url,
    Duration timeout = const Duration(seconds: 12),
  }) async {
    if (configJson.isEmpty) return -1;
    try {
      final result = await _ch
          .invokeMethod<int>('getServerDelay', {
            'config': configJson,
            'url': url ?? defaultUrl,
          })
          .timeout(timeout);
      return result ?? -1;
    } catch (e) {
      debugPrint('NativeDelayProbe.probe: $e');
      return -1;
    }
  }

  /// probe با fallback — اگه اولی fail شد سراغ بعدی می‌ره.
  static Future<int> probeWithFallback(
    String configJson, {
    Duration timeout = const Duration(seconds: 12),
  }) async {
    final urls = <String>[defaultUrl, ...fallbackUrls];
    for (final u in urls) {
      final delay = await probe(configJson, url: u, timeout: timeout);
      if (delay >= 0) return delay;
    }
    return -1;
  }

  /// probe موازی چند config با worker pool.
  ///
  /// برمی‌گردونه: لیست (index, delay). اونهایی که delay < 0 داشتن حذف
  /// نمی‌شن، فقط مقدارشون منفی می‌مونه.
  static Future<List<({int index, int delay})>> probeMany(
    List<String> configs, {
    int workers = 4,
    Duration timeout = const Duration(seconds: 12),
    bool Function()? isCancelled,
  }) async {
    if (configs.isEmpty) return const [];
    final out = <({int index, int delay})>[];
    var next = 0;

    Future<void> worker() async {
      while (true) {
        if (isCancelled?.call() == true) return;
        final i = next++;
        if (i >= configs.length) return;
        final delay = await probeWithFallback(
          configs[i],
          timeout: timeout,
        );
        out.add((index: i, delay: delay));
      }
    }

    final w = workers.clamp(1, 8);
    await Future.wait(
      List<Future<void>>.generate(w, (_) => worker()),
    );
    return out;
  }
}
