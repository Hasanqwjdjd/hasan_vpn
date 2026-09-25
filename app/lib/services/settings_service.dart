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
  static const String _hiddenDnsKey = 'settings_hidden_dns_v1';
  static const String _dnsOverridesKey = 'settings_dns_overrides_v1';
  static const String _dnsPinnedKey = 'settings_dns_pinned_v1';
  static const String _serverNameOverridesKey =
      'settings_server_name_overrides_v1';
  static const String _lastDnsKey = 'settings_last_dns_v1';
  static const String _lastServerKey = 'settings_last_server_v1';

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
    list.add({'name': name, 'primary': primary, 'secondary': secondary});
    await prefs.setString(_customDnsKey, jsonEncode(list));
  }

  static Future<void> updateCustomDns(
      int index, String name, String primary, String secondary) async {
    final prefs = await SharedPreferences.getInstance();
    final list = await getCustomDnsList();
    if (index >= 0 && index < list.length) {
      list[index] = {
        'name': name,
        'primary': primary,
        'secondary': secondary,
      };
      await prefs.setString(_customDnsKey, jsonEncode(list));
    }
  }

  static Future<void> removeCustomDns(int index) async {
    final prefs = await SharedPreferences.getInstance();
    final list = await getCustomDnsList();
    if (index >= 0 && index < list.length) {
      list.removeAt(index);
      await prefs.setString(_customDnsKey, jsonEncode(list));
    }
  }

  // --------------------------------------------------------- Hidden DNS

  static Future<List<String>> getHiddenDns() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_hiddenDnsKey);
    if (raw == null) return [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) return decoded.map((e) => e.toString()).toList();
    } catch (_) {}
    return [];
  }

  static Future<void> addHiddenDns(String key) async {
    final prefs = await SharedPreferences.getInstance();
    final list = await getHiddenDns();
    if (!list.contains(key)) list.add(key);
    await prefs.setString(_hiddenDnsKey, jsonEncode(list));
  }

  static Future<void> removeHiddenDns(String key) async {
    final prefs = await SharedPreferences.getInstance();
    final list = await getHiddenDns();
    list.remove(key);
    await prefs.setString(_hiddenDnsKey, jsonEncode(list));
  }

  // --------------------------------------------------------- DNS Overrides

  static Future<Map<String, Map<String, String>>> getDnsOverrides() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_dnsOverridesKey);
    if (raw == null) return {};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        final out = <String, Map<String, String>>{};
        decoded.forEach((k, v) {
          if (v is Map) {
            out[k.toString()] = v.map(
                (k2, v2) => MapEntry(k2.toString(), v2.toString()));
          }
        });
        return out;
      }
    } catch (_) {}
    return {};
  }

  static Future<void> setDnsOverride(String originalPrimary, String name,
      String primary, String secondary) async {
    final prefs = await SharedPreferences.getInstance();
    final map = await getDnsOverrides();
    map[originalPrimary] = {
      'name': name,
      'primary': primary,
      'secondary': secondary,
    };
    await prefs.setString(_dnsOverridesKey, jsonEncode(map));
  }

  static Future<void> removeDnsOverride(String originalPrimary) async {
    final prefs = await SharedPreferences.getInstance();
    final map = await getDnsOverrides();
    map.remove(originalPrimary);
    await prefs.setString(_dnsOverridesKey, jsonEncode(map));
  }

  // --------------------------------------------------------- DNS Pin

  static Future<List<String>> getPinnedDns() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_dnsPinnedKey);
    if (raw == null) return [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) return decoded.map((e) => e.toString()).toList();
    } catch (_) {}
    return [];
  }

  static Future<void> togglePinnedDns(String key) async {
    final prefs = await SharedPreferences.getInstance();
    final list = await getPinnedDns();
    if (list.contains(key)) {
      list.remove(key);
    } else {
      list.add(key);
    }
    await prefs.setString(_dnsPinnedKey, jsonEncode(list));
  }

  // --------------------------------------------------------- DNS Ping

  static Future<Map<String, int>> getDnsPingResults() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_dnsPingKey);
    if (raw == null) return {};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        return decoded
            .map((k, v) => MapEntry(k.toString(), v is int ? v : -1));
      }
    } catch (_) {}
    return {};
  }

  static Future<void> saveDnsPingResult(String key, int latency) async {
    final prefs = await SharedPreferences.getInstance();
    final map = await getDnsPingResults();
    map[key] = latency;
    await prefs.setString(_dnsPingKey, jsonEncode(map));
  }

  static Future<void> clearDnsPingResults() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_dnsPingKey);
  }

  // --------------------------------------------------------- Server Name Overrides

  static Future<Map<String, String>> getServerNameOverrides() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_serverNameOverridesKey);
    if (raw == null) return {};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        return decoded.map((k, v) => MapEntry(k.toString(), v.toString()));
      }
    } catch (_) {}
    return {};
  }

  static Future<void> setServerNameOverride(
      String serverId, String name) async {
    final prefs = await SharedPreferences.getInstance();
    final map = await getServerNameOverrides();
    map[serverId] = name;
    await prefs.setString(_serverNameOverridesKey, jsonEncode(map));
  }

  static Future<void> removeServerNameOverride(String serverId) async {
    final prefs = await SharedPreferences.getInstance();
    final map = await getServerNameOverrides();
    map.remove(serverId);
    await prefs.setString(_serverNameOverridesKey, jsonEncode(map));
  }

  // --------------------------------------------------------- Server Pings

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

  // --------------------------------------------------------- Last DNS

  /// کلید آخرین DNS فعال: "primary|secondary"
  static Future<String?> getLastDns() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_lastDnsKey);
  }

  static Future<void> setLastDns(String key) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_lastDnsKey, key);
  }

  static Future<void> clearLastDns() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_lastDnsKey);
  }

  // --------------------------------------------------------- Last Server

  static Future<String?> getLastServer() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_lastServerKey);
  }

  static Future<void> setLastServer(String serverId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_lastServerKey, serverId);
  }

  static Future<void> clearLastServer() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_lastServerKey);
  }

  static const String _blockedAppsKey = 'settings_blocked_apps_v1';
  static Future<List<String>> getBlockedApps() async {
    try {
      final p = await SharedPreferences.getInstance();
      return p.getStringList(_blockedAppsKey) ?? <String>[];
    } catch (_) {
      return <String>[];
    }
  }
  static Future<void> setBlockedApps(List<String> packages) async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setStringList(_blockedAppsKey, packages);
    } catch (_) {}
  }

  /// حالت پراکسی هر برنامه: whitelist | blacklist | all
  /// - all:       همه‌ی برنامه‌ها از تونل رد می‌شوند (پیش‌فرض)
  /// - blacklist: برنامه‌های انتخاب‌شده از تونل مستثنی می‌شوند
  /// - whitelist: فقط برنامه‌های انتخاب‌شده از تونل رد می‌شوند
  static const String _proxyModeKey = 'settings_proxy_mode_v1';
  static Future<String> getProxyMode() async {
    try {
      final p = await SharedPreferences.getInstance();
      return p.getString(_proxyModeKey) ?? 'all';
    } catch (_) {
      return 'all';
    }
  }

  static Future<void> setProxyMode(String mode) async {
    try {
      final p = await SharedPreferences.getInstance();
      final m = (mode == 'whitelist' || mode == 'blacklist') ? mode : 'all';
      await p.setString(_proxyModeKey, m);
    } catch (_) {}
  }
  static const String _connectFastestKey = 'settings_connect_fastest_v1';
  static Future<bool> getConnectFastest() async {
    try {
      final p = await SharedPreferences.getInstance();
      return p.getBool(_connectFastestKey) ?? false;
    } catch (_) {
      return false;
    }
  }
  static Future<void> setConnectFastest(bool v) async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setBool(_connectFastestKey, v);
    } catch (_) {}
  }

}
