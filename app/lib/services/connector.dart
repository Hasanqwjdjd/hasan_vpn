import 'package:flutter_v2ray_client/flutter_v2ray.dart';
import 'package:flutter_v2ray_client/model/v2ray_status.dart';
import '../models/server.dart';

class Connector {
  static FlutterV2ray? _v2ray;
  static bool _connected = false;

  static Future<void> init() async {
    _v2ray = FlutterV2ray(
      onStatusChanged: (V2RayStatus status) {
        // وضعیت اتصال رو دنبال کن
        print('V2Ray status: ${status.state}');
        _connected = status.state.toString().toLowerCase().contains('connect');
      },
    );
  }

  static Future<bool> connect(VpnServer server) async {
    try {
      if (_v2ray == null) return false;

      // ۱. اجازه VPN از کاربر بگیر
      final permitted = await _v2ray!.requestPermission();
      if (!permitted) return false;

      // ۲. موتور رو با کانفیگ راه‌اندازی کن
      await _v2ray!.initializeV2Ray(
        remark: server.name,
        config: server.shareLink,
        url: '',
        blockedApps: [],
        bypassSubnets: [],
        proxyOnly: false,
      );

      // ۳. اتصال رو شروع کن
      await _v2ray!.startV2Ray(
        remark: server.name,
        config: server.shareLink,
        proxyOnly: false,
      );
      _connected = true;
      return true;
    } catch (e) {
      print('V2Ray connection error: $e');
      _connected = false;
      return false;
    }
  }

  static Future<void> disconnect() async {
    try {
      await _v2ray?.stopV2Ray();
    } catch (_) {}
    _connected = false;
  }

  static bool get isConnected => _connected;
}
