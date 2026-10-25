import 'package:flutter/material.dart';

import '../controllers/connection.dart';
import '../l10n/s.dart';
import '../ui/kit/tiles.dart';
import '../ui/theme/ios_palette.dart';
import '../screens/nodes_screen.dart';
import '../screens/settings_screen.dart';
import '../screens/cloud_screen.dart';
import '../screens/transport_screen.dart';

/// رجیستری مقصدهای صفحه‌خانه — پورت `ui/home/HomeDestinations.kt`.
/// هر فاز تایل‌های جدید را اینجا اضافه می‌کند؛ فقط مقصدهایی که
/// واقعاً پیاده‌سازی شده‌اند ثبت می‌شوند (قانون بدون داروبازی).
class Destination {
  final String id;
  final String stringKey;
  final TileArt art;
  final Color tint;
  final bool modal;
  final WidgetBuilder builder;

  const Destination({
    required this.id,
    required this.stringKey,
    required this.art,
    required this.tint,
    required this.builder,
    this.modal = false,
  });

  String label() => S.t(stringKey);
}

const String _assets = 'assets/tiles';

final List<Destination> kDestinations = [
  // ── داک ──
  Destination(
    id: 'nodes',
    stringKey: 'home_v2ray',
    art: const TileArt.svg('$_assets/ic_app_v2ray.svg'),
    tint: Ios.tileBlue,
    builder: (_) => const NodesScreen(),
  ),
  Destination(
    id: 'settings',
    stringKey: 'home_settings',
    art: const TileArt.svg('$_assets/ic_app_settings.svg'),
    tint: Ios.tileGray,
    builder: (_) => const SettingsScreen(),
  ),
  Destination(
    id: 'cloud',
    stringKey: 'nav_cloud',
    art: const TileArt.svg('$_assets/ic_app_cloudflare.svg'),
    tint: Ios.tileTeal,
    builder: (_) => const CloudScreen(),
  ),
  // ── گرید: موتورها (فاز P2a/P2b) ──
  Destination(
    id: 'masque',
    stringKey: 'home_masque',
    art: const TileArt.svg('$_assets/ic_app_masque.svg'),
    tint: Ios.tileBlue,
    builder: (_) => const TransportScreen(transport: TransportId.masque),
  ),
  Destination(
    id: 'warp',
    stringKey: 'home_warp',
    art: const TileArt.svg('$_assets/ic_app_warp.svg'),
    tint: Ios.tileTeal,
    builder: (_) => const TransportScreen(transport: TransportId.warp),
  ),
  Destination(
    id: 'psiphon',
    stringKey: 'home_psiphon',
    art: const TileArt.png('$_assets/ic_app_psiphon.png'),
    tint: Ios.tileIndigo,
    builder: (_) => const TransportScreen(transport: TransportId.psiphon),
  ),
  Destination(
    id: 'tor',
    stringKey: 'home_tor',
    art: const TileArt.svg('$_assets/ic_app_tor.svg'),
    tint: Ios.tilePurple,
    builder: (_) => const TransportScreen(transport: TransportId.tor),
  ),
];

Destination? destinationById(String id) {
  for (final d in kDestinations) {
    if (d.id == id) return d;
  }
  return null;
}

/// داک — ترتیب MLM (اسکنر در P2d اضافه می‌شود).
const List<String> kDockIds = ['nodes', 'settings', 'cloud'];

/// چیدمان پیش‌فرض برد (تا وقتی کاربر ترتیب دلخواه بسازد).
const List<String> kBoardDefault = ['masque', 'warp', 'psiphon', 'tor'];
