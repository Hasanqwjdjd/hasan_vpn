import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/server.dart';
import '../models/subscription.dart';

class SubscriptionService {
  static const String _key = 'subscriptions_v3';

  // ═══════════════════════════════════════════════
  // سابسکریپشن‌های تو
  // ═══════════════════════════════════════════════
  static final List<Subscription> defaultSubscriptions = [
    Subscription(
      id: 'aetris',
      name: '🌐 Aetris (GitVerse)',
      url: 'https://gitverse.ru/api/repos/flaafix/AetrisVPN_Black_list/raw/branch/master/configs.txt',
      isDefault: true,
      autoUpdate: true,
    ),
    Subscription(
      id: 'spider',
      name: '🕷 Spider-Hasan',
      url: 'https://spiderpanel-production-d82c.up.railway.app/sub/97ff6e0e-d059-45a2-8fc7-57d09a07a15d',
      isDefault: true,
      autoUpdate: true,
    ),
    Subscription(
      id: 'morning',
      name: '🌅 Morning-Shape',
      url: 'https://morning-shape-fb9a.jdjdxjjsj-wklakd.workers.dev/sub?id=413f4627-bfcb-41ff-8b6b-a0d830364376',
      isDefault: true,
      autoUpdate: true,
    ),
    Subscription(
      id: 'zeus',
      name: '⚡ Zeus (Hasanzeus)',
      url: 'https://1oz95lepua0s.ekz8gsezum2s.workers.dev/feed/Hasanzeus',
      isDefault: true,
      autoUpdate: true,
    ),
    Subscription(
      id: 'patterniha',
      name: '🔷 Patterniha (Serverless)',
      url: 'https://raw.githubusercontent.com/patterniha/Serverless-for-Iran/refs/heads/main/Subscription/Serverless-for-Iran.json',
      isDefault: true,
      autoUpdate: true,
    ),
    Subscription(
      id: 'netra',
      name: '🌐 Netra',
      url: 'https://netra-73f72e.ekz8gsezum2s.workers.dev/7b86010baa2e/sub/raw?app=xray',
      isDefault: true,
      autoUpdate: true,
    ),
  ];

  /// بارگذاری از حافظه — اگه بار اول بود، پیش‌فرض‌ها رو اضافه کن
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

      // اگه پیش‌فرض جدید اضافه شده، به لیست اضافه کن
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

  /// دانلود و پارس
  static Future<List<VpnServer>> fetch(Subscription sub) async {
    final response = await http.get(
      Uri.parse(sub.url),
      headers: {
        'User-Agent': 'HasanVPN/5.0',
        'Accept': '*/*',
      },
    ).timeout(const Duration(seconds: 25));

    if (response.statusCode != 200) {
      throw Exception('HTTP ${response.statusCode}');
    }

    String content = response.body.trim();

    // تشخیص فرمت base64 (اگه لینک نداره ولی طولانیه)
    if (content.length > 100 && !content.contains('://')) {
      try {
        content = utf8.decode(base64.decode(base64.normalize(content)));
      } catch (_) {}
    }

    return parseContent(content, sub.id);
  }

  static List<VpnServer> parseContent(String content, String subId) {
    // اگه JSON بود، اول ازش استخراج کن
    if (content.trim().startsWith('[') || content.trim().startsWith('{')) {
      final fromJson = _parseJson(content, subId);
      if (fromJson.isNotEmpty) return fromJson;
    }

    final servers = <VpnServer>[];
    final lines = content.split('\n');

    int index = 0;
    for (final line in lines) {
      final t = line.trim();
      if (t.isEmpty || !t.contains('://')) continue;

      // پیدا کردن لینک داخل متن (برای JSONهای ناقص)
      final match = RegExp(r'(trojan|vless|vmess|hysteria2|hy2|aether)://[^\s"\\]+')
          .firstMatch(t);
      if (match == null) continue;

      final server = _parseLink(match.group(0)!, '${subId}_$index');
      if (server != null) {
        servers.add(server);
        index++;
      }
    }
    return servers;
  }

  /// پارس JSON (برای Patterniha)
  static List<VpnServer> _parseJson(String content, String subId) {
    try {
      final decoded = jsonDecode(content);
      final results = <VpnServer>[];
      int index = 0;

      void walk(dynamic node) {
        if (node is String) {
          if (node.contains('://')) {
            final match = RegExp(
                    r'(trojan|vless|vmess|hysteria2|hy2|aether)://[^\s"\\]+')
                .firstMatch(node);
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
          // اگه فیلد name یا remarks داشت، اسم بذار
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
        default:
          return null;
      }

      Uri uri;
      try {
        uri = Uri.parse(link);
      } catch (_) {
        return null;
      }

      final host = uri.host;
      if (host.isEmpty) return null;

      final port = uri.hasPort ? uri.port : 443;

      String name;
      if (uri.fragment.isNotEmpty) {
        name = Uri.decodeComponent(uri.fragment);
      } else {
        name = '$scheme://$host';
      }

      final sni = uri.queryParameters['sni'] ??
          uri.queryParameters['host'] ??
          host;

      return VpnServer(
        id: id,
        name: name,
        flag: _guessFlag(name),
        protocol: protocol,
        host: host,
        port: port,
        sniOrHost: sni,
        isDeletable: true,
        shareLink: link,
      );
    } catch (_) {
      return null;
    }
  }

  static String _guessFlag(String name) {
    final n = name.toLowerCase();
    if (n.contains('🇺🇸') || n.contains('united states') || n.contains(' us ')) return '🇺🇸';
    if (n.contains('🇩🇪') || n.contains('germany')) return '🇩🇪';
    if (n.contains('🇫🇷') || n.contains('france')) return '🇫🇷';
    if (n.contains('🇬🇧') || n.contains('england')) return '🇬🇧';
    if (n.contains('🇮🇷') || n.contains('iran')) return '🇮🇷';
    if (n.contains('🇹🇷') || n.contains('turkey')) return '🇹🇷';
    if (n.contains('🇳🇱') || n.contains('netherland')) return '🇳🇱';
    if (n.contains('🇯🇵') || n.contains('japan')) return '🇯🇵';
    if (n.contains('🇭🇰') || n.contains('hong')) return '🇭🇰';
    if (n.contains('🇸🇬') || n.contains('singapore')) return '🇸🇬';
    if (n.contains('🇦🇪') || n.contains('emirates')) return '🇦🇪';
    if (n.contains('🇷🇺') || n.contains('russia')) return '🇷🇺';
    if (n.contains('🇨🇦') || n.contains('canada')) return '🇨🇦';
    if (n.contains('🇮🇳') || n.contains('india')) return '🇮🇳';
    if (n.contains('🇰🇷') || n.contains('korea')) return '🇰🇷';
    if (n.contains('🇦🇺') || n.contains('australia')) return '🇦🇺';
    if (n.contains('🇫🇮') || n.contains('finland')) return '🇫🇮';
    if (n.contains('🇸🇪') || n.contains('sweden')) return '🇸🇪';
    if (n.contains('🇨🇭') || n.contains('switzerland')) return '🇨🇭';
    if (n.contains('🇦🇹') || n.contains('austria')) return '🇦🇹';
    if (n.contains('🇵🇱') || n.contains('poland')) return '🇵🇱';
    if (n.contains('🇮🇹') || n.contains('italy')) return '🇮🇹';
    if (n.contains('🇪🇸') || n.contains('spain')) return '🇪🇸';
    return '🌐';
  }
}
