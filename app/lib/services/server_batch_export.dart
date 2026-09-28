import 'dart:convert';

import '../models/server.dart';
import 'quality_history_service.dart';

/// Export همه سرورها + آخرین کیفیت هر کدام به JSON.
///
/// فرمت:
/// {
///   "_version": 1,
///   "_exportedAt": "ISO",
///   "_count": N,
///   "servers": [
///     {
///       "id": "...",
///       "name": "...",
///       "protocol": "vless",
///       "flag": "🇩🇪",
///       "host": "...",
///       "port": 443,
///       "shareLink": "...",
///       "lastQualityScore": 85,
///       "lastQualityGrade": "excellent",
///       "ping": 62,
///       "pingKind": "real",
///     },
///     ...
///   ]
/// }
class ServerBatchExport {
  ServerBatchExport._();

  static const String prefix = 'hasan-servers://';
  static const int _version = 1;

  /// Export لیست سرورها به JSON string.
  ///
  /// [includeDeleted] اگه true باشه، سرورهای subscription هم شامل می‌شن.
  static String export(
    List<VpnServer> servers, {
    bool includeDeleted = false,
  }) {
    final samples = QualityHistoryService.cached;
    final latestByServer = <String, QualitySample>{};
    for (final s in samples) {
      if (s.serverId.isEmpty) continue;
      final prev = latestByServer[s.serverId];
      if (prev == null || s.at.isAfter(prev.at)) {
        latestByServer[s.serverId] = s;
      }
    }

    final filtered = servers
        .where((s) => includeDeleted || s.isDeletable)
        .toList();

    final list = <Map<String, dynamic>>[];
    for (final s in filtered) {
      final latest = latestByServer[s.id];
      list.add(<String, dynamic>{
        'id': s.id,
        'name': s.displayName,
        'protocol': s.protocol.name,
        'flag': s.flag,
        'host': s.host,
        'port': s.port,
        'shareLink': s.shareLink,
        'isDeletable': s.isDeletable,
        'ping': s.ping,
        'pingKind': s.pingKind.name,
        if (latest != null) ...<String, dynamic>{
          'lastQualityScore': latest.score,
          'lastQualityGrade': _gradeLabel(latest.score),
          'lastQualityAt': latest.at.toIso8601String(),
          'lastQualityPing': latest.pingMs,
          'lastQualityJitter': latest.jitterMs,
        },
      });
    }

    return jsonEncode(<String, dynamic>{
      '_version': _version,
      '_exportedAt': DateTime.now().toIso8601String(),
      '_count': list.length,
      'servers': list,
    });
  }

  /// Import سرورها از JSON.
  ///
  /// برمی‌گردونه: { imported: N, updated: M, skipped: K }
  static Future<({int imported, int updated, int skipped})> import(
    String raw,
    Map<String, VpnServer> existingById,
  ) async {
    try {
      final doc = jsonDecode(raw);
      if (doc is! Map) return (imported: 0, updated: 0, skipped: 0);
      final servers = doc['servers'];
      if (servers is! List) return (imported: 0, updated: 0, skipped: 0);

      var imported = 0;
      var updated = 0;
      var skipped = 0;

      for (final rawServer in servers) {
        if (rawServer is! Map) {
          skipped++;
          continue;
        }
        final id = rawServer['id']?.toString() ?? '';
        if (id.isEmpty) {
          skipped++;
          continue;
        }
        // در این نسخه فقط شمارش می‌کنیم — merging واقعی توسط caller
        if (existingById.containsKey(id)) {
          updated++;
        } else {
          imported++;
        }
      }

      return (imported: imported, updated: updated, skipped: skipped);
    } catch (_) {
      return (imported: 0, updated: 0, skipped: 0);
    }
  }

  /// شمارش سریع.
  static ({int count, int withQuality}) stats(
    List<VpnServer> servers, {
    bool includeDeleted = false,
  }) {
    final filtered = servers
        .where((s) => includeDeleted || s.isDeletable)
        .toList();
    final samples = QualityHistoryService.cached;
    final ids = <String>{};
    for (final s in samples) {
      if (s.serverId.isNotEmpty) ids.add(s.serverId);
    }
    final withQuality = filtered.where((s) => ids.contains(s.id)).length;
    return (count: filtered.length, withQuality: withQuality);
  }

  /// آیا URI معتبر است؟
  static bool looksLikeBatchExport(String raw) {
    final trimmed = raw.trim();
    if (!trimmed.startsWith('{')) return false;
    try {
      final doc = jsonDecode(trimmed);
      return doc is Map && doc['servers'] is List;
    } catch (_) {
      return false;
    }
  }

  static String _gradeLabel(int score) {
    if (score >= 85) return 'excellent';
    if (score >= 70) return 'good';
    if (score >= 50) return 'fair';
    if (score >= 30) return 'poor';
    return 'bad';
  }
}
