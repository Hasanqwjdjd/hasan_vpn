// app/lib/screens/game_hub_screen.dart
//
// Unified Game Hub: 4 tabs — DNS List · DNS Race · Games · Custom DNS.
//
// Replaces the old two-screen split (game_dns_screen.dart +
// game_booster_screen.dart). The DNS List tab embeds the existing
// GameDnsScreen(embedded: true); the other three are local widgets.
//
// Games tab enhancements vs. the old booster:
//   • Real launcher icons (loaded from listApps channel).
//   • "Open" button that launches the game (openApp channel method).
//   • Per-game region dropdown built from GameDatabase servers.
//   • Per-game "Boost this game" toggle persisted in prefs.

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/app_colors.dart';
import '../services/game_booster_service.dart';
import '../services/dns_directory.dart';
import 'game_dns_screen.dart';

class GameHubScreen extends StatefulWidget {
  final String language;
  const GameHubScreen({super.key, this.language = 'fa'});

  @override
  State<GameHubScreen> createState() => _GameHubScreenState();
}

class _GameHubScreenState extends State<GameHubScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  bool get _isFa => widget.language == 'fa';
  String _t(String fa, String en) => _isFa ? fa : en;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 4, vsync: this);
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final fg = AppColors.fg(context);
    final surface = AppColors.surface(context);
    return Scaffold(
      backgroundColor: AppColors.bg(context),
      appBar: AppBar(
        backgroundColor: surface,
        title: Text(_t('گیم بوستر / DNS', 'Game Booster / DNS'),
            style: TextStyle(color: fg, fontSize: 16)),
        iconTheme: IconThemeData(color: fg),
        bottom: TabBar(
          controller: _tabs,
          isScrollable: true,
          labelColor: AppColors.accent,
          unselectedLabelColor: AppColors.muted(context),
          tabs: [
            Tab(text: _t('لیست DNS', 'DNS List')),
            Tab(text: _t('رقابت DNS', 'DNS Race')),
            Tab(text: _t('بازی‌ها', 'Games')),
            Tab(text: _t('DNS سفارشی', 'Custom DNS')),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: [
          GameDnsScreen(language: widget.language, embedded: true),
          _DnsRaceTab(language: widget.language),
          _GamesTab(language: widget.language),
          _CustomDnsTab(language: widget.language),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════
// DNS Race
// ══════════════════════════════════════════════════════════════════

class _DnsRaceTab extends StatefulWidget {
  final String language;
  const _DnsRaceTab({required this.language});
  @override
  State<_DnsRaceTab> createState() => _DnsRaceTabState();
}

class _DnsRaceTabState extends State<_DnsRaceTab>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  bool _racing = false;
  bool _boosting = false;
  String? _error;
  List<Map<String, dynamic>> _results = [];
  Map<String, dynamic>? _winner;
  String? _activeResolver;

  bool get _isFa => widget.language == 'fa';
  String _t(String fa, String en) => _isFa ? fa : en;

  @override
  void initState() {
    super.initState();
    _refreshStatus();
  }

  Future<void> _refreshStatus() async {
    final s = await GameBoosterService.status();
    if (!mounted) return;
    setState(() {
      _boosting = s['running'] == true;
      _activeResolver = s['resolver']?.toString();
    });
  }

  Future<void> _race() async {
    if (_racing) return;
    setState(() {
      _racing = true;
      _error = null;
      _results = [];
      _winner = null;
    });
    // Collect all primary IPv4 addresses from the on-device DNS
    // directory and hand them to the native race. This is why the
    // race previously only showed Electro: the built-in Kotlin list
    // contains a handful of resolvers and everything else was ignored.
    final extra = <String>{};
    for (final e in kAllDnsEntries) {
      final p = e.primary;
      if (p != null && p.contains('.') && !p.contains(':')) {
        extra.add(p);
      }
    }
    final r = await GameBoosterService.raceDns(
      extraIps: extra.toList(),
    );
    if (!mounted) return;
    setState(() {
      _racing = false;
      if (r['ok'] == true) {
        final list = r['results'];
        if (list is List) {
          _results =
              list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
        }
        if (r['winner'] is Map) {
          _winner = Map<String, dynamic>.from(r['winner'] as Map);
        }
      } else {
        _error = r['error']?.toString() ?? _t('رقابت ناموفق', 'Race failed');
      }
    });
  }

  Future<void> _startBoost(String ip) async {
    final r = await GameBoosterService.startDnsBoost(ip);
    if (!mounted) return;
    if (r['ok'] == true) {
      setState(() {
        _boosting = true;
        _activeResolver = ip;
      });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(_t('DNS Boost فعال شد: $ip', 'DNS Boost on: $ip')),
        backgroundColor: const Color(0xFF2E7D32),
      ));
    } else {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(r['error']?.toString() ?? 'error'),
        backgroundColor: Colors.redAccent,
      ));
    }
  }

  Future<void> _stopBoost() async {
    await GameBoosterService.stopDnsBoost();
    if (!mounted) return;
    setState(() {
      _boosting = false;
      _activeResolver = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // Required by AutomaticKeepAliveClientMixin
    final fg = AppColors.fg(context);
    final muted = AppColors.muted(context);
    final surface = AppColors.surface(context);
    final accent = AppColors.accent;

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        if (_boosting)
          Card(
            color: accent.withValues(alpha: 0.15),
            child: ListTile(
              leading: Icon(Icons.bolt, color: accent),
              title: Text(
                _t('بوست فعال: $_activeResolver',
                    'Boost active: $_activeResolver'),
                style: TextStyle(color: fg, fontSize: 13),
              ),
              trailing: TextButton(
                onPressed: _stopBoost,
                child: Text(_t('توقف', 'Stop'),
                    style: const TextStyle(color: Colors.redAccent)),
              ),
            ),
          ),
        const SizedBox(height: 8),
        ElevatedButton.icon(
          onPressed: _racing ? null : _race,
          icon: _racing
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white))
              : const Icon(Icons.speed, size: 18),
          label: Text(_t('شروع رقابت DNS', 'Start DNS Race')),
          style: ElevatedButton.styleFrom(
              backgroundColor: accent, foregroundColor: Colors.white),
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(_error!,
                style: const TextStyle(color: Colors.redAccent, fontSize: 12)),
          ),
        if (_winner != null) ...[
          const SizedBox(height: 12),
          Text(_t('برنده', 'Winner'),
              style: TextStyle(color: muted, fontSize: 12)),
          Card(
            color: surface,
            child: ListTile(
              title: Text(
                '${_winner!['name'] ?? ''} · ${_winner!['ip']}',
                style: TextStyle(color: fg, fontSize: 13),
              ),
              subtitle: Text(
                '${_winner!['latencyMs']} ms',
                style: TextStyle(color: muted, fontSize: 11),
              ),
              trailing: TextButton(
                onPressed: () => _startBoost(_winner!['ip'].toString()),
                child: Text(_t('اعمال', 'Apply'),
                    style: TextStyle(color: accent)),
              ),
            ),
          ),
        ],
        const SizedBox(height: 8),
        ..._results.map((r) {
          final ip = r['ip']?.toString() ?? '';
          final name = r['name']?.toString() ?? '';
          final ms = r['latencyMs'];
          final cat = r['category']?.toString() ?? '';
          return Card(
            color: surface,
            margin: const EdgeInsets.only(bottom: 6),
            child: ListTile(
              dense: true,
              title: Text('$name · $ip',
                  style: TextStyle(color: fg, fontSize: 12)),
              subtitle: Text('$cat · ${ms ?? '-'} ms',
                  style: TextStyle(color: muted, fontSize: 11)),
              trailing: IconButton(
                icon: Icon(Icons.bolt, color: accent, size: 20),
                onPressed: () => _startBoost(ip),
              ),
            ),
          );
        }),
      ],
    );
  }
}

