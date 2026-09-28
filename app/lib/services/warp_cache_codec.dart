import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'warp_endpoint_scanner.dart';
import 'warp_endpoint_tester.dart';

/// Export/import کش endpoint های WARP Scout بین دستگاه‌ها.
///
/// وقتی کاربر یه endpoint سریع پیدا می‌کنه، می‌تونه با یه URI کوتاه
/// به دوستش بده. دوستش import می‌کنه و از همون اول بدون اسکن وصل می‌شه.
///
/// فرمت:
///   hasan-warp-cache://e?f=<Fast endpoint>&s=<Slow endpoint>&o=<other>
class WarpCacheCodec {
  WarpCacheCodec._();

  static const String prefix = 'hasan-warp-cache://';
  static const String _prefLastFast = 'warp_scout_last_fast_v1';
  static const String _prefLastSlow = 'warp_scout_last_slow_v1';

  /// export کش فعلی به یه URI کوتاه.
  static Future<String?> exportCurrent() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final fast = prefs.getString(_prefLastFast) ?? '';
      final slow = prefs.getString(_prefLastSlow) ?? '';
      if (fast.isEmpty && slow.isEmpty) return null;
      final q = <String, String>{};
      if (fast.isNotEmpty) q['f'] = fast;
      if (slow.isNotEmpty) q['s'] = slow;
      return Uri(
        scheme: 'hasan-warp-cache',
        host: 'e',
        queryParameters: q,
      ).toString();
    } catch (_) {
      return null;
    }
  }

  /// import یه URI به SharedPreferences.
  static Future<int> importFrom(String link) async {
    final text = link.trim();
    if (!text.startsWith(prefix)) return 0;
    try {
      final uri = Uri.parse(text);
      final q = uri.queryParameters;
      final fast = (q['f'] ?? '').trim();
      final slow = (q['s'] ?? '').trim();
      if (fast.isEmpty && slow.isEmpty) return 0;
      final prefs = await SharedPreferences.getInstance();
      var imported = 0;
      if (fast.isNotEmpty && _isValidEndpoint(fast)) {
        await prefs.setString(_prefLastFast, fast);
        imported++;
      }
      if (slow.isNotEmpty && _isValidEndpoint(slow)) {
        await prefs.setString(_prefLastSlow, slow);
        imported++;
      }
      // memory cache هم پاک کن تا از prefs دوباره لود بشه
      await WarpEndpointTester.clearCache();
      return imported;
    } catch (_) {
      return 0;
    }
  }

  static bool _isValidEndpoint(String raw) {
    final sep = raw.lastIndexOf(':');
    if (sep <= 0) return false;
    final port = int.tryParse(raw.substring(sep + 1));
    return port != null && port >= 1 && port <= 65535;
  }

  /// آیا URI معتبر به نظر می‌رسه (فقط parse).
  static bool looksLikeCache(String raw) {
    return raw.trim().startsWith(prefix);
  }

  /// کش یه لیست از endpoint های اضافی که کاربر ممکنه ذخیره کرده باشه.
  /// برای import های bulk (مثلاً از share link گروهی).
  static Future<Map<String, int>> exportAll() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final fast = prefs.getString(_prefLastFast) ?? '';
      final slow = prefs.getString(_prefLastSlow) ?? '';
      final out = <String, int>{};
      if (fast.isNotEmpty) {
        out['Fast'] = _tryParseLatency(prefs, 'warp_scout_last_fast_ms');
      }
      if (slow.isNotEmpty) {
        out['Slow'] = _tryParseLatency(prefs, 'warp_scout_last_slow_ms');
      }
      return out;
    } catch (_) {
      return {};
    }
  }

  static int _tryParseLatency(SharedPreferences prefs, String key) {
    final raw = prefs.getInt(key);
    return raw ?? 0;
  }
}

/// ابزار کلی برای JSON serialization از hit list.
class WarpHitSerializer {
  WarpHitSerializer._();

  /// serialize یه لیست از hit به JSON (برای backup یا export).
  static String encode(List<WarpEndpointHit> hits) {
    final list = hits
        .map((h) => <String, dynamic>{
              'h': h.endpoint.host,
              'p': h.endpoint.port,
              'ms': h.latencyMs,
              'o': h.discoveryOrder,
            })
        .toList();
    return jsonEncode(list);
  }

  static List<WarpEndpointHit> decode(String raw) {
    try {
      final list = jsonDecode(raw);
      if (list is! List) return const [];
      return list
          .whereType<Map>()
          .map((m) => WarpEndpointHit(
                endpoint: WarpEndpoint(
                  m['h']?.toString() ?? '',
                  (m['p'] as num?)?.toInt() ?? 0,
                ),
                latencyMs: (m['ms'] as num?)?.toInt() ?? 0,
                discoveryOrder: (m['o'] as num?)?.toInt() ?? 0,
              ))
          .where((h) => h.endpoint.host.isNotEmpty && h.endpoint.port > 0)
          .toList();
    } catch (_) {
      return const [];
    }
  }
}
