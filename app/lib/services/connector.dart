import 'package:flutter_v2ray_client/flutter_v2ray_client.dart';
import '../models/server.dart';

class Connector {
  static late final FlutterV2rayClient _v2ray;

  static Future<void> init() async {
    _v2ray = FlutterV2rayClient();
    await _v2ray.initialize(
      providerBundleIdentifier: 'com.hasan.vpn.VPNProvider',
      groupIdentifier: 'group.com.hasan.vpn',
    );
  }

  static Future<bool> connect(VpnServer server) async {
    try {
      final parsed = FlutterV2rayClient.parseFromURL(server.shareLink);
      final config = parsed.getFullConfiguration();

      final allowed = await _v2ray.requestPermission();
      if (!allowed) return false;

      await _v2ray.startV2Ray(
        remark: parsed.remark,
        config: config,
      );
      return true;
    } catch (e) {
      print('V2Ray connection error: $e');
      return false;
    }
  }

  static Future<void> disconnect() async {
    await _v2ray.stopV2Ray();
  }
}
