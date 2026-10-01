import 'package:flutter/material.dart';

import '../services/app_colors.dart';
import '../services/game_booster_service.dart';

/// Game Booster — three tabs: DNS Race · Games · Custom DNS
class GameBoosterScreen extends StatefulWidget {
  final String language;
  const GameBoosterScreen({super.key, this.language = 'fa'});

  @override
  State<GameBoosterScreen> createState() => _GameBoosterScreenState();
}

class _GameBoosterScreenState extends State<GameBoosterScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;

  bool get _isFa => widget.language == 'fa';
  String _t(String fa, String en) => _isFa ? fa : en;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this);
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
          labelColor: AppColors.accent,
          unselectedLabelColor: AppColors.muted(context),
          tabs: [
            Tab(text: _t('رقابت DNS', 'DNS Race')),
            Tab(text: _t('بازی‌ها', 'Games')),
            Tab(text: _t('DNS سفارشی', 'Custom DNS')),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: [
          _DnsRaceTab(language: widget.language),
          _GamesTab(language: widget.language),
          _CustomDnsTab(language: widget.language),
        ],
      ),
    );
  }
}

class _DnsRaceTab extends StatefulWidget {
  final String language;
  const _DnsRaceTab({required this.language});
  @override
  State<_DnsRaceTab> createState() => _DnsRaceTabState();
}

class _DnsRaceTabState extends State<_DnsRaceTab> {
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
    final r = await GameBoosterService.raceDns();
    if (!mounted) return;
    setState(() {
      _racing = false;
      if (r['ok'] == true) {
        final list = r['results'];
        if (list is List) {
          _results = list
              .map((e) => Map<String, dynamic>.from(e as Map))
              .toList();
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
    final fg = AppColors.fg(context);
    final muted = AppColors.muted(context);
    final surface = AppColors.surface(context);
    final accent = AppColors.accent;

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        if (_boosting)
          Card(
            color: accent.withOpacity(0.15),
            child: ListTile(
              leading: Icon(Icons.bolt, color: accent),
              title: Text(
                _t('بوست فعال: $_activeResolver', 'Boost active: $_activeResolver'),
                style: TextStyle(color: fg, fontSize: 13),
              ),
              trailing: TextButton(
                onPressed: _stopBoost,
                child: Text(_t('توقف', 'Stop'),
                    style: TextStyle(color: Colors.redAccent)),
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

class _GamesTab extends StatefulWidget {
  final String language;
  const _GamesTab({required this.language});
  @override
  State<_GamesTab> createState() => _GamesTabState();
}

class _GamesTabState extends State<_GamesTab> {
  bool _loading = true;
  List<Map<String, dynamic>> _games = [];
  final Map<String, Map<String, dynamic>> _pings = {};

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
    if (!mounted) return;
    setState(() {
      _games = list;
      _loading = false;
    });
  }

  Future<void> _ping(String id) async {
    setState(() => _pings[id] = {'status': 'testing'});
    final r = await GameBoosterService.pingGame(id);
    if (!mounted) return;
    setState(() => _pings[id] = r);
  }

  @override
  Widget build(BuildContext context) {
    final fg = AppColors.fg(context);
    final muted = AppColors.muted(context);
    final surface = AppColors.surface(context);

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
        final installed = g['installed'] == true;
        final ping = _pings[id];
        String pingLabel = '';
        if (ping != null) {
          if (ping['status'] == 'testing') {
            pingLabel = '...';
          } else if (ping['ok'] == true) {
            pingLabel = '${ping['pingMs']} ms';
          } else {
            pingLabel = 'fail';
          }
        }
        return Card(
          color: surface,
          margin: const EdgeInsets.only(bottom: 6),
          child: ListTile(
            leading: Text(g['iconEmoji']?.toString() ?? '🎮',
                style: const TextStyle(fontSize: 22)),
            title: Text(g['name']?.toString() ?? id,
                style: TextStyle(color: fg, fontSize: 13)),
            subtitle: Text(
              installed
                  ? _t('نصب‌شده', 'Installed')
                  : (g['category']?.toString() ?? ''),
              style: TextStyle(
                color: installed ? AppColors.accent : muted,
                fontSize: 11,
              ),
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (pingLabel.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: Text(pingLabel,
                        style: TextStyle(color: muted, fontSize: 11)),
                  ),
                IconButton(
                  icon: const Icon(Icons.speed, size: 18),
                  onPressed: () => _ping(id),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _CustomDnsTab extends StatefulWidget {
  final String language;
  const _CustomDnsTab({required this.language});
  @override
  State<_CustomDnsTab> createState() => _CustomDnsTabState();
}

class _CustomDnsTabState extends State<_CustomDnsTab> {
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
