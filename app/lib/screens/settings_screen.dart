import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'log_viewer_screen.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../services/app_colors.dart';
import '../services/settings_service.dart';
import 'security_test_screen.dart';
import 'backup_screen.dart';
import 'connection_log_screen.dart';
import 'engines_screen.dart';
import 'quality_history_screen.dart';
import '../services/warp_scout_scheduler.dart';
import '../services/quality_alert.dart';
import '../services/server_batch_export.dart';
import '../services/warp_batch_tester.dart';
import '../services/warp_endpoint_health_monitor.dart';
import '../services/update_service.dart';
import 'announcements_screen.dart';
import 'game_dns_screen.dart';
import 'game_booster_screen.dart';
import 'anti_sanction_screen.dart';
import 'live_monitor_screen.dart';
import 'test_settings_screen.dart';
import 'hev_engine_screen.dart';
import 'xray_settings_screen.dart';
import 'routing_screen.dart';
import 'geo_assets_screen.dart';
import 'per_app_proxy_screen.dart';

class SettingsScreen extends StatefulWidget {
  final String themeMode;
  final String language;
  final Function(String) onThemeChanged;
  final Function(String) onLanguageChanged;
  final double fontScale;
  final Function(double) onFontScaleChanged;

  const SettingsScreen({
    super.key,
    required this.themeMode,
    required this.language,
    required this.onThemeChanged,
    required this.onLanguageChanged,
    this.fontScale = 1.0,
    this.onFontScaleChanged = _defaultFontScale,
  });

  static void _defaultFontScale(double _) {}

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late String _theme;
  late String _lang;
  String _vpnMode = 'vpn';
  bool _checkingUpdate = false;
  int _autoTestMin = 0;

  @override
  void initState() {
    super.initState();
    // WARP Scout
    _scoutSchedulerEnabled = WarpScoutScheduler.instance.enabled;
    // ignore: unawaited_futures
    _loadScoutState();
    _theme = widget.themeMode;
    // ignore: unawaited_futures
    SettingsService.getAutoTestIntervalMin().then((v) {
      if (mounted) setState(() => _autoTestMin = v);
    });
    _lang = widget.language;
    // ignore: unawaited_futures
    SettingsService.getVpnMode().then((m) {
      if (mounted) setState(() => _vpnMode = m);
    });
    // These three loaders exist but were never called, which is why the
    // toggles/sliders kept falling back to their hard-coded defaults every
    // time the screen opened: the value was saved, then never read back.
    // ignore: unawaited_futures
    _loadSmartResumePrefSettings();
    // ignore: unawaited_futures
    _loadQualityPrefs();
    // ignore: unawaited_futures
    _loadBatchPrefs();
  }

  Future<void> _loadScoutState() async {
    await WarpScoutScheduler.instance.restore();
    if (!mounted) return;
    setState(() {
      _scoutSchedulerEnabled = WarpScoutScheduler.instance.enabled;
    });
  }

  // (leftover block removed)

  String _t(String fa, String en) => _lang == 'fa' ? fa : en;

  // WARP Scout scheduler state
  bool _scoutSchedulerEnabled = false;

  List<int> _intervalsForScout() => const [
        15, 30, 60, 120, 240, 480, 720,
      ];

  // Batch test state
  bool _batchAutoEnabled = false;
  int _qualityThreshold = 40;
  bool _qualityAlertEnabled = true;
  bool _smartResumeEnabled = true;
  int _batchParallelism = 2;

