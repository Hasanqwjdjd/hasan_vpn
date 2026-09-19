import 'package:flutter_vless/flutter_vless.dart';
import '../models/server.dart';

class V2RayEngine {
  static bool _initialized = false;
  static bool _connected = false;
  static VpnServer? _current;

  // ⭐ FlutterVless با پارامتر onStatusChanged
  static final FlutterVless _engine = FlutterVless(
    onStatusChanged: (VlessStatus status) {
      // وضعیت اتصال
      _connected = status.state == VlessState.connected;
    },
  );

  static bool get isConnected => _connected;
  static VpnServer? get current => _current;

  static Future<void> init() async {
    if (_initialized) return;
    await _engine.initializeVless(
      notificationIconResourceType: 'mipmap',
      notificationIconResourceName: 'ic_launcher',
      providerBundleIdentifier: 'com.hasan.vpn.VPNProvider',
      groupIdentifier: 'group.com.hasan.vpn',
    );
    _initialized = true;
  }

  /// اتصال در حالت پروکسی (بدون VPN)
  static Future<bool> connect(VpnServer server) async {
    try {
      final parsed = FlutterVless.parseFromURL(server.shareLink);
      final config = parsed.getFullConfiguration();

      await _engine.startVless(
        remark: server.name,
        config: config,
        proxyOnly: true,
      );

      _connected = true;
      _current = server;
      return true;
    } catch (e) {
      print('V2Ray connect error: $e');
      _connected = false;
      return false;
    }
  }

  static Future<void> disconnect() async {
    try {
      await _engine.stopVless();
    } catch (_) {}
    _connected = false;
    _current = null;
  }
}
