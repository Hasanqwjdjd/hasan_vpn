import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/server.dart';
import '../models/subscription.dart';
import 'link_parser.dart';
import 'xray_json.dart';

class SubscriptionService {
  static const String _key = 'subscriptions_v3';
  static const String _removedDefaultsKey = 'subscriptions_removed_defaults_v1';

  static final List<Subscription> defaultSubscriptions = [
    Subscription(
      id: 'aetris',
      name: '🌐 Aetris (GitVerse)',
      url:
          'https://gitverse.ru/api/repos/flaafix/AetrisVPN_Black_list/raw/branch/master/configs.txt',
      isDefault: true,
    ),
    Subscription(
      id: 'spider',
      name: '🕷 Spider-Hasan',
      url:
          'https://spiderpanel-production-d82c.up.railway.app/sub/97ff6e0e-d059-45a2-8fc7-57d09a07a15d',
      isDefault: true,
    ),
    Subscription(
      id: 'morning',
      name: '🌅 Morning-Shape',
      url:
          'https://morning-shape-fb9a.jdjdxjjsj-wklakd.workers.dev/sub?id=413f4627-bfcb-41ff-8b6b-a0d830364376',
      isDefault: true,
    ),
    Subscription(
      id: 'zeus',
      name: '⚡ Zeus (Hasanzeus)',
      url:
          'https://1oz95lepua0s.ekz8gsezum2s.workers.dev/feed/Hasanzeus',
      isDefault: true,
    ),
    Subscription(
      id: 'patterniha',
      name: '🔷 Patterniha',
      url:
          'https://raw.githubusercontent.com/patterniha/Serverless-for-Iran/refs/heads/main/Subscription/Serverless-for-Iran.json',
      isDefault: true,
    ),
    Subscription(
      id: 'netra',
      name: '🌐 Netra',
      url:
          'https://netra-73f72e.ekz8gsezum2s.workers.dev/7b86010baa2e/sub/raw?app=xray',
      isDefault: true,
    ),
  ];

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
      jsonEncode(subscriptions.map((s) => s.toJson()).toList()),
    );
  }

  // ---------------------------------------------------------------- network

  static Future<List<VpnServer>> fetch(Subscription subscription) async {
    final response = await http
        .get(
          Uri.parse(subscription.url),
          headers: const {
            'User-Agent': 'HasanVPN/10.0',
            'Accept': '*/*',
          },
        )
        .timeout(const Duration(seconds: 20));

    if (response.statusCode != 200) {
      throw Exception('HTTP ${response.statusCode}');
    }

    // بدنه را خودمان UTF-8 رمزگشایی می‌کنیم؛ response.body بدون charset در هدر
    // به latin1 می‌رود و نام‌های فارسی/ایموجی خراب می‌شوند.
    var content = utf8.decode(response.bodyBytes, allowMalformed: true).trim();
    content = _maybeDecodeBase64(content);

    final servers = parseContent(content, subscription.id);
    if (servers.isEmpty) {
      // پاسخ خراب یا خالی نباید کش قبلی را پاک کند.
      throw Exception('no servers found');
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
      if (server != null) servers.add(server);
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
