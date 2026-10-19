import 'package:flutter/material.dart';

class AppColors {
  static bool isDark(BuildContext c) => Theme.of(c).brightness == Brightness.dark;
  // بخش ۳ — پس‌زمینه‌ی تیره‌ی مشخصاتی: #0F1115
  static Color bg(BuildContext c) => isDark(c) ? const Color(0xFF0F1115) : const Color(0xFFF5F6F8);
  static Color surface(BuildContext c) => isDark(c) ? const Color(0xFF171A21) : Colors.white;
  static Color elevated(BuildContext c) => isDark(c) ? const Color(0xFF1E222B) : const Color(0xFFEAECF0);
  static Color navBar(BuildContext c) => isDark(c) ? const Color(0xFF12151B) : Colors.white;
  static Color fg(BuildContext c) => isDark(c) ? Colors.white : const Color(0xFF0F1015);
  static Color muted(BuildContext c) => isDark(c) ? Colors.white54 : Colors.black54;
  static Color muted2(BuildContext c) => isDark(c) ? Colors.white38 : Colors.black38;
  static Color border(BuildContext c) => isDark(c) ? Colors.white12 : Colors.black12;
  /// بخش ۳ — رنگ اصلی بنفش-آبی مشخصاتی: #6C5CE7
  static const Color accent = Color(0xFF6C5CE7);
  /// بخش ۳ — سبز مخصوص پینگ خوب (<150ms) — رنگ اصلی اپ بنفشه ولی
  /// پینگ خوب باید سبز بماند.
  static const Color good = Color(0xFF3DCF9A);
  static const Color danger = Color(0xFFE07070);
  static const Color warn = Color(0xFFFFB74D);
}
