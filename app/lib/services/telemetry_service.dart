import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'xray_settings.dart';
import 'connection_quality.dart';

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
  /// آخرین امتیاز کیفیت — از home_screen ست می‌شه.
  static int? lastQualityScore;
  static String? lastQualityEmoji;
  static bool _shown = false;
  static DateTime _last = DateTime.fromMillisecondsSinceEpoch(0);
  static String? _lastServer;

  static Future<void> load() async {
    try {
      final p = await SharedPreferences.getInstance();
      // اولویت ۱: telemetry_live_v1
      if (p.containsKey(_key)) {
        enabled = p.getBool(_key) ?? false;
        return;
      }
      // اولویت ۲: xray_settings.showSpeedNotif
      final xs = await XraySettings.load();
      enabled = xs['showSpeedNotif'] == true;
      await p.setBool(_key, enabled);
    } catch (_) {}
  }

  static Future<void> setEnabled(bool v) async {
    enabled = v;
    try {
      final p = await SharedPreferences.getInstance();
      await p.setBool(_key, v);
      await XraySettings.set('showSpeedNotif', v);
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

  /// ست کردن امتیاز کیفیت — از home_screen بعد از هر probe.
  /// اگه notification فعال باشه، متن رو با badge جدید دوباره می‌سازه.
  static void setQuality(int? score, String? emoji) {
    lastQualityScore = score;
    lastQualityEmoji = emoji;
    // re-render اگه notif فعاله
    if (_shown && (enabled || lastQualityScore != null)) {
      onSpeed(down: 0, up: 0, force: true);
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
      // badge کیفیت
      final qEmoji = lastQualityEmoji ?? '';
      final qScore = lastQualityScore;
      final qPart = (qScore != null && qEmoji.isNotEmpty)
          ? '   •   $qEmoji $qScore'
          : '';
      text = '↓ ${_fmt(down)}   ↑ ${_fmt(up)}   •   Ping $pingText$qPart';
    } else {
      // اگه quality هست ولی speed نمایش داده نمی‌شه، بازم badge رو نشون بده
      if (lastQualityScore != null && lastQualityEmoji != null) {
        text = 'Connected · $lastQualityEmoji $lastQualityScore · tap to manage';
      } else {
        text = 'Connected · tap to manage';
      }
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
    lastQualityScore = null;
    lastQualityEmoji = null;
    await _call('telemetryHide');
  }

  static String _fmt(int bps) {
    if (bps >= 1048576) return '${(bps / 1048576).toStringAsFixed(1)} MB/s';
    if (bps >= 1024) return '${(bps / 1024).toStringAsFixed(0)} KB/s';
    return '$bps B/s';
  }
}
