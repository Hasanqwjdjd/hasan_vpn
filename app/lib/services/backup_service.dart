import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// پشتیبان‌گیری و بازیابی کل داده‌های اپ به‌صورت JSON.
///
/// شامل: subscriptions, custom servers, xray settings, routing rules,
/// pinned/manual order, per-app configs, و بقیه. از prefs کلون می‌گیرد
/// و در یک فایل ذخیره می‌کند — کاربر می‌تواند به یک دستگاه دیگر منتقل کند.
class BackupService {
  BackupService._();

  /// کلیدهایی که پشتیبان‌گیری می‌شوند.
  static const List<String> _keys = <String>[
    'subscriptions_v3',
    'custom_servers_v1',
    'server_groups_v1',
    'manual_order',
    'manual_order_v1',
    'pinned',
    'pinned_v1',
    'deleted_ids',
    'deleted_ids_v1',
    'custom_sub_tags_v1',
    'dns_manual_order_v1',
    'xray_core_settings_v2',
    'routing_rules_v1',
    'routing_domain_strategy_v1',
    'test_settings_v1',
    'telemetry_live_v1',
    'settings_last_server_v1',
    'settings_theme_mode_v1',
    'settings_language_v1',
    'settings_font_scale_v1',
    'settings_auto_connect_boot_v1',
    'settings_connect_fastest_v1',
    'telegram_channels_v1',
    'tor_bridge_type',
    'tor_custom_bridges',
    'tor_sni',
    'tor_sni_enabled',
    'per_app_proxy_mode_v1',
    'per_app_blocked_apps_v1',
  ];

  /// خروجی JSON از همه کلیدها. مقادیر با پیشوند "flutter." ذخیره می‌شوند،
  /// ولی ما بدون پیشوند برمی‌گردانیم.
  static Future<String> export() async {
    final prefs = await SharedPreferences.getInstance();
    final map = <String, dynamic>{};
    for (final k in _keys) {
      final v = prefs.get('flutter.$k') ?? prefs.get(k);
      if (v != null) map[k] = v;
    }
    final payload = <String, dynamic>{
      '_version': 1,
      '_exportedAt': DateTime.now().toIso8601String(),
      'data': map,
    };
    return const JsonEncoder.withIndent('  ').convert(payload);
  }

  /// بازیابی از JSON. مقادیر جدید جایگزین قدیمی می‌شوند.
  /// برمی‌گرداند: تعداد کلیدهای بازیابی‌شده.
  static Future<int> restore(String jsonText) async {
    final dynamic decoded = jsonDecode(jsonText);
    if (decoded is! Map) throw 'invalid backup: not an object';
    final data = decoded['data'];
    if (data is! Map) throw 'invalid backup: no data';
    final prefs = await SharedPreferences.getInstance();
    int count = 0;
    for (final entry in data.entries) {
      final k = entry.key.toString();
      final v = entry.value;
      // همه‌ی مقادیر رو با پیشوند flutter. بنویس تا با Dart هم‌خوانی داشته باشه.
      try {
        if (v is String) {
          await prefs.setString('flutter.$k', v);
        } else if (v is int) {
          await prefs.setInt('flutter.$k', v);
        } else if (v is double) {
          await prefs.setDouble('flutter.$k', v);
        } else if (v is bool) {
          await prefs.setBool('flutter.$k', v);
        } else if (v is List) {
          await prefs.setStringList(
            'flutter.$k',
            v.map((e) => e.toString()).toList(),
          );
        }
        count++;
      } catch (_) {}
    }
    return count;
  }

  static Future<int> totalKeyCount() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getKeys().where((k) => k.startsWith('flutter.')).length;
  }
}
