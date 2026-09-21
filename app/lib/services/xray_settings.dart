import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// تنظیمات هسته Xray که روی کانفیگ اعمال می‌شوند.
class XraySettings {
  XraySettings._();

  static const String _key = 'xray_core_settings_v1';

  static const Map<String, dynamic> defaults = {
    'sniffing': true,
    'sniffRouteOnly': false,
    'logLevel': 'warning', // debug | info | warning | error | none
    'allowLan': false,
    'httpInbound': false,
    'httpPort': 10809,
    'socksPort': 10808,
  };

  static Future<Map<String, dynamic>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) return Map<String, dynamic>.from(defaults);
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return Map<String, dynamic>.from(defaults);
      final map = Map<String, dynamic>.from(defaults);
      map.addAll(Map<String, dynamic>.from(decoded));
      return map;
    } catch (_) {
      return Map<String, dynamic>.from(defaults);
    }
  }

  static Future<void> save(Map<String, dynamic> settings) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(settings));
  }

  static Future<void> set(String key, dynamic value) async {
    final s = await load();
    s[key] = value;
    await save(s);
  }

  /// اعمال تنظیمات روی یک کانفیگ JSON هسته
  static Future<String> applyToConfig(String configJson) async {
    try {
      final settings = await load();
      final dynamic decoded = jsonDecode(configJson);
      if (decoded is! Map) return configJson;
      final map = Map<String, dynamic>.from(decoded);

      // ---- log ----
      final level = settings['logLevel']?.toString() ?? 'warning';
      if (level == 'none') {
        map['log'] = {'loglevel': 'none'};
      } else {
        map['log'] = {'loglevel': level};
      }

      // ---- inbounds ----
      final socksPort = (settings['socksPort'] as num?)?.toInt() ?? 10808;
      final allowLan = settings['allowLan'] == true;
      final listen = allowLan ? '0.0.0.0' : '127.0.0.1';
      final sniffingOn = settings['sniffing'] != false;
      final routeOnly = settings['sniffRouteOnly'] == true;

      final sniffingBlock = sniffingOn
          ? <String, dynamic>{
              'enabled': true,
              'destOverride': <String>['http', 'tls', 'quic'],
              if (routeOnly) 'routeOnly': true,
            }
          : <String, dynamic>{'enabled': false};

      final inbounds = <Map<String, dynamic>>[
        {
          'tag': 'socks-in',
          'port': socksPort,
          'listen': listen,
          'protocol': 'socks',
          'settings': {'auth': 'noauth', 'udp': true},
          'sniffing': sniffingBlock,
        },
      ];

      if (settings['httpInbound'] == true) {
        final httpPort = (settings['httpPort'] as num?)?.toInt() ?? 10809;
        inbounds.add({
          'tag': 'http-in',
          'port': httpPort,
          'listen': listen,
          'protocol': 'http',
          'settings': <String, dynamic>{},
          'sniffing': sniffingBlock,
        });
      }

      // اگر inbound از قبل بود، فقط sniffing/listen را روی socks به‌روز کن
      // و در غیر این صورت جایگزین کن.
      final existing = map['inbounds'];
      if (existing is List && existing.isNotEmpty) {
        var touched = false;
        for (var i = 0; i < existing.length; i++) {
          final ib = existing[i];
          if (ib is! Map) continue;
          final proto = ib['protocol']?.toString() ?? '';
          if (proto == 'socks' || proto == 'http') {
            final m = Map<String, dynamic>.from(ib);
            m['listen'] = listen;
            m['sniffing'] = sniffingBlock;
            if (proto == 'socks') m['port'] = socksPort;
            existing[i] = m;
            touched = true;
          }
        }
        if (!touched) {
          map['inbounds'] = inbounds;
        } else {
          // اگر httpInbound روشن است و نبود، اضافه کن
          if (settings['httpInbound'] == true) {
            final hasHttp = existing.any(
              (e) => e is Map && e['protocol']?.toString() == 'http',
            );
            if (!hasHttp) {
              existing.add(inbounds.last);
            }
          }
          map['inbounds'] = existing;
        }
      } else {
        map['inbounds'] = inbounds;
      }

      return jsonEncode(map);
    } catch (_) {
      return configJson;
    }
  }
}
