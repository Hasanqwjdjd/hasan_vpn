import 'dart:convert';

import 'package:flutter/foundation.dart' show debugPrint;

import 'package:shared_preferences/shared_preferences.dart';

/// حالت بازی: ترکیب DNS انتخابی + قوانین فایروال سبک روی هسته Xray
/// الهام از WhiteGame / RethinkDNS / sfdns-pro:
/// - فقط DNS بازی
/// - مسدودسازی QUIC (UDP/443) برای کاهش ترافیک رقابتی
/// - اجبار IPv4
/// - بلاک تله‌متری/تبلیغات رایج
/// - کش DNS کوچک‌تر
///
/// توجه: پینگ زیر ۳۰ms عمدتاً به نزدیکی سرور VPN و مسیر ISP بستگی دارد؛
/// این تنظیمات نویز شبکه را کم می‌کند و رزولوشن را بهینه می‌کند.
class GameBoosterSettings {
  GameBoosterSettings._();

  static const String _key = 'game_booster_settings_v1';

  static const Map<String, dynamic> defaults = {
    'enabled': false,
    'blockQuic': true,
    'forceIpv4': true,
    'blockTelemetry': true,
    'blockAds': true,
    'smallDnsCache': true,
    'preferUdpGames': true,
  };

  static Future<Map<String, dynamic>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) return Map<String, dynamic>.from(defaults);
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return Map<String, dynamic>.from(defaults);
      final map = Map<String, dynamic>.from(defaults);
      map.addAll(Map<String, dynamic>.from(decoded));
      return map;
    } catch (_) {
      return Map<String, dynamic>.from(defaults);
    }
  }

  static Future<void> save(Map<String, dynamic> settings) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(settings));
  }

  static Future<void> set(String key, dynamic value) async {
    final s = await load();
    s[key] = value;
    await save(s);
    // قانون طلایی ۲ — لاگ ذخیره‌سازی تا پایداری تنظیمات قابل اثبات باشد
    debugPrint('[GameBooster] setting saved: $key=$value');
  }

  // ─── بخش ۶ — روتینگ جداگانه‌ی بازی‌ها از تونل ───
  // بسته‌هایی که با تاگل «بوست» در Game Hub انتخاب می‌شوند؛ ترافیک همین
  // اپ‌ها جداگانه از تونل رد می‌شود (در resolveBlockedApps معاف می‌شوند).
  static const String _routedKey = 'game_routed_packages_v1';

  static Future<Set<String>> routedPackages() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final list = prefs.getStringList(_routedKey) ?? const <String>[];
      return list.toSet();
    } catch (_) {
      return <String>{};
    }
  }

  static Future<void> setRoutedPackage(String packageName, bool routed) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final set = await routedPackages();
      if (routed) {
        set.add(packageName);
      } else {
        set.remove(packageName);
      }
      await prefs.setStringList(_routedKey, set.toList());
      debugPrint('[GameBooster] routed through tunnel: $packageName -> $routed '
          '(total ${set.length})');
    } catch (_) {}
  }

  static Future<bool> isEnabled() async {
    final s = await load();
    return s['enabled'] == true;
  }

  /// دامنه‌های تله‌متری رایج بازی‌ها / SDKها
  static const List<String> telemetryDomains = [
    'app-measurement.com',
    'google-analytics.com',
    'crashlytics.com',
    'firebase-settings.crashlytics.com',
    'firebaselogging-pa.googleapis.com',
    'appsflyer.com',
    'adjust.com',
    'branch.io',
    'sentry.io',
    'bugsnag.com',
    'unity3d.com',
    'unityads.unity3d.com',
    'gameanalytics.com',
    'tenjin.io',
    'kochava.com',
    'singular.net',
  ];

  /// دامنه‌های تبلیغات رایج
  static const List<String> adDomains = [
    'doubleclick.net',
    'googlesyndication.com',
    'googleadservices.com',
    'adservice.google.com',
    'pagead2.googlesyndication.com',
    'ad.doubleclick.net',
    'ads.mopub.com',
    'mopub.com',
    'adcolony.com',
    'applovin.com',
    'unityads.unity3d.com',
    'chartboost.com',
    'ironsrc.com',
    'vungle.com',
    'inmobi.com',
  ];
}
