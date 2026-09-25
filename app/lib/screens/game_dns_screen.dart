// app/lib/screens/game_dns_screen.dart
//
// Phase (d) rewrite. Built against the new DnsEntry / DnsRegistryService
// / DnsPingService (dns_directory.dart, dns_registry_service.dart,
// dns_ping_service.dart) instead of the old flat GameDns list + naive
// TCP-connect prober.
//
// Kept from the old screen: the `language` param + `_t(fa, en)` helper
// convention, AppColors usage, and writing the chosen DNS into
// SettingsService.setGameDns() so v2ray_engine.dart's existing read
// path keeps working unchanged (see phase (f) notes in the PR).
//
// Simplified vs. the 1374-line original: the Game Booster panel is
// still here but compact (same GameBoosterSettings backing store); the
// old manual drag-reorder list and the QR import screen were dropped
// in favor of copy/paste JSON import-export (Goal 3.6) to keep this
// file a reasonable size — flag if you want drag-reorder back.

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/services.dart';

import '../models/dns_entry.dart';
import '../services/app_colors.dart';
import '../services/dns_directory.dart';
import '../services/dns_ping_service.dart';
import '../services/dns_registry_service.dart';
import '../services/game_booster_settings.dart';
import '../services/settings_service.dart';
import 'qr_scan_screen.dart';

enum _SortMode { ping, name, country, provider, jitter }

enum _Category { all, pinned, recommended, adBlocking, family, dnssec, ipv6, myCountry, hidden }

class GameDnsScreen extends StatefulWidget {
  final String language;
  const GameDnsScreen({super.key, this.language = 'fa'});

  @override
  State<GameDnsScreen> createState() => _GameDnsScreenState();
}

class _GameDnsScreenState extends State<GameDnsScreen> {
  final _registry = DnsRegistryService.instance;
  final _pinger = DnsPingService.instance;

  late final DnsDirectoryIndex _index;
  Map<String, DnsStats> _stats = {};
  List<CustomDnsEntry> _custom = [];

  String _myCountry = 'IR';
  String _searchQuery = '';
  final _searchController = TextEditingController();
  bool _showSearch = false;

  _Category _category = _Category.all;
  _SortMode _sortMode = _SortMode.ping;

  String? _activeId;
  List<String> _manualOrder = <String>[];
  bool _testingAll = false;
  int _tested = 0;
  int _total = 0;
  final Map<String, PingResult> _liveResults = {};

  bool _boosterExpanded = false;
  Map<String, dynamic> _booster = Map<String, dynamic>.from(GameBoosterSettings.defaults);

  @override
  void initState() {
    super.initState();
    _index = DnsDirectoryIndex.build();
    _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  String _t(String fa, String en) => widget.language == 'fa' ? fa : en;

  Future<void> _load() async {
    final stats = await _registry.loadStats();
    final custom = await _registry.loadCustom();
    final activeId = await _registry.getActiveId();
    final booster = await GameBoosterSettings.load();
    final prefs = await SharedPreferences.getInstance();
    final order = prefs.getStringList('dns_manual_order_v1') ?? <String>[];
    if (!mounted) return;
    setState(() {
      _stats = stats;
      _custom = custom;
      _activeId = activeId;
      _booster = booster;
      _manualOrder = order;
    });
  }

  Future<void> _saveManualOrder(List<String> order) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('dns_manual_order_v1', order);
    if (mounted) setState(() => _manualOrder = order);
  }

  // ---------------------------------------------------------- Data helpers

  DnsEntry _customAsEntry(CustomDnsEntry c) => DnsEntry(
        id: c.id,
        name: '📌 ${c.name}',
        primary: c.primary,
        secondary: c.secondary,
        primaryV6: c.primaryV6,
        secondaryV6: c.secondaryV6,
        dohUrl: c.dohUrl,
        dotHost: c.dotHost,
        country: 'XX',
        provider: 'Custom',
        tags: const {},
        protocols: {c.protocol},
        source: 'User-added',
      );

  List<DnsEntry> get _allEntries => [
        ..._custom.map(_customAsEntry),
        ...kAllDnsEntries,
      ];

  DnsStats _statFor(String id) => _stats[id] ?? DnsStats();

