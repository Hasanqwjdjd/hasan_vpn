import 'package:url_launcher/url_launcher.dart';
import '../models/server.dart';

class Connector {
  static Future<void> init() async {}

  static Future<bool> connect(VpnServer server) async {
    try {
      final uri = Uri.parse(server.shareLink);
      await launchUrl(uri, mode: LaunchMode.externalApplication);
      return true;
    } catch (e) {
      print('Launch error: $e');
      return false;
    }
  }

  static Future<void> disconnect() async {}
}
