import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../controllers/connection.dart';
import '../l10n/s.dart';
import '../services/store_service.dart';
import '../ui/fx/fx.dart';
import '../ui/kit/ios_kit.dart';
import '../ui/kit/tiles.dart';
import '../ui/theme/ios_palette.dart';

/// Geph — پورت `ui/geph/*` از MLM (نسخهٔ سبک P2b):
/// نصب هسته از استور (امضاشده)، کشور خروج، حساب (اختیاری)، دیال اتصال.
class GephScreen extends StatefulWidget {
  const GephScreen({super.key});

  @override
  State<GephScreen> createState() => _GephScreenState();
}

class _GephScreenState extends State<GephScreen> {
  final ConnectionController _conn = ConnectionController.instance;

  bool _installed = false;
  String? _version;
  bool _installing = false;
  int _dlNow = 0;
  int _dlTotal = 0;
  final List<String> _installLog = [];

  static const List<(String, String)> kExits = [
    ('', 'خودکار / Auto'),
    ('NL', 'هلند / Netherlands'),
    ('DE', 'آلمان / Germany'),
    ('US', 'آمریکا / United States'),
    ('SE', 'سوئد / Sweden'),
    ('FI', 'فنلاند / Finland'),
    ('GB', 'انگلستان / United Kingdom'),
  ];

  @override
  void initState() {
    super.initState();
    _conn.addListener(_onChange);
    _refreshInstallState();
  }

  @override
  void dispose() {
    _conn.removeListener(_onChange);
    super.dispose();
  }

  void _onChange() {
    if (mounted) setState(() {});
  }

  Future<void> _refreshInstallState() async {
    final ok = await StoreService.gephInstalled();
    if (!mounted) return;
    setState(() {
      _installed = ok;
      _version = StoreService.gephInstalledVersion;
    });
  }

  String _t(String fa, String en) => S.isFa ? fa : en;

  Future<void> _install() async {
    setState(() {
      _installing = true;
      _installLog.clear();
      _dlNow = 0;
      _dlTotal = 0;
    });
    try {
      await StoreService.installGeph(
        onLog: (m) {
          if (mounted) setState(() => _installLog.add(m));
        },
        onProgress: (now, total) {
          if (mounted) setState(() {
            _dlNow = now;
            _dlTotal = total;
          });
        },
      );
      await _refreshInstallState();
    } finally {
      if (mounted) setState(() => _installing = false);
    }
  }

  Future<void> _onDialTap() async {
    final c = _conn;
    lightHaptic();
    if (c.connecting || c.connected) {
      await c.disconnect();
      return;
    }
    if (!_installed) {
      await _install();
      return;
    }
    await c.connectTransport(TransportId.geph);
  }

