import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../controllers/connection.dart';
import '../l10n/s.dart';
import '../models/server.dart';
import '../services/tor_service.dart';
import '../services/warp_service.dart';
import '../ui/fx/fx.dart';
import '../ui/kit/ios_kit.dart';
import '../ui/kit/tiles.dart';
import '../ui/theme/ios_palette.dart';
import 'log_screen.dart';

/// صفحهٔ هر موتور Transport — پورت `ui/tunnel/TransportScreen.kt`:
/// هیرو با ConnectDial + StatusLine + تنظیمات + کارت «چطور کار می‌کند».
class TransportScreen extends StatefulWidget {
  final TransportId transport;
  const TransportScreen({super.key, required this.transport});

  @override
  State<TransportScreen> createState() => _TransportScreenState();
}

class _TransportScreenState extends State<TransportScreen> {
  SharedPreferences? _prefs;

  @override
  void initState() {
    super.initState();
    ConnectionController.instance.addListener(_onChange);
    SharedPreferences.getInstance().then((p) {
      if (mounted) setState(() => _prefs = p);
    });
  }

  String _pref(String key, String def) => _prefs?.getString(key) ?? def;

  @override
  void dispose() {
    ConnectionController.instance.removeListener(_onChange);
    super.dispose();
  }

  void _onChange() {
    if (mounted) setState(() {});
  }

  String _t(String fa, String en) => S.isFa ? fa : en;

  Color get _accent {
    switch (widget.transport) {
      case TransportId.masque:
        return Ios.tileBlue;
      case TransportId.wireguard:
        return Ios.tileGreen;
      case TransportId.warpOnWarp:
        return Ios.tileOrange;
      case TransportId.warp:
        return Ios.tileTeal;
      case TransportId.psiphon:
        return Ios.tileIndigo;
      case TransportId.tor:
        return Ios.tilePurple;
      case TransportId.geph:
        return Ios.tileBlue;
    }
  }

  String get _titleKey {
    switch (widget.transport) {
      case TransportId.masque:
        return 'home_masque';
      case TransportId.wireguard:
        return 'home_wireguard';
      case TransportId.warpOnWarp:
        return 'home_warp_on_warp';
      case TransportId.warp:
        return 'home_warp';
      case TransportId.psiphon:
        return 'home_psiphon';
      case TransportId.tor:
        return 'home_tor';
      case TransportId.geph:
        return 'home_geph';
    }
  }

  String get _tagline {
    switch (widget.transport) {
      case TransportId.masque:
        return _t(
            'اتصال از طریق MASQUE روی زیرساخت Cloudflare — مقاوم‌ترین مسیر روزمره.',
            'Connect over MASQUE on the Cloudflare edge — the strongest everyday route.');
      case TransportId.warp:
        return _t(
            'WARP رسمی Cloudflare با هویت خودکار و اسکن endpoint سالم.',
            'Official Cloudflare WARP with automatic identity and healthy-endpoint scan.');
      case TransportId.warpOnWarp:
        return _t(
            'WARP روی WARP — دو لایه تونل برای عبور از فیلترینگ سخت.',
            'WARP over WARP — two tunnel layers for the toughest censorship.');
      case TransportId.psiphon:
        return _t(
            'شبکهٔ Psiphon با انتخاب کشور خروج و نردبان خودکار پروتکل‌ها.',
            'The Psiphon network with exit-country choice and an automatic protocol ladder.');
      case TransportId.tor:
        return _t(
            'شبکهٔ Tor با پل‌های obfs4/Snowflake/Meek و WebTunnel HTTPS.',
            'The Tor network with obfs4/Snowflake/Meek bridges and HTTPS WebTunnel.');
      case TransportId.wireguard:
        return _t('تونل WireGuard/AmneziaWG.', 'WireGuard / AmneziaWG tunnel.');
      case TransportId.geph:
        return _t('شبکهٔ Geph (迷雾通).', 'The Geph network.');
    }
  }

  bool _isThisTransport(TransportId id) {
    final c = ConnectionController.instance;
    if (!c.connected && !c.connecting) return false;
    final s = c.activeServer;
    if (s != null) {
      if (s.protocol == VpnProtocol.psiphon) return id == TransportId.psiphon;
      if (s.protocol == VpnProtocol.aether) {
        return id == TransportId.masque ||
            (id == TransportId.warpOnWarp &&
                s.id.contains('_gool'));
      }
      if (s.protocol == VpnProtocol.amneziaWg) return id == TransportId.warp;
      if (s.id.startsWith('tor_fake_')) return id == TransportId.tor;
      return false;
    }
    return false;
  }

