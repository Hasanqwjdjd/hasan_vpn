import 'package:flutter/foundation.dart';
import 'package:flutter_vless/flutter_vless.dart';
import '../models/server.dart';

class V2RayEngine {
  static bool _initialized = false;
  static bool _connected = false;
  static VpnServer? _current;
  static String? lastError;

  static final FlutterVless _engine = FlutterVless(
    onStatusChanged: (dynamic status) {
      debugPrint('V2Ray status: $status');
      try {
        final raw = status.connectionState?.toString() ??
            status.state?.toString() ??
            status.toString();
        final s = raw.toLowerCase();
        if (s.contains('disconnect') ||
            s.contains('idle') ||
            s.contains('stop') ||
            s.contains('closed')) {
          _connected = false;
        } else if (s.contains('connected') || s.contains('connecting')) {
          _connected = s.contains('connected');
        }
      } catch (_) {}
    },
  );

  static bool get isConnected => _connected;
  static VpnServer? get current => _current;

  static Future<void> init() async {
    if (_initialized) return;
    try {
      await _engine.initializeVless(
        notificationIconResourceType: 'mipmap',
        notificationIconResourceName: 'ic_launcher',
      );
    } catch (e) {
      debugPrint('V2Ray init error: $e');
    }
    _initialized = true;
  }

  static Future<bool> connect(VpnServer server) async {
    lastError = null;
    try {
      await init();

      final FlutterVlessURL parser = FlutterVless.parse(server.shareLink);
      final String config = parser.getFullConfiguration();
      if (config.trim().isEmpty) {
        lastError = 'empty config';
        return false;
      }

      final bool allowed = await _engine.requestPermission();
      if (!allowed) {
        lastError = 'VPN permission denied';
        debugPrint(lastError);
        return false;
      }

      await _engine.startVless(
        remark: parser.remark.isNotEmpty ? parser.remark : server.name,
        config: config,
        proxyOnly: false,
      );

      _connected = true;
      _current = server;
      return true;
    } catch (e) {
      lastError = e.toString();
      debugPrint('V2Ray connect error: $e');
      _connected = false;
      _current = null;
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
