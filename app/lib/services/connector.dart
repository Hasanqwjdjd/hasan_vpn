import 'package:url_launcher/url_launcher.dart';
import '../models/server.dart';

class Connector {
  /// باز کردن v2rayNG با کانفیگ (v2rayNG این لینک‌ها رو می‌شناسه)
  static Future<bool> connect(VpnServer server) async {
    try {
      final uri = Uri.parse(server.shareLink);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
        return true;
      }
      return false;
    } catch (_) {
      return false;
    }
  }
}
