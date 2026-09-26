import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/server.dart';
import 'link_parser.dart';

/// سرویس fetch کانفیگ‌های رایگان از کانال‌های تلگرام
/// از طریق preview عمومی (https://t.me/s/<channel>) بدون API key.
class TelegramSourceService {
  TelegramSourceService._();

  static const String channelsKey = 'telegram_channels_v1';
  static const String serversKey = 'telegram_servers_v1';
  static const String lastFetchKey = 'telegram_last_fetch_v1';

  static const String groupId = 'free_telegram';
  static const String groupName = 'سرور رایگان';

  static const int maxServers = 500;
  static const int refreshHours = 7;

  /// کانال‌های پیش‌فرض — کاربر نمی‌تواند حذف کند.
  static const List<String> defaultChannels = [
    'Tesla_confingh',
    'persianvpnhub',
    'FreeAutoConfig',
    'chillguy_vpn',
    'FreakConfig',
    'v2ray_configs_pools',
    'v2ray_configs_pool',
    'configMs',
    'config_vless',
    'V2RayRootFree',
    'v2raydailyupdate',
    'Raydikalx',
    'nim_vpn_ir',
    'outline_vpn',
    'hope_net',
    'proxystore11',
    'yaney_01',
    'fnet00',
    'azadnet',
    'customv2ray',
    'V2raysCollector',
    'sosiranconnect',
  ];

  static final Set<String> _defaultSet = defaultChannels.toSet();

  static bool isDefault(String ch) => _defaultSet.contains(ch);

  /// کانال‌های کاربر (بدون پیش‌فرض‌ها).
  static Future<List<String>> loadUserChannels() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getStringList(channelsKey) ?? <String>[];
    return saved.where((c) => !_defaultSet.contains(c)).toList();
  }

  /// همه کانال‌ها (پیش‌فرض + کاربر).
  static Future<List<String>> loadChannels() async {
    final user = await loadUserChannels();
    return <String>[...defaultChannels, ...user];
  }

  static Future<void> _saveUserChannels(List<String> user) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(channelsKey, user);
  }

  static String _clean(String raw) {
    var s = raw.trim();
    if (s.startsWith('https://t.me/')) {
      s = s.substring('https://t.me/'.length);
    } else if (s.startsWith('http://t.me/')) {
      s = s.substring('http://t.me/'.length);
    } else if (s.startsWith('t.me/')) {
      s = s.substring('t.me/'.length);
    }
    if (s.startsWith('@')) s = s.substring(1);
    // فقط اسم کانال رو نگه دار (بدون مسیر اضافه)
    final slash = s.indexOf('/');
    if (slash >= 0) s = s.substring(0, slash);
    return s.trim();
  }

  static Future<bool> addUserChannel(String raw) async {
    final ch = _clean(raw);
    if (ch.isEmpty) return false;
    if (_defaultSet.contains(ch)) return false;
    final user = await loadUserChannels();
    if (user.contains(ch)) return false;
    user.add(ch);
    await _saveUserChannels(user);
    return true;
  }

  static Future<void> removeUserChannel(String ch) async {
    if (_defaultSet.contains(ch)) return;
    final user = await loadUserChannels();
    if (user.remove(ch)) {
      await _saveUserChannels(user);
    }
  }

  static Future<DateTime?> lastFetch() async {
    final prefs = await SharedPreferences.getInstance();
    final s = prefs.getString(lastFetchKey);
    if (s == null) return null;
    return DateTime.tryParse(s);
  }

  static Future<bool> shouldRefresh() async {
    final last = await lastFetch();
    if (last == null) return true;
    return DateTime.now().difference(last).inHours >= refreshHours;
  }

  /// fetch همه کانال‌ها، round-robin بین‌شون تا سقف maxServers.
  static Future<int> refresh({
    void Function(int done, int total)? onProgress,
  }) async {
    final channels = await loadChannels();
    final perChannel = <String, List<String>>{};
    int done = 0;
    final total = channels.length;

    for (final ch in channels) {
      try {
        final links = await _fetchOne(ch);
        if (links.isNotEmpty) perChannel[ch] = links;
      } catch (_) {}
      done++;
      onProgress?.call(done, total);
      // rate-limit بین کانال‌ها
      await Future.delayed(const Duration(milliseconds: 400));
    }

    // round-robin انتخاب بین کانال‌ها
    final selected = <String>[];
    final seen = <String>{};
    final cursors = <String, int>{for (final c in perChannel.keys) c: 0};
    var added = true;

    while (selected.length < maxServers && added) {
      added = false;
      for (final ch in perChannel.keys) {
        final list = perChannel[ch]!;
        final cur = cursors[ch]!;
        if (cur >= list.length) continue;
        final link = list[cur];
        cursors[ch] = cur + 1;
        final base = _base(link);
        if (seen.contains(base)) continue;
        seen.add(base);
        selected.add(link);
        added = true;
        if (selected.length >= maxServers) break;
      }
    }

    await _saveServerLinks(selected);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(lastFetchKey, DateTime.now().toIso8601String());
    return selected.length;
  }

  static String _base(String link) {
    final i = link.indexOf('#');
    return i < 0 ? link : link.substring(0, i);
  }

  static const String _ua =
      'Mozilla/5.0 (Linux; Android 12) AppleWebKit/537.36 Chrome/120 Mobile';

  /// fetch یه کانال با ۳ مسیر fallback:
  ///   1) t.me مستقیم
  ///   2) r.jina.ai (reader عمومی)
  ///   3) api.allorigins.win (CORS proxy)
  static Future<List<String>> _fetchOne(String channel) async {
    final paths = <String>[
      'https://t.me/s/$channel',
      'https://r.jina.ai/https://t.me/s/$channel',
      'https://api.allorigins.win/raw?url=${Uri.encodeComponent('https://t.me/s/$channel')}',
    ];
    for (final p in paths) {
      try {
        final r = await http.get(Uri.parse(p),
            headers: {'User-Agent': _ua}).timeout(
            const Duration(seconds: 25));
        if (r.statusCode != 200) continue;
        final links = _extractLinks(r.body);
        if (links.isNotEmpty) return links;
      } catch (_) {}
    }
    return [];
  }

  static final RegExp _linkRe = RegExp(
    r'(?:vless|vmess|trojan|ss|ssr|hysteria2|hy2)://[^\s"''<>\\]+',
  );

  static List<String> _extractLinks(String html) {
    final decoded = html
        .replaceAll('&amp;', '&')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'")
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>');
    final out = <String>[];
    for (final m in _linkRe.allMatches(decoded)) {
      var link = m.group(0)!;
      link = link.replaceAll(RegExp(r'[\\]+$'), '');
      if (link.length > 12) out.add(link);
    }
    return out;
  }

  static Future<List<String>> loadServerLinks() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(serversKey) ?? <String>[];
  }

  static Future<void> _saveServerLinks(List<String> links) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(serversKey, links);
  }

  /// ساخت VpnServer از لینک‌های ذخیره‌شده.
  static Future<List<VpnServer>> buildServers() async {
    final links = await loadServerLinks();
    final out = <VpnServer>[];
    for (var i = 0; i < links.length; i++) {
      try {
        final s = LinkParser.parse(links[i], id: 'tg_free_$i');
        if (s != null) out.add(s);
      } catch (_) {}
    }
    return out;
  }

  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(serversKey);
    await prefs.remove(lastFetchKey);
  }

  /// نام نمایشی گروه برای tab.
  static String groupTitle(bool isFa) =>
      isFa ? groupName : 'Free servers';
}
