import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/server.dart';

/// Scheduler برای اجرای دوره‌ای endpoint scan در پس‌زمینه.
///
/// هر [intervalMin] دقیقه (پیش‌فرض ۶۰) یه بار سرور WARP/WARP+/MASQUE
/// انتخاب‌شده رو rescan می‌کنه و اگه endpoint فعلی خراب یا کند شد،
/// بهترین رو جایگزین می‌کنه.
///
/// محافظه‌کار روی باتری:
///   • فقط وقتی کاربر فعالش کرده
///   • فقط اولین سرور WARP/WARP+ فعال
///   • اگه endpoint فعلی سالم باشه، فقط verify سریع
///   • اگه خراب بود، scan کامل Fast
class WarpScoutScheduler {
  WarpScoutScheduler._();
  static final WarpScoutScheduler instance = WarpScoutScheduler._();

  static const String _prefKeyEnabled = 'warp_scout_scheduler_enabled_v1';
  static const String _prefKeyInterval = 'warp_scout_scheduler_interval_v1';
  static const String _prefKeyLastRun = 'warp_scout_scheduler_last_run_v1';
  static const int defaultIntervalMin = 60;

  Timer? _timer;
  bool _enabled = false;
  int _intervalMin = defaultIntervalMin;
  bool _running = false;

  Future<void> Function(VpnServer server, {bool force})? onRescanNeeded;
  List<VpnServer> Function()? serversProvider;

  bool get enabled => _enabled;
  bool get running => _running;
  int get intervalMin => _intervalMin;

  DateTime? _lastRunAt;
  DateTime? get lastRunAt => _lastRunAt;

  Future<void> restore() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _enabled = prefs.getBool(_prefKeyEnabled) ?? false;
      _intervalMin =
          prefs.getInt(_prefKeyInterval) ?? defaultIntervalMin;
      final lastRaw = prefs.getInt(_prefKeyLastRun);
      if (lastRaw != null) {
        _lastRunAt = DateTime.fromMillisecondsSinceEpoch(lastRaw);
      }
      if (_enabled) _startTimer();
    } catch (_) {}
  }

  Future<void> setEnabled(bool value) async {
    _enabled = value;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_prefKeyEnabled, value);
    } catch (_) {}
    if (value) {
      _startTimer();
    } else {
      _timer?.cancel();
      _timer = null;
    }
  }

  Future<void> setIntervalMin(int min) async {
    _intervalMin = min.clamp(15, 720);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_prefKeyInterval, _intervalMin);
    } catch (_) {}
    if (_enabled) _startTimer();
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(
      Duration(minutes: _intervalMin),
      (_) => _tick(),
    );
  }

  Future<void> _tick() async {
    if (_running || !_enabled) return;
    _running = true;
    try {
      final servers = serversProvider?.call() ?? const <VpnServer>[];
      final target = _pickTargetServer(servers);
      if (target == null) return;

      final endpoint = '${target.host}:${target.port}';
      final alive = await _isEndpointAlive(endpoint);

      if (onRescanNeeded != null) {
        await onRescanNeeded!(target, force: !alive);
      }

      _lastRunAt = DateTime.now();
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setInt(
          _prefKeyLastRun,
          _lastRunAt!.millisecondsSinceEpoch,
        );
      } catch (_) {}

      debugPrint('warp-scout-scheduler: rescan ${target.name} '
          'force=${!alive}');
    } catch (e) {
      debugPrint('warp-scout-scheduler: error $e');
    } finally {
      _running = false;
    }
  }

  VpnServer? _pickTargetServer(List<VpnServer> servers) {
    for (final s in servers) {
      if (!s.isDeletable) continue;
      if (s.protocol == VpnProtocol.amneziaWg ||
          s.protocol == VpnProtocol.chain ||
          s.protocol == VpnProtocol.warpMasque) {
        return s;
      }
    }
    return null;
  }

  Future<bool> _isEndpointAlive(String endpoint) async {
    final parts = endpoint.split(':');
    if (parts.length < 2) return false;
    final port = int.tryParse(parts[1]);
    if (port == null || port < 1 || port > 65535) return false;
    Socket? sock;
    try {
      sock = await Socket.connect(
        parts[0],
        port,
        timeout: const Duration(milliseconds: 2500),
      );
      return true;
    } catch (_) {
      return false;
    } finally {
      try { sock?.destroy(); } catch (_) {}
    }
  }

  Future<void> runNow({bool force = true}) async {
    if (_running) return;
    await _tick();
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }
}
