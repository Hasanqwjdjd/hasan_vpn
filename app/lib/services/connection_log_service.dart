import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// یک رکورد اتصال (اتصال/قطع/خطا).
class ConnectionLogEntry {
  final DateTime timestamp;
  final String type; // connect | disconnect | error
  final String target; // server name
  final String? detail;

  const ConnectionLogEntry({
    required this.timestamp,
    required this.type,
    required this.target,
    this.detail,
  });

  Map<String, dynamic> toJson() => {
        'ts': timestamp.toIso8601String(),
        'type': type,
        'target': target,
        if (detail != null) 'detail': detail,
      };

  factory ConnectionLogEntry.fromJson(Map<String, dynamic> j) =>
      ConnectionLogEntry(
        timestamp: DateTime.tryParse(j['ts']?.toString() ?? '') ??
            DateTime.now(),
        type: j['type']?.toString() ?? 'connect',
        target: j['target']?.toString() ?? '',
        detail: j['detail']?.toString(),
      );
}

/// لاگ اتصال‌ها — حداکثر ۲۰۰ رکورد آخر.
class ConnectionLogService {
  ConnectionLogService._();
  static const String _key = 'connection_log_v1';
  static const int _maxEntries = 200;

  // ─── Session accumulator (in-memory only) ───
  // در طول هر session، home_screen بعد از هر probe موفق یک sample اضافه
  // می‌کند. در logDisconnect، خلاصه‌اش به detail اضافه و پاک می‌شود.
  static final List<int> _sessRtt = <int>[];
  static final List<int> _sessJitter = <int>[];
  static final List<double> _sessLoss = <double>[];

  static void _resetSession() {
    _sessRtt.clear();
    _sessJitter.clear();
    _sessLoss.clear();
  }

  /// Feed a fresh probe sample into the current session accumulator.
  /// Safe to call from anywhere; no-op when the value is missing.
  static void recordSample({
    int? rttMs,
    int? jitterMs,
    double? lossPct,
  }) {
    if (rttMs != null && rttMs > 0) _sessRtt.add(rttMs);
    if (jitterMs != null && jitterMs >= 0) _sessJitter.add(jitterMs);
    if (lossPct != null && lossPct >= 0) _sessLoss.add(lossPct);
  }

  /// Human-readable summary of the samples seen so far, or null.
  static String? _sessionSummaryText() {
    if (_sessRtt.isEmpty && _sessJitter.isEmpty && _sessLoss.isEmpty) {
      return null;
    }
    int avgI(List<int> xs) =>
        xs.isEmpty ? 0 : xs.reduce((a, b) => a + b) ~/ xs.length;
    int minI(List<int> xs) =>
        xs.isEmpty ? 0 : xs.reduce((a, b) => a < b ? a : b);
    int maxI(List<int> xs) =>
        xs.isEmpty ? 0 : xs.reduce((a, b) => a > b ? a : b);
    double avgD(List<double> xs) =>
        xs.isEmpty ? 0 : xs.reduce((a, b) => a + b) / xs.length;

    final parts = <String>[];
    if (_sessRtt.isNotEmpty) {
      parts.add('rtt ${avgI(_sessRtt)}ms '
          '(${minI(_sessRtt)}–${maxI(_sessRtt)})');
    }
    if (_sessJitter.isNotEmpty) {
      parts.add('jitter ${avgI(_sessJitter)}ms');
    }
    if (_sessLoss.isNotEmpty) {
      parts.add('loss ${avgD(_sessLoss).toStringAsFixed(1)}%');
    }
    final n = _sessRtt.isNotEmpty
        ? _sessRtt.length
        : (_sessJitter.isNotEmpty ? _sessJitter.length : _sessLoss.length);
    parts.add('n=$n');
    return parts.join(' · ');
  }

  /// Notifier که UI می‌تونه listen کنه — هر بار add/clear صدا زده می‌شه.
  static final ValueNotifier<int> revision = ValueNotifier<int>(0);

  /// signal برای rebuild
  static void _bump() {
    revision.value = revision.value + 1;
  }

  static Future<List<ConnectionLogEntry>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = jsonDecode(raw) as List;
      return list
          .whereType<Map>()
          .map((e) =>
              ConnectionLogEntry.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> add(ConnectionLogEntry e) async {
    final list = await load();
    list.insert(0, e);
    if (list.length > _maxEntries) {
      list.removeRange(_maxEntries, list.length);
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _key,
      jsonEncode(list.map((e) => e.toJson()).toList()),
    );
    _bump();
  }

  static Future<void> clear() async {
    _resetSession();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
    _bump();
  }

  /// helper برای ثبت سریع
  static Future<void> logConnect(String target) {
    _resetSession();
    return add(ConnectionLogEntry(
      timestamp: DateTime.now(),
      type: 'connect',
      target: target,
    ));
  }

  static Future<void> logDisconnect(String target) {
    final summary = _sessionSummaryText();
    _resetSession();
    return add(ConnectionLogEntry(
      timestamp: DateTime.now(),
      type: 'disconnect',
      target: target,
      detail: summary,
    ));
  }

  static Future<void> logError(String target, String detail) =>
      add(ConnectionLogEntry(
        timestamp: DateTime.now(),
        type: 'error',
        target: target,
        detail: detail,
      ));

  /// هر endpoint که در scan WARP/WARP+ تست شد.
  /// [detail] مثلاً "188.114.96.206:878 · 62ms" یا "… · ✕ timeout".
  static Future<void> logWarpScan({
    required String server,
    required String endpoint,
    int? ms,
    String? reason,
  }) {
    final detail = ms != null && ms > 0
        ? '$endpoint · ${ms}ms'
        : '$endpoint · ${reason ?? "no response"}';
    return add(ConnectionLogEntry(
      timestamp: DateTime.now(),
      type: 'warp_scan',
      target: server,
      detail: detail,
    ));
  }

  /// پایان یک rescan — endpoint برنده + زمان کل.
  static Future<void> logWarpRescanResult({
    required String server,
    required String endpoint,
    required int ms,
  }) =>
      add(ConnectionLogEntry(
        timestamp: DateTime.now(),
        type: 'warp_rescan',
        target: server,
        detail: 'winner $endpoint · ${ms}ms',
      ));
}