  Future<void> _onDialTap() async {
    final c = ConnectionController.instance;
    lightHaptic();
    if (c.connecting || c.connected) {
      if (c.connected && !_isThisTransport(widget.transport)) {
        // موتور دیگری فعال است — اول قطعش کن بعد این موتور را وصل کن
        await c.disconnect();
        await Future.delayed(const Duration(milliseconds: 400));
      } else {
        await c.disconnect();
        return;
      }
    }
    await c.connectTransport(widget.transport);
  }

  @override
  Widget build(BuildContext context) {
    final c = ConnectionController.instance;
    final busy = c.connecting;
    final mine = c.connected && _isThisTransport(widget.transport);
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

    final dialLabel = busy
        ? _t('لغو', 'Cancel')
        : (mine ? _t('قطع', 'Disconnect') : _t('اتصال', 'Connect'));

    return IosScreen(
      title: S.t(_titleKey),
      onBack: () => Navigator.pop(context),
      children: [
        const SizedBox(height: 10),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Text(
            _tagline,
            textAlign: TextAlign.center,
            style: TextStyle(
                color: IosPal.of(context).textMuted,
                fontSize: 13,
                height: 20 / 13),
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
                  child: DriftingLights(colors: [_accent]),
                ),
              ),
              ConnectDial(
                label: dialLabel,
                stage: dialStage,
                progress: c.progress,
                accent: _accent,
                onTap: _onDialTap,
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        TransportStatusLine(
          stage: dialStage,
          headline: headline,
          accent: _accent,
          message: c.statusText.isEmpty ? null : c.statusText,
        ),
        const SizedBox(height: 18),
        ..._enginePanels(context, c),
        SettingsSectionHeader(_t('راهنما و گزارش', 'Guide & report')),
        SettingsGroup(
          children: [
            SettingsRow(
              title: _t('گزارش اتصال', 'Connection report'),
              leading: SettingsGlyph(
                  tint: Ios.tileGray, icon: Icons.receipt_long),
              onTap: () => Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const LogScreen())),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: HowItWorksCard(text: _tagline),
        ),
        const SizedBox(height: 24),
      ],
    );
  }

  // ── پنل‌های اختصاصی هر موتور ──

  List<Widget> _enginePanels(BuildContext context, ConnectionController c) {
    switch (widget.transport) {
      case TransportId.masque:
      case TransportId.warpOnWarp:
        return _masquePanel(context);
      case TransportId.warp:
        return _warpPanel(context);
      case TransportId.psiphon:
        return _psiphonPanel(context);
      case TransportId.tor:
        return _torPanel(context);
      case TransportId.wireguard:
      case TransportId.geph:
        return const [];
    }
  }

  static const List<String> kScanModes = [
    'turbo',
    'balanced',
    'thorough',
    'verified',
    'ironclad',
  ];

  List<Widget> _masquePanel(BuildContext context) {
    final isWow = widget.transport == TransportId.warpOnWarp;
    return [
      SettingsSectionHeader(_t('تنظیمات', 'Settings')),
      SettingsGroup(
        children: [
          SettingsRow(
            title: _t('حالت اسکن', 'Scan mode'),
            leading: SettingsGlyph(
                tint: Ios.tileBlue, icon: Icons.radar),
            value: _scanPref,
            onTap: () async {
              final v = await pushIosPicker<String>(
                context,
                title: _t('حالت اسکن', 'Scan mode'),
                selected: _scanPref,
                options: [
                  for (final m in kScanModes)
                    IosPickerOption(m, m,
                        detail: _scanDetail(m)),
                ],
              );
              if (v != null) {
                final p = await SharedPreferences.getInstance();
                await p.setString('transport_masque_scan', v);
                setState(() {});
              }
            },
          ),
          if (isWow)
            SettingsRow(
              title: _t('لایه بیرونی', 'Outer layer'),
              leading: SettingsGlyph(
                  tint: Ios.tileOrange, icon: Icons.layers),
              value: 'WARP',
              chevron: false,
            ),
        ],
      ),
      SettingsFooter(_t(
          'اسکن، مسیر سالم روی شبکهٔ فعلی را پیدا می‌کند؛ حالت سنگین‌تر کندتر ولی پایدارتر است.',
          'Scan finds a healthy path on the current network; heavier modes are slower but steadier.')),
    ];
  }

