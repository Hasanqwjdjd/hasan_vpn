import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/server.dart';
import '../models/subscription.dart';
import 'link_parser.dart';
import 'protected_defaults.dart';
import 'xray_json.dart';

/// Structured error so UI can show HTTP code + reason clearly.
class SubscriptionFetchException implements Exception {
  final String message;
  final int? statusCode;
  final String kind; // 'http', 'timeout', 'dns', 'network', 'format', 'empty'

  SubscriptionFetchException(this.message, {this.statusCode, this.kind = 'network'});

  @override
  String toString() {
    if (statusCode != null) return 'HTTP $statusCode · $message';
    return message;
  }
}

class SubscriptionService {
  static const String _key = 'subscriptions_v3';
  static const String _removedDefaultsKey = 'subscriptions_removed_defaults_v1';

  /// Browser-like UA — some providers block non-browser clients.
  static const String _userAgent =
      'Mozilla/5.0 (Linux; Android 13; Pixel 7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36';

  /// اشتراک‌های پیش‌فرض. لینک‌ها اینجا نیستند: از جدول رمزشدهٔ
  /// [ProtectedDefaults] (ساخته‌شده در CI) فقط لحظهٔ دانلود خوانده می‌شوند.
  static List<Subscription> get defaultSubscriptions => [
        for (final e in ProtectedDefaults.entries)
          Subscription(id: e[0], name: e[1], url: '', isDefault: true),
      ];

  /// آدرس واقعی برای دانلود. برای اشتراک پیش‌فرض از جدول محافظت‌شده می‌آید.
  static String urlFor(Subscription sub) {
    if (sub.isDefault) {
      final u = ProtectedDefaults.urlFor(sub.id);
      if (u != null && u.isNotEmpty) return u;
    }
    return sub.url;
  }

  // ------------------------------------------------------------ persistence

  static Future<Set<String>> _loadRemovedDefaults(SharedPreferences prefs) async {
    try {
      final raw = prefs.getString(_removedDefaultsKey);
      if (raw == null) return <String>{};
      final decoded = jsonDecode(raw);
      if (decoded is List) return decoded.map((e) => e.toString()).toSet();
    } catch (_) {}
    return <String>{};
  }

  /// اشتراک پیش‌فرضی که کاربر حذف کرده نباید در اجرای بعدی برگردد.
  static Future<void> markRemoved(Subscription subscription) async {
    if (!subscription.isDefault) return;
    final prefs = await SharedPreferences.getInstance();
    final removed = await _loadRemovedDefaults(prefs);
    removed.add(subscription.id);
    await prefs.setString(_removedDefaultsKey, jsonEncode(removed.toList()));
  }

