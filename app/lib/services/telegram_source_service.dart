import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/server.dart';
import 'link_parser.dart';
import 'tor_service.dart';
import 'v2ray_engine.dart';

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

  static const MethodChannel _native =
      MethodChannel('com.hasan.hasan_vpn/device');

  static Future<String?> _nativeFetch(String url, int socksPort) async {
    try {
      return await _native.invokeMethod<String>('fetchViaSocks', {
        'url': url,
        'port': socksPort,
      });
    } catch (_) {
      return null;
    }
  }

  /// پورت SOCKS فعال (9050=Tor، 10808=Xray) یا 0.
  static Future<int> _detectSocksPort() async {
    try {
      final st = await TorService.status();
      if (st['running'] == true) {
        final p = (st['socksPort'] as num?)?.toInt() ?? 9050;
        if (p > 0) return p;
      }
    } catch (_) {}
    try {
      if (V2RayEngine.isConnected) return 10808;
    } catch (_) {}
    return 0;
  }

  /// اگه هیچ مسیر فعالی نبود، Tor ساده رو خودکار بالا بیار.
  /// اگه هیچ مسیر فعالی نبود، خودکار Tor رو با vanilla و بعد
  /// webtunnel امتحان کن (توی ایران vanilla معمولاً بلاک می‌شه،
  /// پس webtunnel به‌عنوان fallback دوم میاد).
  static Future<int> _ensureSocks() async {
    final port0 = await _detectSocksPort();
    if (port0 > 0) return port0;

    const bridgeTypes = <String>['vanilla', 'webtunnel'];
    for (final bt in bridgeTypes) {
      try {
        final r = await TorService.start(bridgeType: bt);
        if (r['ok'] != true) continue;
        final deadline =
            DateTime.now().add(const Duration(seconds: 60));
        while (DateTime.now().isBefore(deadline)) {
          await Future.delayed(const Duration(milliseconds: 900));
          final st = await TorService.status();
          final pct = (st['bootstrapPercent'] as num?)?.toInt() ?? 0;
          if (pct >= 100) {
            return (st['socksPort'] as num?)?.toInt() ?? 9050;
          }
          if (st['running'] != true) break;
        }
        try {
          await TorService.stop();
        } catch (_) {}
      } catch (_) {}
    }
    return 0;
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

    // پیدا کردن مسیر SOCKS فعال. اگه هیچ VPN/Tor فعال نبود،
    // خودکار Tor ساده رو بالا میاریم (تا fetch از تونل رد شه).
    int socksPort = await _detectSocksPort();
    if (socksPort == 0) {
      onProgress?.call(0, total);
      socksPort = await _ensureSocks();
    }

    for (final ch in channels) {
      try {
        final links = await _fetchOne(ch, socksPort);
        if (links.isNotEmpty) perChannel[ch] = links;
      } catch (_) {}
      done++;
      onProgress?.call(done, total);
      // rate-limit بین کانال‌ها
      await Future.delayed(const Duration(milliseconds: 300));
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

  /// fetch یه کانال با ۴ مسیر fallback:
  ///   1) از طریق SOCKS محلی (Tor 9050 یا Xray 10808) — مطمئن‌ترین
  ///   2) t.me مستقیم (کار می‌کنه اگه VPN فعال باشه)
  ///   3) r.jina.ai (reader عمومی)
  ///   4) api.allorigins.win (CORS proxy)
  static Future<List<String>> _fetchOne(String channel, int socksPort) async {
    final url = 'https://t.me/s/$channel';

    // 1) SOCKS محلی — هم t.me/s/ هم t.me/
    if (socksPort > 0) {
      for (final u in [url, 'https://t.me/$channel']) {
        final html = await _nativeFetch(u, socksPort);
        if (html != null) {
          final l = _extractLinks(html);
          if (l.isNotEmpty) return l;
        }
      }
    }

    // 2) direct
    try {
      final r = await http.get(Uri.parse(url),
          headers: {'User-Agent': _ua}).timeout(
          const Duration(seconds: 15));
      if (r.statusCode == 200) {
        final l = _extractLinks(r.body);
        if (l.isNotEmpty) return l;
      }
    } catch (_) {}

    // 3+4) public proxies
    final paths = <String>[
      'https://r.jina.ai/$url',
      'https://api.allorigins.win/raw?url=${Uri.encodeComponent(url)}',
    ];
    for (final p in paths) {
      try {
        final r = await http.get(Uri.parse(p),
            headers: {'User-Agent': _ua}).timeout(
            const Duration(seconds: 25));
        if (r.statusCode != 200) continue;
        final l = _extractLinks(r.body);
        if (l.isNotEmpty) return l;
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
        .replaceAll('&#x27;', "'")
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&NewLine;', '\n')
        .replaceAll('&#x2F;', '/');
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
