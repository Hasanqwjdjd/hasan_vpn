import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/server.dart';
import '../models/subscription.dart';

class SubscriptionService {
  static const String _key = 'subscriptions_v3';

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

  static final RegExp _linkRegex = RegExp(
    r'(trojan|vless|vmess|ss|ssr|hysteria2|hy2|aether|ssconf)://[^\s"<>\\]+',
    caseSensitive: false,
  );

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
          .map(
            (item) => Subscription.fromJson(
              Map<String, dynamic>.from(item),
            ),
          )
          .toList();

      for (final defaultSub in defaultSubscriptions) {
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
      jsonEncode(
        subscriptions.map((subscription) => subscription.toJson()).toList(),
      ),
    );
  }

  static Future<List<VpnServer>> fetch(Subscription subscription) async {
    final response = await http
        .get(
          Uri.parse(subscription.url),
          headers: const {
            'User-Agent': 'HasanVPN/10.0',
            'Accept': '*/*',
          },
        )
        .timeout(const Duration(seconds: 25));

    if (response.statusCode != 200) {
      throw Exception('HTTP ${response.statusCode}');
    }

    var content = response.body.trim();

    if (_looksLikeBase64(content)) {
      try {
        content = utf8.decode(
          base64.decode(base64.normalize(content)),
          allowMalformed: false,
        );
      } catch (_) {
        // Content was not valid Base64; parse it as plain text.
      }
    }

    final servers = parseContent(content, subscription.id);
    subscription.cachedLinks = servers.map((s) => s.shareLink).toList();

    return servers;
  }

  static List<VpnServer> fromCache(Subscription subscription) {
    final servers = <VpnServer>[];

    for (var index = 0; index < subscription.cachedLinks.length; index++) {
      final server = _parseLink(
        subscription.cachedLinks[index],
        '${subscription.id}_$index',
      );

      if (server != null) {
        servers.add(server);
      }
    }

    return servers;
  }

  static List<VpnServer> parseContent(String content, String subscriptionId) {
    final servers = <VpnServer>[];
    final trimmed = content.trim();

    if (trimmed.startsWith('[') || trimmed.startsWith('{')) {
      final jsonServers = _parseJson(content, subscriptionId);
      if (jsonServers.isNotEmpty) {
        return jsonServers;
      }
    }

    var index = 0;

    for (final match in _linkRegex.allMatches(content)) {
      final link = match.group(0)?.trim();
      if (link == null || link.isEmpty) {
        continue;
      }

      final server = _parseLink(link, '${subscriptionId}_$index');
      if (server != null) {
        servers.add(server);
        index++;
      }
    }

    return servers;
  }

  static List<VpnServer> _parseJson(
    String content,
    String subscriptionId,
  ) {
    try {
      final decoded = jsonDecode(content);
      final servers = <VpnServer>[];
      var index = 0;

      void walk(dynamic value) {
        if (value is String) {
          for (final match in _linkRegex.allMatches(value)) {
            final link = match.group(0);
            if (link == null) {
              continue;
            }

            final server = _parseLink(
              link,
              '${subscriptionId}_$index',
            );

            if (server != null) {
              servers.add(server);
              index++;
            }
          }
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
      return servers;
    } catch (_) {
      return [];
    }
  }

  static VpnServer? _parseLink(String link, String id) {
    try {
      final separatorIndex = link.indexOf('://');
      if (separatorIndex <= 0) {
        return null;
      }

      final scheme = link.substring(0, separatorIndex).toLowerCase();

      final protocol = switch (scheme) {
        'trojan' => VpnProtocol.trojan,
        'vless' => VpnProtocol.vless,
        'vmess' => VpnProtocol.vmess,
        'hysteria2' || 'hy2' => VpnProtocol.hysteria2,
        'aether' => VpnProtocol.aether,
        'ss' || 'ssr' || 'ssconf' => VpnProtocol.shadowsocks,
        _ => VpnProtocol.custom,
      };

      if (scheme == 'ss' ||
          scheme == 'ssr' ||
          scheme == 'ssconf') {
        return _parseShadowsocks(link, id, protocol);
      }

      final uri = Uri.tryParse(link);
      if (uri == null) {
        return null;
      }

      final host = uri.host;
      if (host.isEmpty && scheme != 'vmess') {
        return null;
      }

      final port = uri.hasPort ? uri.port : 443;

      final displayHost = host.isEmpty ? 'server' : host;
      final name = uri.fragment.isNotEmpty
          ? Uri.decodeComponent(uri.fragment)
          : '$scheme://$displayHost';

      final sni = uri.queryParameters['sni'] ??
          uri.queryParameters['host'] ??
          (host.isNotEmpty ? host : null);

      return VpnServer(
        id: id,
        name: name,
        flag: _guessFlag(name),
        shareLink: link,
        protocol: protocol,
        host: host.isEmpty ? 'unknown' : host,
        port: port,
        sniOrHost: sni,
        isDeletable: true,
      );
    } catch (_) {
      return null;
    }
  }

  static VpnServer? _parseShadowsocks(
    String link,
    String id,
    VpnProtocol protocol,
  ) {
    try {
      var name = 'Shadowsocks';
      var host = 'unknown';
      var port = 443;

      final uri = Uri.tryParse(link);

      if (uri != null && uri.host.isNotEmpty) {
        host = uri.host;
        port = uri.hasPort ? uri.port : 443;

        if (uri.fragment.isNotEmpty) {
          name = Uri.decodeComponent(uri.fragment);
        }
      } else {
        final withoutScheme = link.contains('://')
            ? link.substring(link.indexOf('://') + 3)
            : link;

        final hashIndex = withoutScheme.indexOf('#');
        var main = withoutScheme;

        if (hashIndex >= 0) {
          final encodedName = withoutScheme.substring(hashIndex + 1);
          name = Uri.decodeComponent(encodedName);
          main = withoutScheme.substring(0, hashIndex);
        }

        final atIndex = main.lastIndexOf('@');

        if (atIndex >= 0 && atIndex < main.length - 1) {
          final hostPort = main.substring(atIndex + 1);

          final parsedHostPort = _parseHostPort(hostPort);
          if (parsedHostPort != null) {
            host = parsedHostPort.$1;
            port = parsedHostPort.$2;
          }
        }
      }

      return VpnServer(
        id: id,
        name: name,
        flag: _guessFlag(name),
        shareLink: link,
        protocol: protocol,
        host: host,
        port: port,
        isDeletable: true,
      );
    } catch (_) {
      return null;
    }
  }

  static (String, int)? _parseHostPort(String value) {
    final trimmed = value.trim();

    if (trimmed.isEmpty) {
      return null;
    }

    if (trimmed.startsWith('[')) {
      final closingBracket = trimmed.indexOf(']');
      if (closingBracket <= 1) {
        return null;
      }

      final host = trimmed.substring(1, closingBracket);
      final remainder = trimmed.substring(closingBracket + 1);

      if (!remainder.startsWith(':')) {
        return (host, 443);
      }

      return (
        host,
        int.tryParse(remainder.substring(1)) ?? 443,
      );
    }

    final colonIndex = trimmed.lastIndexOf(':');
    if (colonIndex <= 0 || colonIndex == trimmed.length - 1) {
      return (trimmed, 443);
    }

    final host = trimmed.substring(0, colonIndex);
    final port = int.tryParse(trimmed.substring(colonIndex + 1));

    if (port == null || port < 1 || port > 65535) {
      return (trimmed, 443);
    }

    return (host, port);
  }

  static bool _looksLikeBase64(String content) {
    final trimmed = content.replaceAll(RegExp(r'\s+'), '');

    if (trimmed.length < 40) {
      return false;
    }

    if (trimmed.contains('://') ||
        trimmed.startsWith('{') ||
        trimmed.startsWith('[')) {
      return false;
    }

    return RegExp(r'^[A-Za-z0-9+/_=-]+$').hasMatch(trimmed);
  }

  static String _guessFlag(String name) {
    final value = name.toLowerCase();

    if (value.contains('🇺🇸') ||
        value.contains('united states') ||
        value.contains('usa')) {
      return '🇺🇸';
    }
    if (value.contains('🇩🇪') ||
        value.contains('germany') ||
        value.contains('de ')) {
      return '🇩🇪';
    }
    if (value.contains('🇫🇷') || value.contains('france')) {
      return '🇫🇷';
    }
    if (value.contains('🇬🇧') ||
        value.contains('england') ||
        value.contains('uk')) {
      return '🇬🇧';
    }
    if (value.contains('🇮🇷') || value.contains('iran')) {
      return '🇮🇷';
    }
    if (value.contains('🇹🇷') ||
        value.contains('turkey') ||
        value.contains('türk')) {
      return '🇹🇷';
    }
    if (value.contains('🇳🇱') || value.contains('netherland')) {
      return '🇳🇱';
    }
    if (value.contains('🇯🇵') || value.contains('japan')) {
      return '🇯🇵';
    }
    if (value.contains('🇭🇰') || value.contains('hong')) {
      return '🇭🇰';
    }
    if (value.contains('🇸🇬') || value.contains('singapore')) {
      return '🇸🇬';
    }
    if (value.contains('🇦🇪') ||
        value.contains('emirates') ||
        value.contains('dubai')) {
      return '🇦🇪';
    }
    if (value.contains('🇷🇺') || value.contains('russia')) {
      return '🇷🇺';
    }
    if (value.contains('🇨🇦') || value.contains('canada')) {
      return '🇨🇦';
    }
    if (value.contains('🇮🇳') || value.contains('india')) {
      return '🇮🇳';
    }
    if (value.contains('🇰🇷') || value.contains('korea')) {
      return '🇰🇷';
    }
    if (value.contains('🇦🇺') || value.contains('australia')) {
      return '🇦🇺';
    }

    return '🌐';
  }
}
