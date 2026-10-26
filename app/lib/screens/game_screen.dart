import 'package:flutter/material.dart';

import '../l10n/s.dart';
import '../services/game_booster_service.dart';
import '../ui/kit/ios_kit.dart';
import '../ui/theme/ios_palette.dart';

/// Game Booster — پورت `ui/game/GameBoostScreen.kt` (نسخهٔ P2d) روی
/// موتور واقعی GameBoosterService: کاتالوگ بازی‌ها، پینگ واقعی هر بازی،
/// بوست DNS-only (GameDnsVpnService) با انتخاب رزالور.
class GameScreen extends StatefulWidget {
  const GameScreen({super.key});

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> {
  List<Map<String, dynamic>> _games = [];
  final Map<String, int?> _pings = {};
  final Set<String> _testing = {};
  bool _loading = true;
  bool _boosting = false;
  String _resolver = '1.1.1.1';
  String? _activeGame;

  static const List<(String, String)> kResolvers = [
    ('1.1.1.1', 'Cloudflare'),
    ('8.8.8.8', 'Google'),
    ('9.9.9.9', 'Quad9'),
    ('4.2.2.4', 'Level3'),
    ('178.22.122.100', 'Shecan'),
  ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final games = await GameBoosterService.listGames();
    final st = await GameBoosterService.status();
    if (!mounted) return;
    setState(() {
      _games = games;
      _loading = false;
      _boosting = st['running'] == true;
      _activeGame = st['game_package']?.toString();
    });
  }

  String _t(String fa, String en) => S.isFa ? fa : en;

  Future<void> _pingGame(Map<String, dynamic> g) async {
    final id = g['id']?.toString() ?? g['package']?.toString() ?? '';
    if (id.isEmpty || _testing.contains(id)) return;
    setState(() => _testing.add(id));
    try {
      final r = await GameBoosterService.pingGame(id);
      final ms = (r['ms'] as num?)?.toInt();
      if (mounted) setState(() => _pings[id] = ms);
    } catch (_) {
      if (mounted) setState(() => _pings[id] = -1);
    } finally {
      if (mounted) setState(() => _testing.remove(id));
    }
  }

  Future<void> _toggleBoost(Map<String, dynamic> g) async {
    lightHaptic();
    if (_boosting) {
      await GameBoosterService.stopDnsBoost();
      if (mounted) setState(() => _boosting = false);
      return;
    }
    final pkg = g['package']?.toString() ?? '';
    final r = await GameBoosterService.startDnsBoost(
      _resolver,
      secondary: _resolver == '1.1.1.1' ? '8.8.8.8' : '1.1.1.1',
    );
    final ok = r['ok'] == true;
    if (!mounted) return;
    setState(() {
      _boosting = ok;
      _activeGame = ok ? pkg : null;
    });
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        backgroundColor: IosPal.of(context).card,
        content: Text(
            r['error']?.toString() ?? _t('بوست ناموفق', 'Boost failed'),
            style: const TextStyle(color: Colors.white)),
      ));
    }
  }

  Color _pingColor(int? ms) {
    final pal = IosPal.of(context);
    if (ms == null) return pal.textDim;
    if (ms < 0) return pal.red;
    if (ms < 80) return pal.green;
    if (ms < 200) return pal.orange;
    return pal.red;
  }

  @override
  Widget build(BuildContext context) {
    final pal = IosPal.of(context);
    return IosScreen(
      title: S.t('home_game'),
      onBack: () => Navigator.pop(context),
      trailing: _boosting
          ? TextButton(
              onPressed: () async {
                await GameBoosterService.stopDnsBoost();
                if (mounted) setState(() => _boosting = false);
              },
              child: Text(_t('توقف', 'Stop'),
                  style: TextStyle(color: pal.red)),
            )
          : null,
      children: [
        const SizedBox(height: 10),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Text(
            _t(
                'پینگ واقعی هر بازی را می‌سنجد و با یک VpnService فقط-DNS، کوئری‌های DNS بازی را به سریع‌ترین رزالور می‌برد — ترافیک بازی دست‌نخورده می‌ماند.',
                'Measures real per-game ping and, with a DNS-only VpnService, steers the game\'s DNS queries to the fastest resolver — game traffic stays untouched.'),
            textAlign: TextAlign.center,
            style: TextStyle(
                color: pal.textMuted, fontSize: 13, height: 20 / 13),
          ),
        ),
        const SizedBox(height: 16),
        SettingsSectionHeader(_t('رزالور DNS', 'DNS resolver')),
        SettingsGroup(
          children: [
            SettingsRow(
              title: _t('رزالور', 'Resolver'),
              value: kResolvers
                  .firstWhere((r) => r.$1 == _resolver,
                      orElse: () => kResolvers.first)
                  .$2,
              leading: SettingsGlyph(
                  tint: Ios.tileBlue, icon: Icons.dns_outlined),
              onTap: () async {
                final v = await pushIosPicker<String>(
                  context,
                  title: _t('رزالور DNS', 'DNS resolver'),
                  selected: _resolver,
                  options: [
                    for (final r in kResolvers) IosPickerOption(r.$1, r.$2),
                  ],
                );
                if (v != null) setState(() => _resolver = v);
              },
            ),
          ],
        ),
        SettingsSectionHeader(
            _boosting
                ? _t('بوست فعال — بازی را باز کن', 'Boost active — launch the game')
                : _t('بازی‌ها', 'Games')),
        if (_loading)
          const Padding(
            padding: EdgeInsets.all(32),
            child: Center(
                child: CircularProgressIndicator(color: Colors.white)),
          )
        else if (_games.isEmpty)
          Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              _t('کاتالوگ بازی خالی است', 'No games in catalog'),
              textAlign: TextAlign.center,
              style: TextStyle(color: pal.textMuted, fontSize: 13),
            ),
          )
        else
          SettingsGroup(
            children: [
              for (final g in _games) _gameRow(context, g),
            ],
          ),
        SettingsFooter(_t(
            'برای شروع بوست روی بازی ضربه بزن؛ برای توقف، دکمهٔ توقف بالا یا همان ردیف.',
            'Tap a game to start the boost; stop with the top Stop button or the same row.')),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _gameRow(BuildContext context, Map<String, dynamic> g) {
    final pal = IosPal.of(context);
    final id = g['id']?.toString() ?? g['package']?.toString() ?? '';
    final name =
        g['name']?.toString() ?? g['title']?.toString() ?? id;
    final emoji =
        g['iconEmoji']?.toString() ?? g['emoji']?.toString() ?? '🎮';
    final testing = _testing.contains(id);
    final ping = _pings[id];
    final isActive =
        _boosting && (_activeGame == null || _activeGame == (g['package']?.toString() ?? ''));

    return SettingsRow(
      title: name,
      value: testing ? null : (ping == null ? null : '${ping}ms'),
      chevron: false,
      leading: Text(emoji, style: const TextStyle(fontSize: 20)),
      trailing: testing
          ? const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2))
          : (ping != null
              ? Text('${ping}ms',
                  textDirection: TextDirection.ltr,
                  style: TextStyle(
                      color: _pingColor(ping),
                      fontSize: 12,
                      fontWeight: FontWeight.w600))
              : (isActive
                  ? Icon(Icons.circle, size: 10, color: pal.green)
                  : null)),
      onTap: () {
        if (!_boosting) {
          _pingGame(g);
        } else {
          _toggleBoost(g);
        }
      },
      onLongPress: () => _pingGame(g),
    );
  }
}
