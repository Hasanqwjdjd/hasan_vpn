import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../models/server.dart';
import '../services/app_colors.dart';
import '../services/warp_share_codec.dart';

/// نمایش لینک یک سرور به‌صورت QR تا یک دستگاه دیگر بتواند با اسکن آن
/// سرور را به برنامه‌اش اضافه کند.
class QrShareScreen extends StatelessWidget {
  final VpnServer server;
  final String language;

  const QrShareScreen({
    super.key,
    required this.server,
    this.language = 'fa',
  });

  bool get _isFa => language == 'fa';
  String _t(String fa, String en) => _isFa ? fa : en;

  /// لینک مؤثر برای QR و Clipboard. برای سرورهای WARP/WARP+/MASQUE
  /// از فرمت فشرده hasan-warp:// استفاده کن تا QR کوچیک‌تر بشه.
  String get _effectiveLink {
    if (WarpShareCodec.shouldEncode(server)) {
      final compact = WarpShareCodec.encode(server);
      if (compact != null && compact.isNotEmpty) return compact;
    }
    return server.shareLink;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg(context),
      appBar: AppBar(
        backgroundColor: AppColors.bg(context),
        elevation: 0,
        title: Text(_t('اشتراک‌گذاری سرور', 'Share Server'),
            style: TextStyle(color: AppColors.fg(context))),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('${server.flag}  ${server.name}',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: AppColors.fg(context),
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  )),
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(18),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.15),
                      blurRadius: 16,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: QrImageView(
                  data: _effectiveLink,
                  version: QrVersions.auto,
                  size: 240,
                  gapless: true,
                  backgroundColor: Colors.white,
                ),
              ),
              const SizedBox(height: 20),
              Text(
                _t(
                  'این کد را با برنامه‌ی حسن روی گوشی دیگر اسکن کنید تا سرور اضافه شود',
                  'Scan this code with Hasan VPN on another phone to add this server',
                ),
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.muted(context), height: 1.6),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: _effectiveLink));
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(_t('لینک کپی شد', 'Link copied')),
                        duration: const Duration(seconds: 1),
                      ),
                    );
                  },
                  icon: const Icon(Icons.copy, size: 18),
                  label: Text(_t('کپی لینک', 'Copy Link')),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.accent,
                    side: const BorderSide(color: AppColors.accent),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
