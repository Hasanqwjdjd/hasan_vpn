// app/lib/services/dns_advanced_settings.dart
//
// Phase (e): the new settings from Goal 4 that didn't already exist.
// Kept as its own small service (rather than bloating the 400+ line
// settings_service.dart) since it's all new, versioned state specific
// to the DNS Game feature. Read by v2ray_engine.dart / xray_json.dart
// when building the Xray config (phase (f)).
//
// NOT duplicated here (already covered elsewhere, see Goal 4 notes):
//  - "Block QUIC for DNS" -> GameBoosterSettings.blockQuic (existing)
//  - "Show jitter next to ping" -> UI-only, no persisted setting
//  - "Sniffing uses chosen DNS" -> verified in v2ray_engine.dart, not
//    a user-facing setting

import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

/// Xray's dns.queryStrategy values.
enum DnsQueryStrategy { useIPv4, useIPv6, useIP, asIs }

/// What to try, in order, if the active primary DNS fails to resolve.
enum DnsFallbackStep { primary, secondary, system, direct }

enum DnsCacheSize { disabled, small, medium, large } // 0 / 1K / 10K / 100K

enum RegionPreference { myCountry, nearest, any }

class DnsAdvancedSettings {
  DnsAdvancedSettings._();

  static const String _key = 'game_dns_advanced_settings_v1';

  static const Map<String, dynamic> defaults = {
    'queryStrategy': 'useIPv4',
    'fallbackOrder': ['primary', 'secondary', 'system', 'direct'],
    'dohEnabled': false,
    'dohUrl': null,
    'cacheSize': 'medium',
    'pingAllOnStart': false,
    'regionPreference': 'myCountry',
    'autoRetestIntervalMinutes': 0, // 0 = off
  };

  static Future<Map<String, dynamic>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    final map = Map<String, dynamic>.from(defaults);
    if (raw == null) return map;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) map.addAll(Map<String, dynamic>.from(decoded));
    } catch (_) {}
    return map;
  }

  static Future<void> save(Map<String, dynamic> settings) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(settings));
  }

  static Future<void> set(String key, dynamic value) async {
    final s = await load();
    s[key] = value;
    await save(s);
  }

  // ---------------------------------------------------------- Typed getters

  static Future<DnsQueryStrategy> getQueryStrategy() async {
    final s = await load();
    return DnsQueryStrategy.values.firstWhere(
      (v) => v.name == s['queryStrategy'],
      orElse: () => DnsQueryStrategy.useIPv4,
    );
  }

  static Future<void> setQueryStrategy(DnsQueryStrategy strategy) =>
      set('queryStrategy', strategy.name);

  /// Xray's `dns.queryStrategy` string, e.g. "UseIPv4".
  static String xrayQueryStrategy(DnsQueryStrategy s) {
    switch (s) {
      case DnsQueryStrategy.useIPv4:
        return 'UseIPv4';
      case DnsQueryStrategy.useIPv6:
        return 'UseIPv6';
      case DnsQueryStrategy.useIP:
        return 'UseIP';
      case DnsQueryStrategy.asIs:
        return 'AsIs';
    }
  }

  static Future<List<DnsFallbackStep>> getFallbackOrder() async {
    final s = await load();
    final raw = (s['fallbackOrder'] as List?) ?? defaults['fallbackOrder'] as List;
    return raw
        .map((v) => DnsFallbackStep.values.firstWhere(
              (f) => f.name == v,
              orElse: () => DnsFallbackStep.system,
            ))
        .toList();
  }

  static Future<void> setFallbackOrder(List<DnsFallbackStep> order) =>
      set('fallbackOrder', order.map((e) => e.name).toList());

  static Future<bool> getDohEnabled() async => (await load())['dohEnabled'] == true;
  static Future<void> setDohEnabled(bool v) => set('dohEnabled', v);

  static Future<String?> getDohUrl() async => (await load())['dohUrl'] as String?;
  static Future<void> setDohUrl(String? url) => set('dohUrl', url);

  static Future<DnsCacheSize> getCacheSize() async {
    final s = await load();
    return DnsCacheSize.values.firstWhere(
      (v) => v.name == s['cacheSize'],
      orElse: () => DnsCacheSize.medium,
    );
  }

  static Future<void> setCacheSize(DnsCacheSize size) => set('cacheSize', size.name);

  /// Entry count Xray should use for its DNS cache, per Goal 4.4.
  static int xrayCacheEntries(DnsCacheSize s) {
    switch (s) {
      case DnsCacheSize.disabled:
        return 0;
      case DnsCacheSize.small:
        return 1000;
      case DnsCacheSize.medium:
        return 10000;
      case DnsCacheSize.large:
        return 100000;
    }
  }

  static Future<bool> getPingAllOnStart() async => (await load())['pingAllOnStart'] == true;
  static Future<void> setPingAllOnStart(bool v) => set('pingAllOnStart', v);

  static Future<RegionPreference> getRegionPreference() async {
    final s = await load();
    return RegionPreference.values.firstWhere(
      (v) => v.name == s['regionPreference'],
      orElse: () => RegionPreference.myCountry,
    );
  }

  static Future<void> setRegionPreference(RegionPreference p) =>
      set('regionPreference', p.name);

  /// Minutes between automatic re-tests of the active DNS while the
  /// VPN is running; 0 disables it (default, opt-in per spec).
  static Future<int> getAutoRetestIntervalMinutes() async =>
      (await load())['autoRetestIntervalMinutes'] as int? ?? 0;

  static Future<void> setAutoRetestIntervalMinutes(int minutes) =>
      set('autoRetestIntervalMinutes', minutes < 0 ? 0 : minutes);
}