  static Future<List<Subscription>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);

    if (raw == null) {
      final defaults = List<Subscription>.from(defaultSubscriptions);
      await save(defaults);
      return defaults;
    }

    try {
      final decoded = jsonDecode(raw);

      if (decoded is! List) {
        throw const FormatException('Invalid subscription list');
      }

      final subscriptions = decoded
          .whereType<Map>()
          .map((item) => Subscription.fromJson(Map<String, dynamic>.from(item)))
          .toList();

      final removed = await _loadRemovedDefaults(prefs);
      for (final defaultSub in defaultSubscriptions) {
        if (removed.contains(defaultSub.id)) continue;
        if (!subscriptions.any((s) => s.id == defaultSub.id)) {
          subscriptions.add(defaultSub);
        }
      }

      await save(subscriptions);
      return subscriptions;
    } catch (_) {
      final defaults = List<Subscription>.from(defaultSubscriptions);
      await save(defaults);
      return defaults;
    }
  }

  static Future<void> save(List<Subscription> subscriptions) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _key,
      jsonEncode(subscriptions.map((s) {
        final json = s.toJson();
        // لینک اشتراک پیش‌فرض هرگز روی دستگاه ذخیره نمی‌شود.
        if (s.isDefault && ProtectedDefaults.has(s.id)) json['url'] = '';
        return json;
      }).toList()),
    );
  }

  // ---------------------------------------------------------------- network

  /// Fetch servers. On 404 / network failure keeps previous cachedLinks
  /// (does not wipe). Throws [SubscriptionFetchException] with clear message.
  static Future<List<VpnServer>> fetch(Subscription subscription) async {
    final url = urlFor(subscription);
    if (url.isEmpty) {
      throw SubscriptionFetchException(
        'URL is empty or decrypt failed',
        kind: 'format',
      );
    }

    final http.Response response;
    try {
      response = await http
          .get(
            Uri.parse(url),
            headers: const {
              'User-Agent': _userAgent,
              'Accept': '*/*',
              'Accept-Language': 'en-US,en;q=0.9',
              'Cache-Control': 'no-cache',
            },
          )
          .timeout(const Duration(seconds: 25));
    } on TimeoutException {
      throw SubscriptionFetchException(
        'Request timed out (25s)',
        kind: 'timeout',
      );
    } on SocketException catch (e) {
      final msg = e.message.toLowerCase();
      if (msg.contains('failed host lookup') ||
          msg.contains('name or service not known') ||
          msg.contains('nodename nor servname')) {
        throw SubscriptionFetchException(
          'DNS failure · cannot resolve host',
          kind: 'dns',
        );
      }
      throw SubscriptionFetchException(
        'Network error · ${e.message}',
        kind: 'network',
      );
    } catch (e) {
      if (subscription.isDefault) {
        throw SubscriptionFetchException('network error', kind: 'network');
      }
      throw SubscriptionFetchException(e.toString(), kind: 'network');
    }

    if (response.statusCode == 404) {
      // Keep old cached servers — do not wipe.
      throw SubscriptionFetchException(
        'Not Found (subscription URL may have changed)',
        statusCode: 404,
        kind: 'http',
      );
    }
    if (response.statusCode != 200) {
      throw SubscriptionFetchException(
        'Unexpected status',
        statusCode: response.statusCode,
        kind: 'http',
      );
    }

    // بدنه را خودمان UTF-8 رمزگشایی می‌کنیم؛ response.body بدون charset در هدر
    // به latin1 می‌رود و نام‌های فارسی/ایموجی خراب می‌شوند.
    var content = utf8.decode(response.bodyBytes, allowMalformed: true).trim();
    content = _maybeDecodeBase64(content);

    final servers = parseContent(content, subscription.id);
    if (servers.isEmpty) {
      // پاسخ خراب یا خالی نباید کش قبلی را پاک کند.
      throw SubscriptionFetchException(
        'No servers found in response (invalid or empty body)',
        kind: 'empty',
      );
    }

    subscription.cachedLinks = servers.map((s) => s.shareLink).toList();
    return servers;
  }

  static List<VpnServer> fromCache(Subscription subscription) {
    return _build(subscription.cachedLinks, subscription.id);
  }

  // ---------------------------------------------------------------- parsing

  static List<VpnServer> parseContent(String content, String subscriptionId) {
    final trimmed = content.trim();
    var links = <String>[];

    // کانفیگ کامل Xray JSON (مثل Patterniha) → یک سرور واحد
    if (XrayJson.looksLike(trimmed)) {
      final id = LinkParser.stableId('sub', trimmed);
      final server = XrayJson.parse(trimmed, id: id);
      if (server != null) return <VpnServer>[server];
    }

    // آرایه‌ای از کانفیگ‌های Xray JSON (مثل Patterniha Serverless)
    if (trimmed.startsWith('[')) {
      final xrayServers = _xrayArrayFromJson(trimmed);
      if (xrayServers.isNotEmpty) return xrayServers;
    }

    if (trimmed.startsWith('[') || trimmed.startsWith('{')) {
      links = _linksFromJson(trimmed);
    }
    if (links.isEmpty) {
      links = LinkParser.extractLinks(content);
    }

    return _build(links, subscriptionId);
  }

  static List<VpnServer> _build(List<String> links, String subscriptionId) {
    final servers = <VpnServer>[];
    final seen = <String>{};

    for (final link in links) {
      final id = LinkParser.stableId('sub', link);
      if (!seen.add(id)) continue;
      final server = LinkParser.parse(link, id: id);
      if (server != null) {
        // سرورهای اشتراک قابل حذف یا اشتراک‌گذاری توسط کاربر نیستن
        server.isDeletable = false;
        servers.add(server);
      }
    }
    return servers;
  }

  static List<String> _linksFromJson(String content) {
    try {
      final decoded = jsonDecode(content);
      final links = <String>[];

      void walk(dynamic value) {
        if (value is String) {
          links.addAll(LinkParser.extractLinks(value));
        } else if (value is List) {
          for (final item in value) {
            walk(item);
          }
        } else if (value is Map) {
          for (final item in value.values) {
            walk(item);
          }
        }
      }

      walk(decoded);
      return links;
    } catch (_) {
      return <String>[];
    }
  }

  /// آرایه‌ای از کانفیگ‌های Xray JSON → لیست سرورها.
  /// بعضی اشتراک‌ها (مثل Patterniha) به‌جای لینک، آرایه‌ای از JSON کامل
  /// با outbounds/routing می‌فرستند.
  static List<VpnServer> _xrayArrayFromJson(String content) {
    final servers = <VpnServer>[];
    try {
      final decoded = jsonDecode(content);
      if (decoded is! List) return servers;
      for (final item in decoded) {
        if (item is! Map) continue;
        final jsonString = jsonEncode(item);
        if (!XrayJson.looksLike(jsonString)) continue;
        final id = LinkParser.stableId('xray', jsonString);
        final server = XrayJson.parse(jsonString, id: id);
        if (server != null) {
          server.isDeletable = false;
          servers.add(server);
        }
      }
    } catch (_) {}
    return servers;
  }

  /// اشتراک‌ها معمولاً Base64 هستند (استاندارد یا URL-safe، با یا بدون padding).
  static String _maybeDecodeBase64(String content) {
    final compact = content.replaceAll(RegExp(r'\s+'), '');

    if (compact.length < 24) return content;
    if (compact.contains('://') ||
        compact.startsWith('{') ||
        compact.startsWith('[')) {
      return content;
    }
    if (!RegExp(r'^[A-Za-z0-9+/_=-]+$').hasMatch(compact)) return content;

    try {
      final normalized =
          base64.normalize(compact.replaceAll('-', '+').replaceAll('_', '/'));
      return utf8.decode(base64.decode(normalized), allowMalformed: true);
    } catch (_) {
      return content;
    }
  }
}
