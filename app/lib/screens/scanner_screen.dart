import 'package:flutter/material.dart';

import '../l10n/s.dart';
import '../services/warp_service.dart';
import '../ui/kit/ios_kit.dart';
import '../ui/theme/ios_palette.dart';

/// Scanner — پورت `ui/ScannerTab.kt` (نسخهٔ P2d) روی موتور واقعی اسکن
/// WARP (WarpService.bestEndpoint → _scanFastest روی کاندیدهای واقعی).
class ScannerScreen extends StatefulWidget {
  const ScannerScreen({super.key});

  @override
  State<ScannerScreen> createState() => _ScannerScreenState();
}

class _ScannerScreenState extends State<ScannerScreen> {
  bool _scanning = false;
  String? _best;
  String? _error;
  final List<String> _log = [];

  String _t(String fa, String en) => S.isFa ? fa : en;

  Future<void> _scan() async {
    setState(() {
      _scanning = true;
      _best = null;
      _error = null;
      _log.clear();
    });
    _log.add(_t('اسکن کاندیدهای Cloudflare…', 'Scanning Cloudflare candidates…'));
    try {
      final ep = await WarpService.bestEndpoint();
      if (!mounted) return;
      setState(() {
        _best = ep;
        _scanning = false;
        if (ep == null) {
          _error = _t('endpoint سالمی پیدا نشد — دوباره امتحان کن',
              'No healthy endpoint found — try again');
        } else {
          _log.add(_t('بهترین: $ep', 'Best: $ep'));
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _scanning = false;
        _error = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final pal = IosPal.of(context);
    return IosScreen(
      title: S.t('nav_scanner'),
      onBack: () => Navigator.pop(context),
      children: [
        const SizedBox(height: 10),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Text(
            _t(
                'کاندیدهای واقعی زیرساخت Cloudflare را با اتصال TCP واقعی می‌سنجد تا endpoint سالمِ WARP/MASQUE برای همین شبکه پیدا شود.',
                'Probes real Cloudflare edge candidates with real TCP connects to find a healthy WARP/MASQUE endpoint on this network.'),
            textAlign: TextAlign.center,
            style: TextStyle(
                color: pal.textMuted, fontSize: 13, height: 20 / 13),
          ),
        ),
        const SizedBox(height: 16),
        SettingsGroup(
          children: [
            SettingsActionRow(
              icon: Icons.radar,
              iconColor: pal.blue,
              title: _scanning
                  ? _t('در حال اسکن…', 'Scanning…')
                  : _t('شروع اسکن', 'Start scan'),
              busy: _scanning,
              onTap: _scanning ? null : _scan,
            ),
          ],
        ),
        if (_best != null) ...[
          const SizedBox(height: 12),
          SettingsGroup(
            children: [
              SettingsRow(
                title: _t('بهترین endpoint', 'Best endpoint'),
                value: _best,
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
            child: Text(
              _log.join('\n'),
              style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 11,
                  color: pal.textMuted,
                  height: 1.4),
            ),
          ),
        ],
        SettingsFooter(_t(
            'نتیجهٔ اسکن توسط موتورهای WARP و MASQUE موقع اتصال استفاده می‌شود.',
            'The scan result is used by the WARP and MASQUE engines on connect.')),
        const SizedBox(height: 24),
      ],
    );
  }
}