  String _scanDetail(String m) {
    switch (m) {
      case 'turbo':
        return _t('سریع‌ترین', 'Fastest');
      case 'balanced':
        return _t('متعادل (پیش‌فرض)', 'Balanced (default)');
      case 'thorough':
        return _t('کامل', 'Thorough');
      case 'verified':
        return _t('تأییدشده', 'Verified');
      case 'ironclad':
        return _t('فولادی', 'Ironclad');
    }
    return m;
  }

  String get _scanPref => _pref('transport_masque_scan', 'balanced');

  List<Widget> _warpPanel(BuildContext context) {
    return [
      SettingsSectionHeader(_t('هویت WARP', 'WARP identity')),
      SettingsGroup(
        children: [
          SettingsActionRow(
            icon: Icons.badge_outlined,
            title: _t('بازنشانی هویت WARP', 'Reset WARP identity'),
            onTap: () async {
              await showIosAlert(
                context,
                title: _t('بازنشانی هویت؟', 'Reset identity?'),
                message: _t(
                    'ثبت‌نام جدید انجام می‌شود. تنظیمات فعلی حفظ می‌شود.',
                    'A new registration will be created. Settings are kept.'),
                confirmLabel: _t('بازنشانی', 'Reset'),
                destructive: true,
                onConfirm: () async {
                  await WarpService.reset();
                },
              );
              setState(() {});
            },
          ),
        ],
      ),
      SettingsFooter(_t(
          'اگر ثبت‌نام مستقیم مسدود بود، WARP خودش مسیر جایگزین را امتحان می‌کند.',
          'If direct registration is blocked, WARP automatically tries alternate routes.')),
    ];
  }

  static const List<(String, String)> kPsiphonRegions = [
    ('auto', 'خودکار / Auto'),
    ('NL', 'هلند / Netherlands'),
    ('DE', 'آلمان / Germany'),
    ('US', 'آمریکا / United States'),
    ('GB', 'انگلستان / United Kingdom'),
    ('TR', 'ترکیه / Türkiye'),
    ('FI', 'فنلاند / Finland'),
    ('SE', 'سوئد / Sweden'),
    ('CA', 'کانادا / Canada'),
    ('FR', 'فرانسه / France'),
  ];

  List<Widget> _psiphonPanel(BuildContext context) {
    final region = _pref('transport_psiphon_region', 'auto');
    final label = kPsiphonRegions
        .firstWhere((r) => r.$1 == region, orElse: () => kPsiphonRegions.first)
        .$2;
    return [
      SettingsSectionHeader(_t('کشور خروج', 'Exit country')),
      SettingsGroup(
        children: [
          SettingsRow(
            title: _t('کشور خروج', 'Exit country'),
            leading: SettingsGlyph(
                tint: Ios.tileIndigo, icon: Icons.public),
            value: label,
            onTap: () async {
              final v = await pushIosPicker<String>(
                context,
                title: _t('کشور خروج', 'Exit country'),
                selected: region,
                options: [
                  for (final r in kPsiphonRegions)
                    IosPickerOption(r.$1, r.$2),
                ],
              );
              if (v != null) {
                final p = await SharedPreferences.getInstance();
                await p.setString('transport_psiphon_region', v);
                setState(() {});
              }
            },
          ),
        ],
      ),
      SettingsFooter(_t(
          '«خودکار» بهترین کشور را خودش پیدا می‌کند؛ انتخاب کشور برای عبور از محدودیت‌های منطقه‌ای است.',
          '"Auto" finds the best country itself; a fixed country helps with regional restrictions.')),
    ];
  }

  static const List<(String, String, String)> kTorModes = [
    ('vanilla', 'ساده (بدون پل)', 'Vanilla (no bridge)'),
    ('obfs4', 'obfs4', 'obfs4'),
    ('snowflake', 'Snowflake (P2P)', 'Snowflake (P2P)'),
    ('meek_lite', 'Meek / Azure', 'Meek / Azure'),
    ('conjure', 'Conjure', 'Conjure'),
    ('webtunnel', 'WebTunnel (HTTPS)', 'WebTunnel (HTTPS)'),
  ];

