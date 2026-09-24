import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Live speed / status notification (Dart side).
///
/// Uses a SINGLE Android notification ID (TelemetryNotifier.NOTIFICATION_ID
/// = 4240). Enabling "show speed" only changes the *body* of that same
/// notification; it does not post a second one. Disabling speed keeps one
/// minimal status notification until [hide] is called.
class TelemetryService {
  TelemetryService._();

  static const String _key = 'telemetry_live_v1';
  static const MethodChannel _ch =
      MethodChannel('com.hasan.hasan_vpn/device');

  static bool enabled = false;
  static int? livePing;
  static bool _shown = false;
  static DateTime _last = DateTime.fromMillisecondsSinceEpoch(0);
  static String? _lastServer;

  static Future<void> load() async {
    try {
      final p = await SharedPreferences.getInstance();
      enabled = p.getBool(_key) ?? false;
    } catch (_) {}
  }

  static Future<void> setEnabled(bool v) async {
    enabled = v;
    try {
      final p = await SharedPreferences.getInstance();
      await p.setBool(_key, v);
    } catch (_) {}
    if (v) {
      await _call('notifPermission');
      // Re-post same ID with speed lines if we already had a status notif.
      if (_shown) {
        onSpeed(down: 0, up: 0, server: _lastServer, force: true);
      }
    } else {
      // Speed off: one minimal status line on the SAME notification id.
      if (_shown) {
        final title = (_lastServer == null || _lastServer!.isEmpty)
            ? 'Hasan VPN'
            : 'Hasan VPN · $_lastServer';
        await _call('telemetryShow', <String, dynamic>{
          'title': title,
          'text': 'Connected · tap to manage',
        });
      }
    }
  }

  static Future<void> _call(String method, [Map<String, dynamic>? args]) async {
    try {
      await _ch.invokeMethod<bool>(method, args);
    } catch (_) {}
  }

  static void onSpeed({
    required int down,
    required int up,
    String? server,
    bool force = false,
  }) {
    if (!enabled && !force) return;
    final now = DateTime.now();
    if (!force &&
        now.difference(_last) < const Duration(milliseconds: 1500)) {
      return;
    }
    _last = now;
    if (server != null) _lastServer = server;

    final title = (_lastServer == null || _lastServer!.isEmpty)
        ? 'Hasan VPN'
        : 'Hasan VPN · $_lastServer';

    final String text;
    if (enabled) {
      final p = livePing;
      final pingText = (p != null && p > 0) ? '$p ms' : '-';
      text = '↓ ${_fmt(down)}   ↑ ${_fmt(up)}   •   Ping $pingText';
    } else {
      text = 'Connected · tap to manage';
    }

    _shown = true;
    _call('telemetryShow', <String, dynamic>{
      'title': title,
      'text': text,
    });
  }

  static Future<void> hide({bool force = false}) async {
    if (!_shown && !force) return;
    _shown = false;
    livePing = null;
    await _call('telemetryHide');
  }

  static String _fmt(int bps) {
    if (bps >= 1048576) return '${(bps / 1048576).toStringAsFixed(1)} MB/s';
    if (bps >= 1024) return '${(bps / 1024).toStringAsFixed(0)} KB/s';
    return '$bps B/s';
  }
}
