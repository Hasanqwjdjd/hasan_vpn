import 'package:flutter/material.dart';

import '../controllers/connection.dart';
import '../l10n/s.dart';
import '../ui/fx/fx.dart';
import '../ui/kit/ios_kit.dart';
import '../ui/kit/tiles.dart';
import '../ui/theme/ios_palette.dart';

/// Lantern — SDK رسمی getlantern/lanternsdk-android؛ دیال اتصال و وضعیت.
class LanternScreen extends StatefulWidget {
  const LanternScreen({super.key});

  @override
  State<LanternScreen> createState() => _LanternScreenState();
}

class _LanternScreenState extends State<LanternScreen> {
  final ConnectionController _conn = ConnectionController.instance;

  @override
  void initState() {
    super.initState();
    _conn.addListener(_onChange);
  }

  @override
  void dispose() {
    _conn.removeListener(_onChange);
    super.dispose();
  }

  void _onChange() {
    if (mounted) setState(() {});
  }

  String _t(String fa, String en) => S.isFa ? fa : en;

  bool get _mine =>
      _conn.connected &&
      (_conn.activeServer?.id.startsWith('lantern_fake_') == true);

  Future<void> _onDial() async {
    lightHaptic();
    final c = _conn;
    if (c.connecting) {
      c.cancelConnectFlag();
      return;
    }
    if (c.connected) {
      await c.disconnect();
      return;
    }
    await c.connectLantern();
  }

  @override
  Widget build(BuildContext context) {
    final pal = IosPal.of(context);
    final c = _conn;
    final busy = c.connecting;
    final mine = _mine;
    final otherRunning = c.connected && !mine;

    DialStage stage;
    String headline;
    if (mine) {
      stage = DialStage.connected;
      headline = _t('متصل است', 'Connected');
    } else if (busy) {
      stage = DialStage.connecting;
      headline = _t('در حال اتصال', 'Connecting');
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
      title: 'Lantern',
      onBack: () => Navigator.pop(context),
      children: [
        const SizedBox(height: 10),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Text(
            _t(
                'شبکهٔ Lantern با SDK رسمی‌اش — پروکسی محلی HTTPS که Xray ترافیک TUN را از آن عبور می‌دهد.',
                'The Lantern network via its official SDK — a local HTTP proxy that Xray routes TUN traffic through.'),
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
                  child: DriftingLights(colors: [Ios.warnOrange]),
                ),
              ),
              ConnectDial(
                label: dialLabel,
                stage: stage,
                accent: Ios.warnOrange,
                onTap: _onDial,
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        TransportStatusLine(
          stage: stage,
          headline: headline,
          accent: Ios.warnOrange,
          message: c.statusText.isEmpty ? null : c.statusText,
        ),
        const SizedBox(height: 18),
        SettingsGroup(
          children: [
            SettingsRow(
              title: _t('هسته', 'Core'),
              value: 'lanternsdk-android v1.0.1',
              leading: SettingsGlyph(
                  tint: Ios.warnOrange, icon: Icons.lightbulb_outline),
              chevron: false,
            ),
          ],
        ),
        SettingsFooter(_t(
            'SDK رسمی Lantern در بیلد ادغام شده و ترافیک به‌صورت HTTPS درمی‌آید.',
            'The official Lantern SDK is bundled; traffic is shaped as HTTPS.')),
        const SizedBox(height: 24),
      ],
    );
  }
}
