import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// هشدار بر اساس افت کیفیت.
///
/// اگه امتیاز N بار متوالی زیر آستانه بیاد، یه بار هشدار می‌ده.
/// بعد از بهبودی، resets می‌شه.
class QualityAlert {
  QualityAlert._();
  static final QualityAlert instance = QualityAlert._();

  static const String _prefKeyThreshold = 'quality_alert_threshold_v1';
  static const String _prefKeyEnabled = 'quality_alert_enabled_v1';
  static const int defaultThreshold = 40;
  static const int consecutiveBreaches = 3;

  int _threshold = defaultThreshold;
  bool _enabled = true;
  int _consecutiveBad = 0;
  bool _alreadyAlerted = false;

  int get threshold => _threshold;
  bool get enabled => _enabled;

  /// callback که وقتی هشدار صادر شد صدا زده می‌شه.
  void Function(int score)? onLowQuality;
  void Function()? onRecovered;

  Future<void> restore() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _threshold =
          prefs.getInt(_prefKeyThreshold) ?? defaultThreshold;
      _enabled = prefs.getBool(_prefKeyEnabled) ?? true;
    } catch (_) {}
  }

  Future<void> setThreshold(int v) async {
    _threshold = v.clamp(10, 90);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_prefKeyThreshold, _threshold);
    } catch (_) {}
  }

  Future<void> setEnabled(bool v) async {
    _enabled = v;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_prefKeyEnabled, v);
    } catch (_) {}
  }

  /// ارزیابی یه نمونه جدید.
  void evaluate(int score) {
    if (!_enabled) return;

    if (score < _threshold) {
      _consecutiveBad++;
      if (_consecutiveBad >= consecutiveBreaches && !_alreadyAlerted) {
        _alreadyAlerted = true;
        debugPrint('quality-alert: score $score < $_threshold '
            '($consecutiveBreaches consecutive)');
        onLowQuality?.call(score);
      }
    } else {
      if (_alreadyAlerted) {
        onRecovered?.call();
      }
      _consecutiveBad = 0;
      _alreadyAlerted = false;
    }
  }

  void reset() {
    _consecutiveBad = 0;
    _alreadyAlerted = false;
  }
}
