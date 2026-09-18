import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/server.dart';
import '../models/subscription.dart';

class SubscriptionService {
  static const String _key = 'subscriptions_v1';

  /// بارگذاری اشتراک‌ها از حافظه
  static Future<List<Subscription>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) return [];
    try {
      final list = jsonDecode(raw) as List;
      return list
          .map((e) => Subscription.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  /// ذخیره اشتراک‌ها
  static Future<void> save(List<Subscription> subs) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _key,
      jsonEncode(subs.map((s) => s.toJson()).toList()),
    );
  }

  /// دانلود و پارس کردن سرورهای یک اشتراک
  static Future<List<VpnServer>> fetch(Subscription sub) async {
    final response = await http.get(
      Uri.parse(sub.url),
      headers: {
        'User-Agent': 'HasanVPN/4.0',
      },
    ).timeout(const Duration(seconds: 15));

    if (response.statusCode != 200) {
      throw Exception('HTTP ${response.statusCode}');
    }

    return parseContent(response.body, sub.id);
  }

  /// پارس کردن محتوای اشتراک
  static List<VpnServer> parseContent(String content, String subId) {
    String text = content.trim();

    // اگه base64 بود، decode کن
    try {
      final decoded = utf8.decode(base64.decode(base64.normalize(text)));
      if (decoded.contains('://')) {
        text = decoded;
      }
    } catch (_) {
      // base64 نبود، پس متن خامه
    }

    final servers = <VpnServer>[];
    final lines = text.split('\n');

    int index = 0;
    for (final line in lines) {
      final t = line.trim();
      if (t.isEmpty) continue;
      if (!t.contains('://')) continue;

      final server = _parseLink(t, '${subId}_$index');
      if (server != null) {
        servers.add(server);
        index++;
      }
    }

    return servers;
  }

  /// پارس کردن یک لینک
  static VpnServer? _parseLink(String link, String id) {
    try {
      Uri uri;
      try {
        uri = Uri.parse(link);
      } catch (_) {
        return null;
      }

      final scheme = uri.scheme.toLowerCase();
      VpnProtocol protocol;
      String? password;

      switch (scheme) {
        case 'trojan':
          protocol = VpnProtocol.trojan;
          password = uri.userInfo;
          break;
        case 'vless':
          protocol = VpnProtocol.vless;
          password = uri.userInfo;
          break;
        case 'vmess':
          protocol = VpnProtocol.vmess;
          password = '';
          break;
        case 'hysteria2':
        case 'hy2':
          protocol = VpnProtocol.hysteria2;
          password = uri.userInfo;
          break;
        case 'aether':
          protocol = VpnProtocol.aether;
          password = '';
          break;
        default:
          return null;
      }

      final host = uri.host;
      final port = uri.hasPort ? uri.port : 443;

      // اسم از fragment
      String name = uri.fragment.isNotEmpty
          ? Uri.decodeComponent(uri.fragment)
          : '$scheme://$host';

      // SNI از query
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
        shareLink: link,
      );
    } catch (_) {
      return null;
    }
  }

  static String _guessFlag(String name) {
    final n = name.toLowerCase();
    if (n.contains('🇺🇸') || n.contains('us ') || n.contains('america')) return '🇺🇸';
    if (n.contains('🇩🇪') || n.contains('germany')) return '🇩🇪';
    if (n.contains('🇫🇷') || n.contains('france')) return '🇫🇷';
    if (n.contains('🇬🇧') || n.contains('uk ') || n.contains('england')) return '🇬🇧';
    if (n.contains('🇮🇷') || n.contains('iran')) return '🇮🇷';
    if (n.contains('🇹🇷') || n.contains('turkey')) return '🇹🇷';
    if (n.contains('🇳🇱') || n.contains('netherlands')) return '🇳🇱';
    if (n.contains('🇯🇵') || n.contains('japan')) return '🇯🇵';
    if (n.contains('🇭🇰') || n.contains('hong')) return '🇭🇰';
    if (n.contains('🇸🇬') || n.contains('singapore')) return '🇸🇬';
    if (n.contains('🇦🇪') || n.contains('emirates')) return '🇦🇪';
    return '🌐';
  }
}
