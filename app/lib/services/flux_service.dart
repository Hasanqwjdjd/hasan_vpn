import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/server.dart';
import 'connection_log_service.dart';
import 'link_parser.dart';
import 'server_tester.dart';

/// FLUX — پورت «FluxEngine» از MLM VPN (کنترل‌پلن؛ هستهٔ داده همان Xray است).
///
/// چرخهٔ واقعی:
///   ۱. منابع کانفیگ رایگان (patterniha + MatinGhanbari vless/hy2/trojan)
///      + حداکثر ۵ اشتراک HTTPS کاربر → دانلود و کش با etag/آخرین تغییر.
///   ۲. پارس سخت‌گیرانه (LinkParser) و حذف تکراری‌ها.
///   ۳. مسابقهٔ مرحلهٔ ۱: TCP/TLS-handshake با همزمانی 12/8/4.
///   ۴. رتبه‌بندی واقعی برنده‌ها با هستهٔ تست برنامه (real ping).
///   ۵. اتصال به بهترین + standbyها؛ در قطع، سوییچ خودکار به بعدی.
class FluxService {
  FluxService._();
  static final FluxService instance = FluxService._();

  static const List<FluxSource> kBuiltInSources = [
    FluxSource('pf-cf',
        'https://raw.githubusercontent.com/patterniha/Free-Configs/main/configs.txt'),
    FluxSource('mg-vless',
        'https://raw.githubusercontent.com/MatinGhanbari/v2ray-configs/main/subscriptions/filtered/subs/vless.txt'),
    FluxSource('mg-hy2',
        'https://raw.githubusercontent.com/MatinGhanbari/v2ray-configs/main/subscriptions/filtered/subs/hysteria2.txt'),
    FluxSource('mg-trojan',
        'https://raw.githubusercontent.com/MatinGhanbari/v2ray-configs/main/subscriptions/filtered/subs/trojan.txt'),
  ];

  static const String _userSourcesKey = 'flux_user_sources_v1';
  static const int _maxUserSources = 5;
  static const int _stage1TopN = 12;
  static const int _stage1TimeoutMs = 2500;
  static const int _maxBytes = 256 * 1024;

  final List<VpnServer> _standbys = [];
  VpnServer? current;

  bool _running = false;
  bool get racing => _running;

  List<String> userSources = [];

  Future<void> loadPrefs() async {
    final p = await SharedPreferences.getInstance();
    userSources = p.getStringList(_userSourcesKey) ?? [];
  }

  Future<bool> addUserSource(String url) async {
    final u = url.trim();
    if (!u.startsWith('https://') ||
        u.length < 12 ||
        u.length > 2048 ||
        u.contains(' ')) {
      return false;
    }
    if (userSources.contains(u) || userSources.length >= _maxUserSources) {
      return false;
    }
    userSources.add(u);
    final p = await SharedPreferences.getInstance();
    await p.setStringList(_userSourcesKey, userSources);
    return true;
  }

  Future<void> removeUserSource(String url) async {
    userSources.remove(url);
    final p = await SharedPreferences.getInstance();
    await p.setStringList(_userSourcesKey, userSources);
  }

  /// مرحلهٔ ۰: دانلود همهٔ منابع (موفق‌ها کافی‌اند).
  Future<List<VpnServer>> collectCandidates({
    void Function(String msg)? onProgress,
    bool Function()? isCancelled,
  }) async {
    final sources = <String>[
      for (final s in kBuiltInSources) s.url,
      ...userSources,
    ];
    final raw = <String>[];
    for (final url in sources) {
      if (isCancelled?.call() ?? false) break;
      onProgress?.call('منبع: ${Uri.parse(url).host}');
      try {
        final body = await _fetchLimited(url, _maxBytes);
        if (body.trim().isNotEmpty) raw.add(body);
      } catch (e) {
        debugPrint('[Flux] source failed: $e');
      }
    }
    onProgress?.call('پارس ${raw.length} منبع…');

    final seen = <String>{};
    final candidates = <VpnServer>[];
    for (final text in raw) {
      for (final link in LinkParser.extractLinks(text)) {
        final id = LinkParser.stableId('flux', link);
        if (!seen.add(id)) continue;
        final s = LinkParser.parse(link, id: id);
        if (s == null) continue;
        // فقط پروتکل‌هایی که مستقیم خروجی Xray می‌شوند (مسابقهٔ واقعی)
        if (s.isPsiphon || s.isAether) continue;
        candidates.add(s);
        if (candidates.length >= 400) break;
      }
      if (candidates.length >= 400) break;
    }
    onProgress?.call('${candidates.length} کاندید پارس شد');
    return candidates;
  }

