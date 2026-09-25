import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../services/app_colors.dart';
import '../services/link_parser.dart';

/// صفحه اسکن QR برای افزودن سریع یک کانفیگ.
/// اگر کد QR معتبر (شامل یکی از پروتکل‌های شناخته‌شده) پیدا شود، متن آن
/// از طریق Navigator.pop برگردانده می‌شود تا صفحه‌ی افزودن کانفیگ آن را پر کند.
class QrScanScreen extends StatefulWidget {
  final String language;

  /// 'vpn' (پیش‌فرض) = فقط لینک VPN معتبر
  /// 'dns' = DNS line/JSON قبول می‌کند
  /// 'any' = هر محتوایی
  final String mode;

  const QrScanScreen({super.key, this.language = 'fa', this.mode = 'vpn'});

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
  bool _looksValid(String raw) {
    final mode = widget.mode;
    if (mode == 'any') return raw.trim().isNotEmpty;
    if (mode == 'dns') {
      final t = raw.trim();
      if (t.isEmpty) return false;
      if (t.startsWith('{') || t.startsWith('[')) return true;
      // هر خط: نام/IP/پورت، جدا شده با کاما (حداکثر ۳ بخش)
      for (final line in t.split('\n')) {
        final segs = line.split(',');
        if (segs.length > 3) return false;
        if (segs.any((x) => x.trim().isEmpty)) return false;
      }
      return true;
    }
    return LinkParser.extractLinks(raw).isNotEmpty;
  }

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

  Widget _errorView(BuildContext context, MobileScannerException error) {
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
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        elevation: 0,
        title: Text(
            widget.mode == 'dns'
                ? _t('اسکن QR DNS', 'Scan DNS QR')
                : _t('اسکن QR کانفیگ', 'Scan Config QR'),
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
            errorBuilder: (context, error, child) => _errorView(context, error),
          ),
          Center(
            child: Container(
              width: 240,
              height: 240,
              decoration: BoxDecoration(
                border: Border.all(color: AppColors.accent, width: 2.5),
                borderRadius: BorderRadius.circular(20),
              ),
            ),
          ),
          Positioned(
            bottom: 40,
            left: 24,
            right: 24,
            child: Text(
              _t(
                'کد QR کانفیگ (VLESS / Trojan / VMess / Aether و ...) را داخل کادر بگیرید',
                'Point the frame at a config QR code (VLESS / Trojan / VMess / Aether ...)',
              ),
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
}
