import 'dart:convert';

import '../models/server.dart';
import 'quality_history_service.dart';
import 'warp_endpoint_health_monitor.dart';

/// وضعیت سلامت یک سرور.
enum HealthTier {
  /// سرور سالم — ping نرمال + quality خوب
  healthy,

  /// هشدار — ping بالا یا quality پایین یا fails اخیر
  warning,

  /// مشکل‌دار — چند fails متوالی یا ping خیلی بد
  critical,

  /// هنوز تست نشده
  untested,
}

/// اطلاعات سلامت یک سرور.
class ServerHealth {
  final VpnServer server;
  final HealthTier tier;
  final int? lastPingMs;
  final int? lastQualityScore;
  final DateTime? lastTestAt;
  final int consecutiveFails;
  final String? note;

  const ServerHealth({
    required this.server,
    required this.tier,
    this.lastPingMs,
    this.lastQualityScore,
    this.lastTestAt,
    this.consecutiveFails = 0,
    this.note,
  });

  bool get isDeletable => server.isDeletable;
  String get displayName => server.displayName;
  String get flag => server.flag;
}

/// محاسبه سلامت همه سرورها.
///
/// برای هر سرور، آخرین نمونه‌ی quality + آخرین ping + وضعیت health monitor
/// رو با هم ترکیب می‌کنه و یه tier می‌ده.
class ServerHealthCalculator {
  ServerHealthCalculator._();

  /// محاسبه tier بر اساس:
  ///   - آخرین ping (اگه > 2000ms = warning، > 5000 = critical)
  ///   - آخرین quality score (< 40 = warning، < 20 = critical)
  ///   - consecutiveFails (>= 3 = critical)
  ///   - نبود داده = untested
  static ServerHealth compute(VpnServer server) {
    final lastPing = server.ping;
    final pingKind = server.pingKind;
    final status = server.status;

    // آخرین quality از history
    final samples = QualityHistoryService.forServer(server.id);
    final lastQuality = samples.isNotEmpty ? samples.last : null;

    // health monitor برای سرور فعلی
    final monitorState = WarpEndpointHealthMonitor.instance.state.value;
    final isActiveMonitor = monitorState.running &&
        monitorState.endpoint == '${server.host}:${server.port}';
    final consecutiveFails =
        isActiveMonitor ? monitorState.consecutiveFails : 0;

    // تعیین tier
    HealthTier tier = HealthTier.untested;
    String? note;

    if (consecutiveFails >= 3) {
      tier = HealthTier.critical;
      note = 'monitor: $consecutiveFails fails';
    } else if (status == ServerStatus.offline) {
      tier = HealthTier.critical;
      note = 'offline';
    } else if (lastPing != null && lastPing > 0) {
      final q = lastQuality?.score;
      if (lastPing > 5000 || (q != null && q < 20)) {
        tier = HealthTier.critical;
        note = 'ping ${lastPing}ms';
      } else if (lastPing > 2000 || (q != null && q < 40)) {
        tier = HealthTier.warning;
        note = 'ping ${lastPing}ms';
      } else {
        tier = HealthTier.healthy;
      }
    } else if (lastQuality != null) {
      if (lastQuality.score < 20) {
        tier = HealthTier.critical;
      } else if (lastQuality.score < 40) {
        tier = HealthTier.warning;
      } else {
        tier = HealthTier.healthy;
      }
    }

    // pingKind tcp = تقریبی، کمی عدم اعتماد
    if (tier == HealthTier.healthy && pingKind == PingKind.tcp) {
      // tcp-only رو به warning نمی‌برم — فقط note
      note = 'tcp-only';
    }

    return ServerHealth(
      server: server,
      tier: tier,
      lastPingMs: lastPing,
      lastQualityScore: lastQuality?.score,
      lastTestAt: lastQuality?.at,
      consecutiveFails: consecutiveFails,
      note: note,
    );
  }

  /// محاسبه برای همه سرورها.
  static List<ServerHealth> computeAll(List<VpnServer> servers) {
    return servers.map(compute).toList();
  }

  /// فیلتر بر اساس tier.
  static List<ServerHealth> filter(
    List<ServerHealth> list,
    HealthTier? tier,
  ) {
    if (tier == null) return list;
    return list.where((h) => h.tier == tier).toList();
  }

  /// شمارش هر tier.
  static Map<HealthTier, int> countByTier(List<ServerHealth> list) {
    final out = <HealthTier, int>{
      HealthTier.healthy: 0,
      HealthTier.warning: 0,
      HealthTier.critical: 0,
      HealthTier.untested: 0,
    };
    for (final h in list) {
      out[h.tier] = (out[h.tier] ?? 0) + 1;
    }
    return out;
  }

  /// Export گزارش به JSON.
  static String exportReport(List<ServerHealth> list) {
    final doc = <String, dynamic>{
      '_version': 1,
      '_exportedAt': DateTime.now().toIso8601String(),
      '_count': list.length,
      'summary': {
        'healthy': list.where((h) => h.tier == HealthTier.healthy).length,
        'warning': list.where((h) => h.tier == HealthTier.warning).length,
        'critical':
            list.where((h) => h.tier == HealthTier.critical).length,
        'untested':
            list.where((h) => h.tier == HealthTier.untested).length,
      },
      'servers': list.map((h) => <String, dynamic>{
            'name': h.displayName,
            'flag': h.flag,
            'protocol': h.server.protocol.name,
            'host': h.server.host,
            'port': h.server.port,
            'tier': h.tier.name,
            if (h.lastPingMs != null) 'ping': h.lastPingMs,
            if (h.lastQualityScore != null) 'quality': h.lastQualityScore,
            if (h.lastTestAt != null)
              'lastTestAt': h.lastTestAt!.toIso8601String(),
            if (h.consecutiveFails > 0) 'fails': h.consecutiveFails,
            if (h.note != null) 'note': h.note,
          }).toList(),
    };
    return const JsonEncoder.withIndent('  ').convert(doc);
  }

  /// خواندن لیست سرور از cache که home_screen آماده کرده.
  static Future<List<VpnServer>> loadServersFromCache(
      Map<String, dynamic> prefsMap) async {
    try {
      final raw = prefsMap['quick_export_servers_v1'];
      if (raw == null || raw is! String || raw.isEmpty) return const [];
      final doc = jsonDecode(raw);
      if (doc is! Map) return const [];
      final list = doc['servers'];
      if (list is! List) return const [];
      final out = <VpnServer>[];
      for (final e in list) {
        if (e is! Map) continue;
        final protoStr = e['protocol']?.toString() ?? '';
        final proto = VpnProtocol.values.firstWhere(
          (p) => p.name == protoStr,
          orElse: () => VpnProtocol.custom,
        );
        out.add(VpnServer(
          id: e['id']?.toString() ?? '',
          name: e['name']?.toString() ?? '',
          flag: e['flag']?.toString() ?? '🌐',
          shareLink: e['shareLink']?.toString() ?? '',
          protocol: proto,
          host: e['host']?.toString() ?? '',
          port: (e['port'] as num?)?.toInt() ?? 0,
          isDeletable: e['isDeletable'] == true,
        )
          ..ping = (e['ping'] as num?)?.toInt()
          ..status = _parseStatus(e['pingKind']?.toString()));
      }
      return out;
    } catch (_) {
      return const [];
    }
  }

  static ServerStatus _parseStatus(String? pingKindStr) {
    if (pingKindStr == null) return ServerStatus.idle;
    if (pingKindStr == 'real' || pingKindStr == 'tcp') {
      return ServerStatus.online;
    }
    return ServerStatus.idle;
  }
}