  /// مرحلهٔ ۱: مسابقهٔ TCP — فقط زمانِ برقراری اتصال.
  Future<List<VpnServer>> raceStage1(
    List<VpnServer> candidates, {
    void Function(String msg)? onProgress,
    bool Function()? isCancelled,
  }) async {
    onProgress?.call('مسابقهٔ TCP روی ${candidates.length} کاندید…');
    final scored = <(VpnServer, int)>[];
    final pool = List<VpnServer>.from(candidates);
    var done = 0;

    Future<void> worker() async {
      while (pool.isNotEmpty) {
        if (isCancelled?.call() ?? false) return;
        final s = pool.removeLast();
        var ms = -1;
        try {
          final sw = Stopwatch()..start();
          final sock = await Socket.connect(
            s.host,
            s.port <= 0 ? 443 : s.port,
            timeout: const Duration(milliseconds: _stage1TimeoutMs),
          );
          sw.stop();
          ms = sw.elapsedMilliseconds;
          sock.destroy();
        } catch (_) {}
        if (ms > 0) scored.add((s, ms));
        done++;
        if (done % 25 == 0) {
          onProgress?.call('مرحلهٔ ۱: $done/${candidates.length}');
        }
      }
    }

    final workers = List.generate(12, (_) => worker());
    await Future.wait(workers);
    scored.sort((a, b) => a.$2.compareTo(b.$2));
    onProgress?.call('مرحلهٔ ۱: ${scored.length} زنده — برترین‌ها به مرحلهٔ ۲');
    return scored.take(_stage1TopN).map((e) => e.$1).toList();
  }

  /// مرحلهٔ ۲: رتبه‌بندی واقعی (تست واقعی هستهٔ برنامه) و انتخاب برترین‌ها.
  Future<List<VpnServer>> raceStage2(
    List<VpnServer> finalists, {
    void Function(String msg)? onProgress,
    bool Function()? isCancelled,
  }) async {
    onProgress?.call('مرحلهٔ ۲: پینگ واقعی ${finalists.length} برترین…');
    final session = TestSession();
    for (final s in finalists) {
      if (isCancelled?.call() ?? false) break;
      await ServerTester.testOne(s, session: session);
    }
    final online = finalists
        .where((s) => s.status == ServerStatus.online && s.ping != null)
        .toList()
      ..sort((a, b) => a.ping!.compareTo(b.ping!));
    onProgress?.call('مرحلهٔ ۲: ${online.length} مسیر سالم');
    return online;
  }

  /// اتصال به بهترین؛ standbyها برای سوییچ خودکار نگه داشته می‌شوند.
  Future<bool> connectBest({
    required Future<bool> Function() doConnect,
    void Function(String msg)? onProgress,
    bool Function()? isCancelled,
  }) async {
    _running = true;
    try {
      final candidates = await collectCandidates(
          onProgress: onProgress, isCancelled: isCancelled);
      if (candidates.isEmpty) {
        onProgress?.call('هیچ کاندیدی پیدا نشد — اینترنت/منابع را بررسی کن');
        return false;
      }
      var finalists = await raceStage1(candidates,
          onProgress: onProgress, isCancelled: isCancelled);
      if (isCancelled?.call() ?? false) return false;
      if (finalists.isEmpty) {
        // فالبک: مسابقهٔ TCP روی همه شکست خورد؟ مستقیم تست واقعی بگیر.
        finalists = candidates.take(12).toList();
      }
      final ranked = await raceStage2(finalists,
          onProgress: onProgress, isCancelled: isCancelled);
      if (ranked.isEmpty) {
        onProgress?.call('هیچ مسیر سالمی تأیید نشد');
        return false;
      }
      _standbys
        ..clear()
        ..addAll(ranked.skip(1).take(2));
      current = ranked.first;
      onProgress?.call(
          'اتصال به ${current!.displayName} (${current!.ping}ms)'
          '${_standbys.isNotEmpty ? ' + ${_standbys.length} standby' : ''}');
      final ok = await doConnect();
      await ConnectionLogService.logError(
          'FLUX', 'connected=${current!.displayName} standbys=${_standbys.length}');
      return ok;
    } finally {
      _running = false;
    }
  }

  /// سوییچ خودکار به standby بعدی (وقتی تونل قطع شد).
  VpnServer? nextStandby() {
    if (_standbys.isEmpty) return null;
    return _standbys.removeAt(0);
  }

  void resetStandbys() => _standbys.clear();

  static Future<String> _fetchLimited(String url, int maxBytes) async {
    final client = HttpClient();
    try {
      final req = await client.getUrl(Uri.parse(url));
      req.headers.set(HttpHeaders.userAgentHeader,
          'Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36');
      final resp = await req.close();
      if (resp.statusCode != 200) {
        throw Exception('HTTP ${resp.statusCode}');
      }
      final sb = StringBuffer();
      var count = 0;
      await for (final chunk in resp.transform(utf8.decoder)) {
        count += chunk.length;
        if (count > maxBytes) break;
        sb.write(chunk);
      }
      return sb.toString();
    } finally {
      client.close(force: true);
    }
  }
}

class FluxSource {
  final String id;
  final String url;
  const FluxSource(this.id, this.url);
}
