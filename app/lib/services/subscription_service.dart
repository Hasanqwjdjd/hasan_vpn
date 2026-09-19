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
      url: 'https://gitverse.ru/api/repos/flaafix/AetrisVPN_Black_list/raw/branch/master/configs.txt',
      isDefault: true,
    ),
    Subscription(
      id: 'spider',
      name: '🕷 Spider-Hasan',
      url: 'https://spiderpanel-production-d82c.up.railway.app/sub/97ff6e0e-d059-45a2-8fc7-57d09a07a15d',
      isDefault: true,
    ),
    Subscription(
      id: 'morning',
      name: '🌅 Morning-Shape',
      url: 'https://morning-shape-fb9a.jdjdxjjsj-wklakd.workers.dev/sub?id=413f4627-bfcb-41ff-8b6b-a0d830364376',
      isDefault: true,
    ),
    Subscription(
      id: 'zeus',
      name: '⚡ Zeus (Hasanzeus)',
      url: 'https://1oz95lepua0s.ekz8gsezum2s.workers.dev/feed/Hasanzeus',
      isDefault: true,
    ),
    Subscription(
      id: 'patterniha',
      name: '🔷 Patterniha',
      url: 'https://raw.githubusercontent.com/patterniha/Serverless-for-Iran/refs/heads/main/Subscription/Serverless-for-Iran.json',
      isDefault: true,
    ),
    Subscription(
      id: 'netra',
      name: '🌐 Netra',
      url: 'https://netra-73f72e.ekz8gsezum2s.workers.dev/7b86010baa2e/sub/raw?app=xray',
      isDefault: true,
    ),
  ];

  static Future<List<Subscription>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) {
      await save(defaultSubscriptions);
      return List.from(defaultSubscriptions);
    }
    try {
      final list = jsonDecode(raw) as List;
      final subs = list
          .map((e) => Subscription.fromJson(e as Map<String, dynamic>))
          .toList();
      for (final def in defaultSubscriptions) {
        if (!subs.any((s) => s.id == def.id)) {
          subs.add(def);
        }
      }
      await save(subs);
      return subs;
    } catch (_) {
      return List.from(defaultSubscriptions);
    }
  }

  static Future<void> save(List<Subscription> subs) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _key,
      jsonEncode(subs.map((s) => s.toJson()).toList()),
    );
  }

  static Future<List<VpnServer>> fetch(Subscription sub) async {
    final response = await http.get(
      Uri.parse(sub.url),
      headers: {
        'User-Agent': 'HasanVPN/10.0',
        'Accept': '*/*',
      },
    ).timeout(const Duration(seconds: 25));

    if (response.statusCode != 200) {
      throw Exception('HTTP ${response.statusCode}');
    }

    String content = response.body.trim();

    if (content.length > 100 &&
        !content.contains('://') &&
        !content.trim().startsWith('[') &&
        !content.trim().startsWith('{')) {
      try {
        content = utf8.decode(base64.decode(base64.normalize(content)));
      } catch (_) {}
    }

    final servers = parseContent(content, sub.id);
    sub.cachedLinks = servers.map((s) => s.shareLink).toList();
    return servers;
  }

  static List<VpnServer> fromCache(Subscription sub) {
    final servers = <VpnServer>[];
    int i = 0;
    for (final link in sub.cachedLinks) {
      final s = _parseLink(link, '${sub.id}_$i');
      if (s != null) {
        servers.add(s);
        i++;
      }
    }
    return servers;
  }

  static List<VpnServer> parseContent(String content, String subId) {
    final servers = <VpnServer>[];

    final trimmed = content.trim();
    if (trimmed.startsWith('[') || trimmed.startsWith('{')) {
      final fromJson = _parseJson(content, subId);
      if (fromJson.isNotEmpty) return fromJson;
    }

    final regex = RegExp(
      r'(trojan|vless|vmess|ss|ssr|hysteria2|hy2|aether|ssconf)://[^\s"<>\\]+',
      caseSensitive: false,
    );

    int index = 0;
    for (final match in regex.allMatches(content)) {
      final link = match.group(0);
      if (link == null) continue;

      final server = _parseLink(link, '${subId}_$index');
      if (server != null) {
        servers.add(server);
        index++;
      }
    }
    return servers;
  }

  static List<VpnServer> _parseJson(String content, String subId) {
    try {
      final decoded = jsonDecode(content);
      final results = <VpnServer>[];
      int index = 0;

      void walk(dynamic node) {
        if (node is String) {
          if (node.contains('://')) {
            final match = RegExp(
              r'(trojan|vless|vmess|ss|ssr|hysteria2|hy2|aether|ssconf)://[^\s"\\]+',
              caseSensitive: false,
            ).firstMatch(node);
            if (match != null) {
              final s = _parseLink(match.group(0)!, '${subId}_$index');
              if (s != null) {
                results.add(s);
                index++;
              }
            }
          }
        } else if (node is List) {
          for (final item in node) {
            walk(item);
          }
        } else if (node is Map) {
          for (final v in node.values) {
            walk(v);
          }
        }
      }

      walk(decoded);
      return results;
    } catch (_) {
      return [];
    }
  }

  static VpnServer? _parseLink(String link, String id) {
    try {
      final scheme = link.split('://').first.toLowerCase();
      VpnProtocol protocol;

      switch (scheme) {
        case 'trojan':
          protocol = VpnProtocol.trojan;
          break;
        case 'vless':
          protocol = VpnProtocol.vless;
          break;
        case 'vmess':
          protocol = VpnProtocol.vmess;
          break;
        case 'hysteria2':
        case 'hy2':
          protocol = VpnProtocol.hysteria2;
          break;
        case 'aether':
          protocol = VpnProtocol.aether;
          break;
        case 'ss':
        case 'ssr':
        case 'ssconf':
          protocol = VpnProtocol.shadowsocks;
          break;
        default:
          protocol = VpnProtocol.custom;
      }

      if (scheme == 'ss' || scheme == 'ssr') {
        return _parseShadowsocks(link, id, protocol);
      }

      Uri uri;
      try {
        uri = Uri.parse(link);
      } catch (_) {
        return null;
      }

      final host = uri.host;
      if (host.isEmpty && scheme != 'vmess') return null;

      final port = uri.hasPort ? uri.port : 443;

      String name;
      if (uri.fragment.isNotEmpty) {
        name = Uri.decodeComponent(uri.fragment);
      } else {
        name = '\( scheme:// \){host.isEmpty ? "server" : host}';
      }

      final sni = uri.queryParameters['sni'] ??
          uri.queryParameters['host'] ??
          (host.isNotEmpty ? host : null);

      return VpnServer(
        id: id,
        name: name,
        flag: _guessFlag(name),
        protocol: protocol,
        host: host.isEmpty ? 'unknown' : host,
        port: port,
        sniOrHost: sni,
        isDeletable: true,
        shareLink: link,
      );
    } catch (_) {
      return null;
    }
  }

  static VpnServer? _parseShadowsocks(
      String link, String id, VpnProtocol protocol) {
    try {
      String name = 'Shadowsocks';
      String host = 'unknown';
      int port = 443;

      final uri = Uri.tryParse(link);
      if (uri != null && uri.host.isNotEmpty) {
        host = uri.host;
        port = uri.hasPort ? uri.port : 443;
        if (uri.fragment.isNotEmpty) {
          name = Uri.decodeComponent(uri.fragment);
        }
      } else {
        final withoutScheme =
            link.contains('://') ? link.split('://').last : link;
        final hashIdx = withoutScheme.indexOf('#');
        String main = withoutScheme;
        if (hashIdx >= 0) {
          name = Uri.decodeComponent(withoutScheme.substring(hashIdx + 1));
          main = withoutScheme.substring(0, hashIdx);
        }
        try {
          utf8.decode(base64.decode(base64.normalize(main.split('@').first)));
        } catch (_) {}
        if (main.contains('@')) {
          final afterAt = main.split('@').last;
          final hostPort = afterAt.split('#')[0];
          if (hostPort.contains(':')) {
            final parts = hostPort.split(':');
            host = parts[0];
            port = int.tryParse(parts.last) ?? 443;
          }
        }
      }

      return VpnServer(
        id: id,
        name: name,
        flag: _guessFlag(name),
        protocol: protocol,
        host: host,
        port: port,
        isDeletable: true,
        shareLink: link,
      );
    } catch (_) {
      return null;
    }
  }

  static String _guessFlag(String name) {
    final n = name.toLowerCase();
    if (n.contains('🇺🇸') || n.contains('united states') || n.contains('usa')) {
      return '🇺🇸';
    }
    if (n.contains('🇩🇪') || n.contains('germany') || n.contains('de ')) {
      return '🇩🇪';
    }
    if (n.contains('🇫🇷') || n.contains('france')) return '🇫🇷';
    if (n.contains('🇬🇧') || n.contains('england') || n.contains('uk')) {
      return '🇬🇧';
    }
    if (n.contains('🇮🇷') || n.contains('iran')) return '🇮🇷';
    if (n.contains('🇹🇷') || n.contains('turkey') || n.contains('türk')) {
      return '🇹🇷';
    }
    if (n.contains('🇳🇱') || n.contains('netherland')) return '🇳🇱';
    if (n.contains('🇯🇵') || n.contains('japan')) return '🇯🇵';
    if (n.contains('🇭🇰') || n.contains('hong')) return '🇭🇰';
    if (n.contains('🇸🇬') || n.contains('singapore')) return '🇸🇬';
    if (n.contains('🇦🇪') || n.contains('emirates') || n.contains('dubai')) {
      return '🇦🇪';
    }
    if (n.contains('🇷🇺') || n.contains('russia')) return '🇷🇺';
    if (n.contains('🇨🇦') || n.contains('canada')) return '🇨🇦';
    if (n.contains('🇮🇳') || n.contains('india')) return '🇮🇳';
    if (n.contains('🇰🇷') || n.contains('korea')) return '🇰🇷';
    if (n.contains('🇦🇺') || n.contains('australia')) return '🇦🇺';
    return '🌐';
  }
}
