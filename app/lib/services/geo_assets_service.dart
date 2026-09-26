import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

/// Geo asset file manager (geoip.dat, geosite.dat, ...).
class GeoAssetsService {
  GeoAssetsService._();

  static const List<Map<String, String>> catalog = [
    {
      'id': 'geoip',
      'name': 'geoip.dat',
      'url':
          'https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geoip.dat',
    },
    {
      'id': 'geosite',
      'name': 'geosite.dat',
      'url':
          'https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geosite.dat',
    },
    {
      'id': 'geoip-cn-private',
      'name': 'geoip-only-cn-private.dat',
      'url':
          'https://github.com/Loyalsoldier/geoip/releases/latest/download/geoip-only-cn-private.dat',
    },
  ];

  /// منابع پیش‌فرض نام‌گذاری‌شده برای فایل‌های Geo.
  static const List<Map<String, String>> sources = [
    {
      'id': 'chocolate4u-iran',
      'name': 'Chocolate4U/Iran-v2ray-rules',
      'geoip':
          'https://github.com/chocolate4u/Iran-v2ray-rules/releases/latest/download/geoip.dat',
      'geosite':
          'https://github.com/chocolate4u/Iran-v2ray-rules/releases/latest/download/geosite.dat',
    },
    {
      'id': 'loyalsoldier',
      'name': 'Loyalsoldier/v2ray-rules-dat',
      'geoip':
          'https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geoip.dat',
      'geosite':
          'https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geosite.dat',
    },
    {
      'id': 'runetfreedom-russia',
      'name': 'runetfreedom/russia-v2ray-rules-dat',
      'geoip':
          'https://github.com/runetfreedom/russia-v2ray-rules-dat/releases/latest/download/geoip.dat',
      'geosite':
          'https://github.com/runetfreedom/russia-v2ray-rules-dat/releases/latest/download/geosite.dat',
    },
  ];

  /// دانلود فایل‌های geoip+geosite از یک source مشخص.
  static Future<bool> downloadFromSource(String sourceId) async {
    final src = sources.firstWhere(
      (e) => e['id'] == sourceId,
      orElse: () => const <String, String>{},
    );
    if (src.isEmpty) return false;
    final geoipOk = await download('geoip.dat', src['geoip'] ?? '');
    final geositeOk = await download('geosite.dat', src['geosite'] ?? '');
    return geoipOk && geositeOk;
  }

  static Future<Directory> _dir() async {
    final base = await getApplicationDocumentsDirectory();
    final d = Directory('${base.path}/assets');
    if (!await d.exists()) await d.create(recursive: true);
    return d;
  }

  static Future<String> pathFor(String fileName) async {
    final d = await _dir();
    return '${d.path}/$fileName';
  }

  static Future<List<Map<String, dynamic>>> listAssets() async {
    final d = await _dir();
    final out = <Map<String, dynamic>>[];
    for (final c in catalog) {
      final p = File('${d.path}/${c['name']}');
      final exists = await p.exists();
      out.add({
        'id': c['id'],
        'name': c['name'],
        'url': c['url'],
        'exists': exists,
        'size': exists ? await p.length() : 0,
        'path': p.path,
      });
    }
    await for (final e in d.list()) {
      if (e is File && e.path.endsWith('.dat')) {
        final name = e.uri.pathSegments.last;
        if (catalog.any((c) => c['name'] == name)) continue;
        out.add({
          'id': name,
          'name': name,
          'url': '',
          'exists': true,
          'size': await e.length(),
          'path': e.path,
        });
      }
    }
    return out;
  }

  static Future<bool> download(String name, String url) async {
    if (url.isEmpty) return false;
    try {
      final resp = await http.get(Uri.parse(url)).timeout(
            const Duration(minutes: 5),
          );
      if (resp.statusCode != 200) return false;
      final p = await pathFor(name);
      await File(p).writeAsBytes(resp.bodyBytes, flush: true);
      return true;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> delete(String name) async {
    try {
      final p = await pathFor(name);
      final f = File(p);
      if (await f.exists()) await f.delete();
      return true;
    } catch (_) {
      return false;
    }
  }
}
