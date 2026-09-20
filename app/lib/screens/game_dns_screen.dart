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
  int? _activeIndex;
  String _ipPref = 'ipv4';
  List<Map<String, String>> _customDns = [];
  Map<String, int> _pingResults = {};
  bool _testing = false;
  int _tested = 0;
  int _total = 0;

  bool get _isFa => widget.language == 'fa';
  String _t(String fa, String en) => _isFa ? fa : en;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final primary = await SettingsService.getGameDnsPrimary();
    final pref = await SettingsService.getDnsIpPreference();
    final custom = await SettingsService.getCustomDnsList();
    final pings = await SettingsService.getDnsPingResults();
    if (!mounted) return;
    setState(() {
      _ipPref = pref;
      _customDns = custom;
      _pingResults = pings;
      _activeIndex = kGameDnsList.indexWhere((d) => d.primary == primary);
      if (_activeIndex == -1) _activeIndex = null;
    });
  }

  List<GameDns> get _allDns => [
        ...kGameDnsList,
        ..._customDns
            .map((m) => GameDns(
                  name: '✏️ ${m['name'] ?? 'Custom'}',
                  primary: m['primary'] ?? '',
                  secondary: m['secondary'] ?? '',
                ))
            .toList(),
      ];

  Future<void> _select(GameDns dns) async {
    await SettingsService.setGameDns(dns.primary, dns.secondary);
    if (!mounted) return;
    setState(() {
      _activeIndex = _allDns.indexOf(dns);
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(_t('DNS فعال شد', 'DNS activated')),
        duration: const Duration(seconds: 1),
      ),
    );
  }

  Future<void> _clear() async {
    await SettingsService.clearGameDns();
    if (!mounted) return;
    setState(() => _activeIndex = null);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(_t('DNS پیش‌فرض فعال شد', 'Default DNS restored')),
        duration: const Duration(seconds: 1),
      ),
    );
  }

  void _copy(GameDns dns) {
    Clipboard.setData(ClipboardData(text: '${dns.primary}, ${dns.secondary}'));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(_t('کپی شد', 'Copied')),
        duration: const Duration(seconds: 1),
      ),
    );
  }

  Future<void> _setIpPref(String value) async {
    await SettingsService.setDnsIpPreference(value);
    if (!mounted) return;
    setState(() => _ipPref = value);
  }

  // ---------------------------------------------------------- ping DNS

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
    final list = _allDns;
    if (list.isEmpty) return;
    setState(() {
      _testing = true;
      _tested = 0;
      _total = list.length;
    });

    final results = <String, int>{};
    for (var i = 0; i < list.length; i++) {
      final dns = list[i];
      int ping = -1;
      if (dns.primary.isNotEmpty && !dns.primary.startsWith('http')) {
        ping = await _pingDns(dns.primary);
      }
      results[dns.primary] = ping;
      if (mounted) {
        setState(() {
          _pingResults = Map<String, int>.from(results);
          _tested = i + 1;
        });
      }
    }

    for (final e in results.entries) {
      await SettingsService.saveDnsPingResult(e.key, e.value);
    }

    if (mounted) {
      setState(() => _testing = false);
      final ok = results.values.where((v) => v > 0).length;
      _showMsg(_t('$ok از $total دی‌ان‌اس پاسخ داد', '$ok of $total DNS responded'));
    }
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

  // --------------------------------------------------------- add DNS

  Future<void> _addCustomDns() async {
    final nameCtrl = TextEditingController();
    final primaryCtrl = TextEditingController();
    final secondaryCtrl = TextEditingController();

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.elevated(ctx),
        title: Text(_t('افزودن DNS جدید', 'Add New DNS'),
            style: TextStyle(color: AppColors.fg(ctx))),
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
                hintText: '8.8.8.8',
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
                hintText: '8.8.4.4',
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
            child: Text(_t('افزودن', 'Add'),
                style: const TextStyle(color: AppColors.accent)),
          ),
        ],
      ),
    );

    if (ok != true) return;
    final name = nameCtrl.text.trim();
    final primary = primaryCtrl.text.trim();
    final secondary = secondaryCtrl.text.trim();

    final ipRegex = RegExp(r'^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$');
    if (name.isEmpty || !ipRegex.hasMatch(primary) ||
        !ipRegex.hasMatch(secondary)) {
      _showMsg(_t('نام و آدرس‌های IPv4 معتبر لازم است',
          'A name and valid IPv4 addresses are required'));
      return;
    }

    await SettingsService.addCustomDns(name, primary, secondary);
    await _load();
    if (!mounted) return;
    _showMsg(_t('DNS اضافه شد', 'DNS added'));
  }

  Future<void> _removeCustom(int globalIndex) async {
    final all = _allDns;
    final dns = all[globalIndex];
    final customIndex = _customDns
        .indexWhere((m) => m['primary'] == dns.primary && m['name'] == dns.name.substring(3));
    if (customIndex == -1) return;
    await SettingsService.removeCustomDns(customIndex);
    await _load();
  }

  // --------------------------------------------------------- share DNS

  void _shareDns(GameDns dns) {
    final text = 'DNS: ${dns.name}\n'
        'Primary: ${dns.primary}\n'
        'Secondary: ${dns.secondary}';
    Clipboard.setData(ClipboardData(text: text));
    _showMsg(_t('لینک اشتراک کپی شد', 'Share text copied'));
  }

  void _showMsg(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), duration: const Duration(seconds: 2)),
    );
  }

  // -------------------------------------------------------------- widgets

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

  @override
  Widget build(BuildContext context) {
    final all = _allDns;

    return Scaffold(
      backgroundColor: AppColors.bg(context),
      appBar: AppBar(
        backgroundColor: AppColors.bg(context),
        elevation: 0,
        iconTheme: IconThemeData(color: AppColors.fg(context)),
        title: Text(_t('DNS بازی', 'Game DNS'),
            style: TextStyle(color: AppColors.fg(context))),
        actions: [
          if (_activeIndex != null)
            IconButton(
              icon: const Icon(Icons.clear, color: AppColors.danger),
              tooltip: _t('حذف انتخاب', 'Clear'),
              onPressed: _clear,
            ),
          IconButton(
            icon: _testing
                ? const Icon(Icons.stop_circle_outlined,
                    color: AppColors.danger)
                : const Icon(Icons.speed, color: AppColors.accent),
            tooltip: _t('تست همه', 'Test all'),
            onPressed: _testing ? null : _testAllDns,
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

          // راهنما
          Container(
            padding: const EdgeInsets.all(12),
            margin: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.accent.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.accent.withOpacity(0.3)),
            ),
            child: Row(
              children: [
                const Icon(Icons.info_outline,
                    color: AppColors.accent, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _t(
                      'این DNS فقط در حالت «فقط پروکسی» اعمال می‌شود.',
                      'These DNS only apply in "proxy only" mode.',
                    ),
                    style: TextStyle(
                        color: AppColors.fg(context),
                        fontSize: 12,
                        height: 1.6),
                  ),
                ),
              ],
            ),
          ),

          // نوار پیشرفت تست
          if (_testing)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: LinearProgressIndicator(
                value: _total > 0 ? _tested / _total : 0,
                color: AppColors.accent,
                backgroundColor: AppColors.border(context),
              ),
            ),

          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              itemCount: all.length,
              itemBuilder: (_, i) {
                final dns = all[i];
                final active = i == _activeIndex;
                final ping = _pingResults[dns.primary];
                final isCustom = i >= kGameDnsList.length;

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
                          icon: Icon(Icons.bolt,
                              color: AppColors.warn, size: 18),
                          onPressed: () => _testOneDns(dns),
                          tooltip: _t('تست پینگ', 'Test ping'),
                        ),
                        IconButton(
                          icon: Icon(Icons.share_outlined,
                              color: AppColors.muted(context), size: 18),
                          onPressed: () => _shareDns(dns),
                          tooltip: _t('اشتراک‌گذاری', 'Share'),
                        ),
                        if (isCustom)
                          IconButton(
                            icon: const Icon(Icons.delete_outline,
                                color: AppColors.danger, size: 18),
                            onPressed: () => _removeCustom(i),
                            tooltip: _t('حذف', 'Delete'),
                          ),
                        if (active)
                          const Icon(Icons.check_circle,
                              color: AppColors.accent, size: 22)
                        else
                          Icon(Icons.radio_button_unchecked,
                              color: AppColors.muted2(context), size: 22),
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
