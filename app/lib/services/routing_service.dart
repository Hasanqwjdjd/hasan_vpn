import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Routing rules persistence + defaults matching v2rayNG/PattNG
/// (geoip:private + geosite:private LAN bypass).
class RoutingService {
  RoutingService._();

  static const String _key = 'routing_rules_v1';
  static const String _strategyKey = 'routing_domain_strategy_v1';

  static List<Map<String, dynamic>> get defaultRules => [
        {
          'id': 'proxy-google',
          'enabled': false,
          'outboundTag': 'proxy',
          'domain': <String>['geosite:google'],
          'ip': <String>[],
          'port': '',
          'protocol': <String>[],
          'remark': 'Proxy Google [geosite:google]',
        },
        {
          'id': 'lan-geoip',
          'enabled': true,
          'outboundTag': 'direct',
          'domain': <String>[],
          'ip': <String>['geoip:private'],
          'port': '',
          'protocol': <String>[],
          'remark': 'LAN IP (geoip:private)',
        },
        {
          'id': 'lan-geosite',
          'enabled': true,
          'outboundTag': 'direct',
          'domain': <String>['geosite:private'],
          'ip': <String>[],
          'port': '',
          'protocol': <String>[],
          'remark': 'LAN domain (geosite:private)',
        },
        {
          'id': 'cn-dns-ip',
          'enabled': false,
          'outboundTag': 'direct',
          'domain': <String>[],
          'ip': <String>[
            '223.5.5.5',
            '223.6.6.6',
            '2400:3200::1',
            '2400:3200:baba::1',
          ],
          'port': '',
          'protocol': <String>[],
          'remark': 'Bypass CN public DNS IP',
        },
        {
          'id': 'cn-dns-domain',
          'enabled': false,
          'outboundTag': 'direct',
          'domain': <String>[
            'domain:alidns.com',
            'domain:doh.pub',
            'domain:dot.pub',
            'domain:360.cn',
            'domain:dnspod.cn',
          ],
          'ip': <String>[],
          'port': '',
          'protocol': <String>[],
          'remark': 'Bypass CN public DNS domain',
        },
        {
          'id': 'cn-ip',
          'enabled': false,
          'outboundTag': 'direct',
          'domain': <String>[],
          'ip': <String>['geoip:cn'],
          'port': '',
          'protocol': <String>[],
          'remark': 'Bypass China IP [geoip:cn]',
        },
        {
          'id': 'cn-domain',
          'enabled': false,
          'outboundTag': 'direct',
          'domain': <String>['geosite:cn'],
          'ip': <String>[],
          'port': '',
          'protocol': <String>[],
          'remark': 'Bypass China domain [geosite:cn]',
        },
      ];

  static Future<List<Map<String, dynamic>>> loadRules() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) return List.from(defaultRules.map((e) => Map<String, dynamic>.from(e)));
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return List.from(defaultRules.map((e) => Map<String, dynamic>.from(e)));
      return decoded.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    } catch (_) {
      return List.from(defaultRules.map((e) => Map<String, dynamic>.from(e)));
    }
  }

  static Future<void> saveRules(List<Map<String, dynamic>> rules) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(rules));
  }

  static Future<String> getDomainStrategy() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_strategyKey) ?? 'AsIs';
  }

  static Future<void> setDomainStrategy(String s) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_strategyKey, s);
  }

  /// Build routing.rules array for injection into xray config.
  static Future<List<Map<String, dynamic>>> buildConfigRules() async {
    final rules = await loadRules();
    final out = <Map<String, dynamic>>[];
    for (final r in rules) {
      if (r['enabled'] != true) continue;
      final rule = <String, dynamic>{
        'type': 'field',
        'outboundTag': r['outboundTag'] ?? 'proxy',
      };
      final domains = (r['domain'] as List?)?.cast<String>() ?? [];
      final ips = (r['ip'] as List?)?.cast<String>() ?? [];
      final protocols = (r['protocol'] as List?)?.cast<String>() ?? [];
      final port = r['port']?.toString() ?? '';
      if (domains.isNotEmpty) rule['domain'] = domains;
      if (ips.isNotEmpty) rule['ip'] = ips;
      if (protocols.isNotEmpty) rule['protocol'] = protocols;
      if (port.isNotEmpty) rule['port'] = port;
      out.add(rule);
    }
    return out;
  }
}
