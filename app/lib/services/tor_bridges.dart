import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// پل‌های پیشنهادی برای هر نوع مخفی‌سازی — mobile-first.
/// موبایل ایران سخت‌تر از WiFi است ولی با webtunnel / snowflake / meek
/// هنوز قابل تلاش است. پل‌های obfs4 ثابت ممکن است روی Irancell/MCI
/// بسته باشند؛ باز هم امتحان می‌شوند ولی اولویت آخرند.
class TorBridges {
  TorBridges._();

  /// ترتیب ترجیح برای شبکهٔ موبایل ایران.
  static const List<String> mobilePreferredTypes = <String>[
    'webtunnel',
    'snowflake',
    'meek_lite',
    'obfs4',
  ];

  /// WebTunnel — شبیه HTTPS، بهترین کاندید برای 4G.
  /// کاربر باید URL واقعی از bridges.torproject.org / @GetBridgesBot بگیرد.
  /// خطوط نمونه فقط ساختار را نشان می‌دهند؛ اگر خالی باشد UI از کاربر می‌خواهد.
  static const List<String> webtunnel = <String>[
    // placeholderهای ساختاری — با پل واقعی جایگزین شوند
    // 'webtunnel 192.0.2.3:443 url=https://example.cdn/path ver=0x01',
  ];

  /// Snowflake — P2P، سخت برای فیلتر کامل.
  static const List<String> snowflake = <String>[
    'snowflake 192.0.2.3:1 2B280B23E1107BB62ABFC40DDCC8824814F80A72',
    'snowflake 192.0.2.4:1 8838024498816A039FCBBAB14E6F40A0843051FA',
    'snowflake 192.0.2.5:1 2B280B23E1107BB62ABFC40DDCC8824814F80A72 url=https://snowflake-broker.torproject.net/ fronts=cdn.sstatic.net,ajax.aspnetcdn.com ice=stun:stun.l.google.com:19302,stun:stun.antisip.com:3478',
  ];

  /// meek با جبهه Azure / CDNهای رایج (domain fronting).
  static List<String> meekLiteFor(String host) => <String>[
        'meek_lite 192.0.2.2:443 url=https://$host/ front=$host',
      ];

  static const List<String> meekFronts = <String>[
    'ajax.aspnetcdn.com',
    'ajax.microsoft.com',
    'az766322.vo.msecnd.net',
    'cdn.ampproject.org',
    'play.googleapis.com',
    'www.google.com',
    'www.msftconnecttest.com',
    'azure.microsoft.com',
    'drive.google.com',
    'api.github.com',
  ];

  /// obfs4 — هنوز امتحان می‌شود؛ بعضی روی موبایل بسته است (مثلاً 45.145.95.6).
  static const List<String> obfs4 = <String>[
    'obfs4 85.31.186.98:443 011F2599C0E9B27EE74B353155E244813763C3E5 cert=ayq0XzCwhpdysn5o0EyDUbmSOx3X/oTEbzDMvczHOdBJKlvIdHHLJGkZARtT4dcBFArPPg iat-mode=0',
    'obfs4 85.31.186.26:443 91A6354697E6B02A386312F68D82CF86824D3606 cert=PBwr+S8JTVoY5s2ZoU4crfN3+7iRHvBkthvS7X6nJDMqLmRU+aGWDsBqsjt8tgALri8DA iat-mode=0',
    'obfs4 193.11.166.194:27015 2D82C2E354D531A68469ADF7F878FA6060C6BEB4 cert=4TLQPJrTSaDffMK7Nbao6LC7G9OW/NHkUwIdjLSS3KYf0Nv4/nQiiI8dY2TcsQx01NniOg iat-mode=0',
    'obfs4 193.11.166.194:27020 86AC7B8D43B3F0A5B7EC1B0D3D22AC2ABDC1BF76 cert=hn+QhFuKUvNJKZQZoqk0pWXBjNq9NbqmxTBna0e+7OxsSJqhvz0j7BF9+YyRzTXj9wW4Ig iat-mode=0',
  ];

  static const List<String> conjure = <String>[];

  /// DNSTT بدون pubkey معتبر کار نمی‌کند — خالی نگه داشته می‌شود تا کاربر
  /// بتواند پل سفارشی با فرمت `dnstt <pubkey-hex> <domain> [resolver=..]`
  /// اضافه کند.
  static const List<String> dnstt = <String>[];

  // ── داینامیک: fetch از moat API torproject.org + کش ────
  static const String _moatUrl =
      'https://bridges.torproject.org/moat/circumvention/request';
  static const String _moatVersion = '0.1.0';
  static const String _cacheKey = 'tor_bridges_dynamic_v1';
  static const Duration _cacheTtl = Duration(hours: 12);

  /// cache در memory تا برایType سریع جواب بده.
  static final Map<String, List<String>> _memoryCache = {};

  /// آخرین زمان موفق fetch به‌ازای هر نوع.
  static final Map<String, DateTime> _memoryStamp = {};

  /// خواندن از SharedPreferences در اولین استفاده.
  static bool _loadedFromDisk = false;

