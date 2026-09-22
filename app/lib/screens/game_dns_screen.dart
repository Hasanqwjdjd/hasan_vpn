import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../models/game_dns.dart';
import '../services/app_colors.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/settings_service.dart';
import '../services/network_prober.dart';
import '../services/game_booster_settings.dart';
import '../services/home_widget_service.dart';

/// لیست DNSهای اضافی پرکاربرد (اضافه‌شده در پچ).
const List<GameDns> kExtraDnsList = <GameDns>[
  GameDns(name: 'AdGuard', primary: '94.140.14.14', secondary: '94.140.15.15'),
  GameDns(name: 'AdGuard Family', primary: '94.140.14.15', secondary: '94.140.15.16'),
  GameDns(name: 'AdGuard Unfiltered', primary: '94.140.14.140', secondary: '94.140.14.141'),
  GameDns(name: 'Quad9', primary: '9.9.9.9', secondary: '149.112.112.112'),
  GameDns(name: 'Quad9 Unsecured', primary: '9.9.9.10', secondary: '149.112.112.10'),
  GameDns(name: 'OpenDNS', primary: '208.67.222.222', secondary: '208.67.220.220'),
  GameDns(name: 'OpenDNS FamilyShield', primary: '208.67.222.123', secondary: '208.67.220.123'),
  GameDns(name: 'DNS.SB', primary: '185.222.222.222', secondary: '45.11.45.11'),
  GameDns(name: 'Digital Society CH', primary: '185.95.218.42', secondary: '185.95.218.43'),
  GameDns(name: 'Comodo Secure', primary: '8.26.56.26', secondary: '8.20.247.20'),
  GameDns(name: 'Verisign', primary: '64.6.64.6', secondary: '64.6.65.6'),
  GameDns(name: 'Level3', primary: '4.2.2.1', secondary: '4.2.2.2'),
  GameDns(name: 'Yandex', primary: '77.88.8.8', secondary: '77.88.8.1'),
  GameDns(name: 'Yandex Safe', primary: '77.88.8.88', secondary: '77.88.8.2'),
  GameDns(name: 'Mullvad', primary: '194.242.2.2', secondary: '194.242.2.3'),
  GameDns(name: 'Mullvad Adblock', primary: '194.242.2.3', secondary: '194.242.2.4'),
  GameDns(name: 'CleanBrowsing Security', primary: '185.228.168.9', secondary: '185.228.169.9'),
  GameDns(name: 'CleanBrowsing Family', primary: '185.228.168.168', secondary: '185.228.169.168'),
  GameDns(name: 'DNS0.eu', primary: '193.110.81.0', secondary: '185.253.5.0'),
  GameDns(name: 'UncensoredDNS', primary: '91.239.100.100', secondary: '89.233.43.71'),
  GameDns(name: 'ControlD', primary: '76.76.2.0', secondary: '76.76.10.0'),
  GameDns(name: 'Freenom World', primary: '80.80.80.80', secondary: '80.80.81.81'),
  GameDns(name: 'SafeDNS', primary: '195.46.39.39', secondary: '195.46.39.40'),
  GameDns(name: 'Dyn', primary: '216.146.35.35', secondary: '216.146.36.36'),
  GameDns(name: 'Norton ConnectSafe', primary: '199.85.126.10', secondary: '199.85.127.10'),
];

class GameDnsScreen extends StatefulWidget {
  final String language;

  const GameDnsScreen({super.key, this.language = 'fa'});

  @override
  State<GameDnsScreen> createState() => _GameDnsScreenState();
}

class _GameDnsScreenState extends State<GameDnsScreen> {
  int _sortMode = 1;

  String? _activeKey; // DNS فعال واقعی (برای اتصال)
  String? _selectedKey; // DNS انتخاب‌شده در UI (فقط هایلایت)
  String _ipPref = 'ipv4';

  List<Map<String, String>> _customDns = [];
  // Set به‌جای List: تا با هزاران آیتم هم .contains() آنی (O(1)) بمونه
  // و روی هر رندر/سورت کند نشه.
  Set<String> _hiddenDns = {};
  Set<String> _pinnedKeys = {};
  // ایندکس آماده برای _customIndexOf، تا به‌جای اسکن خطی لیست کاستوم
  // به ازای هر تایل (O(n) در هر رندر)، یک lookup آنی باشه.
  Map<String, int> _customIndexByKey = {};
  Map<String, Map<String, String>> _overrides = {};
  Map<String, int> _pingResults = {};
  List<String> _manualOrder = <String>[];
  final Map<String, GlobalKey> _tileKeys = <String, GlobalKey>{};

