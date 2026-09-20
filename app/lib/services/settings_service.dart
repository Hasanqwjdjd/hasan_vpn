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

  /// 'vpn' (پیش‌فرض) | 'proxy'
  static Future<String> getVpnMode() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_vpnModeKey) ?? 'vpn';
  }

  static Future<void> setVpnMode(String mode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_vpnModeKey, mode);
  }

  // --------------------------------------------------------- game DNS

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

  // --------------------------------------------------------- DNS IP pref

  /// 'ipv4' | 'ipv6' | 'both' (پیش‌فرض: 'ipv4')
  static Future<String> getDnsIpPreference() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_dnsPreferenceKey) ?? 'ipv4';
  }

  static Future<void> setDnsIpPreference(String pref) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_dnsPreferenceKey, pref);
  }
}
