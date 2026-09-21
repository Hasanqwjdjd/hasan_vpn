import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

class TelemetryService {
  TelemetryService._();

  static const String _key = 'telemetry_live_v1';
  static const MethodChannel _ch =
      MethodChannel('com.hasan.hasan_vpn/device');

  static bool enabled = false;
  static int? livePing;
  static bool _shown = false;
  static DateTime _last = DateTime.fromMillisecondsSinceEpoch(0);

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
    } else {
      await hide(force: true);
    }
  }

  static Future<void> _call(String method, [Map<String, dynamic>? args]) async {
    try {
      await _ch.invokeMethod<bool>(method, args);
    } catch (_) {}
  }

  static void onSpeed({required int down, required int up, String? server}) {
    if (!enabled) return;
    final now = DateTime.now();
    if (now.difference(_last) < const Duration(milliseconds: 1500)) return;
    _last = now;

    final p = livePing;
    final pingText = (p != null && p > 0) ? '$p ms' : '-';
    final title = (server == null || server.isEmpty)
        ? 'Hasan VPN'
        : 'Hasan VPN · $server';
    _shown = true;
    _call('telemetryShow', <String, dynamic>{
      'title': title,
      'text': '↓ ${_fmt(down)}   ↑ ${_fmt(up)}   •   Ping $pingText',
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
