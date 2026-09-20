import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../models/server.dart';
import '../services/app_colors.dart';

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
                      color: Colors.black.withOpacity(0.15),
                      blurRadius: 16,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: QrImageView(
                  data: server.shareLink,
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
                    Clipboard.setData(ClipboardData(text: server.shareLink));
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(_t('لینک کپی شد', 'Link copied')),
                        duration: const Duration(seconds: 1),
                      ),
                    );
                  },
                  icon: const Icon(Icons.copy, size: 18),
                  label: Text(_t('کپی ل
