import 'dart:convert';

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
  }

  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }

  /// helper برای ثبت سریع
  static Future<void> logConnect(String target) =>
      add(ConnectionLogEntry(
        timestamp: DateTime.now(),
        type: 'connect',
        target: target,
      ));

  static Future<void> logDisconnect(String target) =>
      add(ConnectionLogEntry(
        timestamp: DateTime.now(),
        type: 'disconnect',
        target: target,
      ));

  static Future<void> logError(String target, String detail) =>
      add(ConnectionLogEntry(
        timestamp: DateTime.now(),
        type: 'error',
        target: target,
        detail: detail,
      ));
}
