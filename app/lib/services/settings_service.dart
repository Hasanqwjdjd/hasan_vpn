import 'package:shared_preferences/shared_preferences.dart';

class SettingsService {
  static const String _themeKey = 'settings_theme_mode_v1';
  static const String _langKey = 'settings_language_v1';

  /// تم: 'dark' یا 'light' یا 'system'
  static Future<String> getThemeMode() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_themeKey) ?? 'dark';
  }

  static Future<void> setThemeMode(String mode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_themeKey, mode);
  }

  /// زبان: 'fa' یا 'en'
  static Future<String> getLanguage() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_langKey) ?? 'fa';
  }

  static Future<void> setLanguage(String lang) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_langKey, lang);
  }
}
