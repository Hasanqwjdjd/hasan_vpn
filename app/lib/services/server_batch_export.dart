import 'dart:convert';

import '../models/server.dart';

/// Export همه سرورها به JSON.
///
/// فرمت:
/// {
///   "_version": 2,
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
///       "ping": 62,
///       "pingKind": "real",
///     },
///     ...
///   ]
/// }
class ServerBatchExport {
  ServerBatchExport._();

  static const String prefix = 'hasan-servers://';
  static const int _version = 2;

  /// Export لیست سرورها به JSON string.
  ///
  /// [includeDeleted] اگه true باشه، سرورهای subscription هم شامل می‌شن.
  static String export(
    List<VpnServer> servers, {
    bool includeDeleted = false,
  }) {
    final filtered = servers
        .where((s) => includeDeleted || s.isDeletable)
        .toList();

    final list = <Map<String, dynamic>>[];
    for (final s in filtered) {
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
    // تاریخچه کیفیت حذف شده — با تعداد سرورهای تست‌شده (با پینگ) جایگزین می‌شود.
    final withQuality = filtered
        .where((s) => s.ping != null && s.ping! > 0)
        .length;
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
}
