import 'package:flutter/material.dart';

import '../controllers/connection.dart';
import '../l10n/s.dart';
import '../services/flux_service.dart';
import '../ui/fx/fx.dart';
import '../ui/kit/ios_kit.dart';
import '../ui/kit/tiles.dart';
import '../ui/theme/ios_palette.dart';

/// FLUX — پورت `ui/flux/FluxScreen.kt` (نسخهٔ P2c):
/// دیال اتصال + مدیریت منابع + لاگ مسابقه؛ موتور واقعی FluxService.
class FluxScreen extends StatefulWidget {
  const FluxScreen({super.key});

  @override
  State<FluxScreen> createState() => _FluxScreenState();
}

class _FluxScreenState extends State<FluxScreen> {
  final ConnectionController _conn = ConnectionController.instance;
  final FluxService _flux = FluxService.instance;
  final List<String> _logLines = [];

  @override
  void initState() {
    super.initState();
    _conn.addListener(_onChange);
    _flux.loadPrefs().then((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _conn.removeListener(_onChange);
    super.dispose();
  }

  void _onChange() {
    if (mounted) setState(() {});
  }

  void _log(String m) {
    if (!mounted) return;
    setState(() {
      _logLines.add(m);
      if (_logLines.length > 30) _logLines.removeAt(0);
    });
  }

  String _t(String fa, String en) => S.isFa ? fa : en;

  bool get _mine =>
      _conn.connected && (_conn.activeServer?.id.startsWith('flux_') == true);

  Future<void> _onDial() async {
    lightHaptic();
    final c = _conn;
    if (c.connecting) {
      c.cancelConnectFlag();
      return;
    }
    if (c.connected) {
      await c.disconnect();
      if (!_mine) return;
      return;
    }
    setState(_logLines.clear);
    await c.connectFlux(onProgress: _log);
  }

  Future<void> _addSource() async {
    final url = await showIosPrompt(
      context,
      title: _t('افزودن منبع', 'Add source'),
      message: _t('آدرس HTTPS اشتراک (حداکثر ۵ منبع)', 'HTTPS subscription URL (max 5)'),
      hint: 'https://',
      keyboardType: TextInputType.url,
    );
    if (url == null || url.trim().isEmpty) return;
    final ok = await _flux.addUserSource(url.trim());
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        backgroundColor: IosPal.of(context).card,
        content: Text(
            _t('منبع نامعتبر یا تکراری (سقف ۵)', 'Invalid/duplicate source (max 5)'),
            style: const TextStyle(color: Colors.white)),
      ));
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final pal = IosPal.of(context);
    final c = _conn;
    final busy = c.connecting || _flux.racing;
    final mine = _mine;
    final otherRunning = c.connected && !mine;

    DialStage stage;
    String headline;
    if (mine) {
      stage = DialStage.connected;
      headline = _t('متصل است', 'Connected');
    } else if (busy) {
      stage = DialStage.connecting;
      headline = _t('در حال مسابقه…', 'Racing…');
    } else if (c.stage == ConnStage.failed && c.statusText.isNotEmpty) {
      stage = DialStage.failed;
      headline = _t('اتصال برقرار نشد', 'Could not connect');
    } else {
      stage = DialStage.idle;
      headline = _t('آماده', 'Ready');
    }
    if (otherRunning) {
      headline = _t('موتور دیگری متصل است', 'Another engine is connected');
    }
    final dialLabel = busy
        ? _t('لغو', 'Cancel')
        : (mine ? _t('قطع', 'Disconnect') : _t('اتصال', 'Connect'));

    return IosScreen(
      title: S.t('flux_title_short'),
      onBack: () => Navigator.pop(context),
      children: [
        const SizedBox(height: 10),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Text(
            _t(
                'کانفیگ‌های رایگانِ شناخته‌شده را می‌گیرد، مسابقهٔ واقعی می‌دهد و سریع‌ترین خروجی سالم را وصل می‌کند؛ در قطع، خودش سراغ بعدی می‌رود.',
                'Fetches known free config sources, races them for real, connects the fastest healthy exit — and auto-switches on failure.'),
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
                  child: DriftingLights(colors: [Ios.tileIndigo]),
                ),
              ),
              ConnectDial(
                label: dialLabel,
                stage: stage,
                accent: Ios.tileIndigo,
                onTap: _onDial,
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        TransportStatusLine(
          stage: stage,
          headline: headline,
          accent: Ios.tileIndigo,
          message: c.statusText.isEmpty ? null : c.statusText,
        ),
        if (_logLines.isNotEmpty) ...[
          const SizedBox(height: 14),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: FrostedGlass(
              borderRadius: BorderRadius.circular(IosRadius.control),
              blur: 12,
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final l in _logLines)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 2),
                      child: Text(
                        l,
                        style: const TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 11,
                            color: Colors.white,
                            height: 1.35),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
        SettingsSectionHeader(_t('منابع', 'Sources')),
        SettingsGroup(
          children: [
            for (final s in FluxService.kBuiltInSources)
              SettingsRow(
                title: Uri.parse(s.url).host,
                value: s.id,
                chevron: false,
                leading: SettingsGlyph(
                    tint: Ios.tileTeal, icon: Icons.rss_feed),
              ),
            for (final u in _flux.userSources)
              SettingsRow(
                title: Uri.tryParse(u)?.host ?? u,
                value: _t('کاربر', 'custom'),
                leading: SettingsGlyph(
                    tint: Ios.tileGreen, icon: Icons.link),
                onLongPress: () {
                  showIosAlert(
                    context,
                    title: _t('حذف منبع؟', 'Remove source?'),
                    message: u,
                    confirmLabel: _t('حذف', 'Remove'),
                    destructive: true,
                    onConfirm: () async {
                      await _flux.removeUserSource(u);
                      setState(() {});
                    },
                  );
                },
              ),
            SettingsActionRow(
              icon: Icons.add,
              iconColor: pal.blue,
              title: _t('افزودن منبع (اشتراک HTTPS)', 'Add source (HTTPS sub)'),
              onTap: _addSource,
            ),
          ],
        ),
        SettingsFooter(_t(
            'مسابقه: مرحلهٔ ۱ زمان TCP با همزمانی ۱۲؛ مرحلهٔ ۲ پینگ واقعی روی برترین‌ها. حداکثر ۴۰۰ کاندید.',
            'Race: stage-1 TCP timing at concurrency 12; stage-2 real ping on the best. Max 400 candidates.')),
        const SizedBox(height: 24),
      ],
    );
  }
}
