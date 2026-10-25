import 'package:flutter/material.dart';

import '../controllers/servers.dart';
import '../l10n/s.dart';
import '../services/free_config_engine.dart';
import '../ui/fx/fx.dart';
import '../ui/kit/ios_kit.dart';
import '../ui/theme/ios_palette.dart';

/// Free Configs — پورت `ui/FreeConfigTab.kt` (نسخهٔ P2c) روی موتور واقعی
/// FreeConfigEngine: یافتن کانفیگ رایگان از منابع عمومی و افزودن به V2Ray.
class FreeConfigScreen extends StatefulWidget {
  const FreeConfigScreen({super.key});

  @override
  State<FreeConfigScreen> createState() => _FreeConfigScreenState();
}

class _FreeConfigScreenState extends State<FreeConfigScreen> {
  bool _busy = false;
  int _found = 0;
  int _added = 0;
  String? _error;
  final List<String> _log = [];

  String _t(String fa, String en) => S.isFa ? fa : en;

  Future<void> _run() async {
    setState(() {
      _busy = true;
      _found = 0;
      _added = 0;
      _error = null;
      _log.clear();
    });
    try {
      final links = await FreeConfigEngine.fetchCandidates(
        onProgress: (done, total) {
          if (mounted) {
            setState(() => _log.add('منابع: $done/$total'));
          }
        },
      );
      _found = links.length;
      final n = await ServerRepository.instance.addFromLink(links.join('\n'));
      _added = n;
    } catch (e) {
      _error = e.toString();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final pal = IosPal.of(context);
    return IosScreen(
      title: S.t('home_freeconfig'),
      onBack: () => Navigator.pop(context),
      children: [
        const SizedBox(height: 10),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Text(
            _t(
                'کانفیگ‌های رایگان عمومی را از منابع شناخته‌شده می‌گیرد و به لیست V2Ray اضافه می‌کند.',
                'Fetches public free configs from known sources and adds them to the V2Ray list.'),
            textAlign: TextAlign.center,
            style: TextStyle(
                color: pal.textMuted, fontSize: 13, height: 20 / 13),
          ),
        ),
        const SizedBox(height: 16),
        SettingsGroup(
          children: [
            SettingsActionRow(
              icon: Icons.cloud_download_outlined,
              iconColor: pal.blue,
              title: _busy
                  ? _t('در حال جست‌وجو…', 'Searching…')
                  : _t('جست‌وجو و افزودن', 'Search & add'),
              busy: _busy,
              onTap: _busy ? null : _run,
            ),
          ],
        ),
        if (_found > 0) ...[
          const SizedBox(height: 12),
          SettingsGroup(
            children: [
              SettingsRow(
                title: _t('پیدا شده', 'Found'),
                value: '$_found',
                chevron: false,
                leading: SettingsGlyph(
                    tint: Ios.tileTeal, icon: Icons.search),
              ),
              SettingsRow(
                title: _t('افزوده‌شده به V2Ray', 'Added to V2Ray'),
                value: '$_added',
                chevron: false,
                leading: SettingsGlyph(
                    tint: Ios.tileGreen, icon: Icons.check_circle_outline),
              ),
            ],
          ),
        ],
        if (_error != null) ...[
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(_error!,
                style: TextStyle(color: pal.red, fontSize: 13)),
          ),
        ],
        if (_log.isNotEmpty) ...[
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: FrostedGlass(
              borderRadius: BorderRadius.circular(IosRadius.control),
              blur: 12,
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final l in _log)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 2),
                      child: Text(l,
                          style: TextStyle(
                              color: pal.textMuted, fontSize: 11)),
                    ),
                ],
              ),
            ),
          ),
        ],
        SettingsFooter(_t(
            'پس از افزودن، در تب V2Ray تست بگیر و سریع‌ترین را وصل کن.',
            'After adding, test in the V2Ray tab and connect the fastest.')),
        const SizedBox(height: 24),
      ],
    );
  }
}
