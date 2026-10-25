import 'package:flutter/material.dart';

/// پالت دقیق iOS — پورت ۱:۱ از MLM VPN
/// `ui/theme/Theme.kt` + `ui/settings/IosSettings.kt` (L114-198)
/// + تینت‌های ثابتِ `ui/home/HomeDestinations.kt` (L78-87).
class Ios {
  Ios._();

  // ── تینت‌های ثابتِ تایل‌ها (هر دو حالت روشن/تاریک یکسان) ──
  static const Color tileBlue = Color(0xFF007AFF);
  static const Color tileGreen = Color(0xFF34C759);
  static const Color tileIndigo = Color(0xFF5856D6);
  static const Color tileOrange = Color(0xFFFF9500);
  static const Color tilePink = Color(0xFFFF2D55);
  static const Color tilePurple = Color(0xFFAF52DE);
  static const Color tileRed = Color(0xFFFF3B30);
  static const Color tileTeal = Color(0xFF5AC8FA);
  static const Color tileYellow = Color(0xFFFFCC00);
  static const Color tileGray = Color(0xFF8E8E93);

  // ── رنگ‌های وضعیت روی صفحه‌خانه ──
  static const Color lampGreen1 = Color(0xFF5AF08A);
  static const Color lampGreen2 = Color(0xFF2FBF5C);
  static const Color lampRing = Color(0xFF0B0B0C);
  static const Color badgeRed = Color(0xFFFF3B30);
  static const Color shieldOn = Color(0xFF34C759);
  static const Color upTeal = Color(0xFF5AC8FA);
  static const Color exitDialogRed = Color(0xFFFF453A);
  static const Color warnOrange = Color(0xFFFF9F0A);
  static const Color cfOrange = Color(0xFFF6821F);

  // ── اسپلش ──
  static const Color splashBase = Color(0xFF0A101C);
}

/// توکن‌های حالت‌دار (روشن/تاریک) — مقادیر عیناً از Theme.kt / IosSettings.kt.
class IosPal {
  const IosPal({
    required this.dark,
    required this.background,
    required this.card,
    required this.dialog,
    required this.separator,
    required this.blue,
    required this.green,
    required this.indigo,
    required this.orange,
    required this.pink,
    required this.purple,
    required this.red,
    required this.teal,
    required this.yellow,
    required this.gray,
    required this.cfOrange,
    required this.pageWash,
    required this.surface,
    required this.border,
    required this.textMuted,
    required this.textDim,
    required this.glassTint,
    required this.glassWash,
    required this.glassRim,
    required this.featureScrim,
    required this.noWallpaperFill,
  });

  final bool dark;
  final Color background;
  final Color card;
  final Color dialog;
  final Color separator;
  final Color blue;
  final Color green;
  final Color indigo;
  final Color orange;
  final Color pink;
  final Color purple;
  final Color red;
  final Color teal;
  final Color yellow;
  final Color gray;
  final Color cfOrange;
  final Color pageWash;
  final Color surface;
  final Color border;
  final Color textMuted;
  final Color textDim;
  final Color glassTint;
  final Color glassWash;
  final Color glassRim;
  final Color featureScrim;
  final Color noWallpaperFill;

  static const IosPal darkPal = IosPal(
    dark: true,
    background: Color(0xFF000000),
    card: Color(0xFF1C1C1E),
    dialog: Color(0xE61C1C1E), // #1C1C1E α .97
    separator: Color(0x21FFFFFF), // White α .13
    blue: Color(0xFF0A84FF),
    green: Color(0xFF32D74B),
    indigo: Color(0xFF5E5CE6),
    orange: Color(0xFFFF9F0A),
    pink: Color(0xFFFF375F),
    purple: Color(0xFFBF5AF2),
    red: Color(0xFFFF453A),
    teal: Color(0xFF64D2FF),
    yellow: Color(0xFFFFD60A),
    gray: Color(0xFF8E8E93),
    cfOrange: Color(0xFFF6821F),
    pageWash: Color(0x42000000), // Black α .26
    surface: Color(0xD11C1C1E), // CardOverWallpaper #1C1C1E α .82
    border: Color(0x24FFFFFF), // White α .14
    textMuted: Color(0x9EFFFFFF), // White α .62
    textDim: Color(0x73FFFFFF), // White α .45
    glassTint: Color(0x57000000), // Black α .34
    glassWash: Color(0x14FFFFFF), // White α .08
    glassRim: Color(0x26FFFFFF), // White α .15
    featureScrim: Color(0x73000000), // Black α .45
    noWallpaperFill: Color(0xEB1C1C1E), // #1C1C1E α .92
  );

  static const IosPal lightPal = IosPal(
    dark: false,
    background: Color(0xFF1C1C1E),
    card: Color(0xFF2C2C2E),
    dialog: Color(0xF23A3A3C), // #3A3A3C α .95
    separator: Color(0x38FFFFFF), // White α .22
    blue: Color(0xFF007AFF),
    green: Color(0xFF34C759),
    indigo: Color(0xFF5856D6),
    orange: Color(0xFFFF9500),
    pink: Color(0xFFFF2D55),
    purple: Color(0xFFAF52DE),
    red: Color(0xFFFF3B30),
    teal: Color(0xFF32ADE6),
    yellow: Color(0xFFFFCC00),
    gray: Color(0xFF8E8E93),
    cfOrange: Color(0xFFF6821F),
    pageWash: Color(0x21000000), // Black α .13
    surface: Color(0x9E48484A), // #48484A α .62
    border: Color(0x3DFFFFFF), // White α .24
    textMuted: Color(0xBDFFFFFF), // White α .74
    textDim: Color(0x73FFFFFF),
    glassTint: Color(0x29000000), // Black α .16
    glassWash: Color(0x33FFFFFF), // White α .20
    glassRim: Color(0xA6FFFFFF), // White α .65
    featureScrim: Color(0x33000000), // Black α .20
    noWallpaperFill: Color(0xF03A3A3C), // #3A3A3C α .94
  );

  static IosPal of(BuildContext c) =>
      Theme.of(c).brightness == Brightness.dark ? darkPal : lightPal;

  // نام‌های میان‌بر پرکاربرد
  static Color label(BuildContext c) => Colors.white;
  static Color secondaryLabel(BuildContext c) => of(c).textMuted;
}
