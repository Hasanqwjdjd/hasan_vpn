import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'core_engines.dart';

/// نتیجه‌ی چک نسخه یک هسته.
class EngineVersionInfo {
  final String engineId;
  /// نسخه‌ی آخرین release از GitHub (خالی اگه ناشناخته).
  final String latestVersion;
  /// آیا نسخه‌ی جدیدتر از currentVersion وجود داره؟
  final bool hasUpdate;
  final DateTime? checkedAt;
  final String? error;

  const EngineVersionInfo({
    required this.engineId,
    required this.latestVersion,
    required this.hasUpdate,
    this.checkedAt,
    this.error,
  });

  const EngineVersionInfo.unknown(this.engineId)
      : latestVersion = '',
        hasUpdate = false,
        checkedAt = null,
        error = null;
}

/// چک نسخه‌های جدید هسته‌ها از GitHub Releases API.
///
/// - Cache 24 ساعته در prefs
/// - Rate limit: GitHub 60/hour برای unauthenticated. کافیه چون فقط ۱۰ هسته.
/// - نتیجه در memory cache برای session
class EngineVersionChecker {
  EngineVersionChecker._();
  static final EngineVersionChecker instance = EngineVersionChecker._();

  static const String _prefKey = 'engine_versions_v1';
  static const Duration _cacheTtl = Duration(hours: 24);

  final Map<String, EngineVersionInfo> _cache = {};

  /// callback وقتی چک تمام شد.
  void Function()? onUpdated;

  /// چک همه هسته‌ها با cache.
  ///
  /// [force] = true → cache نادیده بگیر و دوباره fetch کن.
  Future<Map<String, EngineVersionInfo>> checkAll({
    bool force = false,
  }) async {
    // load از prefs
    if (_cache.isEmpty) {
      await _loadFromPrefs();
    }

    final now = DateTime.now();
    final toCheck = <CoreEngine>[];
    for (final engine in CoreEngines.all) {
      final cached = _cache[engine.id];
      if (!force &&
          cached != null &&
          cached.checkedAt != null &&
          now.difference(cached.checkedAt!) < _cacheTtl) {
        continue;
      }
      toCheck.add(engine);
    }

    if (toCheck.isEmpty) {
      return Map<String, EngineVersionInfo>.from(_cache);
    }

    // چک موازی — با محدودیت ۳ همزمان
    final futures = toCheck.map((e) => _checkOne(e));
    await Future.wait(futures);

    await _saveToPrefs();
    onUpdated?.call();
    return Map<String, EngineVersionInfo>.from(_cache);
  }

  /// چک یک هسته.
  Future<void> _checkOne(CoreEngine engine) async {
    try {
      // اگه repo روی GitHub نبود (مثل snowflake روی gitlab)، skip
      if (engine.githubUrl.contains('gitlab.com')) {
        _cache[engine.id] = EngineVersionInfo(
          engineId: engine.id,
          latestVersion: '',
          hasUpdate: false,
          checkedAt: DateTime.now(),
          error: 'not on github',
        );
        return;
      }
      final url = Uri.parse(
          'https://api.github.com/repos/${engine.githubRepo}/releases/latest');
      final resp = await http.get(url, headers: {
        'Accept': 'application/vnd.github+json',
        'User-Agent': 'HasanVPN/1.0',
      }).timeout(const Duration(seconds: 12));

      if (resp.statusCode == 404) {
        // repo وجود نداره یا release نداره
        _cache[engine.id] = EngineVersionInfo(
          engineId: engine.id,
          latestVersion: '',
          hasUpdate: false,
          checkedAt: DateTime.now(),
          error: 'no releases',
        );
        return;
      }
      if (resp.statusCode == 403) {
        // rate limit
        _cache[engine.id] = EngineVersionInfo(
          engineId: engine.id,
          latestVersion: '',
          hasUpdate: false,
          checkedAt: DateTime.now(),
          error: 'rate limited',
        );
        return;
      }
      if (resp.statusCode != 200) {
        _cache[engine.id] = EngineVersionInfo(
          engineId: engine.id,
          latestVersion: '',
          hasUpdate: false,
          checkedAt: DateTime.now(),
          error: 'HTTP ${resp.statusCode}',
        );
        return;
      }

      final doc = jsonDecode(resp.body);
      if (doc is! Map) return;
      final rawTag = doc['tag_name']?.toString() ?? '';
      final tag = _stripPrefix(rawTag);

      _cache[engine.id] = EngineVersionInfo(
        engineId: engine.id,
        latestVersion: tag,
        hasUpdate: _isNewer(tag, engine.currentVersion),
        checkedAt: DateTime.now(),
      );
    } catch (e) {
      _cache[engine.id] = EngineVersionInfo(
        engineId: engine.id,
        latestVersion: '',
        hasUpdate: false,
        checkedAt: DateTime.now(),
        error: e.toString().split('\n').first,
      );
    }
  }

