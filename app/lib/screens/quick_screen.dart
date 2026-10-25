import 'package:flutter/material.dart';

import '../app/app_shell.dart';
import '../controllers/connection.dart';
import '../controllers/servers.dart';
import '../l10n/s.dart';
import '../models/server.dart';
import '../ui/fx/fx.dart';
import '../ui/kit/ios_kit.dart';
import '../ui/kit/tiles.dart';
import '../ui/theme/ios_palette.dart';

/// Quick Connect — پورت `ui/QuickConnectTab.kt` (نسخهٔ P2c):
/// یک دیال بزرگ؛ اتصال به سریع‌ترین سرور آنلاین یا آخرین سرور انتخابی.
class QuickConnectScreen extends StatefulWidget {
  const QuickConnectScreen({super.key});

  @override
  State<QuickConnectScreen> createState() => _QuickConnectScreenState();
}

class _QuickConnectScreenState extends State<QuickConnectScreen> {
  final ConnectionController _conn = ConnectionController.instance;
  final ServerRepository _repo = ServerRepository.instance;

  @override
  void initState() {
    super.initState();
    _conn.addListener(_onChange);
    _repo.addListener(_onChange);
  }

  @override
  void dispose() {
    _conn.removeListener(_onChange);
    _repo.removeListener(_onChange);
    super.dispose();
  }

  void _onChange() {
    if (mounted) setState(() {});
  }

  String _t(String fa, String en) => S.isFa ? fa : en;

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
    // سریع‌ترین آنلاین → آخرین انتخاب → اولین سرور
    var target = _repo.fastest();
    target ??= _repo.selected;
    target ??= _repo.servers.isNotEmpty ? _repo.servers.first : null;
    if (target == null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        backgroundColor: IosPal.of(context).card,
        content: Text(
            _t('سروری نیست — اول در V2Ray کانفیگ اضافه کن',
                'No servers — add a config in V2Ray first'),
            style: const TextStyle(color: Colors.white)),
      ));
      return;
    }
    await _repo.select(target);
    await c.connectServer(target);
  }

  @override
  Widget build(BuildContext context) {
    final pal = IosPal.of(context);
    final c = _conn;
    final busy = c.connecting;
    final connected = c.connected;

    final target = _repo.fastest() ??
        _repo.selected ??
        (_repo.servers.isNotEmpty ? _repo.servers.first : null);
    final targetLabel = target?.displayName ?? _t('—', '—');
    final targetPing = (target != null &&
            target.status == ServerStatus.online &&
            target.ping != null)
        ? '${target.ping}ms'
        : '·';

    final dialLabel = busy
        ? _t('لغو', 'Cancel')
        : (connected ? _t('قطع', 'Disconnect') : _t('اتصال', 'Connect'));
    final stage = connected
        ? DialStage.connected
        : busy
            ? DialStage.connecting
            : (c.stage == ConnStage.failed
                ? DialStage.failed
                : DialStage.idle);
    final headline = connected
        ? _t('متصل — ${c.activeServer?.displayName ?? ''}', 'Connected — ${c.activeServer?.displayName ?? ''}')
        : busy
            ? _t('در حال اتصال', 'Connecting')
            : (c.stage == ConnStage.failed
                ? _t('اتصال برقرار نشد', 'Could not connect')
                : _t('آماده', 'Ready'));

    return IosScreen(
      title: S.t('quick_connect'),
      onBack: () => Navigator.pop(context),
      children: [
        const SizedBox(height: 10),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Text(
            _t('سریع‌ترین سرورِ سالم، با یک ضربه.', 'The fastest healthy server, one tap away.'),
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
                stage: stage,
                accent: Ios.tileBlue,
                onTap: _onDial,
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        TransportStatusLine(
          stage: stage,
          headline: headline,
          accent: Ios.tileBlue,
          message: c.statusText.isEmpty ? null : c.statusText,
        ),
        const SizedBox(height: 18),
        SettingsSectionHeader(_t('مقصد', 'Target')),
        SettingsGroup(
          children: [
            SettingsRow(
              title: targetLabel,
              value: targetPing,
              leading: SettingsGlyph(
                  tint: Ios.tileBlue, icon: Icons.bolt),
              chevron: false,
              onTap: () => AppShellState.openTab('nodes'),
            ),
          ],
        ),
        SettingsFooter(_t(
            'برای انتخاب مقصد دستی، ضربه بزن تا تب V2Ray باز شود. سرورها باید یک‌بار تست شده باشند.',
            'Tap the target to open the V2Ray tab for manual pick. Servers should be tested once first.')),
        const SizedBox(height: 24),
      ],
    );
  }
}
