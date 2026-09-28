import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/server.dart';
import 'quality_history_service.dart';

/// یک بازه‌ی آماری (protocol/country/hour).
class InsightBucket {
  final String label;
  final int count;
  final int avgScore;
  final int avgPing;
  final int minScore;
  final int maxScore;

  const InsightBucket({
    required this.label,
    required this.count,
    required this.avgScore,
    required this.avgPing,
    required this.minScore,
    required this.maxScore,
  });

  bool get reliable => count >= 3;
}

/// تحلیل داده‌های کیفیت.
///
/// برای هر نمونه، protocol/country رو از سرور مربوطه می‌گیره (اگه موجود
/// باشه) و آمار گروه‌بندی‌شده می‌سازه. اگه سرور پاک شده باشه، sample
/// نادیده گرفته می‌شه.
class QualityInsights {
  QualityInsights._();

  /// محاسبه‌ی insights از cache فعلی.
  ///
  /// [servers] باید لیست کامل سرورها باشه (شامل subscription).
  static QualityInsightsResult compute(
    List<VpnServer> servers, {
    Duration? window,
  }) {
    final samples = QualityHistoryService.filtered(window);
    if (samples.isEmpty || servers.isEmpty) {
      return const QualityInsightsResult.empty();
    }

    // map: serverId → VpnServer
    final byId = <String, VpnServer>{};
    for (final s in servers) {
      byId[s.id] = s;
    }

    // گروه‌ها
    final byProtocol = <String, List<QualitySample>>{};
    final byCountry = <String, List<QualitySample>>{};
    final byHour = <int, List<QualitySample>>{};

    for (final sample in samples) {
      final server = byId[sample.serverId];
      if (server == null) continue;

      // per protocol
      final proto = _protocolLabel(server.protocol);
      byProtocol.putIfAbsent(proto, () => <QualitySample>[]).add(sample);

      // per country (از flag ایموجی سرور)
      final country = _countryFromFlag(server.flag);
      if (country.isNotEmpty) {
        byCountry.putIfAbsent(country, () => <QualitySample>[]).add(sample);
      }

      // per hour (به وقت محلی)
      final local = sample.at.toLocal();
      byHour.putIfAbsent(local.hour, () => <QualitySample>[]).add(sample);
    }

    return QualityInsightsResult(
      protocolBuckets: _buildBuckets(byProtocol),
      countryBuckets: _buildBuckets(byCountry),
      hourBuckets: _buildHourBuckets(byHour),
      totalSamples: samples.length,
      serverCount: byId.length,
    );
  }

  static Map<String, List<InsightBucket>> _buildBuckets(
    Map<String, List<QualitySample>> groups,
  ) {
    final out = <String, List<InsightBucket>>{};
    for (final entry in groups.entries) {
      final bucket = _bucketFor(entry.key, entry.value);
      if (bucket != null) {
        out[entry.key] = [bucket];
      }
    }
    // مرتب‌سازی نزولی بر اساس avg score
    final sorted = out.entries.toList()
      ..sort((a, b) =>
          (b.value.first.avgScore).compareTo(a.value.first.avgScore));
    return <String, List<InsightBucket>>{
      for (final e in sorted) e.key: e.value,
    };
  }

  static Map<int, List<InsightBucket>> _buildHourBuckets(
    Map<int, List<QualitySample>> groups,
  ) {
    final out = <int, List<InsightBucket>>{};
    for (final entry in groups.entries) {
      final bucket = _bucketFor('${entry.key}:00', entry.value);
      if (bucket != null) {
        out[entry.key] = [bucket];
      }
    }
    return out;
  }

  static InsightBucket? _bucketFor(
      String label, List<QualitySample> samples) {
    if (samples.isEmpty) return null;
    var sumScore = 0;
    var sumPing = 0;
    var minScore = 100;
    var maxScore = 0;
    for (final s in samples) {
      sumScore += s.score;
      sumPing += s.pingMs;
      if (s.score < minScore) minScore = s.score;
      if (s.score > maxScore) maxScore = s.score;
    }
    return InsightBucket(
      label: label,
      count: samples.length,
      avgScore: (sumScore / samples.length).round(),
      avgPing: (sumPing / samples.length).round(),
      minScore: minScore,
      maxScore: maxScore,
    );
  }

