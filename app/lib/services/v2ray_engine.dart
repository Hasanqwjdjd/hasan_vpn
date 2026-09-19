import 'package:flutter_vless/flutter_vless.dart';
import '../models/server.dart';

class V2RayEngine {
  static bool _initialized = false;
  static bool _connected = false;
  static VpnServer? _current;

  static final FlutterVless _engine = FlutterVless(
    onStatusChanged: (dynamic status) {
      print('V2Ray status: $status');
    },
  );

  static bool get isConnected => _connected;
  static VpnServer? get current => _current;

  static Future<void> init() async {
    if (_initialized) return;
    try {
      await _engine.initializeVless(
        providerBundleIdentifier: 'com.hasan.hasan_vpn',
        groupIdentifier: 'group.com.hasan.hasan_vpn',
      );
    } catch (e) {
      print('V2Ray init error: $e');
    }
    _initialized = true;
  }

  static Future<bool> connect(VpnServer server) async {
    try {
      final parsed = FlutterVless.parse(server.shareLink);
      final config = parsed.getFullConfiguration();

      try {
        await _engine.requestPermission();
      } catch (_) {}

      await _engine.startVless(
        remark: server.name,
        config: config,
        proxyOnly: false,
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