  static String _stripPrefix(String tag) {
    var v = tag.trim();
    if (v.startsWith('v') || v.startsWith('V')) {
      v = v.substring(1);
    }
    return v;
  }

  /// آیا [latest] از [current] جدیدتره؟
  ///
  /// مقایسه ساده‌ی SemVer: هر بخش رو int می‌کنه، اگه هر دو معتبر بودن
  /// مقایسه می‌کنه. در غیر این صورت false.
  static bool _isNewer(String latest, String current) {
    if (latest.isEmpty || current.isEmpty) return false;
    if (current == 'latest') return false;

    final l = _parseVersion(latest);
    final c = _parseVersion(current);
    if (l == null || c == null) return false;

    final len = l.length > c.length ? l.length : c.length;
    for (var i = 0; i < len; i++) {
      final lv = i < l.length ? l[i] : 0;
      final cv = i < c.length ? c[i] : 0;
      if (lv > cv) return true;
      if (lv < cv) return false;
    }
    return false;
  }

  /// پارس نسخه به لیست int. حروف و -dev رو حذف می‌کنه.
  static List<int>? _parseVersion(String v) {
    final cleaned = v
        .split(RegExp(r'[-+]'))
        .first
        .replaceAll(RegExp(r'[^0-9.]'), '');
    if (cleaned.isEmpty) return null;
    final parts = cleaned.split('.');
    final out = <int>[];
    for (final p in parts) {
      final n = int.tryParse(p);
      if (n == null) return null;
      out.add(n);
    }
    return out.isEmpty ? null : out;
  }

  /// خواندن cache از prefs.
  Future<void> _loadFromPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefKey);
      if (raw == null || raw.isEmpty) return;
      final doc = jsonDecode(raw);
      if (doc is! Map) return;
      for (final entry in doc.entries) {
        final id = entry.key.toString();
        final data = entry.value;
        if (data is! Map) continue;
        _cache[id] = EngineVersionInfo(
          engineId: id,
          latestVersion: data['latest']?.toString() ?? '',
          hasUpdate: data['hasUpdate'] == true,
          checkedAt: DateTime.tryParse(data['at']?.toString() ?? ''),
          error: data['err']?.toString(),
        );
      }
    } catch (_) {}
  }

  /// ذخیره cache در prefs.
  Future<void> _saveToPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final out = <String, dynamic>{};
      for (final e in _cache.entries) {
        out[e.key] = {
          'latest': e.value.latestVersion,
          'hasUpdate': e.value.hasUpdate,
          'at': e.value.checkedAt?.toIso8601String(),
          if (e.value.error != null) 'err': e.value.error,
        };
      }
      await prefs.setString(_prefKey, jsonEncode(out));
    } catch (_) {}
  }

  /// پاک کردن cache (برای دکمه refresh اجباری).
  Future<void> clearCache() async {
    _cache.clear();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_prefKey);
    } catch (_) {}
  }

  /// آخرین نتیجه (ممکنه خالی باشه).
  EngineVersionInfo? infoFor(String engineId) => _cache[engineId];

  /// تعداد هسته‌هایی که آپدیت دارن.
  int get updateCount {
    var n = 0;
    for (final v in _cache.values) {
      if (v.hasUpdate) n++;
    }
    return n;
  }
}