  List<Widget> _torPanel(BuildContext context) {
    final mode = _pref('transport_tor_mode', 'vanilla');
    final modeLabel = kTorModes
        .firstWhere((m) => m.$1 == mode, orElse: () => kTorModes.first)
        .$2;
    final isFa = S.isFa;
    return [
      SettingsSectionHeader(_t('حالت اتصال', 'Connection mode')),
      SettingsGroup(
        children: [
          SettingsRow(
            title: _t('حالت اتصال', 'Connection mode'),
            leading:
                SettingsGlyph(tint: Ios.tilePurple, icon: Icons.vpn_key),
            value: modeLabel,
            onTap: () async {
              final v = await pushIosPicker<String>(
                context,
                title: _t('حالت اتصال Tor', 'Tor connection mode'),
                selected: mode,
                footer: _t(
                    'نردبان خودکار: ساده → Meek → obfs4 → Snowflake. WebTunnel ترافیک را شبیه HTTPS معمولی می‌کند.',
                    'Ladder: Vanilla → Meek → obfs4 → Snowflake. WebTunnel disguises traffic as normal HTTPS.'),
                options: [
                  for (final m in kTorModes)
                    IosPickerOption(
                        m.$1, isFa ? m.$2 : m.$3),
                ],
              );
              if (v != null) {
                final p = await SharedPreferences.getInstance();
                await p.setString('transport_tor_mode', v);
                setState(() {});
              }
            },
          ),
          SettingsRow(
            title: _t('پل‌های دستی', 'Custom bridges'),
            leading: SettingsGlyph(
                tint: Ios.tileGray, icon: Icons.format_list_bulleted),
            value: _bridgeCountLabel,
            onTap: _editBridges,
          ),
          SettingsActionRow(
            icon: Icons.cloud_download_outlined,
            title: _t('دریافت پل از Moat', 'Fetch bridges from Moat'),
            busy: _moatBusy,
            onTap: _moatBusy ? null : _fetchMoat,
          ),
        ],
      ),
      SettingsFooter(_t(
          'WebTunnel از همین صفحه با نوع «WebTunnel (HTTPS)» در دسترس است؛ برای پل دستی، خطوط bridge را در «پل‌های دستی» وارد کنید.',
          'WebTunnel is available by picking "WebTunnel (HTTPS)"; paste bridge lines under "Custom bridges".')),
    ];
  }

  String get _bridgeCountLabel {
    final raw = _pref('transport_tor_bridges', '');
    final n = raw
        .split('\n')
        .where((e) => e.trim().isNotEmpty)
        .length;
    return n == 0 ? _t('خالی', 'Empty') : '$n';
  }

  bool _moatBusy = false;

  Future<void> _editBridges() async {
    final p = await SharedPreferences.getInstance();
    final current = p.getString('transport_tor_bridges') ?? '';
    final out = await showIosPrompt(
      context,
      title: _t('پل‌های دستی', 'Custom bridges'),
      message: _t('هر خط یک bridge', 'One bridge per line'),
      initial: current,
      multiline: true,
      confirmLabel: S.t('ok'),
      cancelLabel: _t('انصراف', 'Cancel'),
    );
    if (out != null) {
      await p.setString('transport_tor_bridges', out);
      setState(() {});
    }
  }

  Future<void> _fetchMoat() async {
    final p = await SharedPreferences.getInstance();
    final mode = p.getString('transport_tor_mode') ?? 'obfs4';
    setState(() => _moatBusy = true);
    try {
      final r = await TorService.fetchMoatBridges(mode, country: 'ir');
      final bridges = (r['bridges'] as List?) ?? const [];
      if (bridges.isNotEmpty) {
        final existing =
            (p.getString('transport_tor_bridges') ?? '').trim();
        final merged = <String>{
          ...existing.split('\n').map((e) => e.trim()),
          ...bridges.map((e) => e.toString().trim()),
        }..removeWhere((e) => e.isEmpty);
        await p.setString('transport_tor_bridges', merged.join('\n'));
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            backgroundColor: IosPal.of(context).card,
            content: Text(
              _t('${bridges.length} پل دریافت شد',
                  '${bridges.length} bridges fetched'),
              style: const TextStyle(color: Colors.white),
            ),
          ));
        }
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          backgroundColor: IosPal.of(context).card,
          content: Text(
            r['error']?.toString() ?? _t('پلی دریافت نشد', 'No bridges'),
            style: const TextStyle(color: Colors.white),
          ),
        ));
      }
    } finally {
      if (mounted) setState(() => _moatBusy = false);
    }
  }
}