  Future<void> _exportAllServers() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final exportRaw = prefs.getString('quick_export_servers_v1');
      if (exportRaw == null || exportRaw.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_t(
                'داده‌ای برای خروجی نیست — اول یه سرور اضافه کن',
                'Nothing to export — add a server first')),
            duration: const Duration(seconds: 2),
          ),
        );
        return;
      }
      await Clipboard.setData(ClipboardData(text: exportRaw));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_t(
              'خروجی گرفته شد (' + exportRaw.length.toString() + ' بایت)',
              'Exported (' + exportRaw.length.toString() + ' bytes)')),
          duration: const Duration(seconds: 2),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_t('خطا: ' + e.toString(), 'Error: ' + e.toString())),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> _loadSmartResumePrefSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!mounted) return;
      setState(() {
        _smartResumeEnabled = prefs.getBool('smart_resume_v1') ?? true;
      });
    } catch (_) {}
  }

  Future<void> _saveSmartResume(bool v) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('smart_resume_v1', v);
    } catch (_) {}
  }

  Future<void> _loadQualityPrefs() async {
    try {
      await QualityAlert.instance.restore();
      if (!mounted) return;
      setState(() {
        _qualityThreshold = QualityAlert.instance.threshold;
        _qualityAlertEnabled = QualityAlert.instance.enabled;
      });
    } catch (_) {}
  }

  Future<void> _loadBatchPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!mounted) return;
      setState(() {
        _batchAutoEnabled = prefs.getBool('batch_auto_v1') ?? false;
        _batchParallelism = prefs.getInt('batch_parallelism_v1') ?? 2;
      });
    } catch (_) {}
  }

  Future<void> _saveBatchPref(String key, Object value) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (value is bool) await prefs.setBool(key, value);
      if (value is int) await prefs.setInt(key, value);
    } catch (_) {}
  }

  /// فقط https و فقط دامنه‌های GitHub (ریپو و دانلود بروزرسانی).
  bool _isAllowedUrl(Uri uri) {
    if (uri.scheme != 'https') return false;
    final h = uri.host.toLowerCase();
    return h == 'github.com' ||
        h.endsWith('.github.com') ||
        h.endsWith('.githubusercontent.com');
  }

  Future<void> _openUrl(String url) async {
    try {
      final uri = Uri.parse(url);
      if (!_isAllowedUrl(uri)) {
        throw const FormatException('blocked url');
      }
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (e) {
      await Clipboard.setData(ClipboardData(text: url));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(_t('لینک کپی شد — توی مرورگر پیست کن',
                  'Link copied — paste in browser')),
              duration: const Duration(seconds: 4)),
        );
      }
    }
  }

  int _compareVersion(String a, String b) {
    final pa = a.split('.').map((e) => int.tryParse(e) ?? 0).toList();
    final pb = b.split('.').map((e) => int.tryParse(e) ?? 0).toList();
    final len = pa.length > pb.length ? pa.length : pb.length;
    for (var i = 0; i < len; i++) {
      final va = i < pa.length ? pa[i] : 0;
      final vb = i < pb.length ? pb[i] : 0;
      if (va != vb) return va - vb;
    }
    return 0;
  }

  Future<void> _checkUpdate() async {
    setState(() => _checkingUpdate = true);
    try {
      final info = await UpdateService.fetchLatest();
      final isNewer =
          _compareVersion(info.version, SettingsService.currentVersion) > 0;
      if (!mounted) return;
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: AppColors.elevated(ctx),
          title: Text(
            isNewer
                ? _t('بروزرسانی موجود است', 'Update Available')
                : _t('برنامه بروز است', 'App is up to date'),
            style: TextStyle(color: AppColors.fg(ctx)),
          ),
          content: Text(
            isNewer
                ? _t(
                    'نسخه فعلی: ${SettingsService.currentVersion}\nنسخه جدید: ${info.version}\nمعماری گوشی: ${info.abi}',
                    'Current: ${SettingsService.currentVersion}\nNew: ${info.version}\nCPU: ${info.abi}')
                : _t(
                    'نسخه فعلی: ${SettingsService.currentVersion}\nشما آخرین نسخه را دارید',
                    'Current: ${SettingsService.currentVersion}\nYou have the latest version'),
            style: TextStyle(color: AppColors.muted(ctx), height: 1.7),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(_t('بستن', 'Close'),
                  style: TextStyle(color: AppColors.muted(ctx))),
            ),
            if (isNewer)
              TextButton(
                onPressed: () async {
                  Navigator.pop(ctx);
                  await _openUrl(info.apkUrl);
                },
                child: Text(_t('دانلود APK', 'Download APK'),
                    style: const TextStyle(color: AppColors.accent)),
              ),
          ],
        ),
      );
    } catch (e) {
      _showMsg(_t('خطا در بررسی بروزرسانی', 'Error checking for update'));
    } finally {
      if (mounted) setState(() => _checkingUpdate = false);
    }
  }

  void _showMsg(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg(context),
      appBar: AppBar(
        backgroundColor: AppColors.bg(context),
        elevation: 0,
        iconTheme: IconThemeData(color: AppColors.fg(context)),
        title: Text(_t('تنظیمات', 'Settings'),
            style: TextStyle(color: AppColors.fg(context))),
        centerTitle: true,
        actions: [
          IconButton(
            onPressed: _exportAllServers,
            icon: const Icon(Icons.ios_share),
            tooltip: _t('خروجی همه سرورها', 'Export all servers'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ------- حالت اتصال -------
          _sectionTitle(_t('حالت اتصال', 'Connection Mode')),
          _card(
            context,
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      _vpnMode == 'vpn'
                          ? Icons.vpn_lock
                          : Icons.settings_ethernet,
                      color: AppColors.muted(context),
                      size: 20,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        _lang == 'fa'
                            ? (_vpnMode == 'vpn'
                                ? 'VPN کامل (پیش‌فرض)'
                                : 'فقط پروکسی (SOCKS/HTTP)')
                            : (_vpnMode == 'vpn'
                                ? 'Full VPN (default)'
                                : 'Proxy only (SOCKS/HTTP)'),
                        style: TextStyle(
                            color: AppColors.fg(context), fontSize: 14),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    _modeChip(context, 'vpn', _t('VPN', 'VPN')),
                    const SizedBox(width: 6),
                    _modeChip(context, 'proxy', _t('فقط پروکسی', 'Proxy only')),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  _lang == 'fa'
                      ? 'در حالت «فقط پروکسی» هیچ VPN‌ای روشن نمی‌شه و باید برنامه‌ها رو دستی روی SOCKS5 127.0.0.1:10808 (یا HTTP روی 10809) تنظیم کنی.'
                      : 'In proxy-only mode no system VPN is created; configure apps manually to SOCKS5 127.0.0.1:10808 (or HTTP on 10809).',
                  style: TextStyle(
                      color: AppColors.muted2(context),
                      fontSize: 11,
                      height: 1.5),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // ------- منابع تلگرام -------
          // ------- Smart Resume ---------
          _sectionTitle(_t('اتصال هوشمند', 'Smart Resume')),

          _card(
            context,
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              activeColor: AppColors.accent,
              title: Text(
                _t('اتصال خودکار بعد از بازگشت شبکه',
                    'Auto-reconnect on network return'),
                style:
                    TextStyle(color: AppColors.fg(context), fontSize: 13),
              ),
              subtitle: Text(
                _t(
                  'وقتی شبکه از قطع به وصل برگرده، خودکار به آخرین سرور وصل شه. اگه دستی قطع کنی، وصل نمی‌شه.',
                  'Reconnects to the last server when network comes back. Does not reconnect if you manually disconnected.',
                ),
                style: TextStyle(
                    color: AppColors.muted2(context),
                    fontSize: 10.5,
                    height: 1.4),
              ),
              value: _smartResumeEnabled,
              onChanged: (v) async {
                setState(() => _smartResumeEnabled = v);
                await _saveSmartResume(v);
              },
            ),
          ),

          _sectionTitle(_t('DNS بازی', 'Game DNS')),
          _card(
            context,
            InkWell(
              onTap: () async {
                await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => GameDnsScreen(language: _lang),
                  ),
                );
                if (mounted) setState(() {});
              },
              child: Row(
                children: [
                  Icon(Icons.sports_esports,
                      color: AppColors.muted(context), size: 20),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _t('کاهش پینگ بازی', 'Reduce game ping'),
                          style: TextStyle(
                              color: AppColors.fg(context), fontSize: 14),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _t(
                            'DNS های تست‌شده برای فری‌فایر، پابجی، کلش',
                            'Tested DNS for Free Fire, PUBG, CoC',
                          ),
                          style: TextStyle(
                            color: AppColors.muted2(context),
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(Icons.chevron_left,
                      color: AppColors.muted2(context), size: 20),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          const SizedBox(height: 8),
          _card(
            context,
            InkWell(
              onTap: () async {
                await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => GameBoosterScreen(language: _lang),
                  ),
                );
                if (mounted) setState(() {});
              },
              child: Row(
                children: [
                  Icon(Icons.speed, color: AppColors.muted(context), size: 20),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _t('بوستر بازی (مسابقه DNS و پینگ بازی)', 'Game Booster (DNS race & game ping)'),
                      style: TextStyle(color: AppColors.fg(context), fontSize: 14),
                    ),
                  ),
                  Icon(Icons.chevron_left,
                      color: AppColors.muted2(context), size: 20),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          _card(
            context,
            InkWell(
              onTap: () async {
                await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => AntiSanctionScreen(language: _lang),
                  ),
                );
                if (mounted) setState(() {});
              },
              child: Row(
                children: [
                  Icon(Icons.travel_explore, color: AppColors.muted(context), size: 20),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _t('رفع تحریم / جمینای', 'Sanction / Gemini fix'),
                      style: TextStyle(color: AppColors.fg(context), fontSize: 14),
                    ),
                  ),
                  Icon(Icons.chevron_left,
                      color: AppColors.muted2(context), size: 20),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          // ------- تست و امنیت -------
          _sectionTitle(_t('تست و امنیت', 'Test & Security')),
          _card(
            context,
            InkWell(
              onTap: () async {
                await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) =>
                        SecurityTestScreen(language: _lang),
                  ),
                );
              },
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.security,
                    color: AppColors.accent),
                title: Text(
                  _t('IP / سرعت / نشت DNS',
                      'IP / Speed / DNS leak'),
                  style: TextStyle(color: AppColors.fg(context)),
                ),
                subtitle: Text(
                  _t(
                    'تست IP خروجی، سرعت دانلود و بررسی نشت DNS',
                    'Check exit IP, download speed, and DNS leak',
                  ),
                  style: TextStyle(
                      color: AppColors.muted2(context), fontSize: 11),
                ),
                trailing: Icon(Icons.chevron_left,
                    color: AppColors.muted(context)),
              ),
            ),
          ),
          const SizedBox(height: 16),

          // ------- هسته و تست -------
          _sectionTitle(_t('هسته و تست', 'Core & Test')),
          _card(
            context,
            InkWell(
              onTap: () async {
                await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => EnginesScreen(language: _lang),
                  ),
                );
                if (mounted) setState(() {});
              },
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.memory,
                    color: AppColors.accent),
                title: Text(
                  _t('هسته‌ها و موتورها', 'Engines & Cores'),
                  style: TextStyle(color: AppColors.fg(context)),
                ),
                subtitle: Text(
                  _t(
                    'لیست هسته‌های native با نسخه و چک آپدیت خودکار',
                    'Native cores list with version & auto update check',
                  ),
                  style: TextStyle(
                      color: AppColors.muted2(context), fontSize: 11),
                ),
                trailing: Icon(Icons.chevron_left,
                    color: AppColors.muted(context)),
              ),
            ),
          ),
          const SizedBox(height: 12),
          _card(
            context,
            InkWell(
              onTap: () async {
                await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) =>
                        QualityHistoryScreen(language: _lang),
                  ),
                );
              },
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.timeline,
                    color: AppColors.accent),
                title: Text(
                  _t('تاریخچه کیفیت', 'Quality history'),
                  style: TextStyle(color: AppColors.fg(context)),
                ),
                subtitle: Text(
                  _t(
                    'نمودار امتیاز اتصال، پینگ و نوسان در بازه‌های زمانی',
                    'Chart of connection score, ping and jitter over time',
                  ),
                  style: TextStyle(
                      color: AppColors.muted2(context), fontSize: 11),
                ),
                trailing: Icon(Icons.chevron_left,
                    color: AppColors.muted(context)),
              ),
            ),
          ),
          const SizedBox(height: 12),
          _card(
            context,
            Column(
              children: [
                _navRow(
                  context,
                  icon: Icons.memory,
                  title: _t('تنظیمات هسته Xray', 'Xray core settings'),
                  subtitle: _t(
                    'VPN، DNS، Mux، Fragment، Observatory',
                    'VPN, DNS, Mux, Fragment, Observatory',
                  ),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) =>
                            XraySettingsScreen(language: _lang),
                      ),
                    );
                  },
                ),
                Divider(height: 1, color: AppColors.border(context)),
                _navRow(
                  context,
                  icon: Icons.alt_route,
                  title: _t('مسیریابی', 'Routing'),
                  subtitle: _t(
                    'قوانین دامنه/IP، استراتژی، LAN bypass',
                    'Domain/IP rules, strategy, LAN bypass',
                  ),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) =>
                            RoutingScreen(language: _lang),
                      ),
                    );
                  },
                ),
                Divider(height: 1, color: AppColors.border(context)),
                _navRow(
                  context,
                  icon: Icons.map_outlined,
                  title: _t('فایل‌های Geo', 'Geo assets'),
                  subtitle: _t(
                    'geoip.dat، geosite.dat، دانلود/حذف',
                    'geoip.dat, geosite.dat, download/delete',
                  ),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) =>
                            GeoAssetsScreen(language: _lang),
                      ),
                    );
                  },
                ),
                Divider(height: 1, color: AppColors.border(context)),
                _navRow(
                  context,
                  icon: Icons.tune,
                  title: _t('موتور HEV', 'HEV Engine'),
                  subtitle: _t(
                    'تونل، SOCKS5، mapdns، misc',
                    'Tunnel, SOCKS5, mapdns, misc',
                  ),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) =>
                            HevEngineScreen(language: _lang),
                      ),
                    );
                  },
                ),
                Divider(height: 1, color: AppColors.border(context)),
                _navRow(
                  context,
                  icon: Icons.speed,
                  title: _t('تنظیمات تست و رتبه‌بندی', 'Test & ranking'),
                  subtitle: _t(
                    'نمونه، هم‌زمانی، آدرس تست',
                    'Samples, concurrency, delay URL',
                  ),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) =>
                            TestSettingsScreen(language: _lang),
                      ),
                    );
                  },
                ),
                Divider(height: 1, color: AppColors.border(context)),
                _navRow(
                  context,
                  icon: Icons.notifications_none,
                  title: _t('اعلان‌ها', 'Announcements'),
                  subtitle: _t(
                    'اتصال، شبکه، اشتراک، هسته',
                    'Connection, network, subscription, core',
                  ),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) =>
                            AnnouncementsScreen(language: _lang),
                      ),
                    );
                  },
                ),
                Divider(height: 1, color: AppColors.border(context)),
                _navRow(
                  context,
                  icon: Icons.monitor_heart_outlined,
                  title: _t('مانیتور زنده', 'Live Monitor'),
                  subtitle: _t(
                    'مصرف CPU، حافظه، باتری، حرارت و سرعت شبکه',
                    'CPU, memory, battery, temp and network speed',
                  ),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) =>
                            LiveMonitorScreen(language: _lang),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // ------- تم -------
          _card(
            context,
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.apps, color: AppColors.accent, size: 20),
              title: Text(
                _t('پراکسی هر برنامه', 'Per-app proxy'),
                style: TextStyle(color: AppColors.fg(context), fontSize: 14),
              ),
              subtitle: Text(
                _t('انتخاب برنامه‌هایی که از VPN رد نشوند',
                    'Choose apps that bypass or use the VPN'),
                style: TextStyle(color: AppColors.muted2(context), fontSize: 11),
              ),
              trailing: Icon(Icons.chevron_left,
                  color: AppColors.muted2(context), size: 20),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) =>
                      PerAppProxyScreen(language: widget.language),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          _sectionTitle(_t('عیب‌یابی', 'Diagnostics')),
          _card(
            context,
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.bug_report_outlined,
                  color: AppColors.accent, size: 20),
              title: Text(
                _t('لاگ‌های برنامه', 'App Logs'),
                style: TextStyle(color: AppColors.fg(context), fontSize: 14),
              ),
              subtitle: Text(
                _t('مشاهده‌ی کامل لاگ‌های هسته‌ها (Psiphon/Tor/Xray/...)',
                    'Full log of all cores (Psiphon/Tor/Xray/...)'),
                style: TextStyle(color: AppColors.muted2(context), fontSize: 11),
              ),
              trailing: Icon(Icons.chevron_left,
                  color: AppColors.muted2(context), size: 20),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => LogViewerScreen(language: widget.language),
                ),
              ),
            ),
          ),

          _sectionTitle(_t('تم برنامه', 'Theme')),
          _card(
            context,
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.brightness_6,
                        color: AppColors.muted(context), size: 20),
                    const SizedBox(width: 12),
                    Text(
                      _theme == 'dark'
                          ? _t('تاریک', 'Dark')
                          : _theme == 'light'
                              ? _t('روشن', 'Light')
                              : _t('سیستم', 'System'),
                      style: TextStyle(
                          color: AppColors.fg(context), fontSize: 14),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    _themeChip(context, 'dark', _t('تاریک', 'Dark')),
                    const SizedBox(width: 6),
                    _themeChip(context, 'light', _t('روشن', 'Light')),
                    const SizedBox(width: 6),
                    _themeChip(context, 'system', _t('سیستم', 'System')),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // ------- زبان -------
          _sectionTitle(_t('زبان', 'Language')),
          _card(
            context,
            Row(
              children: [
                Icon(Icons.language,
                    color: AppColors.muted(context), size: 20),
                const SizedBox(width: 12),
                Expanded(
                  child: Row(
                    children: [
                      _langChip(context, 'fa', '🇮🇷 فارسی'),
                      const SizedBox(width: 6),
                      _langChip(context, 'en', '🇬🇧 English'),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // ------- اندازه فونت -------
          _sectionTitle(_t('اندازه فونت', 'Font size')),
          _card(
            context,
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.text_fields,
                        color: AppColors.muted(context), size: 20),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        _t('مقیاس متن', 'Text scale'),
                        style: TextStyle(
                            color: AppColors.fg(context), fontSize: 14),
                      ),
                    ),
                    Text(
                      '${(widget.fontScale * 100).round()}%',
                      style: const TextStyle(
                          color: AppColors.accent,
                          fontSize: 13,
                          fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
                Slider(
                  value: widget.fontScale,
                  min: 0.8,
                  max: 1.4,
                  divisions: 6,
                  activeColor: AppColors.accent,
                  label: '${(widget.fontScale * 100).round()}%',
                  onChanged: (v) {
                    widget.onFontScaleChanged(v);
                    setState(() {});
                  },
                ),
              ],
            ),
          ),

          // ------- تاریخچه اتصال -------
          _sectionTitle(_t('تاریخچه', 'History')),
          _card(
            context,
            InkWell(
              onTap: () async {
                await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) =>
                        ConnectionLogScreen(language: _lang),
                  ),
                );
              },
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.history,
                    color: AppColors.accent),
                title: Text(
                  _t('تاریخچه اتصال‌ها',
                      'Connection history'),
                  style: TextStyle(color: AppColors.fg(context)),
                ),
                subtitle: Text(
                  _t(
                    'آخرین اتصال‌ها، قطع‌ها و خطاها',
                    'Recent connects, disconnects, and errors',
                  ),
                  style: TextStyle(
                      color: AppColors.muted2(context), fontSize: 11),
                ),
                trailing: Icon(Icons.chevron_left,
                    color: AppColors.muted(context)),
              ),
            ),
          ),
          const SizedBox(height: 16),

          // ------- پشتیبان‌گیری -------
          _sectionTitle(_t('پشتیبان‌گیری', 'Backup')),
          _card(
            context,
            InkWell(
              onTap: () async {
                await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => BackupScreen(language: _lang),
                  ),
                );
              },
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.backup_outlined,
                    color: AppColors.accent),
                title: Text(
                  _t('خروجی/بازیابی تنظیمات',
                      'Export/Restore settings'),
                  style: TextStyle(color: AppColors.fg(context)),
                ),
                subtitle: Text(
                  _t(
                    'همه‌ی داده‌ها را در یک فایل JSON ذخیره کن یا برگردان',
                    'Save all data in one JSON file or restore it',
                  ),
                  style: TextStyle(
                      color: AppColors.muted2(context), fontSize: 11),
                ),
                trailing: Icon(Icons.chevron_left,
                    color: AppColors.muted(context)),
              ),
            ),
          ),
          const SizedBox(height: 16),

          // ------- بروزرسانی -------
          _sectionTitle(_t('بروزرسانی', 'Update')),
          _card(
            context,
            InkWell(
              onTap: _checkingUpdate ? null : _checkUpdate,
              child: Row(
                children: [
                  Icon(Icons.system_update_alt,
                      color: AppColors.muted(context), size: 20),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(_t('بررسی بروزرسانی برنامه',
                            'Check for app updates'),
                            style: TextStyle(
                                color: AppColors.fg(context), fontSize: 14)),
                        const SizedBox(height: 2),
                        Text('v${SettingsService.currentVersion}',
                            style: TextStyle(
                                color: AppColors.muted2(context),
                                fontSize: 11)),
                      ],
                    ),
                  ),
                  if (_checkingUpdate)
                    const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: AppColors.accent))
                  else
                    Icon(Icons.chevron_left,
                        color: AppColors.muted2(context), size: 20),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // ------- درباره -------
          _sectionTitle(_t('درباره برنامه', 'About')),
          _card(
            context,
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.code,
                        color: AppColors.muted(context), size: 20),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        _t('حسن - نسخه ${SettingsService.currentVersion}',
                            'Hasan - v${SettingsService.currentVersion}'),
                        style: TextStyle(
                            color: AppColors.fg(context),
                            fontSize: 14,
                            fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  _lang == 'fa'
                      ? 'این برنامه با تلاش حسن سیگما برای راحت‌تر شدن از دست فیلتر و محدودیت‌ها توسعه یافته است — مخصوص کسانی که همیشه با فیلترشکن درگیر بوده‌اند (مثل دوکی سوسکی، ابول ابی و کباب‌السگ!). سه هفته بی‌خوابی کشیدم تا به اینجا برسد. و با تقدیم ویژه به پدر بزرگوارم، حاجی احسان ❤️ — حاجی جون، غمت نباشه.'
                      : 'Built with care by Hasan Sigma to make life easier under filtering — for anyone who is always wrestling with VPNs. Three weeks of sleepless nights went into this. Dedicated with love to my dear father, Hajji Ehsan ❤️.',
                  style: TextStyle(
                      color: AppColors.muted(context),
                      fontSize: 12,
                      height: 1.7),
                ),
                const SizedBox(height: 14),
                InkWell(
                  onTap: () => _openUrl('https://github.com/Hasanqwjdjd/hasan_vpn'),
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: AppColors.elevated(context),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppColors.border(context)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.open_in_new,
                            color: AppColors.muted(context), size: 16),
                        const SizedBox(width: 8),
                        Text(_t('مشاهده در گیت‌هاب', 'View on GitHub'),
                            style: TextStyle(
                                color: AppColors.fg(context), fontSize: 13)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 40),
        ],
      ),
    );
  }

  Widget _sectionTitle(String text) => Padding(
        padding: const EdgeInsets.only(right: 8, bottom: 8),
        child: Text(text,
            style: const TextStyle(
                color: AppColors.accent,
                fontSize: 12,
                fontWeight: FontWeight.w600)),
      );

  Widget _card(BuildContext context, Widget child) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.surface(context),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border(context)),
        ),
        child: child,
      );

  Widget _navRow(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            Icon(icon, color: AppColors.muted(context), size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: TextStyle(
                          color: AppColors.fg(context), fontSize: 14)),
                  const SizedBox(height: 2),
                  Text(subtitle,
                      style: TextStyle(
                          color: AppColors.muted2(context), fontSize: 11)),
                ],
              ),
            ),
            Icon(Icons.chevron_left,
                color: AppColors.muted2(context), size: 20),
          ],
        ),
      ),
    );
  }

  Widget _themeChip(BuildContext context, String value, String label) {
    final active = _theme == value;
    return GestureDetector(
      onTap: () {
        setState(() => _theme = value);
        widget.onThemeChanged(value);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: active
              ? AppColors.accent.withOpacity(0.15)
              : AppColors.elevated(context),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
              color: active ? AppColors.accent : AppColors.border(context)),
        ),
        child: Text(label,
            style: TextStyle(
                color: active ? AppColors.accent : AppColors.muted(context),
                fontSize: 11)),
      ),
    );
  }

  Widget _langChip(BuildContext context, String value, String label) {
    final active = _lang == value;
    return Expanded(
      child: GestureDetector(
        onTap: () {
          setState(() => _lang = value);
          widget.onLanguageChanged(value);
        },
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: active
                ? AppColors.accent.withOpacity(0.15)
                : AppColors.elevated(context),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
                color: active ? AppColors.accent : AppColors.border(context)),
          ),
          child: Text(label,
              textAlign: TextAlign.center,
              style: TextStyle(
                  color:
                      active ? AppColors.accent : AppColors.muted(context),
                  fontSize: 12)),
        ),
      ),
    );
  }

  Widget _modeChip(BuildContext context, String value, String label) {
    final active = _vpnMode == value;
    return Expanded(
      child: GestureDetector(
        onTap: () {
          setState(() => _vpnMode = value);
          SettingsService.setVpnMode(value);
        },
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: active
                ? AppColors.accent.withOpacity(0.15)
                : AppColors.elevated(context),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
                color: active ? AppColors.accent : AppColors.border(context)),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: active ? AppColors.accent : AppColors.muted(context),
              fontSize: 12,
            ),
          ),
        ),
      ),
    );
  }
}
