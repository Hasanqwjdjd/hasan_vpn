import 'package:flutter/material.dart';

import '../controllers/connection.dart';
import '../l10n/s.dart';
import '../ui/kit/tiles.dart';
import '../ui/theme/ios_palette.dart';
import '../screens/nodes_screen.dart';
import '../screens/settings_screen.dart';
import '../screens/cloud_screen.dart';
import '../screens/flux_screen.dart';
import '../screens/freeconfig_screen.dart';
import '../screens/game_screen.dart';
import '../screens/geph_screen.dart';
import '../screens/lantern_screen.dart';
import '../screens/quick_screen.dart';
import '../screens/scanner_screen.dart';
import '../screens/store_screen.dart';
import '../screens/transport_screen.dart';
import '../screens/widgetstudio_screen.dart';
import '../screens/wg_screen.dart';

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
    id: 'scanner',
    stringKey: 'nav_scanner',
    art: const TileArt.svg('$_assets/ic_glyph_radar.svg'),
    tint: Ios.tileBlue,
    builder: (_) => const ScannerScreen(),
  ),
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
    id: 'wireguard',
    stringKey: 'home_wireguard',
    art: const TileArt.svg('$_assets/ic_app_wireguard.svg'),
    tint: Ios.tileGreen,
    builder: (_) => const WireGuardScreen(),
  ),
  Destination(
    id: 'warp_on_warp',
    stringKey: 'home_warp_on_warp',
    art: const TileArt.svg('$_assets/ic_glyph_layers.svg'),
    tint: Ios.tileOrange,
    builder: (_) =>
        const TransportScreen(transport: TransportId.warpOnWarp),
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
  Destination(
    id: 'geph',
    stringKey: 'home_geph',
    art: const TileArt.svg('$_assets/ic_app_geph.svg'),
    tint: Ios.tileBlue,
    builder: (_) => const GephScreen(),
  ),
  Destination(
    id: 'quick',
    stringKey: 'quick_connect',
    art: const TileArt.glyph(Icons.rocket_launch),
    tint: Ios.tileBlue,
    builder: (_) => const QuickConnectScreen(),
  ),
  Destination(
    id: 'flux',
    stringKey: 'flux_title_short',
    art: const TileArt.png('$_assets/ic_app_flux.png'),
    tint: Ios.tileIndigo,
    builder: (_) => const FluxScreen(),
  ),
  Destination(
    id: 'freeconfig',
    stringKey: 'home_freeconfig',
    art: const TileArt.glyph(Icons.cloud_download),
    tint: Ios.tileTeal,
    builder: (_) => const FreeConfigScreen(),
  ),
  Destination(
    id: 'lantern',
    stringKey: 'home_lantern',
    art: const TileArt.glyph(Icons.lightbulb_outline),
    tint: Ios.tileYellow,
    builder: (_) => const LanternScreen(),
  ),
  Destination(
    id: 'game',
    stringKey: 'home_game',
    art: const TileArt.svg('$_assets/ic_glyph_pad.svg'),
    tint: Ios.tileGreen,
    builder: (_) => const GameScreen(),
  ),
  Destination(
    id: 'store',
    stringKey: 'home_store',
    art: const TileArt.svg('$_assets/ic_app_store.svg'),
    tint: Ios.tileBlue,
    builder: (_) => const StoreScreen(),
  ),
  Destination(
    id: 'widgetstudio',
    stringKey: 'studio_home_tile',
    art: const TileArt.glyph(Icons.widgets_outlined),
    tint: Ios.tileIndigo,
    builder: (_) => const WidgetStudioScreen(),
  ),
];

Destination? destinationById(String id) {
  for (final d in kDestinations) {
    if (d.id == id) return d;
  }
  return null;
}

/// داک — ترتیب MLM: اسکنر/V2Ray/تنظیمات/ابر.
const List<String> kDockIds = ['scanner', 'nodes', 'settings', 'cloud'];

/// چیدمان پیش‌فرض برد — ترتیب MLM (HomeDestinations.kt BOARD_DEFAULT).
const List<String> kBoardDefault = [
  'masque',
  'wireguard',
  'warp_on_warp',
  'warp',
  'psiphon',
  'tor',
  'geph',
  'quick',
  'flux',
  'freeconfig',
  'lantern',
  'game',
  'store',
  'widgetstudio',
];