  bool _testing = false;
  bool _cancelTest = false;
  int _tested = 0;
  int _total = 0;

  bool _showSearch = false;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  final ScrollController _scrollController = ScrollController();

  /// حالت بازی (DNS + فایروال سبک)
  Map<String, dynamic> _booster = Map<String, dynamic>.from(
    GameBoosterSettings.defaults,
  );
  /// جمع/باز کردن گزینه‌های حالت بازی (علامت ^ / v)
  bool _boosterExpanded = false;

  bool get _isFa => widget.language == 'fa';
  String _t(String fa, String en) => _isFa ? fa : en;

  /// کلید یکتا برای هر DNS (چون چند DNS ممکنه primary یکسان داشته باشن).
  static String _keyOf(GameDns d) => '${d.primary}|${d.secondary}';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final activePrimary = await SettingsService.getGameDnsPrimary();
    final activeSecondary = await SettingsService.getGameDnsSecondary();
    final pref = await SettingsService.getDnsIpPreference();
    final custom = await SettingsService.getCustomDnsList();
    final hidden = await SettingsService.getHiddenDns();
    final pinned = await SettingsService.getPinnedDns();
    final overrides = await SettingsService.getDnsOverrides();
    final pings = await SettingsService.getDnsPingResults();
    final booster = await GameBoosterSettings.load();
    final prefs = await SharedPreferences.getInstance();
    final savedOrder = prefs.getStringList('dns_manual_order_v1') ?? <String>[];
    if (!mounted) return;
    _manualOrder = savedOrder;
    setState(() {
      _booster = booster;
      _ipPref = pref;
      _customDns = custom;
      _customIndexByKey = <String, int>{
        for (var i = 0; i < custom.length; i++)
          '${custom[i]['primary']}|${custom[i]['secondary']}': i,
      };
      _hiddenDns = hidden.toSet();
      _pinnedKeys = pinned.toSet();
      _overrides = overrides;
      _pingResults = pings;
      if (activePrimary != null && activeSecondary != null) {
        _activeKey = '$activePrimary|$activeSecondary';
        _selectedKey ??= _activeKey;
      } else {
        _activeKey = null;
      }
    });
  }

  List<GameDns> get _visibleDns {
    final list = <GameDns>[];

    for (final d in <GameDns>[...kGameDnsList, ...kExtraDnsList]) {
      final ov = _overrides[d.primary];
      final effective = ov != null
          ? GameDns(
              name: ov['name'] ?? d.name,
              primary: ov['primary'] ?? d.primary,
              secondary: ov['secondary'] ?? d.secondary,
              primaryV6: d.primaryV6,
              secondaryV6: d.secondaryV6,
            )
          : d;
      if (_hiddenDns.contains(_keyOf(effective))) continue;
      list.add(effective);
    }

    for (final m in _customDns) {
      final d = GameDns(
        name: '✏️ ${m['name'] ?? 'Custom'}',
        primary: m['primary'] ?? '',
        secondary: m['secondary'] ?? '',
      );
      if (_hiddenDns.contains(_keyOf(d))) continue;
      list.add(d);
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

    // اگر کاربر دستی جابه‌جا کرده، از ترتیب دستی استفاده کن
    if (_manualOrder.isNotEmpty) {
      final pos = <String, int>{};
      for (var i = 0; i < _manualOrder.length; i++) {
        pos[_manualOrder[i]] = i;
      }
      filtered.sort((a, b) {
        final ai = pos[_keyOf(a)] ?? 9999999;
        final bi = pos[_keyOf(b)] ?? 9999999;
        if (ai != bi) return ai.compareTo(bi);
        return 0;
      });
      return filtered;
    }

    // در غیر این صورت همیشه بر اساس پینگ (پین‌شده‌ها اول)
    filtered.sort((a, b) {
      final pa = _pinnedKeys.contains(_keyOf(a));
      final pb = _pinnedKeys.contains(_keyOf(b));
      if (pa != pb) return pa ? -1 : 1;

      final pingA = _pingResults[_keyOf(a)];
      final pingB = _pingResults[_keyOf(b)];
      final validA = pingA != null && pingA > 0;
      final validB = pingB != null && pingB > 0;
      if (validA != validB) return validA ? -1 : 1;
      if (validA && validB) {
        final c = pingA.compareTo(pingB);
        if (c != 0) return c;
      }
      return a.name.compareTo(b.name);
    });

    return filtered;
  }

  Future<void> _select(GameDns dns) async {
    await SettingsService.setGameDns(dns.primary, dns.secondary);
    await SettingsService.setLastDns(_keyOf(dns));
    if (!mounted) return;
    setState(() {
      _activeKey = _keyOf(dns);
      _selectedKey = _keyOf(dns);
    });
    _showMsg(
      _t('DNS فعال شد: ${dns.name} (${dns.primary})',
          'DNS activated: ${dns.name} (${dns.primary})'),
    );
  }



  Future<void> _clear() async {
    await SettingsService.clearGameDns();
    await SettingsService.clearLastDns();
    if (!mounted) return;
    setState(() => _activeKey = null);
    _showMsg(_t('DNS پیش‌فرض فعال شد', 'Default DNS restored'));
  }

  Future<void> _saveManualOrder() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('dns_manual_order_v1', _manualOrder);
  }

  Future<void> _onReorder(int oldIndex, int newIndex) async {
    if (newIndex > oldIndex) newIndex -= 1;
    final list = List<GameDns>.from(_visibleDns);
    final item = list.removeAt(oldIndex);
    list.insert(newIndex, item);
    setState(() {
      _manualOrder = list.map((d) => _keyOf(d)).toList();
    });
    await _saveManualOrder();
  }

  Future<void> _deleteDuplicates() async {
    final list = _visibleDns;
    final seen = <String>{};
    final toDelete = <GameDns>[];
    for (final d in list) {
      final key = _keyOf(d);
      if (seen.contains(key)) {
        toDelete.add(d);
      } else {
        seen.add(key);
      }
    }
    if (toDelete.isEmpty) {
      _showMsg(_t('DNS تکراری وجود ندارد', 'No duplicates'));
      return;
    }
    for (final d in toDelete) {
      if (_customIndexOf(d) != null) {
        for (var i = _customDns.length - 1; i >= 0; i--) {
          if (_customDns[i]['primary'] == d.primary &&
              _customDns[i]['secondary'] == d.secondary) {
            await SettingsService.removeCustomDns(i);
          }
        }
      } else {
        await SettingsService.addHiddenDns(_keyOf(d));
      }
    }
    await _load();
    if (!mounted) return;
    _showMsg(_t('${toDelete.length} تکراری حذف شد',
        '${toDelete.length} duplicates deleted'));
  }

  Future<void> _toggleActive() async {
    // اگر همین الان فعال است → قطع
    if (_activeKey != null) {
      await _clear();
      return;
    }

    // باگ قبلی: همیشه کم‌پینگ‌ترین فعال می‌شد، نه آن‌که کاربر انتخاب کرده.
    final list = _visibleDns;
    if (list.isEmpty) {
      _showMsg(_t('هیچ DNS‌ای موجود نیست', 'No DNS available'));
      return;
    }

    GameDns? target;
    if (_selectedKey != null) {
      for (final d in list) {
        if (_keyOf(d) == _selectedKey) {
          target = d;
          break;
        }
      }
    }
    // اگر چیزی انتخاب نشده، کم‌پینگ‌ترین
    if (target == null) {
      final sorted = List<GameDns>.from(list);
      sorted.sort((a, b) {
        final pa = _pingResults[_keyOf(a)] ?? 99999;
        final pb = _pingResults[_keyOf(b)] ?? 99999;
        return pa.compareTo(pb);
      });
      target = sorted.first;
    }

    await _select(target);
  }

  Future<void> _jumpToSelected() async {
    final targetKey = _selectedKey ?? _activeKey;
    if (targetKey == null) {
      _showMsg(_t('هیچ DNS‌ای انتخاب نشده',
          'No DNS selected'));
      return;
    }
    final list = _visibleDns;
    final idx = list.indexWhere((d) => _keyOf(d) == targetKey);
    if (idx == -1) {
      _showMsg(_t('DNS انتخاب‌شده در لیست نیست',
          'Selected DNS is not in the list'));
      return;
    }
    final key = _tileKeys[targetKey];
    final ctx = key?.currentContext;
    if (ctx != null) {
      await Scrollable.ensureVisible(
        ctx,
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeOutCubic,
        alignment: 0.15,
      );
      return;
    }
    if (_scrollController.hasClients) {
      final approx = (idx * 78.0)
          .clamp(0.0, _scrollController.position.maxScrollExtent);
      await _scrollController.animateTo(
        approx,
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeOut,
      );
    }
  }

  Future<void> _togglePin(GameDns dns) async {
    await SettingsService.togglePinnedDns(_keyOf(dns));
    await _load();
  }

  Future<int> _pingDns(String host, {int port = 53}) async {
    // چند نمونه به‌جای یک تلاش تکی: نتیجه پایدارتره و نوسان/پکت‌لاس واقعی
    // رو هم لحاظ می‌کنه (منطق برگرفته از NetworkProber در WhiteGame).
    final result = await NetworkProber.probeTcp(
      host,
      port: port,
      samples: 3,
      timeout: const Duration(milliseconds: 1200),
    );
    return result.avgMs ?? -1;
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
    var doneCount = 0;
    // تست دسته‌ای و هم‌زمان (نه یکی‌یکی): با لیست‌های بزرگ (صدها/هزاران
    // DNS) تست ترتیبی با تایم‌اوت چندثانیه‌ای روی هر کدوم عملاً غیرقابل
    // استفاده می‌شه. اینجا هم‌زمان چند تا رو تست می‌کنیم (مثل الگوی
    // chunked+awaitAll در WhiteGame) و UI هم قفل نمی‌مونه.
    await NetworkProber.runBatched<GameDns>(
      list,
      12,
      (dns) async {
        if (_cancelTest) return;
        int ping = -1;
        if (dns.primary.isNotEmpty && !dns.primary.startsWith('http')) {
          ping = await _pingDns(dns.primary);
        }
        final key = _keyOf(dns);
        results[key] = ping;
        await SettingsService.saveDnsPingResult(key, ping);
        doneCount++;
        if (!mounted) return;
        setState(() {
          _pingResults[key] = ping;
          _tested = doneCount;
        });
      },
      isCancelled: () => _cancelTest,
    );

    if (!mounted) return;
    setState(() => _testing = false);
    if (_cancelTest) {
      _showMsg(_t('تست لغو شد', 'Test cancelled'));
    } else {
      final ok = results.values.where((v) => v > 0).length;
      _showMsg(_t('$ok از $_total دی‌ان‌اس پاسخ داد',
          '$ok of $_total DNS responded'));
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
    final key = _keyOf(dns);
    await SettingsService.saveDnsPingResult(key, ping);
    if (!mounted) return;
    setState(() {
      _pingResults = Map<String, int>.from(_pingResults)..[key] = ping;
    });
    _showMsg(ping > 0
        ? _t('پینگ: $ping ms', 'Ping: $ping ms')
        : _t('پاسخی نیامد', 'No response'));
  }

  String _lastName = '';
  String _lastPrimary = '';
  String _lastSecondary = '';

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

    _lastName = name;
    _lastPrimary = primary;
    _lastSecondary = secondary;
    return true;
  }

  int? _customIndexOf(GameDns dns) {
    return _customIndexByKey['${dns.primary}|${dns.secondary}'];
  }

  Future<void> _addCustomDns() async {
    final ok = await _showDnsDialog(
      title: _t('افزودن DNS جدید', 'Add New DNS'),
      nameInit: '',
      primaryInit: '',
      secondaryInit: '',
    );
    if (!ok) return;
    await SettingsService.addCustomDns(_lastName, _lastPrimary, _lastSecondary);
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
      await SettingsService.updateCustomDns(
          customIndex, _lastName, _lastPrimary, _lastSecondary);
    } else {
      await SettingsService.setDnsOverride(
          dns.primary, _lastName, _lastPrimary, _lastSecondary);
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
        content: Text(dns.name, style: TextStyle(color: AppColors.muted(ctx))),
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
      await SettingsService.addHiddenDns(_keyOf(dns));
      await SettingsService.removeDnsOverride(dns.primary);
    }

    if (_activeKey == _keyOf(dns)) {
      await SettingsService.clearGameDns();
      _activeKey = null;
    }
    await _load();
    if (!mounted) return;
    _showMsg(_t('حذف شد', 'Deleted'));
  }

  void _copy(GameDns dns) {
    Clipboard.setData(ClipboardData(text: '${dns.primary}, ${dns.secondary}'));
    _showMsg(_t('کپی شد', 'Copied'));
  }

  void _shareDns(GameDns dns) {
    final text = 'DNS: ' + dns.name + '\n'
        'Primary: ' + dns.primary + '\n'
        'Secondary: ' + dns.secondary;
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.elevated(ctx),
        title: Text(
          _t('اشتراک‌گذاری DNS', 'Share DNS'),
          style: TextStyle(color: AppColors.fg(ctx)),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
              ),
              child: QrImageView(
                data: text,
                version: QrVersions.auto,
                size: 220,
                backgroundColor: Colors.white,
              ),
            ),
            const SizedBox(height: 12),
            SelectableText(
              text,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppColors.fg(ctx),
                fontSize: 12,
                fontFamily: 'monospace',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: text));
              Navigator.pop(ctx);
              _showMsg(_t('کپی شد', 'Copied'));
            },
            child: Text(
              _t('کپی متن', 'Copy text'),
              style: TextStyle(color: AppColors.muted(ctx)),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(
              _t('بستن', 'Close'),
              style: const TextStyle(color: AppColors.accent),
            ),
          ),
        ],
      ),
    );
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
    setState(() {
      _sortMode = 1;
      _manualOrder = <String>[];
    });
    // ignore: unawaited_futures
    _saveManualOrder();
    _showMsg(_t('مرتب بر اساس پینگ', 'Sorted by ping'));
  }

  Widget _boosterSwitch(String key, String title) {
    return SwitchListTile(
      contentPadding: EdgeInsets.zero,
      dense: true,
      title: Text(
        title,
        style: TextStyle(color: AppColors.fg(context), fontSize: 12),
      ),
      value: _booster[key] == true,
      activeColor: AppColors.accent,
      onChanged: (v) async {
        setState(() => _booster[key] = v);
        if (key == 'forceIpv4' && v) {
          setState(() => _ipPref = 'ipv4');
          await SettingsService.setDnsIpPreference('ipv4');
        }
        await GameBoosterSettings.save(_booster);
      },
    );
  }

  Widget _ipChip(String value, String label) {
    final active = _ipPref == value;
    return Expanded(
      child: GestureDetector(
        onTap: () => _setIpPref(value),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
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
              fontSize: 12,
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

  Widget _smallIcon({
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: Icon(icon, color: color, size: 17),
      ),
    );
  }

  Widget _buildDnsTile(GameDns dns) {
    final key = _keyOf(dns);
    final active = key == _activeKey;
    final selected = key == _selectedKey;
    final ping = _pingResults[key];
    final pinned = _pinnedKeys.contains(key);

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        color: (active || selected)
            ? AppColors.accent.withOpacity(0.08)
            : AppColors.surface(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: (active || selected)
              ? AppColors.accent
              : AppColors.border(context),
          width: (active || selected) ? 1.5 : 1,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () {
            setState(() => _selectedKey = key);
          },
          // نگه داشتن = فعال‌سازی همان DNS (نه کم‌پینگ‌ترین)
          onLongPress: () => _select(dns),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(4, 8, 8, 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                InkWell(
                  onTap: () => _togglePin(dns),
                  borderRadius: BorderRadius.circular(20),
                  child: Padding(
                    padding: const EdgeInsets.all(6),
                    child: Icon(
                      pinned ? Icons.push_pin : Icons.push_pin_outlined,
                      size: 17,
                      color: pinned
                          ? AppColors.accent
                          : AppColors.muted2(context),
                    ),
                  ),
                ),

                if (active)
                  Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: Icon(Icons.check_circle,
                        size: 18, color: AppColors.accent),
                  ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        dns.name,
                        style: TextStyle(
                          color: AppColors.fg(context),
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 3),
                      Directionality(
                        textDirection: TextDirection.ltr,
                        child: Text(
                          '${dns.primary} · ${dns.secondary}',
                          style: TextStyle(
                            color: AppColors.muted2(context),
                            fontSize: 10.5,
                            fontFamily: 'monospace',
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(width: 4),

                if (ping != null && ping > 0)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                    decoration: BoxDecoration(
                      color: _pingColor(ping).withOpacity(0.15),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      '$ping',
                      style: TextStyle(
                        color: _pingColor(ping),
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  )
                else if (ping != null && ping <= 0)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    child: Text('✕',
                        style: TextStyle(
                            color: AppColors.danger,
                            fontSize: 12,
                            fontWeight: FontWeight.w700)),
                  ),

                const SizedBox(width: 4),

                _smallIcon(
                  icon: Icons.bolt,
                  color: AppColors.warn,
                  onTap: () => _testOneDns(dns),
                ),
                _smallIcon(
                  icon: Icons.edit_outlined,
                  color: AppColors.muted(context),
                  onTap: () => _editDns(dns),
                ),
                if (_customIndexOf(dns) != null)
                    _smallIcon(
                      icon: Icons.share_outlined,
                      color: AppColors.muted(context),
                      onTap: () => _shareDns(dns),
                    ),
                _smallIcon(
                  icon: Icons.delete_outline,
                  color: AppColors.danger,
                  onTap: () => _deleteDns(dns),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildConnectButton() {
    final active = _activeKey != null;
    GameDns? activeDns;
    if (active) {
      for (final d in _visibleDns) {
        if (_keyOf(d) == _activeKey) {
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
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                active ? Icons.dns : Icons.power_settings_new,
                size: 38,
                color:
                    active ? AppColors.accent : AppColors.muted2(context),
              ),
              const SizedBox(height: 6),
              Text(
                active
                    ? _t('قطع DNS', 'Disable DNS')
                    : _t('فعال‌سازی DNS', 'Enable DNS'),
                style: TextStyle(
                  color:
                      active ? AppColors.accent : AppColors.muted2(context),
                  fontSize: 11.5,
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

  void _showDnsMenu() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.elevated(context),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 8),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.muted2(context),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 12),
              ListTile(
                leading: const Icon(Icons.add_circle_outline,
                    color: AppColors.accent),
                title: Text(_t('افزودن DNS جدید', 'Add new DNS'),
                    style: TextStyle(color: AppColors.fg(context))),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _addCustomDns();
                },
              ),
              ListTile(
                leading: const Icon(Icons.content_copy,
                    color: AppColors.accent),
                title: Text(_t('حذف DNS تکراری', 'Delete duplicates'),
                    style: TextStyle(color: AppColors.fg(context))),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _deleteDuplicates();
                },
              ),
              ListTile(
                leading:
                    const Icon(Icons.my_location, color: AppColors.accent),
                title: Text(_t('پیدا کردن انتخاب‌شده', 'Find selected'),
                    style: TextStyle(color: AppColors.fg(context))),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _jumpToSelected();
                },
              ),
              Divider(color: AppColors.border(context), height: 1),
              ListTile(
                leading: Icon(
                  _sortMode == 0 ? Icons.sort_by_alpha : Icons.speed,
                  color: AppColors.accent,
                ),
                title: Text(
                    _t('مرتب‌سازی بر اساس پینگ', 'Sort by ping'),
                    style: TextStyle(color: AppColors.fg(context))),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _toggleSort();
                },
              ),
            ],
          ),
        );
      },
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
            icon: Icon(Icons.menu, color: AppColors.fg(context)),
            tooltip: _t('منو', 'Menu'),
            onPressed: _showDnsMenu,
          ),
        ],
      ),
      body: Column(
        children: [
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

          Container(
            margin: const EdgeInsets.fromLTRB(12, 10, 12, 0),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.surface(context),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.border(context)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    _t('نسخه‌ی IP', 'IP version'),
                    style: TextStyle(
                      color: AppColors.muted(context),
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Flexible(
                  flex: 3,
                  child: Row(
                    children: [
                      _ipChip('ipv4', 'IPv4'),
                      const SizedBox(width: 4),
                      _ipChip('ipv6', 'IPv6'),
                      const SizedBox(width: 4),
                      _ipChip('both', _t('هر دو', 'Both')),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // ---- حالت بازی: DNS + فایروال سبک ----
          Container(
            margin: const EdgeInsets.fromLTRB(12, 10, 12, 0),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: (_booster['enabled'] == true)
                  ? AppColors.accent.withOpacity(0.08)
                  : AppColors.surface(context),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: (_booster['enabled'] == true)
                    ? AppColors.accent
                    : AppColors.border(context),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                        title: Text(
                          _t('حالت بازی (DNS + فایروال)',
                              'Game Mode (DNS + Firewall)'),
                          style: TextStyle(
                            color: AppColors.fg(context),
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        subtitle: _boosterExpanded
                            ? Text(
                                _t(
                                  'مسدودسازی QUIC/IPv6/تله‌متری + DNS بازی',
                                  'Block QUIC/IPv6/telemetry + game DNS',
                                ),
                                style: TextStyle(
                                    color: AppColors.muted2(context),
                                    fontSize: 10),
                              )
                            : null,
                        value: _booster['enabled'] == true,
                        activeColor: AppColors.accent,
                        onChanged: (v) async {
                          setState(() {
                            _booster['enabled'] = v;
                            if (v) _boosterExpanded = true;
                          });
                          if (v) {
                            setState(() {
                              _booster['blockQuic'] = true;
                              _booster['forceIpv4'] = true;
                              _ipPref = 'ipv4';
                            });
                            await SettingsService.setDnsIpPreference('ipv4');
                          }
                          await GameBoosterSettings.save(_booster);
                        },
                      ),
                    ),
                    IconButton(
                      tooltip: _boosterExpanded
                          ? _t('جمع کردن', 'Collapse')
                          : _t('باز کردن', 'Expand'),
                      onPressed: () =>
                          setState(() => _boosterExpanded = !_boosterExpanded),
                      icon: Icon(
                        _boosterExpanded
                            ? Icons.keyboard_arrow_up
                            : Icons.keyboard_arrow_down,
                        color: AppColors.accent,
                      ),
                    ),
                  ],
                ),
                if (_booster['enabled'] == true && _boosterExpanded) ...[
                  const Divider(height: 12),
                  _boosterSwitch(
                    'blockQuic',
                    _t('مسدودسازی QUIC (UDP/443)', 'Block QUIC (UDP/443)'),
                  ),
                  _boosterSwitch(
                    'forceIpv4',
                    _t('اجبار IPv4', 'Force IPv4'),
                  ),
                  _boosterSwitch(
                    'blockTelemetry',
                    _t('مسدودسازی تله‌متری بازی', 'Block game telemetry'),
                  ),
                  _boosterSwitch(
                    'blockAds',
                    _t('مسدودسازی تبلیغات', 'Block ads'),
                  ),
                  _boosterSwitch(
                    'smallDnsCache',
                    _t('کش DNS کوچک‌تر', 'Smaller DNS cache'),
                  ),
                ],
              ],
            ),
          ),

          const SizedBox(height: 10),
          _buildConnectButton(),
          const SizedBox(height: 10),

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
                    _t(
                        '$_tested از $_total · ${_total - _tested} باقی',
                        '$_tested of $_total · ${_total - _tested} left'),
                    style: TextStyle(
                        color: AppColors.muted2(context), fontSize: 11),
                  ),
                ],
              ),
            ),

          Expanded(
            child: ReorderableListView.builder(
              scrollController: _scrollController,
              // فاصلهٔ بیشتر پایین تا آخرین DNS زیر نوار سیستم بریده نشود
              padding: EdgeInsets.fromLTRB(
                10,
                6,
                10,
                96 + MediaQuery.of(context).padding.bottom,
              ),
              itemCount: all.length,
              onReorder: _onReorder,
              buildDefaultDragHandles: false,
              proxyDecorator: (child, index, animation) {
                return Material(
                  color: Colors.transparent,
                  elevation: 6,
                  borderRadius: BorderRadius.circular(12),
                  child: child,
                );
              },
              itemBuilder: (_, i) {
                final dns = all[i];
                final k = _keyOf(dns);
                final tileKey = _tileKeys.putIfAbsent(k, () => GlobalKey());
                return ReorderableDelayedDragStartListener(
                  key: ValueKey('dns_reorder_$k'),
                  index: i,
                  child: KeyedSubtree(
                    key: tileKey,
                    child: _buildDnsTile(dns),
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