// ══════════════════════════════════════════════════════════════════
// Games (enhanced)
// ══════════════════════════════════════════════════════════════════

class _GamesTab extends StatefulWidget {
  final String language;
  const _GamesTab({required this.language});
  @override
  State<_GamesTab> createState() => _GamesTabState();
}

class _GamesTabState extends State<_GamesTab>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  static const _deviceChannel = MethodChannel('com.hasan.hasan_vpn/device');

  bool _loading = true;
  List<Map<String, dynamic>> _games = [];
  final Map<String, Map<String, dynamic>> _pings = {};
  final Map<String, String> _selectedRegion = {}; // game id → region
  final Map<String, bool> _boosted = {}; // game id → boost
  final Map<String, Uint8List> _iconCache = {}; // package → icon bytes
  final Set<String> _installed = {}; // installed packages

  bool get _isFa => widget.language == 'fa';
  String _t(String fa, String en) => _isFa ? fa : en;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final list = await GameBoosterService.listGames();
    final apps = await _loadInstalledApps();
    final prefs = await SharedPreferences.getInstance();
    final regions = <String, String>{};
    final boosted = <String, bool>{};
    for (final g in list) {
      final id = g['id']?.toString() ?? '';
      if (id.isEmpty) continue;
      regions[id] = prefs.getString('game_region_$id') ?? '';
      boosted[id] = prefs.getBool('game_boost_$id') ?? false;
    }
    if (!mounted) return;
    setState(() {
      _games = list;
      _iconCache.addAll(apps.icons);
      _installed.addAll(apps.installed);
      _selectedRegion.addAll(regions);
      _boosted.addAll(boosted);
      _loading = false;
    });
  }

  Future<({Map<String, Uint8List> icons, Set<String> installed})>
      _loadInstalledApps() async {
    // Icon extraction + base64 encoding on the native side is slow
    // (~1-2 s for a phone with 200+ apps). Cache the result for 6
    // hours; on subsequent opens the games tab paints instantly.
    const cacheKey = 'game_hub_icons_v1';
    const installedKey = 'game_hub_installed_v1';
    const stampKey = 'game_hub_icons_stamp_v1';
    const ttl = Duration(hours: 6);
    try {
      final prefs = await SharedPreferences.getInstance();
      final stampStr = prefs.getString(stampKey);
      if (stampStr != null) {
        final stamp = DateTime.tryParse(stampStr);
        if (stamp != null &&
            DateTime.now().difference(stamp) < ttl) {
          final cached = prefs.getString(cacheKey);
          final installedList = prefs.getStringList(installedKey);
          if (cached != null && installedList != null) {
            final decoded = jsonDecode(cached) as Map;
            final icons = <String, Uint8List>{};
            decoded.forEach((k, v) {
              try {
                icons[k.toString()] = base64Decode(v.toString());
              } catch (_) {}
            });
            return (icons: icons, installed: installedList.toSet());
          }
        }
      }
    } catch (_) {}

    try {
      final raw = await _deviceChannel.invokeMethod<List<dynamic>>('listApps');
      final icons = <String, Uint8List>{};
      final installed = <String>{};
      if (raw != null) {
        for (final e in raw) {
          if (e is! Map) continue;
          final pkg = e['package']?.toString() ?? '';
          if (pkg.isEmpty) continue;
          installed.add(pkg);
          final b64 = e['icon']?.toString() ?? '';
          if (b64.isNotEmpty) {
            try {
              icons[pkg] = base64Decode(b64);
            } catch (_) {}
          }
        }
      }
      // Persist for next open.
      try {
        final prefs = await SharedPreferences.getInstance();
        final enc = <String, String>{};
        icons.forEach((k, v) {
          try {
            enc[k] = base64Encode(v);
          } catch (_) {}
        });
        await prefs.setString(cacheKey, jsonEncode(enc));
        await prefs.setStringList(installedKey, installed.toList());
        await prefs.setString(stampKey, DateTime.now().toIso8601String());
      } catch (_) {}
      return (icons: icons, installed: installed);
    } catch (_) {
      return (icons: <String, Uint8List>{}, installed: <String>{});
    }
  }

  Future<void> _ping(String id, String? region) async {
    setState(() => _pings[id] = {'status': 'testing'});
    final r = await GameBoosterService.pingGame(id, region: region);
    if (!mounted) return;
    setState(() => _pings[id] = r);
  }

  Future<void> _openGame(String pkg) async {
    try {
      await _deviceChannel
          .invokeMethod<bool>('openApp', {'package': pkg});
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(_t('باز کردن ناموفق', 'Could not launch')),
        backgroundColor: Colors.redAccent,
      ));
    }
  }

  Future<void> _toggleBoost(String id, bool v) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('game_boost_$id', v);
    if (!mounted) return;
    setState(() => _boosted[id] = v);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(v
          ? _t('این بازی به حالت بوست اضافه شد',
              'Game added to Boost mode')
          : _t('این بازی از حالت بوست حذف شد',
              'Game removed from Boost mode')),
      duration: const Duration(seconds: 1),
    ));
  }

  Future<void> _setRegion(String id, String region) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('game_region_$id', region);
    if (!mounted) return;
    setState(() => _selectedRegion[id] = region);
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // Required by AutomaticKeepAliveClientMixin
    final fg = AppColors.fg(context);
    final muted = AppColors.muted(context);
    final surface = AppColors.surface(context);
    final accent = AppColors.accent;

    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_games.isEmpty) {
      return Center(
        child: Text(_t('لیست بازی خالی است', 'No games'),
            style: TextStyle(color: muted)),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: _games.length,
      itemBuilder: (_, i) {
        final g = _games[i];
        final id = g['id']?.toString() ?? '';
        final pkg = g['packageName']?.toString() ?? '';
        final installed = _installed.contains(pkg);
        final iconBytes = _iconCache[pkg];
        final emoji = g['iconEmoji']?.toString() ?? '🎮';
        final category = g['category']?.toString() ?? '';
        final boost = _boosted[id] == true;
        final ping = _pings[id];

        final regions = (g['regions'] is List)
            ? (g['regions'] as List)
                .map((e) => Map<String, dynamic>.from(e as Map))
                .toList()
            : <Map<String, dynamic>>[];
        final regionIds = regions
            .map((r) => r['region']?.toString() ?? '')
            .where((s) => s.isNotEmpty)
            .toList();
        final selectedRegion = _selectedRegion[id]?.isNotEmpty == true
            ? _selectedRegion[id]!
            : (regionIds.isNotEmpty ? regionIds.first : '');

        String pingLabel = '';
        Color pingColor = muted;
        if (ping != null) {
          if (ping['status'] == 'testing') {
            pingLabel = '...';
          } else if (ping['ok'] == true) {
            final ms = ping['pingMs'];
            pingLabel = '$ms ms';
            if (ms is int) {
              pingColor = ms < 80
                  ? const Color(0xFF3DCF9A)
                  : (ms < 200
                      ? const Color(0xFFFFB74D)
                      : const Color(0xFFE07070));
            }
          } else {
            pingLabel = 'fail';
            pingColor = AppColors.danger;
          }
        }

        return Card(
          color: surface,
          margin: const EdgeInsets.only(bottom: 8),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 10, 10, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: SizedBox(
                        width: 40,
                        height: 40,
                        child: iconBytes != null
                            ? Image.memory(iconBytes,
                                fit: BoxFit.cover,
                                gaplessPlayback: true)
                            : Container(
                                color: accent.withValues(alpha: 0.15),
                                alignment: Alignment.center,
                                child: Text(emoji,
                                    style: const TextStyle(fontSize: 20)),
                              ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  g['name']?.toString() ?? id,
                                  style: TextStyle(
                                      color: fg,
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              if (boost)
                                Padding(
                                  padding: const EdgeInsets.only(left: 4),
                                  child: Icon(Icons.local_fire_department,
                                      color: accent, size: 18),
                                ),
                            ],
                          ),
                          const SizedBox(height: 2),
                          Text(
                            installed
                                ? _t('نصب‌شده', 'Installed')
                                : _t('نصب نشده', 'Not installed'),
                            style: TextStyle(
                              color: installed ? accent : muted,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (pingLabel.isNotEmpty)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: pingColor.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          pingLabel,
                          style: TextStyle(
                              color: pingColor,
                              fontSize: 11,
                              fontWeight: FontWeight.w700),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                if (regionIds.isNotEmpty)
                  Row(
                    children: [
                      Icon(Icons.public, size: 14, color: muted),
                      const SizedBox(width: 6),
                      Text(_t('منطقه:', 'Region:'),
                          style: TextStyle(color: muted, fontSize: 11)),
                      const SizedBox(width: 6),
                      Expanded(
                        child: DropdownButton<String>(
                          value: selectedRegion.isEmpty
                              ? null
                              : selectedRegion,
                          isExpanded: true,
                          isDense: true,
                          dropdownColor: surface,
                          style:
                              TextStyle(color: fg, fontSize: 12),
                          underline: const SizedBox.shrink(),
                          items: regions.map((r) {
                            final rid = r['region']?.toString() ?? '';
                            final dn = r['displayName']?.toString() ?? rid;
                            return DropdownMenuItem<String>(
                              value: rid,
                              child: Text('$dn ($rid)',
                                  style: TextStyle(
                                      color: fg, fontSize: 12)),
                            );
                          }).toList(),
                          onChanged: (v) {
                            if (v == null) return;
                            _setRegion(id, v);
                          },
                        ),
                      ),
                    ],
                  ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _ping(id, selectedRegion),
                        icon: const Icon(Icons.speed, size: 16),
                        label: Text(_t('پینگ', 'Ping'),
                            style: const TextStyle(fontSize: 12)),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: accent,
                          side: BorderSide(
                              color: accent.withValues(alpha: 0.6)),
                          padding:
                              const EdgeInsets.symmetric(vertical: 6),
                        ),
                      ),
                    ),
                    if (installed) ...[
                      const SizedBox(width: 6),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => _openGame(pkg),
                          icon: const Icon(Icons.open_in_new, size: 16),
                          label: Text(_t('باز کردن', 'Open'),
                              style: const TextStyle(fontSize: 12)),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: fg,
                            side: BorderSide(
                                color: AppColors.border(context)),
                            padding:
                                const EdgeInsets.symmetric(vertical: 6),
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(width: 6),
                    IconButton(
                      tooltip: boost
                          ? _t('حذف از بوست', 'Remove from boost')
                          : _t('افزودن به بوست', 'Add to boost'),
                      onPressed: () => _toggleBoost(id, !boost),
                      icon: Icon(
                        boost
                            ? Icons.local_fire_department
                            : Icons.local_fire_department_outlined,
                        color: boost ? accent : muted,
                        size: 22,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

// ══════════════════════════════════════════════════════════════════
// Custom DNS
// ══════════════════════════════════════════════════════════════════

class _CustomDnsTab extends StatefulWidget {
  final String language;
  const _CustomDnsTab({required this.language});
  @override
  State<_CustomDnsTab> createState() => _CustomDnsTabState();
}

class _CustomDnsTabState extends State<_CustomDnsTab>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  final _primaryCtrl = TextEditingController(text: '8.8.8.8');
  final _secondaryCtrl = TextEditingController(text: '1.1.1.1');
  bool _busy = false;

  bool get _isFa => widget.language == 'fa';
  String _t(String fa, String en) => _isFa ? fa : en;

  @override
  void dispose() {
    _primaryCtrl.dispose();
    _secondaryCtrl.dispose();
    super.dispose();
  }

  Future<void> _apply() async {
    final p = _primaryCtrl.text.trim();
    if (p.isEmpty) return;
    setState(() => _busy = true);
    final r = await GameBoosterService.startDnsBoost(
      p,
      secondary: _secondaryCtrl.text.trim().isEmpty
          ? null
          : _secondaryCtrl.text.trim(),
    );
    if (!mounted) return;
    setState(() => _busy = false);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(r['ok'] == true
          ? _t('اعمال شد', 'Applied')
          : (r['error']?.toString() ?? 'error')),
      backgroundColor:
          r['ok'] == true ? const Color(0xFF2E7D32) : Colors.redAccent,
    ));
  }

  Future<void> _stop() async {
    await GameBoosterService.stopDnsBoost();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(_t('بوست متوقف شد', 'Boost stopped')),
    ));
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // Required by AutomaticKeepAliveClientMixin
    final fg = AppColors.fg(context);
    final muted = AppColors.muted(context);
    final surface = AppColors.surface(context);
    final accent = AppColors.accent;

    InputDecoration deco(String label) => InputDecoration(
          labelText: label,
          labelStyle: TextStyle(color: muted),
          filled: true,
          fillColor: surface,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        );

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          _t(
            'DNS اصلی و فرعی را وارد کنید و بوست را فعال کنید.',
            'Enter primary/secondary DNS and start boost.',
          ),
          style: TextStyle(color: muted, fontSize: 12),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _primaryCtrl,
          style: TextStyle(color: fg, fontFamily: 'monospace'),
          decoration: deco(_t('DNS اصلی', 'Primary DNS')),
          keyboardType: TextInputType.number,
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _secondaryCtrl,
          style: TextStyle(color: fg, fontFamily: 'monospace'),
          decoration: deco(_t('DNS فرعی (اختیاری)', 'Secondary (optional)')),
          keyboardType: TextInputType.number,
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: ElevatedButton(
                onPressed: _busy ? null : _apply,
                style: ElevatedButton.styleFrom(
                    backgroundColor: accent, foregroundColor: Colors.white),
                child: Text(_t('اعمال بوست', 'Apply boost')),
              ),
            ),
            const SizedBox(width: 10),
            OutlinedButton(
              onPressed: _stop,
              child: Text(_t('توقف', 'Stop')),
            ),
          ],
        ),
      ],
    );
  }
}
