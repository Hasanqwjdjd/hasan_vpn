import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'connection_quality.dart';

/// یک نمونه ثبت‌شده — با timestamp.
class QualitySample {
  final DateTime at;
  final int score;
  final int pingMs;
  final int jitterMs;
  final double lossPct;
  /// شناسه سروری که این نمونه ازش اومده (خالی = global/قدیمی).
  final String serverId;

  const QualitySample({
    required this.at,
    required this.score,
    required this.pingMs,
    required this.jitterMs,
    required this.lossPct,
    this.serverId = '',
  });

  Map<String, dynamic> toJson() => {
        'at': at.toIso8601String(),
        's': score,
        'p': pingMs,
        'j': jitterMs,
        'l': lossPct,
        if (serverId.isNotEmpty) 'sid': serverId,
      };

  factory QualitySample.fromJson(Map<String, dynamic> j) => QualitySample(
        at: DateTime.tryParse(j['at']?.toString() ?? '') ?? DateTime.now(),
        score: (j['s'] as num?)?.toInt() ?? 0,
        pingMs: (j['p'] as num?)?.toInt() ?? 0,
        jitterMs: (j['j'] as num?)?.toInt() ?? 0,
        lossPct: (j['l'] as num?)?.toDouble() ?? 0.0,
        serverId: j['sid']?.toString() ?? '',
      );
}

/// تاریخچه کیفیت — حداکثر ۱۰۰۰ نمونه (تقریباً یک هفته).
class QualityHistoryService {
  QualityHistoryService._();
  static const String _key = 'quality_history_v1';
  static const int _maxSamples = 1000;

  /// آخرین لیست لود‌شده — برای دسترسی sync.
  static List<QualitySample> _cache = const [];
  static List<QualitySample> get cached => _cache;

  /// افزودن یک نمونه.
  static Future<void> add(QualitySample s) async {
    try {
      final list = await load();
      list.add(s);
      // حذف قدیمی‌ها اگه بیش از حد شد
      if (list.length > _maxSamples) {
        list.removeRange(0, list.length - _maxSamples);
      }
      await _persist(list);
    } catch (_) {}
  }

  static Future<List<QualitySample>> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key);
      if (raw == null || raw.isEmpty) {
        _cache = const [];
        return [];
      }
      final list = jsonDecode(raw);
      if (list is! List) return [];
      final out = list
          .whereType<Map>()
          .map((m) => QualitySample.fromJson(Map<String, dynamic>.from(m)))
          .toList();
      _cache = out;
      return out;
    } catch (_) {
      return [];
    }
  }

  static Future<void> _persist(List<QualitySample> list) async {
    _cache = list;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _key,
        jsonEncode(list.map((e) => e.toJson()).toList()),
      );
    } catch (_) {}
  }

  static Future<void> clear() async {
    _cache = const [];
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_key);
    } catch (_) {}
  }

  /// نمونه‌ها در بازه مشخص — ۲۴h / ۷d / همه.
  static List<QualitySample> filtered(Duration? window) {
    if (window == null) return _cache;
    final cutoff = DateTime.now().subtract(window);
    return _cache.where((s) => s.at.isAfter(cutoff)).toList();
  }

  /// نمونه‌ها برای یه سرور مشخص.
  static List<QualitySample> forServer(String serverId, {Duration? window}) {
    if (serverId.isEmpty) return const [];
    var out = _cache.where((s) => s.serverId == serverId).toList();
    if (window != null) {
      final cutoff = DateTime.now().subtract(window);
      out = out.where((s) => s.at.isAfter(cutoff)).toList();
    }
    return out;
  }

  /// لیست شناسه‌های سرور که نمونه دارن + تعداد نمونه.
  static Map<String, int> get serverIdsWithCounts {
    final out = <String, int>{};
    for (final s in _cache) {
      if (s.serverId.isEmpty) continue;
      out[s.serverId] = (out[s.serverId] ?? 0) + 1;
    }
    return out;
  }

  /// آمار خلاصه.
  static QualityStats stats(List<QualitySample> samples) {
    if (samples.isEmpty) {
      return const QualityStats(
        count: 0,
        avgScore: 0,
        minScore: 0,
        maxScore: 0,
        avgPing: 0,
        avgJitter: 0,
      );
    }
    var sumScore = 0;
    var sumPing = 0;
    var sumJitter = 0;
    var minScore = 100;
    var maxScore = 0;
    for (final s in samples) {
      sumScore += s.score;
      sumPing += s.pingMs;
      sumJitter += s.jitterMs;
      if (s.score < minScore) minScore = s.score;
      if (s.score > maxScore) maxScore = s.score;
    }
    return QualityStats(
      count: samples.length,
      avgScore: (sumScore / samples.length).round(),
      minScore: minScore,
      maxScore: maxScore,
      avgPing: (sumPing / samples.length).round(),
      avgJitter: (sumJitter / samples.length).round(),
    );
  }

  /// Export به JSON string برای بکاپ.
  static Future<String> export() async {
    final samples = await load();
    final doc = <String, dynamic>{
      '_version': 1,
      '_exportedAt': DateTime.now().toIso8601String(),
      'samples': samples.map((s) => s.toJson()).toList(),
    };
    return jsonEncode(doc);
  }

  /// Import از JSON string.
  static Future<int> import(String raw) async {
    try {
      final doc = jsonDecode(raw);
      if (doc is! Map) return 0;
      final samples = doc['samples'];
      if (samples is! List) return 0;
      final imported = samples
          .whereType<Map>()
          .map((m) => QualitySample.fromJson(Map<String, dynamic>.from(m)))
          .toList();
      if (imported.isEmpty) return 0;
      // merge — بدون duplicate (توسط timestamp + score)
      final existing = await load();
      final seen = existing
          .map((s) => '${s.at.millisecondsSinceEpoch}_${s.score}')
          .toSet();
      var added = 0;
      for (final s in imported) {
        final k = '${s.at.millisecondsSinceEpoch}_${s.score}';
        if (seen.add(k)) {
          existing.add(s);
          added++;
        }
      }
      existing.sort((a, b) => a.at.compareTo(b.at));
      if (existing.length > _maxSamples) {
        existing.removeRange(0, existing.length - _maxSamples);
      }
      await _persist(existing);
      return added;
    } catch (_) {
      return 0;
    }
  }
}

class QualityStats {
  final int count;
  final int avgScore;
  final int minScore;
  final int maxScore;
  final int avgPing;
  final int avgJitter;

  const QualityStats({
    required this.count,
    required this.avgScore,
    required this.minScore,
    required this.maxScore,
    required this.avgPing,
    required this.avgJitter,
  });
}