  static String _protocolLabel(VpnProtocol p) {
    switch (p) {
      case VpnProtocol.vless:
        return 'VLESS';
      case VpnProtocol.vmess:
        return 'VMess';
      case VpnProtocol.trojan:
        return 'Trojan';
      case VpnProtocol.shadowsocks:
        return 'Shadowsocks';
      case VpnProtocol.hysteria2:
        return 'Hysteria2';
      case VpnProtocol.warpMasque:
        return 'WARP MASQUE';
      case VpnProtocol.amneziaWg:
        return 'WARP';
      case VpnProtocol.chain:
        return 'Chain';
      case VpnProtocol.socks5:
        return 'SOCKS5';
      case VpnProtocol.ssh:
        return 'SSH';
      case VpnProtocol.masterdns:
        return 'MasterDNS';
      case VpnProtocol.psiphon:
        return 'Psiphon';
      case VpnProtocol.tunnel:
        return 'Tunnel';
      case VpnProtocol.aether:
        return 'Aether';
      case VpnProtocol.xrayJson:
        return 'Xray JSON';
      case VpnProtocol.custom:
        return 'Custom';
    }
  }

  /// استخراج نام کشور از ایموجی flag.
  ///
  /// این یه جدول ساده‌ست — کامل نیست ولی برای کشورهای رایج کافیه.
  static String _countryFromFlag(String flag) {
    if (flag.isEmpty) return '';
    switch (flag) {
      case '🇮🇷':
        return 'ایران';
      case '🇩🇪':
        return 'آلمان';
      case '🇺🇸':
        return 'آمریکا';
      case '🇬🇧':
        return 'بریتانیا';
      case '🇫🇷':
        return 'فرانسه';
      case '🇳🇱':
        return 'هلند';
      case '🇸🇪':
        return 'سوئد';
      case '🇨🇭':
        return 'سوئیس';
      case '🇦🇹':
        return 'اتریش';
      case '🇫🇮':
        return 'فینلاند';
      case '🇹🇷':
        return 'ترکیه';
      case '🇷🇺':
        return 'روسیه';
      case '🇺🇦':
        return 'اوکراین';
      case '🇮🇳':
        return 'هند';
      case '🇯🇵':
        return 'ژاپن';
      case '🇸🇬':
        return 'سنگاپور';
      case '🇦🇪':
        return 'امارات';
      case '🌐':
        return '';
      default:
        return flag;
    }
  }

  /// پیشنهاد بهترین ساعت.
  static ({int hour, int avgScore})? bestHour(
      QualityInsightsResult result) {
    if (result.hourBuckets.isEmpty) return null;
    MapEntry<int, List<InsightBucket>>? best;
    for (final e in result.hourBuckets.entries) {
      if (e.value.isEmpty) continue;
      final bucket = e.value.first;
      if (!bucket.reliable) continue;
      if (best == null ||
          bucket.avgScore > best.value.first.avgScore) {
        best = e;
      }
    }
    if (best == null) return null;
    return (hour: best.key, avgScore: best.value.first.avgScore);
  }
}

class QualityInsightsResult {
  final Map<String, List<InsightBucket>> protocolBuckets;
  final Map<String, List<InsightBucket>> countryBuckets;
  final Map<int, List<InsightBucket>> hourBuckets;
  final int totalSamples;
  final int serverCount;

  const QualityInsightsResult({
    required this.protocolBuckets,
    required this.countryBuckets,
    required this.hourBuckets,
    required this.totalSamples,
    required this.serverCount,
  });

  const QualityInsightsResult.empty()
      : protocolBuckets = const {},
        countryBuckets = const {},
        hourBuckets = const {},
        totalSamples = 0,
        serverCount = 0;

  bool get isEmpty => totalSamples == 0;
}