  @override
  Widget build(BuildContext context) {
    final pal = IosPal.of(context);
    final c = _conn;
    final busy = c.connecting;
    final mine = c.connected &&
        (c.activeServer?.id.startsWith('geph_fake_') == true);
    final otherRunning = c.connected && !mine;

    DialStage dialStage;
    String headline;
    if (mine) {
      dialStage = DialStage.connected;
      headline = _t('متصل است', 'Connected');
    } else if (busy) {
      dialStage = DialStage.connecting;
      headline = _t('در حال اتصال', 'Connecting');
    } else if (c.stage == ConnStage.failed && c.statusText.isNotEmpty) {
      dialStage = DialStage.failed;
      headline = _t('اتصال برقرار نشد', 'Could not connect');
    } else {
      dialStage = DialStage.idle;
      headline = _t('آماده', 'Ready');
    }
    if (otherRunning) {
      headline = _t('موتور دیگری متصل است', 'Another engine is connected');
    }
    final dialLabel = _installing
        ? _t('در حال نصب…', 'Installing…')
        : busy
            ? _t('لغو', 'Cancel')
            : (mine ? _t('قطع', 'Disconnect') : _t('اتصال', 'Connect'));

    return IosScreen(
      title: S.t('home_geph'),
      onBack: () => Navigator.pop(context),
      children: [
        const SizedBox(height: 10),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Text(
            _t(
                'شبکهٔ Geph (迷雾通) — معماری دومرحله‌ای با پل‌های چرخان؛ مخصوص سخت‌ترین فیلترینگ‌ها.',
                'The Geph network — two-hop architecture with rotating bridges, built for the hardest censorship.'),
            textAlign: TextAlign.center,
            style: TextStyle(
                color: pal.textMuted, fontSize: 13, height: 20 / 13),
          ),
        ),
        const SizedBox(height: 18),
        Center(
          child: Stack(
            alignment: Alignment.center,
            children: [
              Positioned.fill(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(120),
                  child: DriftingLights(colors: [Ios.tileBlue]),
                ),
              ),
              ConnectDial(
                label: dialLabel,
                stage: dialStage,
                accent: Ios.tileBlue,
                onTap: _installing ? null : _onDialTap,
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        TransportStatusLine(
          stage: dialStage,
          headline: headline,
          accent: Ios.tileBlue,
          message: c.statusText.isEmpty ? null : c.statusText,
        ),
        const SizedBox(height: 18),

        // ── نصب هسته ──
        SettingsSectionHeader(_t('هستهٔ Geph', 'Geph core')),
        SettingsGroup(
          children: [
            SettingsRow(
              title: _installed
                  ? _t('نصب شده — نسخهٔ $_version',
                      'Installed — version $_version')
                  : _t('نصب نشده', 'Not installed'),
              leading: SettingsGlyph(
                  tint: Ios.tileBlue, icon: Icons.memory),
              chevron: false,
            ),
            SettingsActionRow(
              icon: _installed
                  ? Icons.refresh
                  : Icons.download_outlined,
              iconColor: pal.blue,
              title: _installed
                  ? _t('به‌روزرسانی از استور رسمی گف',
                      'Update from the official Geph store')
                  : _t('نصب از استور رسمی گف',
                      'Install from the official Geph store'),
              busy: _installing,
              onTap: _installing ? null : _install,
            ),
          ],
        ),
        if (_installing && _dlTotal > 0)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: _dlNow / _dlTotal,
                    minHeight: 4,
                    backgroundColor:
                        Colors.white.withValues(alpha: 0.15),
                    valueColor:
                        const AlwaysStoppedAnimation<Color>(
                            Color(0xFF0A84FF)),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${(_dlNow / 1048576).toStringAsFixed(1)} / ${(_dlTotal / 1048576).toStringAsFixed(1)} MB',
                  textDirection: TextDirection.ltr,
                  style: TextStyle(
                      color: pal.textMuted, fontSize: 11),
                ),
              ],
            ),
          ),
        if (_installLog.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 6, 20, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final l in _installLog)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 2),
                    child: Text(l,
                        style: TextStyle(
                            color: pal.textMuted, fontSize: 12)),
                  ),
              ],
            ),
          ),
        SettingsFooter(_t(
            'هسته از بستهٔ رسمی خود گف برداشته می‌شود؛ امضای فهرست نسخه‌ها و هش بسته بررسی و سپس یک‌بار اجرای آزمایشی انجام می‌شود.',
            'The core is extracted from Geph\'s official package after signature and digest checks plus one probe run.')),

        // ── تنظیمات ──
        SettingsSectionHeader(_t('تنظیمات', 'Settings')),
        SettingsGroup(
          children: [
            SettingsRow(
              title: _t('کشور خروج', 'Exit country'),
              leading: SettingsGlyph(
                  tint: Ios.tileIndigo, icon: Icons.public),
              value: _exitLabel(),
              onTap: () async {
                final v = await pushIosPicker<String>(
                  context,
                  title: _t('کشور خروج', 'Exit country'),
                  selected: _pref('geph_exit_country', ''),
                  options: [
                    for (final e in kExits) IosPickerOption(e.$1, e.$2),
                  ],
                );
                if (v != null) {
                  final p = await SharedPreferences.getInstance();
                  await p.setString('geph_exit_country', v);
                  setState(() {});
                }
              },
            ),
            SettingsRow(
              title: _t('حساب (اختیاری)', 'Account (optional)'),
              leading: SettingsGlyph(
                  tint: Ios.tileGreen, icon: Icons.key_outlined),
              value: _hasSecret() ? '••••' : _t('پلن رایگان', 'Free plan'),
              onTap: _editSecret,
            ),
          ],
        ),
        SettingsFooter(_t(
            'بدون حساب، پلن رایگان گف استفاده می‌شود. کد ۲۴رقمی حساب Plus خود را می‌توانی در «حساب» وارد کنی.',
            'Without an account the free plan is used; paste your 24-digit Plus secret under Account.')),
        const SizedBox(height: 24),
      ],
    );
  }

  String _pref(String key, String def) => _prefs?.getString(key) ?? def;

  SharedPreferences? _prefs;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    SharedPreferences.getInstance().then((p) {
      if (mounted) setState(() => _prefs = p);
    });
  }

  bool _hasSecret() =>
      (_pref('geph_secret', '')).trim().isNotEmpty;

  String _exitLabel() {
    final v = _pref('geph_exit_country', '');
    for (final e in kExits) {
      if (e.$1 == v) return e.$2;
    }
    return v.isEmpty ? _t('خودکار', 'Auto') : v;
  }

  Future<void> _editSecret() async {
    final p = await SharedPreferences.getInstance();
    final out = await showIosPrompt(
      context,
      title: _t('حساب Geph', 'Geph account'),
      message: _t('کد ۲۴رقمی حساب (Secret) — خالی = رایگان',
          '24-digit account secret — empty = free'),
      initial: p.getString('geph_secret') ?? '',
      keyboardType: TextInputType.number,
      confirmLabel: _t('ذخیره', 'Save'),
      cancelLabel: _t('انصراف', 'Cancel'),
    );
    if (out != null) {
      await p.setString('geph_secret', out.trim());
      setState(() {});
    }
  }
}
