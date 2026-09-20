import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../services/app_colors.dart';
import '../services/link_parser.dart';

/// صفحه اسکن QR برای افزودن سریع یک کانفیگ.
/// اگر کد QR معتبر (شامل یکی از پروتکل‌های شناخته‌شده) پیدا شود، متن آن
/// از طریق Navigator.pop برگردانده می‌شود تا صفحه‌ی افزودن کانفیگ آن را پر کند.
class QrScanScreen extends StatefulWidget {
  final String language;

  const QrScanScreen({super.key, this.language = 'fa'});

  @override
  State<QrScanScreen> createState() => _QrScanScreenState();
}

class _QrScanScreenState extends State<QrScanScreen> {
  final MobileScannerController _controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.normal,
    facing: CameraFacing.back,
    torchEnabled: false,
  );

  bool _handled = false;
  bool _torchOn = false;

  bool get _isFa => widget.language == 'fa';
  String _t(String fa, String en) => _isFa ? fa : en;

  /// QR معتبر = حداقل یک لینک پشتیبانی‌شده (vless / vmess / trojan / ss /
  /// hysteria2 / aether) داخل متن داشته باشد.
  bool _looksValid(String raw) => LinkParser.extractLinks(raw).isNotEmpty;

  void _onDetect(BarcodeCapture capture) {
    if (_handled) return;
    for (final barcode in capture.barcodes) {
      final raw = barcode.rawValue;
      if (raw == null || raw.trim().isEmpty) continue;
      if (_looksValid(raw)) {
        _handled = true;
        Navigator.pop(context, raw.trim());
        return;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        elevation: 0,
        title: Text(_t('اسکن QR کانفیگ', 'Scan Config QR'),
            style: const TextStyle(color: Colors.white)),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            icon: Icon(_torchOn ? Icons.flash_on : Icons.flash_off,
                color: Colors.white),
            onPressed: () {
              _controller.toggleTorch();
              setState(() => _torchOn = !_torchOn);
            },
          ),
          IconButton(
            icon: const Icon(Icons.cameraswitch, color: Colors.white),
            onPressed: () => _controller.switchCamera(),
          ),
        ],
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          MobileScanner(
            controller: _controller,
            onDetect: _onDetect,
            errorBuilder: (BuildContext context, dynamic error, [Widget? child]) {
              String details = '';
              try {
                details = (error.errorDetails?.message ?? '').toString();
              } catch (_) {}
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    _t(
                      'دسترسی به دوربین ممکن نشد.\nاز تنظیمات گوشی مجوز دوربین را فعال کنید.\n\n$details',
                      'Could not access camera.\nEnable camera permission from phone settings.\n\n$details',
                    ),
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white),
                  ),
                ),
              );
            },
          ),
          // فریم راه