  int? _liveOrStoredPing(String id) => _liveResults[id]?.medianMs ?? _statFor(id).lastPingMs;
  int? _liveOrStoredJitter(String id) => _liveResults[id]?.jitterMs ?? _statFor(id).lastJitterMs;

  String _stabilityOf(String id) {
    final r = _liveResults[id];
    if (r != null) return r.stability;
    return _statFor(id).stability;
  }

  Color _stabilityColor(String stability) {
    switch (stability) {
      case 'green':
        return Colors.greenAccent.shade400;
      case 'yellow':
        return Colors.amberAccent.shade400;
      case 'red':
        return AppColors.danger;
      default:
        return AppColors.muted2(context);
    }
  }

  List<DnsEntry> get _visibleEntries {
    final showHidden = _category == _Category.hidden;
    var list = _allEntries.where((e) {
      final stat = _statFor(e.id);
      if (stat.deleted) return false;
      return showHidden ? stat.hidden : !stat.hidden;
    }).toList();

    switch (_category) {
      case _Category.all:
      case _Category.hidden:
        break;
      case _Category.pinned:
        list = list.where((e) => _statFor(e.id).pinned).toList();
        break;
      case _Category.recommended:
        list = list.where((e) => e.country == _myCountry || e.tags.contains(DnsTag.anycast)).toList();
        break;
      case _Category.adBlocking:
        list = list.where((e) => e.tags.contains(DnsTag.blocking)).toList();
        break;
      case _Category.family:
        list = list.where((e) => e.tags.contains(DnsTag.family)).toList();
        break;
      case _Category.dnssec:
        list = list.where((e) => e.tags.contains(DnsTag.dnssec)).toList();
        break;
      case _Category.ipv6:
        list = list.where((e) => e.hasV6).toList();
        break;
      case _Category.myCountry:
        list = list.where((e) => e.country == _myCountry).toList();
        break;
    }

    // مرتب‌سازی بر اساس _manualOrder
    if (_manualOrder.isNotEmpty) {
      final pos = <String, int>{};
      for (var i = 0; i < _manualOrder.length; i++) {
        pos[_manualOrder[i]] = i;
      }
      list.sort((a, b) {
        final ai = pos[a.id] ?? 9999999;
        final bi = pos[b.id] ?? 9999999;
        if (ai != bi) return ai.compareTo(bi);
        return 0;
      });
    }

    if (_searchQuery.trim().isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      list = list
          .where((e) =>
              e.name.toLowerCase().contains(q) ||
              e.provider.toLowerCase().contains(q) ||
              e.country.toLowerCase().contains(q) ||
              (e.primary?.contains(q) ?? false) ||
              (e.primaryV6?.toLowerCase().contains(q) ?? false))
          .toList();
    }

    switch (_sortMode) {
      case _SortMode.ping:
        list.sort((a, b) {
          final pa = _liveOrStoredPing(a.id);
          final pb = _liveOrStoredPing(b.id);
          if (pa == null && pb == null) return a.name.compareTo(b.name);
          if (pa == null) return 1;
          if (pb == null) return -1;
          return pa.compareTo(pb);
        });
        break;
      case _SortMode.name:
        list.sort((a, b) => a.name.compareTo(b.name));
        break;
      case _SortMode.country:
        list.sort((a, b) => a.country.compareTo(b.country));
        break;
      case _SortMode.provider:
        list.sort((a, b) => a.provider.compareTo(b.provider));
        break;
      case _SortMode.jitter:
        list.sort((a, b) {
          final ja = _liveOrStoredJitter(a.id);
          final jb = _liveOrStoredJitter(b.id);
          if (ja == null && jb == null) return 0;
          if (ja == null) return 1;
          if (jb == null) return -1;
          return ja.compareTo(jb);
        });
        break;
    }

    // Pinned entries always float to the top, within whatever sort was chosen.
    list.sort((a, b) {
      final pa = _statFor(a.id).pinned;
      final pb = _statFor(b.id).pinned;
      if (pa == pb) return 0;
      return pa ? -1 : 1;
    });

    return list;
  }

  DnsEntry? get _activeEntry {
    if (_activeId == null) return null;
    try {
      return _allEntries.firstWhere((e) => e.id == _activeId);
    } catch (_) {
      return null;
    }
  }

