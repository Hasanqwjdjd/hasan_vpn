import 'package:url_launcher/url_launcher.dart';
import '../models/server.dart';

class Connector {
  static Future<void> init() async {}

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

  static Future<void> disconnect() async {}
}
