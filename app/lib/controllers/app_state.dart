import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../l10n/s.dart';
import '../services/settings_service.dart';

/// وضعیت سراسری ظاهر — پورت `ui/home/Appearance.kt` از MLM VPN.
/// کلیدهای SharedPreferences دقیقاً مثل MLM هستند تا رفتار یکسان بماند.
class AppearanceStore extends ChangeNotifier {
  AppearanceStore._();
  static final AppearanceStore instance = AppearanceStore._();

  static const String kTheme = 'app_theme'; // auto | light | dark
  static const String kIconScale = 'home_icon_scale'; // 60..140
  static const String kTextScale = 'app_text_scale'; // 60..140
  static const String kTextScaleAuto = 'app_text_scale_auto'; // bool
  static const String kLabelScale = 'home_label_scale'; // 60..140
  static const String kDockLabels = 'home_dock_labels'; // bool
  static const String kWallpaperEverywhere = 'wallpaper_everywhere'; // bool
  static const String kWallpaperId = 'wallpaper_id'; // preset id | 'custom'
  static const String kWallpaperBlur = 'wallpaper_blur'; // 0..100

  static const int scaleMin = 60;
  static const int scaleMax = 140;

  String theme = 'dark';
  int iconScale = 100;
  int textScale = 100;
  bool textScaleAuto = true;
  int labelScale = 100;
  bool dockLabels = false;
  bool wallpaperEverywhere = true;
  String wallpaperId = 'dusk';
  int wallpaperBlur = 0;

  Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    theme = p.getString(kTheme) ?? 'dark';
    iconScale = p.getInt(kIconScale) ?? 100;
    textScale = p.getInt(kTextScale) ?? 100;
    textScaleAuto = p.getBool(kTextScaleAuto) ?? true;
    labelScale = p.getInt(kLabelScale) ?? 100;
    dockLabels = p.getBool(kDockLabels) ?? false;
    wallpaperEverywhere = p.getBool(kWallpaperEverywhere) ?? true;
    wallpaperId = p.getString(kWallpaperId) ?? 'dusk';
    wallpaperBlur = p.getInt(kWallpaperBlur) ?? 0;
    notifyListeners();
  }

  Future<void> _set(String key, Object value) async {
    final p = await SharedPreferences.getInstance();
    if (value is String) {
      await p.setString(key, value);
    } else if (value is bool) {
      await p.setBool(key, value);
    } else if (value is int) {
      await p.setInt(key, value);
    }
    notifyListeners();
  }

  Future<void> setTheme(String v) async {
    theme = v;
    await _set(kTheme, v);
  }

  Future<void> setIconScale(int v) async {
    iconScale = v.clamp(scaleMin, scaleMax);
    await _set(kIconScale, iconScale);
  }

  Future<void> setTextScale(int v) async {
    textScale = v.clamp(scaleMin, scaleMax);
    await _set(kTextScale, textScale);
  }

  Future<void> setTextScaleAuto(bool v) async {
    textScaleAuto = v;
    await _set(kTextScaleAuto, v);
  }

  Future<void> setLabelScale(int v) async {
    labelScale = v.clamp(scaleMin, scaleMax);
    await _set(kLabelScale, labelScale);
  }

  Future<void> setDockLabels(bool v) async {
    dockLabels = v;
    await _set(kDockLabels, v);
  }

  Future<void> setWallpaperEverywhere(bool v) async {
    wallpaperEverywhere = v;
    await _set(kWallpaperEverywhere, v);
  }

  Future<void> setWallpaperId(String v) async {
    wallpaperId = v;
    await _set(kWallpaperId, v);
  }

  Future<void> setWallpaperBlur(int v) async {
    wallpaperBlur = v.clamp(0, 100);
    await _set(kWallpaperBlur, wallpaperBlur);
  }

  /// مقدار موثر اسکیل متن: «دنبال سیستم» ضربدر انتخاب دستی.
  /// MLM ضربِ fontScale سیستم در مقدار کاربر است (MainActivity L96-110).
  double effectiveTextScaler(double systemScale) {
    if (textScaleAuto) return systemScale;
    return systemScale * (textScale / 100.0);
  }
}

/// زبان برنامه — کلید همان تنظیم قدیمی برنامه (settings_language_v2).
class LocaleStore extends ChangeNotifier {
  LocaleStore._();
  static final LocaleStore instance = LocaleStore._();

  String lang = 'fa';

  Future<void> load() async {
    lang = await SettingsService.getLanguage();
    S.lang = lang;
    notifyListeners();
  }

  Future<void> set(String v) async {
    lang = v;
    S.lang = v;
    await SettingsService.setLanguage(v);
    notifyListeners();
  }
}

/// تم Material — فونت IRANSansX + اسکیم رنگ iOS.
/// حالت‌ها: auto | light | dark (کلید app_theme، پیش‌فرض dark مثل MLM).
class ThemeController extends ChangeNotifier {
  ThemeController._();
  static final ThemeController instance = ThemeController._();

  void bind(AppearanceStore appearance) {
    _appearance?.removeListener(_onAppearance);
    _appearance = appearance;
    appearance.addListener(_onAppearance);
  }

  AppearanceStore? _appearance;
  void _onAppearance() => notifyListeners();

  ThemeMode get mode {
    switch (_appearance?.theme ?? 'dark') {
      case 'light':
        return ThemeMode.light;
      case 'auto':
        return ThemeMode.system;
      default:
        return ThemeMode.dark;
    }
  }

  static const String fontFamily = 'IRANSansX';

  ThemeData themeData(Brightness brightness) {
    final scheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF0A84FF),
      brightness: brightness,
    );
    final base = ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      fontFamily: fontFamily,
      brightness: brightness,
    );
    return base.copyWith(
      scaffoldBackgroundColor: Colors.transparent,
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.all(Colors.white),
        trackColor: WidgetStateProperty.resolveWith((states) =>
            states.contains(WidgetState.selected)
                ? (brightness == Brightness.dark
                    ? const Color(0xFF0A84FF)
                    : const Color(0xFF007AFF))
                : const Color(0xFF39393D)),
      ),
    );
  }
}