  // ---------------------------------------------------------- Actions

  Future<void> _setActive(DnsEntry e) async {
    await SettingsService.setGameDns(e.xrayPrimary, e.xraySecondary ?? e.xrayPrimary);
    await _registry.setActiveId(e.id);
    if (!mounted) return;
    setState(() => _activeId = e.id);
    _toast(_t('تنظیم شد: ${e.name}', 'Set active: ${e.name}'));
  }

  Future<void> _clearActive() async {
    await SettingsService.clearGameDns();
    await _registry.clearActiveId();
    if (!mounted) return;
    setState(() => _activeId = null);
    _toast(_t('DNS غیرفعال شد', 'DNS disabled'));
  }

  Future<void> _togglePin(DnsEntry e) async {
    final cur = _statFor(e.id).pinned;
    await _registry.setPinned(e.id, !cur);
    await _load();
  }

  Future<void> _hide(DnsEntry e) async {
    await _registry.setHidden(e.id, true);
    await _load();
  }

  Future<void> _unhide(DnsEntry e) async {
    await _registry.setHidden(e.id, false);
    await _load();
  }

  Future<void> _importFromQr() async {
    final result = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => QrScanScreen(language: widget.language),
      ),
    );
    if (result == null || result.isEmpty || !mounted) return;
    final trimmed = result.trim();
    try {
      // JSON blob (single or full registry)
      if (trimmed.startsWith('{') || trimmed.startsWith('[')) {
        await _registry.importJson(trimmed, merge: true);
        await _load();
        _toast(_t('از QR وارد شد', 'Imported from QR'));
        return;
      }
      // plain: name,primary,secondary یا فقط IP
      final parts = trimmed.split(',').map((e) => e.trim()).toList();
      if (parts.length == 1 && parts[0].isNotEmpty) {
        await _registry.addCustom(CustomDnsEntry(
          id: 'qr_${DateTime.now().millisecondsSinceEpoch}',
          name: parts[0],
          primary: parts[0],
          secondary: parts[0],
        ));
      } else if (parts.length >= 2) {
        await _registry.addCustom(CustomDnsEntry(
          id: 'qr_${DateTime.now().millisecondsSinceEpoch}',
          name: parts[0].isNotEmpty ? parts[0] : parts[1],
          primary: parts[1],
          secondary: parts.length > 2 ? parts[2] : parts[1],
        ));
      } else {
        _toast(_t('محتوای QR قابل خواندن نبود', 'QR content not understood'));
        return;
      }
      await _load();
      _toast(_t('از QR وارد شد', 'Imported from QR'));
    } catch (e) {
      _toast(_t('خطا در ورود QR: $e', 'QR import error: $e'));
    }
  }

  Future<void> _delete(DnsEntry e) async {
    if (e.provider == 'Custom') {
      await _registry.removeCustom(e.id);
    } else {
      await _registry.setDeleted(e.id, true);
    }
    await _load();
    _toast(_t('حذف شد', 'Deleted'));
  }

  Future<void> _copyIp(DnsEntry e) async {
    final text = e.primary ?? e.primaryV6 ?? e.dohUrl ?? '';
    await Clipboard.setData(ClipboardData(text: text));
    _toast(_t('کپی شد', 'Copied'));
  }

  Future<void> _pingOne(DnsEntry e) async {
    _toast(_t('در حال پینگ...', 'Pinging...'));
    final r = await _pinger.pingEntry(e, samples: 5);
    await _registry.recordPing(e.id, medianMs: r.medianMs, jitterMs: r.jitterMs, succeeded: r.isReachable);
    if (!mounted) return;
    setState(() => _liveResults[e.id] = r);
    _toast(r.isReachable
        ? _t('پینگ: ${r.medianMs}ms (jitter ${r.jitterMs}ms)', 'Ping: ${r.medianMs}ms (jitter ${r.jitterMs}ms)')
        : _t('پاسخ نداد', 'No response'));
  }

  Future<void> _pingAllVisible() async {
    if (_testingAll) return;
    final list = _visibleEntries;
    if (list.isEmpty) return;
    setState(() {
      _testingAll = true;
      _tested = 0;
      _total = list.length;
    });

    final results = await _pinger.pingBatch(
      list,
      samples: 3,
      concurrency: 12,
      onProgress: (done, total) {
        if (!mounted) return;
        setState(() => _tested = done);
      },
    );

    for (final entry in results.entries) {
      final r = entry.value;
      await _registry.recordPing(entry.key, medianMs: r.medianMs, jitterMs: r.jitterMs, succeeded: r.isReachable);
    }

    if (!mounted) return;
    setState(() {
      _liveResults.addAll(results);
      _testingAll = false;
    });
    final ok = results.values.where((r) => r.isReachable).length;
    _toast(_t('$ok از $_total پاسخ دادند', '$ok of $_total responded'));
  }

  /// "انتخاب بهترین خودکار": pings the Recommended bucket (my country +
  /// anycast) and switches to the lowest-jitter of the 3 fastest.
  Future<void> _autoSelectBest() async {
    final candidates = _allEntries
        .where((e) => (e.country == _myCountry || e.tags.contains(DnsTag.anycast)) && !_statFor(e.id).hidden)
        .take(40) // cap so this stays snappy even with 250+ entries
        .toList();
    if (candidates.isEmpty) return;
    _toast(_t('در حال یافتن بهترین DNS...', 'Finding the best DNS...'));
    final best = await _pinger.autoSelectBest(candidates, samples: 5);
    if (best == null) {
      _toast(_t('هیچ‌کدام پاسخ ندادند', 'None responded'));
      return;
    }
    await _setActive(best);
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), duration: const Duration(seconds: 2)));
  }

  Future<void> _exportRegistry() async {
    final json = await _registry.exportJson();
    await Clipboard.setData(ClipboardData(text: json));
    _toast(_t('رجیستری در کلیپ‌بورد کپی شد', 'Registry copied to clipboard'));
  }

  Future<void> _importRegistry() async {
    final data = await Clipboard.getData('text/plain');
    final text = data?.text;
    if (text == null || text.trim().isEmpty) {
      _toast(_t('کلیپ‌بورد خالی است', 'Clipboard is empty'));
      return;
    }
    try {
      await _registry.importJson(text, merge: true);
      await _load();
      _toast(_t('وارد شد', 'Imported'));
    } catch (_) {
      _toast(_t('فرمت نامعتبر', 'Invalid format'));
    }
  }

  // ---------------------------------------------------------- UI

  @override
  Widget build(BuildContext context) {
    final visible = _visibleEntries;

    return Scaffold(
      backgroundColor: AppColors.bg(context),
      appBar: AppBar(
        backgroundColor: AppColors.surface(context),
        title: Text(_t('DNS گیم', 'Game DNS')),
        actions: [
          IconButton(
            icon: Icon(_showSearch ? Icons.close : Icons.search, color: AppColors.fg(context)),
            onPressed: () => setState(() => _showSearch = !_showSearch),
          ),
          IconButton(
            icon: Icon(Icons.speed, color: AppColors.fg(context)),
            tooltip: _t('پینگ همه', 'Ping all'),
            onPressed: _testingAll ? null : _pingAllVisible,
          ),
          PopupMenuButton<String>(
            icon: Icon(Icons.more_vert, color: AppColors.fg(context)),
            onSelected: (v) {
              if (v == 'export') _exportRegistry();
              if (v == 'import') _importRegistry();
              if (v == 'qr') _importFromQr();
            },
            itemBuilder: (_) => [
              PopupMenuItem(value: 'export', child: Text(_t('برون‌بری (کپی)', 'Export (copy)'))),
              PopupMenuItem(value: 'import', child: Text(_t('درون‌ریزی (چسباندن)', 'Import (paste)'))),
              PopupMenuItem(value: 'qr', child: Text(_t('ورود با QR', 'Import via QR'))),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          if (_showSearch) _buildSearchBar(),
          _buildActiveCard(),
          _buildBoosterPanel(),
          if (_testingAll) _buildProgressBar(),
          _buildCategoryChips(),
          _buildStabilityLegend(),
          _buildSortRow(visible.length),
          Expanded(
            child: visible.isEmpty
                ? Center(child: Text(_t('چیزی پیدا نشد', 'Nothing found'), style: TextStyle(color: AppColors.muted(context))))
                : ReorderableListView.builder(
                    buildDefaultDragHandles: false,
                    itemCount: visible.length,
                    onReorder: (oldIndex, newIndex) {
                      if (newIndex > oldIndex) newIndex -= 1;
                      final ids = visible.map((e) => e.id).toList();
                      final moved = ids.removeAt(oldIndex);
                      ids.insert(newIndex, moved);
                      _saveManualOrder(ids);
                    },
                    itemBuilder: (context, i) => ReorderableDragStartListener(
                      key: ValueKey(visible[i].id),
                      index: i,
                      child: _buildTile(visible[i]),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: TextField(
        controller: _searchController,
        style: TextStyle(color: AppColors.fg(context)),
        decoration: InputDecoration(
          hintText: _t('جستجو (نام، IP، کشور، ارائه‌دهنده)', 'Search (name, IP, country, provider)'),
          hintStyle: TextStyle(color: AppColors.muted2(context)),
          filled: true,
          fillColor: AppColors.elevated(context),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
          prefixIcon: Icon(Icons.search, color: AppColors.muted2(context)),
        ),
        onChanged: (v) => setState(() => _searchQuery = v),
      ),
    );
  }

  Widget _buildActiveCard() {
    final active = _activeEntry;
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 10, 12, 4),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.elevated(context),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border(context)),
      ),
      child: Row(
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              color: active != null ? _stabilityColor(_stabilityOf(active.id)) : AppColors.muted2(context),
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  active?.name ?? _t('هیچ DNS فعالی انتخاب نشده', 'No active DNS selected'),
                  style: TextStyle(color: AppColors.fg(context), fontWeight: FontWeight.bold),
                ),
                if (active != null)
                  Text(
                    '${active.xrayPrimary}'
                    '${_liveOrStoredPing(active.id) != null ? '  ·  ${_liveOrStoredPing(active.id)}ms' : ''}'
                    '${_liveOrStoredJitter(active.id) != null ? '  ·  jitter ${_liveOrStoredJitter(active.id)}ms' : ''}',
                    style: TextStyle(color: AppColors.muted(context), fontSize: 12),
                  ),
              ],
            ),
          ),
          if (active == null)
            TextButton(
              onPressed: _autoSelectBest,
              child: Text(
                _t('اتصال', 'Connect'),
                style: TextStyle(color: AppColors.accent, fontWeight: FontWeight.w600),
              ),
            )
          else
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextButton(
                  onPressed: _autoSelectBest,
                  child: Text(
                    _t('تغییر', 'Change'),
                    style: TextStyle(color: AppColors.muted(context)),
                  ),
                ),
                TextButton(
                  onPressed: _clearActive,
                  child: Text(
                    _t('قطع', 'Disconnect'),
                    style: const TextStyle(color: AppColors.danger, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildBoosterPanel() {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 4, 12, 4),
      decoration: BoxDecoration(color: AppColors.surface(context), borderRadius: BorderRadius.circular(12)),
      child: Column(
        children: [
          ListTile(
            dense: true,
            title: Text(_t('حالت بازی', 'Game Mode'), style: TextStyle(color: AppColors.fg(context))),
            leading: Switch(
              value: _booster['enabled'] == true,
              onChanged: (v) async {
                await GameBoosterSettings.set('enabled', v);
                await _load();
              },
            ),
            trailing: IconButton(
              icon: Icon(_boosterExpanded ? Icons.expand_less : Icons.expand_more, color: AppColors.muted2(context)),
              onPressed: () => setState(() => _boosterExpanded = !_boosterExpanded),
            ),
          ),
          if (_boosterExpanded)
            ..._boosterToggleKeys.map((k) => CheckboxListTile(
                  dense: true,
                  value: _booster[k] == true,
                  title: Text(_boosterLabel(k), style: TextStyle(color: AppColors.muted(context), fontSize: 13)),
                  onChanged: (v) async {
                    await GameBoosterSettings.set(k, v ?? false);
                    await _load();
                  },
                )),
        ],
      ),
    );
  }

  static const _boosterToggleKeys = [
    'blockQuic',
    'forceIpv4',
    'blockTelemetry',
    'blockAds',
    'smallDnsCache',
    'preferUdpGames',
  ];

  String _boosterLabel(String key) {
    switch (key) {
      case 'blockQuic':
        return _t('مسدودسازی QUIC', 'Block QUIC');
      case 'forceIpv4':
        return _t('اجبار IPv4', 'Force IPv4');
      case 'blockTelemetry':
        return _t('بلاک تله‌متری', 'Block telemetry');
      case 'blockAds':
        return _t('بلاک تبلیغات', 'Block ads');
      case 'smallDnsCache':
        return _t('کش کوچک DNS', 'Small DNS cache');
      case 'preferUdpGames':
        return _t('ترجیح UDP برای بازی', 'Prefer UDP for games');
      default:
        return key;
    }
  }

  Widget _buildProgressBar() {
    final v = _total == 0 ? 0.0 : _tested / _total;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Column(
        children: [
          LinearProgressIndicator(value: v, backgroundColor: AppColors.elevated(context), color: AppColors.accent),
          const SizedBox(height: 4),
          Text('$_tested / $_total', style: TextStyle(color: AppColors.muted2(context), fontSize: 11)),
        ],
      ),
    );
  }

  Widget _buildCategoryChips() {
    final chips = <(_Category, String)>[
      (_Category.all, _t('همه', 'All')),
      (_Category.pinned, _t('پین‌شده', 'Pinned')),
      (_Category.recommended, _t('پیشنهادی', 'Recommended')),
      (_Category.adBlocking, _t('مانع تبلیغ', 'Ad-blocking')),
      (_Category.family, _t('خانواده', 'Family')),
      (_Category.dnssec, 'DNSSEC'),
      (_Category.ipv6, 'IPv6'),
      (_Category.myCountry, _t('کشور من', 'My country')),
      (_Category.hidden, _t('مخفی‌شده', 'Hidden')),
    ];
    return SizedBox(
      height: 40,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        children: chips.map((c) {
          final selected = _category == c.$1;
          return Padding(
            padding: const EdgeInsets.only(right: 6),
            child: ChoiceChip(
              label: Text(c.$2, style: TextStyle(fontSize: 12, color: selected ? AppColors.bg(context) : AppColors.fg(context))),
              selected: selected,
              selectedColor: AppColors.accent,
              backgroundColor: AppColors.elevated(context),
              onSelected: (_) => setState(() => _category = c.$1),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildStabilityLegend() {
    Widget item(Color c, String fa, String en) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(color: c, shape: BoxShape.circle),
              ),
              const SizedBox(width: 4),
              Text(_t(fa, en),
                  style: TextStyle(color: AppColors.muted2(context), fontSize: 10)),
            ],
          ),
        );
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 2, 12, 6),
      child: Row(
        children: [
          item(const Color(0xFF3DCF9A), 'پایدار', 'Stable'),
          item(const Color(0xFFFFB74D), 'متوسط', 'Medium'),
          item(const Color(0xFFE07070), 'ناپایدار', 'Unstable'),
        ],
      ),
    );
  }

  Widget _buildSortRow(int count) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 2),
      child: Row(
        children: [
          Text('$count ${_t('نتیجه', 'results')}', style: TextStyle(color: AppColors.muted2(context), fontSize: 12)),
          const Spacer(),
          Text(_t('مرتب‌سازی: ', 'Sort: '), style: TextStyle(color: AppColors.muted2(context), fontSize: 12)),
          DropdownButton<_SortMode>(
            value: _sortMode,
            dropdownColor: AppColors.surface(context),
            underline: const SizedBox(),
            style: TextStyle(color: AppColors.fg(context), fontSize: 12),
            items: [
              DropdownMenuItem(value: _SortMode.ping, child: Text(_t('پینگ', 'Ping'))),
              DropdownMenuItem(value: _SortMode.name, child: Text(_t('نام', 'Name'))),
              DropdownMenuItem(value: _SortMode.country, child: Text(_t('کشور', 'Country'))),
              DropdownMenuItem(value: _SortMode.provider, child: Text(_t('ارائه‌دهنده', 'Provider'))),
              DropdownMenuItem(value: _SortMode.jitter, child: Text(_t('نوسان', 'Jitter'))),
            ],
            onChanged: (v) => setState(() => _sortMode = v ?? _SortMode.ping),
          ),
        ],
      ),
    );
  }

  Widget _buildTile(DnsEntry e) {
    final stability = _stabilityOf(e.id);
    final ping = _liveOrStoredPing(e.id);
    final jitter = _liveOrStoredJitter(e.id);
    final pinned = _statFor(e.id).pinned;
    final isActive = e.id == _activeId;

    return ListTile(
      key: ValueKey(e.id),
      onTap: () => _setActive(e),
      onLongPress: () => _openActionSheet(e),
      leading: Container(
        width: 10,
        height: 10,
        margin: const EdgeInsets.only(top: 4),
        decoration: BoxDecoration(color: _stabilityColor(stability), shape: BoxShape.circle),
      ),
      title: Text(
        e.name,
        style: TextStyle(
          color: isActive ? AppColors.accent : AppColors.fg(context),
          fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        '${e.provider} · ${e.country}'
        '${e.xrayPrimary.isNotEmpty ? ' · ${e.xrayPrimary}' : ''}'
        '${jitter != null ? ' · jitter ${jitter}ms' : ''}',
        style: TextStyle(color: AppColors.muted2(context), fontSize: 11),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (pinned)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: Icon(Icons.push_pin, size: 16, color: AppColors.accent),
            ),
          if (ping != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: _pingBgColor(ping),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '${ping}ms',
                style: TextStyle(
                  color: _pingTextColor(ping),
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Text(
                '—',
                style: TextStyle(color: AppColors.muted2(context), fontSize: 14),
              ),
            ),
          IconButton(
            icon: Icon(Icons.more_vert, size: 18, color: AppColors.muted2(context)),
            onPressed: () => _openActionSheet(e),
          ),
        ],
      ),
    );
  }

  Color _pingBgColor(int ms) {
    if (ms < 100) return const Color(0x223DCF9A);
    if (ms < 300) return const Color(0x22FFB74D);
    return const Color(0x22E07070);
  }

  Color _pingTextColor(int ms) {
    if (ms < 100) return const Color(0xFF3DCF9A);
    if (ms < 300) return const Color(0xFFFFB74D);
    return const Color(0xFFE07070);
  }

  void _openActionSheet(DnsEntry e) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface(context),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(Icons.check_circle_outline, color: AppColors.fg(context)),
              title: Text(_t('تنظیم به‌عنوان اصلی', 'Set as primary')),
              onTap: () {
                Navigator.pop(context);
                _setActive(e);
              },
            ),
            ListTile(
              leading: Icon(_statFor(e.id).pinned ? Icons.push_pin : Icons.push_pin_outlined, color: AppColors.fg(context)),
              title: Text(_statFor(e.id).pinned ? _t('برداشتن پین', 'Unpin') : _t('پین کردن', 'Pin')),
              onTap: () {
                Navigator.pop(context);
                _togglePin(e);
              },
            ),
            ListTile(
              leading: Icon(Icons.speed, color: AppColors.fg(context)),
              title: Text(_t('پینگ', 'Ping')),
              onTap: () {
                Navigator.pop(context);
                _pingOne(e);
              },
            ),
            ListTile(
              leading: Icon(Icons.copy, color: AppColors.fg(context)),
              title: Text(_t('کپی IP', 'Copy IP')),
              onTap: () {
                Navigator.pop(context);
                _copyIp(e);
              },
            ),
            if (_statFor(e.id).hidden)
              ListTile(
                leading: const Icon(Icons.restore, color: AppColors.accent),
                title: Text(_t('بازگرداندن', 'Restore'),
                    style: const TextStyle(color: AppColors.accent)),
                onTap: () {
                  Navigator.pop(context);
                  _unhide(e);
                },
              )
            else
              ListTile(
                leading: Icon(Icons.visibility_off_outlined, color: AppColors.fg(context)),
                title: Text(_t('مخفی کردن', 'Hide')),
                onTap: () {
                  Navigator.pop(context);
                  _hide(e);
                },
              ),
            ListTile(
              leading: const Icon(Icons.delete_outline, color: AppColors.danger),
              title: Text(_t('حذف', 'Delete'),
                  style: const TextStyle(color: AppColors.danger)),
              onTap: () {
                Navigator.pop(context);
                _delete(e);
              },
            ),
          ],
        ),
      ),
    );
  }
}
