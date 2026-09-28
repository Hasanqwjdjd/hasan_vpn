import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// پشتیبان‌گیری و بازیابی کل داده‌های اپ به‌صورت JSON.
///
/// از SharedPreferences خودکار discovery می‌کنه — یعنی هر کلید جدیدی که
/// در آینده اضافه بشه، بدون تغییر این فایل backup می‌شه. فقط چند کلید
/// ephemeral/cache استثنا می‌شن.
class BackupService {
  BackupService._();

  /// کلیدهایی که در backup نمیان (cache / ephemeral / حجیم).
  static const List<String> _excludePrefixes = <String>[
    'quick_export_servers_v1', // کش export
    'pingng_diagnostic_log', // log تشخیصی (حجیم)
    'PINGNG_DIAGNOSTIC_LOG',
    'widget_', // اسلات‌های ویجت (per-device)
    'server_geo_', // کش geo (فقط برای نمایش)
    'server_flag_', // کش flag
    'quick_home_widgets_v1', // اسلات‌های ویجت
    'telegram_last_error', // خطا (گذرا)
    'warp_health_endpoint_v1_', // endpoint health (per-server، از prefs read می‌شه)
    'final_mask_winners_', // کش برنده‌ها (خودکار بازسازی می‌شه)
    'desync_tuner_winner_', // کش برنده desync
    'warp_scout_last_fast_v1', // کش endpoint (خودکار بازسازی)
    'warp_scout_last_slow_v1',
    'warp_scout_last_fast_ms',
    'warp_scout_last_slow_ms',
  ];

  /// کلیدهایی که به‌طور پیش‌فرض exclude می‌شن مگر includeLogs=true.
  static const List<String> _logKeys = <String>[
    'connection_log_v1',
    'quality_history_v1',
  ];

  /// خروجی JSON از همه کلیدهای قابل backup.
  ///
  /// [includeLogs] اگه true باشه، لاگ‌های بزرگ (connection log + quality
  /// history) هم شامل می‌شن. پیش‌فرض false چون می‌تونه فایل رو بزرگ کنه.
  static Future<String> export({bool includeLogs = false}) async {
    final prefs = await SharedPreferences.getInstance();
    final map = <String, dynamic>{};

    for (final k in prefs.getKeys()) {
      // فقط کلیدهای flutter. (namespace Dart)
      String bare;
      if (k.startsWith('flutter.')) {
        bare = k.substring('flutter.'.length);
      } else {
        // کلیدهای native — فقط اگه صریحاً در includeLogs باشن یا مهم باشن
        continue;
      }

      // exclude prefix ها
      if (_excludePrefixes.any((p) => bare.startsWith(p))) continue;

      // log keys فقط با includeLogs
      if (!includeLogs && _logKeys.contains(bare)) continue;

      final v = prefs.get(k);
      if (v != null) map[bare] = v;
    }

    final payload = <String, dynamic>{
      '_version': 2,
      '_exportedAt': DateTime.now().toIso8601String(),
      '_app': 'Hasan VPN',
      '_includeLogs': includeLogs,
      '_count': map.length,
      'data': map,
    };
    return const JsonEncoder.withIndent('  ').convert(payload);
  }

  /// بازیابی از JSON. مقادیر جدید جایگزین قدیمی می‌شوند.
  ///
  /// پشتیبانی از نسخه ۱ (که فقط لیست ثابت داشت) و نسخه ۲ (auto-discover).
  /// برمی‌گرداند: تعداد کلیدهای بازیابی‌شده.
  static Future<int> restore(String jsonText) async {
    final dynamic decoded;
    try {
      decoded = jsonDecode(jsonText);
    } catch (e) {
      throw FormatException('invalid backup: not valid JSON ($e)');
    }
    if (decoded is! Map) {
      throw const FormatException('invalid backup: not an object');
    }
    final data = decoded['data'];
    if (data is! Map) {
      throw const FormatException('invalid backup: no data field');
    }
    final prefs = await SharedPreferences.getInstance();
    var count = 0;
    for (final entry in data.entries) {
      final k = entry.key.toString();
      final v = entry.value;
      // حذف پیشوند flutter. اگه دوباره داشت
      final bare = k.startsWith('flutter.') ? k : k;
      try {
        if (v is String) {
          await prefs.setString('flutter.$bare', v);
        } else if (v is int) {
          await prefs.setInt('flutter.$bare', v);
        } else if (v is double) {
          await prefs.setDouble('flutter.$bare', v);
        } else if (v is bool) {
          await prefs.setBool('flutter.$bare', v);
        } else if (v is List) {
          await prefs.setStringList(
            'flutter.$bare',
            v.map((e) => e.toString()).toList(),
          );
        }
        count++;
      } catch (_) {}
    }
    return count;
  }

  /// تعداد کلیدهای قابل backup.
  static Future<int> backupableKeyCount({bool includeLogs = false}) async {
    final prefs = await SharedPreferences.getInstance();
    var count = 0;
    for (final k in prefs.getKeys()) {
      if (!k.startsWith('flutter.')) continue;
      final bare = k.substring('flutter.'.length);
      if (_excludePrefixes.any((p) => bare.startsWith(p))) continue;
      if (!includeLogs && _logKeys.contains(bare)) continue;
      count++;
    }
    return count;
  }

  /// تعداد کلیدها با پیشوند flutter.
  static Future<int> totalKeyCount() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getKeys().where((k) => k.startsWith('flutter.')).length;
  }

  /// مجموع بایت تقریبی — برای هشدار به کاربر.
  static Future<int> estimatedBytes({bool includeLogs = false}) async {
    try {
      final json = await export(includeLogs: includeLogs);
      return json.length;
    } catch (_) {
      return 0;
    }
  }
}
