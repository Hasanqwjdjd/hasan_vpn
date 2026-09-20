import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/game_dns.dart';
import '../services/app_colors.dart';
import '../services/settings_service.dart';

class GameDnsScreen extends StatefulWidget {
  final String language;

  const GameDnsScreen({super.key, this.language = 'fa'});

  @override
  State<GameDnsScreen> createState() => _GameDnsScreenState();
}

class _GameDnsScreenState extends State<GameDnsScreen> {
  // ترتیب نمایش: 0 = بر اساس نام، 1 = بر اساس پینگ
  int _sortMode = 0;

  int? _activeIndex;
  String? _activePrimary;
  String _ipPref = 'ipv4';

  List<Map<String, String>> _customDns = [];
  List<String> _hiddenDns = [];
  Map<String, Map<String, String>> _overrides = {};
  Map<String, int> _pingResults = {};

  bool _testing = false;
  bool _cancelTest = false;
  int _tested = 0;
  int _total = 0;

  bool _showSearch = false;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  bool get _isFa => widget.language == 'fa';
  String _t(String fa, String en) => _isFa ? fa : en;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final primary = await SettingsService.getGameDnsPrimary();
    final pref = await SettingsService.getDnsIpPreference();
    final custom = await SettingsService.getCustomDnsList();
    final hidden = await SettingsService.getHiddenDns();
    final overrides = await SettingsService.getDnsOverrides();
    final pings = await SettingsService.getDnsPingResults();
    if (!mounted) return;
    setState(() {
      _ipPref = pref;
      _customDns = custom;
      _hiddenDns = hidden;
      _overrides = overrides;
      _pingResults = pings;
      _activePrimary = primary;
    });
  }

  /// لیست نهایی DNS‌ها با اعمال مخفی‌ها، ویرایش‌ها و سفارشی‌ها.
  List<GameDns> get _visibleDns {
    final list = <GameDns>[];

    for (final d in kGameDnsList) {
      if (_hiddenDns.contains(d.primary)) continue;
      final ov = _overrides[d.primary];
      if (ov != null) {
        list.add(GameDns(
          name: ov['name'] ?? d.name,
          primary: ov['primary'] ?? d.primary,
          secondary: ov['secondary'] ?? d.secondary,
          primaryV6: d.primaryV6,
          secondaryV6: d.secondaryV6,
        ));
      } else {
        list.add(d);
      }
    }

    for (final m in _customDns) {
      list.add(GameDns(
        name: '✏️ ${m['name'] ?? 'Custom'}',
        primary: m['primary'] ?? '',
        secondary: m['secondary'] ?? '',
      ));
    }

    var filtered = list;
    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      filtered = list.where((d) {
        return d.name.toLowerCase().contains(q) ||
            d.primary.toLowerCase().contains(q) ||
            d.secondary.toLowerCase().contains(q);
      }).toList();
    }

    if (_sortMode == 0) {
      filtered.sort((a, b) => a.name.compareTo(b.name));
    } else {
      filtered.sort((a, b) {
        final pa = _pingResults[a.primary] ?? 99999;
        final pb = _pingResults[b.primary] ?? 99999;
        if (pa <= 0) return 1;
        if (pb <= 0) return -1;
        return pa.compareTo(pb);
      });
    }

    return filtered;
  }

  // -------------------------------------------------------- activation

  Future<void> _select(GameDns dns) async {
    await SettingsService.setGameDns(dns.primary, dns.secondary);
    if (!mounted) return;
    setState(() => _activePrimary = dns.primary);
    _showMsg(_t('DNS فعال شد', 'DNS activated'));
  }

  Future<void> _clear() async {
    await SettingsService.clearGameDns();
    if (!mounted) return;
    setState(() => _activePrimary = null);
    _showMsg(_t('DNS پیش‌فرض فعال شد', 'Default DNS restored'));
  }

  Future<void> _toggleActive() async {
    if (_activePrimary != null) {
      await _clear();
    } else {
      // اگر DNS انتخاب نشده باشد، اولین DNS مرتبط با پینگ را انتخاب کن.
      final list = _visibleDns;
      if (list.isNotEmpty) {
        final sorted = List<GameDns>.from(list);
        sorted.sort((a, b) {
          final pa = _pingResults[a.primary] ?? 99999;
          final pb = _pingResults[b.primary] ?? 99999;
          return pa.compareTo(pb);
        });
        await _select(sorted.first);
      } else {
        _showMsg(_t('هیچ DNS‌ای موجود نیست', 'No DNS available'));
      }
    }
  }

  // -------------------------------------------------------- ping

  Future<int> _pingDns(String host, {int port = 53}) async {
    final watch = Stopwatch()..start();
    try {
      final socket = await Socket.connect(
        host,
        port,
        timeout: const Duration(seconds: 3),
      );
      watch.stop();
      socket.destroy();
      return watch.elapsedMilliseconds.clamp(1, 9999);
    } catch (_) {
      return -1;
    }
  }

  Future<void> _testAllDns() async {
    if (_testing) return;
    final list = _visibleDns;
    if (list.isEmpty) return;
    _cancelTest = false;
    setState(() {
      _testing = true;
      _tested = 0;
      _total = list.length;
    });

    final results = <String, int>{};
    for (var i = 0; i < list.length; i++) {
      if (_cancelTest) break;
      final dns = list[i];
      int ping = -1;
      if (dns.primary.isNotEmpty && !dns.primary.startsWith('http')) {
        ping = await _pingDns(dns.primary);
      }
      results[dns.primary] = ping;
      await SettingsService.saveDnsPingResult(dns.primary, ping);
      if (!mounted) return;
      setState(() {
        _pingResults = Map<String, int>.from(_pingResults)..[dns.primary] = ping;
        _tested = i + 1;
      });
    }

    if (!mounted) return;
    setState(() => _testing = false);
    if (_cancelTest) {
      _showMsg(_t('تست لغو شد', 'Test cancelled'));
    } else {
      final ok = results.values.where((v) => v > 0).length;
      _showMsg(_t('$ok از $_total دی‌ان‌اس پاسخ داد', '$ok of $_total DNS responded'));
    }
  }

  void _cancelTestAll() {
    _cancelTest = true;
  }

  Future<void> _testOneDns(GameDns dns) async {
    if (dns.primary.isEmpty || dns.primary.startsWith('http')) {
      _showMsg(_t('این DNS قابل تست نیست', 'This DNS cannot be tested'));
      return;
    }
    final ping = await _pingDns(dns.primary);
    await SettingsService.saveDnsPingResult(dns.primary, ping);
    if (!mounted) return;
    setState(() {
      _pingResults = Map<String, int>.from(_pingResults)..[dns.primary] = ping;
    });
    _showMsg(ping > 0
        ? _t('پینگ: $ping ms', 'Ping: $ping ms')
        : _t('پاسخی نیامد', 'No response'));
  }

  // -------------------------------------------------------- add / edit / delete

  Future<bool> _showDnsDialog({
    required String title,
    required String nameInit,
    required String primaryInit,
    required String secondaryInit,
  }) async {
    final nameCtrl = TextEditingController(text: nameInit);
    final primaryCtrl = TextEditingController(text: primaryInit);
    final secondaryCtrl = TextEditingController(text: secondaryInit);

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.elevated(ctx),
        title: Text(title, style: TextStyle(color: AppColors.fg(ctx))),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtrl,
              style: TextStyle(color: AppColors.fg(ctx)),
              decoration: InputDecoration(
                labelText: _t('نام', 'Name'),
                labelStyle: TextStyle(color: AppColors.muted(ctx)),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: primaryCtrl,
              keyboardType: TextInputType.number,
              style: TextStyle(color: AppColors.fg(ctx)),
              decoration: InputDecoration(
                labelText: _t('DNS اصلی', 'Primary DNS'),
                labelStyle: TextStyle(color: AppColors.muted(ctx)),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: secondaryCtrl,
              keyboardType: TextInputType.number,
              style: TextStyle(color: AppColors.fg(ctx)),
              decoration: InputDecoration(
                labelText: _t('DNS پشتیبان', 'Secondary DNS'),
                labelStyle: TextStyle(color: AppColors.muted(ctx)),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(_t('لغو', 'Cancel'),
                style: TextStyle(color: AppColors.muted(ctx))),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(_t('ذخیره', 'Save'),
                style: const TextStyle(color: AppColors.accent)),
          ),
        ],
      ),
    );

    if (ok != true) return false;

    final name = nameCtrl.text.trim();
    final primary = primaryCtrl.text.trim();
    final secondary = secondaryCtrl.text.trim();
    final ipRegex = RegExp(r'^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$');

    if (name.isEmpty ||
        !ipRegex.hasMatch(primary) ||
        !ipRegex.hasMatch(secondary)) {
      _showMsg(_t('نام و آدرس‌های IPv4 معتبر لازم است',
          'A name and valid IPv4 addresses are required'));
      return false;
    }

    _lastDialogName = name;
    _lastDialogPrimary = primary;
    _lastDialogSecondary = secondary;
    return true;
  }

  String _lastDialogName = '';
  String _lastDialogPrimary = '';
  String _lastDialogSecondary = '';

  /// پیدا کردن index سفارشی بودن یک DNS.
  int? _customIndexOf(GameDns dns) {
    for (var i = 0; i < _customDns.length; i++) {
      if (_customDns[i]['primary'] == dns.primary) return i;
    }
    return null;
  }

  Future<void> _addCustomDns() async {
    final ok = await _showDnsDialog(
      title: _t('افزودن DNS جدید', 'Add New DNS'),
      nameInit: '',
      primaryInit: '',
      secondaryInit: '',
    );
    if (!ok) return;
    await SettingsService.addCustomDns(
        _lastDialogName, _lastDialogPrimary, _lastDialogSecondary);
    await _load();
    if (!mounted) return;
    _showMsg(_t('DNS اضافه شد', 'DNS added'));
  }

  Future<void> _editDns(GameDns dns) async {
    final ok = await _showDnsDialog(
      title: _t('ویرایش DNS', 'Edit DNS'),
      nameInit: dns.name.replaceFirst('✏️ ', ''),
      primaryInit: dns.primary,
      secondaryInit: dns.secondary,
    );
    if (!ok) return;

    final customIndex = _customIndexOf(dns);
    if (customIndex != null) {
      // ویرایش DNS سفارشی
      await SettingsService.updateCustomDns(
        customIndex,
        _lastDialogName,
        _lastDialogPrimary,
        _lastDialogSecondary,
      );
    } else {
      // ویرایش DNS پیش‌فرض → ذخیره به‌صورت override
      await SettingsService.setDnsOverride(
        dns.primary,
        _lastDialogName,
        _lastDialogPrimary,
        _lastDialogSecondary,
      );
    }
    await _load();
    if (!mounted) return;
    _showMsg(_t('DNS ویرایش شد', 'DNS edited'));
  }

  Future<void> _deleteDns(GameDns dns) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.elevated(ctx),
        title: Text(_t('حذف DNS؟', 'Delete DNS?'),
            style: TextStyle(color: AppColors.fg(ctx))),
        content: Text(dns.name,
            style: TextStyle(color: AppColors.muted(ctx))),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(_t('لغو', 'Cancel'),
                style: TextStyle(color: AppColors.muted(ctx))),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(_t('حذف', 'Delete'),
                style: const TextStyle(color: AppColors.danger)),
          ),
        ],
      ),
    );
    if (ok != true) return;

    final customIndex = _customIndexOf(dns);
    if (customIndex != null) {
      await SettingsService.removeCustomDns(customIndex);
    } else {
      await SettingsService.addHiddenDns(dns.primary);
      await SettingsService.removeDnsOverride(dns.primary);
    }

    if (_activePrimary == dns.primary) {
      await SettingsService.clearGameDns();
      _activePrimary = null;
    }
    await _load();
    if (!mounted) return;
    _showMsg(_t('حذف شد', 'Deleted'));
  }

  // -------------------------------------------------------- share / copy

  void _shareDns(GameDns dns) {
    final text = 'DNS: ${dns.name}\n'
        'Primary: ${dns.primary}\n'
        'Secondary: ${dns.secondary}';
    Clipboard.setData(ClipboardData(text: text));
    _showMsg(_t('متن اشتراک‌گذاری کپی شد', 'Share text copied'));
  }

  void _copy(GameDns dns) {
    Clipboard.setData(ClipboardData(text: '${dns.primary}, ${dns.secondary}'));
    _showMsg(_t('کپی شد', 'Copied'));
  }

  void _showMsg(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), duration: const Duration(seconds: 2)),
    );
  }

  Future<void> _setIpPref(String value) async {
    await SettingsService.setDnsIpPreference(value);
    if (!mounted) return;
    setState(() => _ipPref = value);
  }

  void _toggleSearch() {
    setState(() {
      _showSearch = !_showSearch;
      if (!_showSearch) {
        _searchController.clear();
        _searchQuery = '';
      }
    });
  }

  void _toggleSort() {
    setState(() => _sortMode = _sortMode == 0 ? 1 : 0);
    _showMsg(_sortMode == 0
        ? _t('مرتب بر اساس نام', 'Sorted by name')
        : _t('مرتب بر اساس پینگ', 'Sorted by ping'));
  }

  // -------------------------------------------------------- widgets

  Widget _ipChip(String value, String label) {
    final active = _ipPref == value;
    return Expanded(
      child: GestureDetector(
        onTap: () => _setIpPref(value),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: active
                ? AppColors.accent.withOpacity(0.15)
                : AppColors.elevated(context),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: active ? AppColors.accent : AppColors.border(context),
            ),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: active ? AppColors.accent : AppColors.muted(context),
              fontSize: 12.5,
              fontWeight: active ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }

  Color _pingColor(int ping) {
    if (ping <= 0) return AppColors.danger;
    if (ping < 50) return AppColors.accent;
    if (ping < 150) return AppColors.warn;
    return AppColors.danger;
  }

  Widget _buildConnectButton() {
    final active = _activePrimary != null;
    GameDns? activeDns;
    if (active) {
      for (final d in _visibleDns) {
        if (d.primary == _activePrimary) {
          activeDns = d;
          break;
        }
      }
    }

    return GestureDetector(
      onTap: _toggleActive,
      child: Container(
        width: 130,
        height: 130,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
            color: active ? AppColors.accent : AppColors.border(context),
            width: 3,
          ),
          color: active
              ? AppColors.accent.withOpacity(0.15)
              : Colors.transparent,
          boxShadow: active
              ? [
                  BoxShadow(
                    color: AppColors.accent.withOpacity(0.3),
                    blurRadius: 20,
                    spreadRadius: 2,
                  ),
                ]
              : null,
        ),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                active ? Icons.dns : Icons.power_settings_new,
                size: 42,
                color: active ? AppColors.accent : AppColors.muted2(context),
              ),
              const SizedBox(height: 6),
              Text(
                active
                    ? _t('قطع DNS', 'Disable DNS')
                    : _t('فعال‌سازی DNS', 'Enable DNS'),
                style: TextStyle(
                  color: active ? AppColors.accent : AppColors.muted2(context),
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (active && activeDns != null)
                Padding(
                  padding: const EdgeInsets.only(top: 4, left: 8, right: 8),
                  child: Text(
                    activeDns.name.replaceFirst('✏️ ', ''),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: AppColors.muted(context),
                      fontSize: 10,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final all = _visibleDns;

    return Scaffold(
      backgroundColor: AppColors.bg(context),
      appBar: AppBar(
        backgroundColor: AppColors.bg(context),
        elevation: 0,
        iconTheme: IconThemeData(color: AppColors.fg(context)),
        title: Text(_t('DNS بازی', 'Game DNS'),
            style: TextStyle(color: AppColors.fg(context))),
        actions: [
          IconButton(
            icon: Icon(
              _sortMode == 0 ? Icons.sort_by_alpha : Icons.speed,
              color: AppColors.accent,
            ),
            tooltip: _t('مرتب‌سازی', 'Sort'),
            onPressed: _toggleSort,
          ),
          IconButton(
            icon: Icon(
              _showSearch ? Icons.close : Icons.search,
              color: AppColors.muted(context),
            ),
            tooltip: _t('جستجو', 'Search'),
            onPressed: _toggleSearch,
          ),
          IconButton(
            icon: _testing
                ? const Icon(Icons.stop_circle_outlined,
                    color: AppColors.danger)
                : const Icon(Icons.speed, color: AppColors.accent),
            tooltip: _t('تست همه', 'Test all'),
            onPressed: _testing ? _cancelTestAll : _testAllDns,
          ),
          IconButton(
            icon: const Icon(Icons.add, color: AppColors.accent),
            tooltip: _t('افزودن DNS', 'Add DNS'),
            onPressed: _addCustomDns,
          ),
        ],
      ),
      body: Column(
        children: [
          // سرچ
          if (_showSearch)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
              child: TextField(
                controller: _searchController,
                autofocus: true,
                style: TextStyle(color: AppColors.fg(context), fontSize: 14),
                decoration: InputDecoration(
                  hintText: _t('جستجو...', 'Search...'),
                  hintStyle: TextStyle(color: AppColors.muted2(context)),
                  prefixIcon: Icon(Icons.search,
                      color: AppColors.muted(context), size: 20),
                  filled: true,
                  fillColor: AppColors.surface(context),
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 8),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
                onChanged: (v) {
                  setState(() => _searchQuery = v);
                },
              ),
            ),

          // انتخاب IP
          Container(
            margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.surface(context),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.border(context)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_t('نسخه‌ی IP', 'IP version'),
                    style: TextStyle(
                        color: AppColors.muted(context),
                        fontSize: 12,
                        fontWeight: FontWeight.w600)),
                const SizedBox(height: 10),
                Row(
                  children: [
                    _ipChip('ipv4', 'IPv4'),
                    const SizedBox(width: 6),
                    _ipChip('ipv6', 'IPv6'),
                    const SizedBox(width: 6),
                    _ipChip('both', _t('هر دو', 'Both')),
                  ],
                ),
              ],
            ),
          ),

          // دکمه اتصال
          const SizedBox(height: 12),
          _buildConnectButton(),
          const SizedBox(height: 12),

          // نوار پیشرفت تست
          if (_testing)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Column(
                children: [
                  LinearProgressIndicator(
                    value: _total > 0 ? _tested / _total : 0,
                    color: AppColors.accent,
                    backgroundColor: AppColors.border(context),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _t('$_tested از $_total تست شد · ${_total - _tested} باقی‌مانده',
                        '$_tested of $_total tested · ${_total - _tested} remaining'),
                    style: TextStyle(
                        color: AppColors.muted2(context), fontSize: 11),
                  ),
                ],
              ),
            ),

          // لیست DNS
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              itemCount: all.length,
              itemBuilder: (_, i) {
                final dns = all[i];
                final active = dns.primary == _activePrimary;
                final ping = _pingResults[dns.primary];

                return Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  decoration: BoxDecoration(
                    color: active
                        ? AppColors.accent.withOpacity(0.1)
                        : AppColors.surface(context),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: active
                          ? AppColors.accent
                          : AppColors.border(context),
                      width: active ? 1.5 : 1,
                    ),
                  ),
                  child: ListTile(
                    onTap: () => _select(dns),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 4),
                    title: Row(
                      children: [
                        Expanded(
                          child: Text(
                            dns.name,
                            style: TextStyle(
                              color: AppColors.fg(context),
                              fontSize: 13.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        if (ping != null && ping > 0)
                          Text(
                            '$ping ms',
                            style: TextStyle(
                              color: _pingColor(ping),
                              fontSize: 11.5,
                              fontWeight: FontWeight.w700,
                            ),
                          )
                        else if (ping != null && ping <= 0)
                          const Text('✕',
                              style: TextStyle(
                                  color: AppColors.danger,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700)),
                      ],
                    ),
                    subtitle: Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        dns.primaryV6 != null
                            ? '${dns.primary}\n${dns.secondary}\n${dns.primaryV6}\n${dns.secondaryV6}'
                            : '${dns.primary}\n${dns.secondary}',
                        style: TextStyle(
                            color: AppColors.muted2(context),
                            fontSize: 11,
                            height: 1.5),
                      ),
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(minWidth: 26),
                          icon: const Icon(Icons.bolt,
                              color: AppColors.warn, size: 17),
                          onPressed: () => _testOneDns(dns),
                          tooltip: _t('تست پینگ', 'Test ping'),
                        ),
                        IconButton(
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(minWidth: 26),
                          icon: const Icon(Icons.edit_outlined,
                              color: AppColors.muted, size: 17),
                          onPressed: () => _editDns(dns),
                          tooltip: _t('ویرایش', 'Edit'),
                        ),
                        IconButton(
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(minWidth: 26),
                          icon: const Icon(Icons.share_outlined,
                              color: AppColors.muted, size: 17),
                          onPressed: () => _shareDns(dns),
                          tooltip: _t('اشتراک‌گذاری', 'Share'),
                        ),
                        IconButton(
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(minWidth: 26),
                          icon: const Icon(Icons.copy,
                              color: AppColors.accent, size: 17),
                          onPressed: () => _copy(dns),
                          tooltip: _t('کپی', 'Copy'),
                        ),
                        IconButton(
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(minWidth: 26),
                          icon: const Icon(Icons.delete_outline,
                              color: AppColors.danger, size: 17),
                          onPressed: () => _deleteDns(dns),
                          tooltip: _t('حذف', 'Delete'),
                        ),
                        if (active)
                          const Icon(Icons.check_circle,
                              color: AppColors.accent, size: 20)
                        else
                          Icon(Icons.radio_button_unchecked,
                              color: AppColors.muted2(context), size: 20),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
