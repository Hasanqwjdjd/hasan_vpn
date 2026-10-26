import 'package:flutter/material.dart';

import '../l10n/s.dart';
import '../services/store_service.dart';
import '../ui/kit/ios_kit.dart';
import '../ui/theme/ios_palette.dart';

/// Store — پورت `ui/store/StoreScreen.kt` (نسخهٔ P2d):
/// فهرست موتورها؛ موتورهای همراه برنامه + هستهٔ Geph قابل نصب/به‌روزرسانی
/// از استور رسمی خود گف (امضاشده).
class StoreScreen extends StatefulWidget {
  const StoreScreen({super.key});

  @override
  State<StoreScreen> createState() => _StoreScreenState();
}

class _StoreScreenState extends State<StoreScreen> {
  bool _gephInstalled = false;
  String? _gephVersion;
  bool _installing = false;
  String? _latest;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final ok = await StoreService.gephInstalled();
    final latest = await StoreService.gephLatest();
    if (!mounted) return;
    setState(() {
      _gephInstalled = ok;
      _gephVersion = StoreService.gephInstalledVersion;
      _latest = latest?.version;
    });
  }

  Future<void> _installGeph() async {
    setState(() => _installing = true);
    try {
      await StoreService.installGeph();
      await _refresh();
    } finally {
      if (mounted) setState(() => _installing = false);
    }
  }

  String _t(String fa, String en) => S.isFa ? fa : en;

  @override
  Widget build(BuildContext context) {
    final pal = IosPal.of(context);
    return IosScreen(
      title: S.t('home_store'),
      onBack: () => Navigator.pop(context),
      children: [
        const SizedBox(height: 10),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Text(
            _t(
                'موتورهایی که با برنامه می‌آیند و موتورهایی که از سازندهٔ خودشان، امضاشده و هش‌تأییدشده، نصب می‌شوند.',
                'Engines bundled with the app, and engines installed from their own developers — signature- and digest-verified.'),
            textAlign: TextAlign.center,
            style: TextStyle(
                color: pal.textMuted, fontSize: 13, height: 20 / 13),
          ),
        ),
        SettingsSectionHeader(_t('قابل نصب', 'Installable')),
        SettingsGroup(
          children: [
            SettingsRow(
              title: _t('هستهٔ Geph', 'Geph core'),
              value: _gephInstalled
                  ? (_latest != null && _latest != _gephVersion
                      ? _t('به‌روزرسانی: $_latest', 'Update: $_latest')
                      : _t('نصب شده ${_gephVersion ?? ''}',
                          'Installed ${_gephVersion ?? ''}'))
                  : (_latest != null ? 'v$_latest' : _t('بررسی…', 'Checking…')),
              leading: SettingsGlyph(
                  tint: Ios.tileBlue, icon: Icons.public),
              onTap: _installing ? null : _installGeph,
            ),
            if (_installing)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: LinearProgressIndicator(minHeight: 3),
              ),
          ],
        ),
        SettingsFooter(_t(
            'هستهٔ گف از APK رسمی خود گف برداشته می‌شود؛ امضای فهرست نسخه‌ها (minisign) و هش SHA-256 بررسی می‌شود.',
            'The Geph core is extracted from Geph\'s official APK after minisign signature and SHA-256 checks.')),
        SettingsSectionHeader(_t('همراه برنامه', 'Bundled')),
        SettingsGroup(
          children: [
            _bundledRow(context, 'Xray-core', 'libxray.so', Ios.tileBlue),
            _bundledRow(context, 'Aether (MASQUE/WG/WARP²)', 'libaether.so',
                Ios.tilePurple),
            _bundledRow(context, 'Tor', 'libtor.so', Ios.tilePurple),
            _bundledRow(
                context, 'Lyrebird (obfs4)', 'liblyrebird.so', Ios.tileTeal),
            _bundledRow(
                context, 'Snowflake', 'libsnowflake.so', Ios.tileTeal),
            _bundledRow(
                context, 'Conjure', 'libconjure.so', Ios.tileTeal),
            _bundledRow(
                context, 'Psiphon core', 'libpingng_psiphon.so', Ios.tileIndigo),
          ],
        ),
        SettingsFooter(_t(
            'این هسته‌ها با خود APK منتشر می‌شوند و از استور قابل تعویض نیستند.',
            'These cores ship inside the APK and are not swappable from the store.')),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _bundledRow(BuildContext context, String name, String file,
      Color tint) {
    final pal = IosPal.of(context);
    return SettingsRow(
      title: name,
      value: file,
      chevron: false,
      leading: SettingsGlyph(tint: tint, icon: Icons.memory),
      trailing: Text(_t('داخلی', 'built-in'),
          style: TextStyle(color: pal.textMuted, fontSize: 12)),
    );
  }
}
