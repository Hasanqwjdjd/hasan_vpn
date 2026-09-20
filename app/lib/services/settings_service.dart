import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:package_info_plus/package_info_plus.dart';

class SettingsService {
  static String currentVersion = '10.0.0';
  static const String _themeKey = 'settings_theme_mode_v2';
  static const String _langKey = 'settings_language_v2';
  static const String _vpnModeKey = 'settings_vpn_mode_v2';
  static const String _gameDnsPrimaryKey = 'settings_game_dns_primary_v1';
  static const String _gameDnsSecondaryKey = 'settings_game_dns_secondary_v1';
  static const String _dnsPreferenceKey = 'settings_dns_pref_v1';
  static const String _customDnsKey = 'settings_custom_dns_v1';
  static const String _dnsPingKey = 'settings_dns_ping_v1';

  static Future<void> loadVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      currentVersion = info.version;
    } catch (_) {}
  }

  static Future<String> getThemeMode() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_themeKey) ?? 'dark';
  }

  static Future<void> setThemeMode(String mode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_themeKey, mode);
  }

  static Future<String> getLanguage() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_langKey) ?? 'fa';
  }

  static Future<void> setLanguage(String lang) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_langKey, lang);
  }

  static Future<String> getVpnMode() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_vpnModeKey) ?? 'vpn';
  }

  static Future<void> setVpnMode(String mode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_vpnModeKey, mode);
  }

  // --------------------------------------------------------- Game DNS

  static Future<String?> getGameDnsPrimary() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_gameDnsPrimaryKey);
  }

  static Future<String?> getGameDnsSecondary() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_gameDnsSecondaryKey);
  }

  static Future<List<String>?> getGameDns() async {
    final prefs = await SharedPreferences.getInstance();
    final p = prefs.getString(_gameDnsPrimaryKey);
    final s = prefs.getString(_gameDnsSecondaryKey);
    if (p == null || s == null) return null;
    return <String>[p, s];
  }

  static Future<void> setGameDns(String primary, String secondary) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_gameDnsPrimaryKey, primary);
    await prefs.setString(_gameDnsSecondaryKey, secondary);
  }

  static Future<void> clearGameDns() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_gameDnsPrimaryKey);
    await prefs.remove(_gameDnsSecondaryKey);
  }

  static Future<String> getDnsIpPreference() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_dnsPreferenceKey) ?? 'ipv4';
  }

  static Future<void> setDnsIpPreference(String pref) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_dnsPreferenceKey, pref);
  }

  // --------------------------------------------------------- Custom DNS

  /// لیست DNS‌های سفارشی که کاربر خودش اضافه کرده است.
  /// فرمت: [{'name': '...', 'primary': '...', 'secondary': '...'}]
  static Future<List<Map<String, String>>> getCustomDnsList() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_customDnsKey);
    if (raw == null) return [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return [];
      return decoded
          .whereType<Map>()
          .map((m) => Map<String, String>.from(m))
          .toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> addCustomDns(
      String name, String primary, String secondary) async {
    final prefs = await SharedPreferences.getInstance();
    final list = await getCustomDnsList();
    list.add({
      'name': name,
      'primary': primary,
      'secondary': secondary,
    });
    await prefs.setString(_customDnsKey, jsonEncode(list));
  }

  static Future<void> removeCustomDns(int index) async {
    final prefs = await SharedPreferences.getInstance();
    final list = await getCustomDnsList();
    if (index >= 0 && index < list.length) {
      list.removeAt(index);
      await prefs.setString(_customDnsKey, jsonEncode(list));
    }
  }

  // --------------------------------------------------------- DNS Ping

  /// ذخیره‌ی نتیجه‌ی پینگ DNS‌ها.
  /// فرمت: {'primary|secondary': latency_ms, ...}
  static Future<Map<String, int>> getDnsPingResults() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_dnsPingKey);
    if (raw == null) return {};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        return decoded.map((k, v) => MapEntry(k.toString(), v is int ? v : -1));
      }
    } catch (_) {}
    return {};
  }

  static Future<void> saveDnsPingResult(String primary, int latency) async {
    final prefs = await SharedPreferences.getInstance();
    final map = await getDnsPingResults();
    map[primary] = latency;
    await prefs.setString(_dnsPingKey, jsonEncode(map));
  }

  static Future<void> clearDnsPingResults() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_dnsPingKey);
  }

  // --------------------------------------------------------- Server Ping

  /// ذخیره‌ی پینگ سرورها برای ماندگاری پس از بستن برنامه.
  /// فرمت: {'server_id': {'ping': int, 'kind': 'tcp'|'real', 'ts': ...}, ...}
  static Future<Map<String, dynamic>> getServerPings() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('server_pings_v1');
    if (raw == null) return {};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    } catch (_) {}
    return {};
  }

  static Future<void> saveServerPings(Map<String, dynamic> pings) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('server_pings_v1', jsonEncode(pings));
  }

  static Future<void> clearServerPings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('server_pings_v1');
  }
}
