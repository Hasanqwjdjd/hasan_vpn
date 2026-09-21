import 'package:flutter/material.dart';

class AppColors {
  static bool isDark(BuildContext c) => Theme.of(c).brightness == Brightness.dark;
  static Color bg(BuildContext c) => isDark(c) ? const Color(0xFF08090C) : const Color(0xFFF5F6F8);
  static Color surface(BuildContext c) => isDark(c) ? const Color(0xFF12141A) : Colors.white;
  static Color elevated(BuildContext c) => isDark(c) ? const Color(0xFF1A1D25) : const Color(0xFFEAECF0);
  static Color navBar(BuildContext c) => isDark(c) ? const Color(0xFF0E1015) : Colors.white;
  static Color fg(BuildContext c) => isDark(c) ? Colors.white : const Color(0xFF0F1015);
  static Color muted(BuildContext c) => isDark(c) ? Colors.white54 : Colors.black54;
  static Color muted2(BuildContext c) => isDark(c) ? Colors.white38 : Colors.black38;
  static Color border(BuildContext c) => isDark(c) ? Colors.white12 : Colors.black12;
  static const Color accent = Color(0xFF3DCF9A);
  static const Color danger = Color(0xFFE07070);
  static const Color warn = Color(0xFFFFB74D);
}
