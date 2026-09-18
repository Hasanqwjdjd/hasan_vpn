import 'package:flutter_vless/flutter_vless.dart';
import '../models/server.dart';

class Connector {
  static late final FlutterVless _flutterVless;

  static Future<void> init() async {
    _flutterVless = FlutterVless(
      onStatusChanged: (status) {
        print('VLESS Status: $status');
      },
    );
    await _flutterVless.initializeVless(
      providerBundleIdentifier: 'com.hasan.vpn.VPNProvider',
      groupIdentifier: 'group.com.hasan.vpn',
    );
  }

  static Future<bool> connect(VpnServer server) async {
    try {
      final parsed = FlutterVless.parseFromURL(server.shareLink);
      final config = parsed.getFullConfiguration();

      final allowed = await _flutterVless.requestPermission();
      if (!allowed) return false;

      await _flutterVless.startVless(
        remark: parsed.remark,
        config: config,
      );
      return true;
    } catch (e) {
      print('VLESS connection error: $e');
      return false;
    }
  }

  static Future<void> disconnect() async {
    await _flutterVless.stopVless();
  }
}