  static Future<void> _ensureLoaded() async {
    if (_loadedFromDisk) return;
    _loadedFromDisk = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_cacheKey);
      if (raw == null || raw.isEmpty) return;
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return;
      final stamp = DateTime.tryParse(decoded['stamp']?.toString() ?? '');
      if (stamp == null || DateTime.now().difference(stamp) > _cacheTtl) return;
      final bridges = decoded['bridges'];
      if (bridges is! Map) return;
      for (final entry in bridges.entries) {
        final key = entry.key.toString();
        final value = entry.value;
        if (value is List) {
          _memoryCache[key] = value.map((e) => e.toString()).toList();
          _memoryStamp[key] = stamp;
        }
      }
    } catch (e) {
      debugPrint('tor_bridges: load cache failed: $e');
    }
  }

  static Future<void> _persistCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final stamp = DateTime.now();
      final body = <String, dynamic>{
        'stamp': stamp.toIso8601String(),
        'bridges': _memoryCache,
      };
      await prefs.setString(_cacheKey, jsonEncode(body));
    } catch (e) {
      debugPrint('tor_bridges: persist cache failed: $e');
    }
  }

  /// fetch پل‌های تازه از moat API Tor Project.
  ///
  /// ورودی: نوع پل ('obfs4', 'snowflake', 'meek_lite', 'conjure')
  /// خروجی: لیست bridge strings یا null در صورت شکست.
  static Future<List<String>?> fetchDynamic(
    String bridgeType, {
    String country = 'ir',
    Duration timeout = const Duration(seconds: 15),
  }) async {
    // type های پشتیبانی‌شده توسط moat API
    const supported = {'obfs4', 'snowflake', 'meek_lite', 'conjure', 'webtunnel'};
    if (!supported.contains(bridgeType)) return null;

    await _ensureLoaded();

    try {
      final body = jsonEncode(<String, dynamic>{
        'country': country.toLowerCase(),
        'transports': [bridgeType],
        'type': 'moat',
        'version': _moatVersion,
      });
      final resp = await http
          .post(
            Uri.parse(_moatUrl),
            headers: <String, String>{
              'Content-Type': 'application/json',
              'Accept': 'application/json',
            },
            body: body,
          )
          .timeout(timeout);

      if (resp.statusCode != 200) {
        debugPrint(
            'tor_bridges: fetch $bridgeType failed HTTP ${resp.statusCode}');
        return null;
      }

      final decoded = jsonDecode(resp.body);
      if (decoded is! Map) return null;
      final settings = decoded['settings'];
      if (settings is! Map) return null;
      final bridges = settings['bridges'];
      if (bridges is! Map) return null;

      // bridges.bridge_strings یا bridges.bridges
      final strings = bridges['bridge_strings'] ?? bridges['bridges'];
      if (strings is! List || strings.isEmpty) return null;

      final list = strings
          .map((e) => e.toString().trim())
          .where((e) => e.isNotEmpty)
          .toList();
      if (list.isEmpty) return null;

      _memoryCache[bridgeType] = list;
      _memoryStamp[bridgeType] = DateTime.now();
      // ignore: unawaited_futures
      _persistCache();
      debugPrint('tor_bridges: fetched ${list.length} $bridgeType bridges');
      return list;
    } catch (e) {
      debugPrint('tor_bridges: fetch $bridgeType error: $e');
      return null;
    }
  }

  /// fetch چند نوع با هم.
  static Future<Map<String, List<String>>> fetchMany(
    Iterable<String> types, {
    String country = 'ir',
  }) async {
    final out = <String, List<String>>{};
    for (final t in types) {
      final r = await fetchDynamic(t, country: country);
      if (r != null && r.isNotEmpty) out[t] = r;
    }
    return out;
  }

  /// پاک کردن کش (برای دکمه Refresh).
  static Future<void> clearCache() async {
    _memoryCache.clear();
    _memoryStamp.clear();
    _loadedFromDisk = false;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_cacheKey);
    } catch (_) {}
  }

  /// آخرین زمان موفق fetch برای این نوع (null = کش نداریم).
  static DateTime? lastFetch(String bridgeType) => _memoryStamp[bridgeType];

  /// آیا کش تازه داریم؟
  static bool hasFreshCache(String bridgeType) {
    final s = _memoryStamp[bridgeType];
    if (s == null) return false;
    return DateTime.now().difference(s) <= _cacheTtl;
  }

  /// نسخه sync — اول dynamic cache در memory، بعد fallback به static.
  /// اگه هنوز fetch نکردی، این تابع static برمی‌گردونه؛ بعد از
  /// `await fetchDynamic(...)` نسخه تازه رو می‌بینی.
  static List<String> forType(String bridgeType, {String? sni}) {
    final cached = _memoryCache[bridgeType];
    if (cached != null && cached.isNotEmpty) {
      return List<String>.from(cached);
    }
    return _staticForType(bridgeType, sni: sni);
  }

  /// نسخه async — اگه کش تازه داری همون، وگرنه fetch می‌کنه.
  static Future<List<String>> forTypeAsync(
    String bridgeType, {
    String? sni,
    String country = 'ir',
    bool forceRefresh = false,
  }) async {
    await _ensureLoaded();
    if (!forceRefresh && hasFreshCache(bridgeType)) {
      return List<String>.from(_memoryCache[bridgeType]!);
    }
    final fresh = await fetchDynamic(bridgeType, country: country);
    if (fresh != null && fresh.isNotEmpty) return fresh;
    return _staticForType(bridgeType, sni: sni);
  }

  static List<String> _staticForType(String bridgeType, {String? sni}) {
    switch (bridgeType) {
      case 'webtunnel':
        return List<String>.from(webtunnel);
      case 'snowflake':
        return List<String>.from(snowflake);
      case 'meek_lite':
        if (sni != null && sni.isNotEmpty) {
          return meekLiteFor(sni);
        }
        return meekFronts
            .map((h) => 'meek_lite 192.0.2.2:443 url=https://$h/ front=$h')
            .toList();
      case 'obfs4':
        return List<String>.from(obfs4);
      case 'conjure':
        return List<String>.from(conjure);
      case 'dnstt':
        return List<String>.from(dnstt);
      default:
        return <String>[];
    }
  }

  /// آیا برای این نوع پل، «پل‌های رایگان» داریم که در UI نمایش داده بشن؟
  /// طبق درخواست کاربر:
  ///   - vanilla (ساده) و webtunnel → نیازی به نمایش ندارن
  ///   - obfs4 / snowflake / meek_lite / conjure → باید نمایش داده بشن
  ///   - dnstt → فقط با پل سفارشی (pubkey لازمه)
  static bool hasFree(String bridgeType) {
    switch (bridgeType) {
      case 'vanilla':
      case 'webtunnel':
      case 'dnstt':
        return false;
      case 'obfs4':
      case 'snowflake':
      case 'meek_lite':
      case 'conjure':
        return true;
      default:
        return false;
    }
  }

  static String shortLabel(String bridgeLine) {
    final parts = bridgeLine.trim().split(RegExp(r'\s+'));
    if (parts.length >= 2) {
      return '${parts[0]} · ${parts[1]}';
    }
    if (parts.isNotEmpty) return parts[0];
    return bridgeLine;
  }

  static ({String host, int port})? parseEndpoint(String bridgeLine) {
    final line = bridgeLine.trim();
    if (line.isEmpty) return null;

    final frontMatch =
        RegExp(r'fronts?=([^\s]+)', caseSensitive: false).firstMatch(line);
    if (frontMatch != null) {
      final host = frontMatch.group(1)!.split(',').first.trim();
      if (host.isNotEmpty && !host.startsWith('192.0.2.')) {
        return (host: host, port: 443);
      }
    }

    final urlMatch =
        RegExp(r'url=https?://([^/\s:]+)', caseSensitive: false).firstMatch(line);
    if (urlMatch != null) {
      return (host: urlMatch.group(1)!, port: 443);
    }

    final parts = line.split(RegExp(r'\s+'));
    if (parts.length < 2) return null;
    final hp = parts[1];
    final colon = hp.lastIndexOf(':');
    if (colon <= 0) return null;
    final host = hp.substring(0, colon);
    final port = int.tryParse(hp.substring(colon + 1));
    if (port == null) return null;
    if (host.startsWith('192.0.2.')) return null;
    return (host: host, port: port);
  }

  /// استخر اضافی برای دکمه «پل‌های رایگان جدید».
  static List<String> extraPool(String bridgeType) {
    switch (bridgeType) {
      case 'obfs4':
        return const [
          'obfs4 38.229.33.83:80 0CAD576E561AEE617D2137E67723A123A23A123B cert=iCsa3l3BbZv+2u9bvcpTNUVG4Esge/XabRocHl86p23Z/aMsM0Vuom9g4bbz2PlY9/oNzQ iat-mode=0',
          'obfs4 37.218.245.14:38224 D9A82D2F9C2F65A18407B1D2B764F130847F8B5D cert=bjRaMvr/wWjJwG+SN5pRaqFHycJksMui9n7hMKqNpX0ZQfRyb9a5EwQ5N2N4YdX6bY0+1Q iat-mode=0',
        ];
      case 'meek_lite':
        return meekFronts
            .skip(3)
            .map((h) =>
                'meek_lite 192.0.2.2:443 url=https://$h/ front=$h')
            .toList();
      case 'snowflake':
        return const [
          'snowflake 192.0.2.6:1 2B280B23E1107BB62ABFC40DDCC8824814F80A72 url=https://snowflake-broker.torproject.net/ fronts=ajax.aspnetcdn.com ice=stun:stun.l.google.com:19302',
          'snowflake 192.0.2.7:1 2B280B23E1107BB62ABFC40DDCC8824814F80A72 url=https://snowflake-broker.torproject.net/ fronts=www.google.com ice=stun:stun.voipgate.com:3478',
        ];
      case 'conjure':
        return const [
          'conjure 192.0.2.5:80 url=https://registration.refraction.network/api',
        ];
      default:
        return const [];
    }
  }
}
