import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Core Xray / VPN settings applied at config-generation time.
/// Keys and defaults mirror v2rayNG / PattNG preference semantics
/// (see 2dust/v2rayNG SettingsManager + preference XML).
class XraySettings {
  XraySettings._();

  static const String _key = 'xray_core_settings_v2';

  /// Defaults aligned with v2rayNG / PattNG common defaults.
  static const Map<String, dynamic> defaults = {
    // ---- VPN / DNS (A1) ----
    'enableIpv6': false,
    'preferIpv6': false,
    'localDns': false,
    'fakeDns': false,
    'vpnDns': '1.1.1.1,8.8.8.8',
    'vpnDns6': '2606:4700:4700::1111,2001:4860:4860::8888',

    // ---- Advanced (A2) ----
    'mtu': 1500,
    'useHevTun': false,
    'hevLogLevel': 'warn',
    'hevTcpRwTimeout': 60,
    'hevUdpRwTimeout': 60,
    'sniffing': true,
    'sniffRouteOnly': false,
    'localProxyEnable': false,
    'localProxyPort': 10809,
    'localProxyUser': '',
    'localProxyPass': '',
    'shareProxyLan': false,
    'randomPort': false,
    'dnsProtocol': 'udp',
    'dohUrl': 'https://cloudflare-dns.com/dns-query',
    'directDns': '1.1.1.1',
    'dnsHosts': '',
    'dnsLeakProtection': true,
    'skipCertVerify': false,
    // Reality overrides — وقتی کاربر پر کنه، روی همه outboundهای reality
    // اعمال می‌شه (به‌جای مقادیر لینک).
    'realityPublicKey': '',
    'realityShortId': '',
    'realityFingerprint': '',
    'realityServerName': '',
    'realitySpiderX': '',

    // ---- Mux (A3) ----
    'muxEnable': false,
    'muxConcurrency': 8,
    'muxXudpConcurrency': 8,
    'muxXudpQuic': 'reject',

    // ---- Fragment (A4) ----
    // پیش‌فرض روشن — روی ایران SNI خوانده می‌شود و بدون Fragment
    // VLESS/VMess/Trojan بلاک می‌شوند.
    'fragmentEnable': false,
    'fragmentPackets': 'tlshello',
    'fragmentLength': '100-200',
    'fragmentInterval': '10-20',
    'fragmentMaxSplit': 0,

    // ---- Observatory (A5) ----
    'observatoryEnable': false,
    'leastPingInterval': 300,
    'leastLoadInterval': 300,
    'leastLoadMethod': 'HEAD',
    'leastLoadSample': 3,
    'leastLoadTimeout': 5,
    'maxFailedAttempts': 3,

    // ---- Routing domainStrategy ----
    'domainStrategy': 'AsIs',

    // ---- Delay / connection info test URLs ----
    'delayTestUrl': 'https://www.gstatic.com/generate_204',
    'connInfoUrl': 'https://api.ip.sb/geoip',
    'concurrentDelayTests': 16,

    // ---- SOCKS5 UDP ----
    'socks5Udp': true,

    // ---- UI / behavior ----
    'shareVpnLan': false,
    'showSpeedNotif': false,
    'confirmDelete': true,
    'twoColumnGrid': false,
    'showAllTab': true,

    // ---- VPN extras ----
    'vpnInterface': '',
    'bypassLan': false,
    'addHttpProxyToVpn': false,
    'alwaysOnVpn': false,
    'autoConnectBoot': false,

    // ---- Legacy / existing ----
    'logLevel': 'warning',
    'allowLan': false,
    'httpInbound': false,
    'httpPort': 10809,
    'socksPort': 10808,
  };

  static Future<Map<String, dynamic>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) {
      final old = prefs.getString('xray_core_settings_v1');
      if (old != null) {
        try {
          final decoded = jsonDecode(old);
          if (decoded is Map) {
            final map = Map<String, dynamic>.from(defaults);
            map.addAll(Map<String, dynamic>.from(decoded));
            await prefs.setString(_key, jsonEncode(map));
            return map;
          }
        } catch (_) {}
      }
      return Map<String, dynamic>.from(defaults);
    }
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

  static Future<T?> get<T>(String key) async {
    final s = await load();
    final v = s[key];
    if (v is T) return v;
    return null;
  }

  /// Apply settings onto a core JSON config string.
  /// FIX: اعمال DNS مخصوص یه سرور روی کانفیگ نهایی.
  /// اگه server.dns پر باشه، جایگزین dns.servers در کل کانفیگ می‌شه.
  static String applyServerDns(String configJson, String? dns) {
    if (dns == null || dns.trim().isEmpty) return configJson;
    try {
      final dynamic decoded = jsonDecode(configJson);
      if (decoded is! Map) return configJson;
      final map = Map<String, dynamic>.from(decoded);

      final servers = dns
          .split(RegExp(r'[,\s]+'))
          .where((s) => s.trim().isNotEmpty)
          .map((s) => s.trim())
          .toList();
      if (servers.isEmpty) return configJson;

      final dnsBlock = Map<String, dynamic>.from(
          map['dns'] as Map? ?? <String, dynamic>{});
      dnsBlock['servers'] = servers;
      dnsBlock['queryStrategy'] ??= 'UseIPv4';
      dnsBlock['disableFallback'] ??= false;
      map['dns'] = dnsBlock;

      return jsonEncode(map);
    } catch (_) {
      return configJson;
    }
  }

  /// FIX: اعمال تنظیمات TLS مخصوص یه سرور روی کانفیگ نهایی.
  /// روی outbound اصلی (اولین outbound غیر-آزاد) اعمال می‌شه.
  static String applyServerTls(
    String configJson,
    Map<String, dynamic> tls, {
    String? sniOverride,
  }) {
    if (tls.isEmpty) return configJson;
    try {
      final dynamic decoded = jsonDecode(configJson);
      if (decoded is! Map) return configJson;
      final map = Map<String, dynamic>.from(decoded);

      final fp = tls['fingerprint']?.toString() ?? '';
      final insecure = tls['allowInsecure'] == true;
      final alpnStr = tls['alpn']?.toString() ?? '';
      final cipher = tls['cipherSuites']?.toString() ?? '';
      final ech = tls['echConfigList']?.toString() ?? '';
      final verifyName = tls['verifyPeerCertByName']?.toString() ?? '';
      final pinSha = tls['pinnedPeerCertSha256']?.toString() ?? '';
      final finalMask = tls['finalMask']?.toString() ?? '';
      final dialMode = tls['dialMode']?.toString() ?? '';
      final browserDialer = tls['browserDialer'] == true;
      final targetStrategy = tls['targetStrategy']?.toString() ?? '';

      _applyToOutbounds(map, (ob) {
        final stream = Map<String, dynamic>.from(
            ob['streamSettings'] as Map? ?? {});
        final security = stream['security']?.toString().toLowerCase() ?? '';
        if (security != 'tls' &&
            security != 'xtls' &&
            security != 'reality') {
          return;
        }

        // tlsSettings
        final ts = Map<String, dynamic>.from(
            stream['tlsSettings'] as Map? ?? {});
        if (fp.isNotEmpty) ts['fingerprint'] = fp;
        if (insecure) ts['allowInsecure'] = true;
        if (alpnStr.isNotEmpty) {
          ts['alpn'] = alpnStr
              .split(RegExp(r'[,\s]+'))
              .where((s) => s.isNotEmpty)
              .toList();
        }
        if (cipher.isNotEmpty) ts['cipherSuites'] = cipher;
        if (ech.isNotEmpty) ts['echConfigList'] = ech;
        if (verifyName.isNotEmpty) ts['verifyPeerCertByName'] = verifyName;
        if (pinSha.isNotEmpty) ts['pinnedPeerCertSha256'] = pinSha;
        if (sniOverride != null && sniOverride.isNotEmpty) {
          ts['serverName'] = sniOverride;
        }
        if (ts.isNotEmpty) stream['tlsSettings'] = ts;

        // sockopt.dialMode + finalMask
        final sockopt = Map<String, dynamic>.from(
            stream['sockopt'] as Map? ?? {});
        if (dialMode.isNotEmpty) sockopt['dialMode'] = dialMode;
        if (finalMask.isNotEmpty) {
          try {
            final fm = jsonDecode(finalMask);
            sockopt['finalMask'] = fm;
          } catch (_) {
            sockopt['finalMask'] = finalMask;
          }
        }
        if (sockopt.isNotEmpty) stream['sockopt'] = sockopt;

        // targetStrategy + browserDialer
        if (targetStrategy.isNotEmpty) {
          stream['targetStrategy'] = targetStrategy;
        }
        if (browserDialer) {
          stream['browserDialer'] = true;
        }

        ob['streamSettings'] = stream;
      });

      return jsonEncode(map);
    } catch (_) {
      return configJson;
    }
  }

  static Future<String> applyToConfig(String configJson) async {
    try {
      final settings = await load();
      final dynamic decoded = jsonDecode(configJson);
      if (decoded is! Map) return configJson;
      final map = Map<String, dynamic>.from(decoded);

      final level = settings['logLevel']?.toString() ?? 'warning';
      map['log'] = {'loglevel': level == 'none' ? 'none' : level};

      int socksPort = (settings['socksPort'] as num?)?.toInt() ?? 10808;
      if (settings['randomPort'] == true) {
        socksPort = 20000 + (DateTime.now().microsecondsSinceEpoch % 20000);
      }
      final allowLan = settings['shareProxyLan'] == true ||
          settings['shareVpnLan'] == true ||
          settings['allowLan'] == true;
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
      final socks5Udp = settings['socks5Udp'] != false;

      final inbounds = <Map<String, dynamic>>[
        {
          'tag': 'socks-in',
          'port': socksPort,
          'listen': listen,
          'protocol': 'socks',
          'settings': {'auth': 'noauth', 'udp': socks5Udp},
          'sniffing': sniffingBlock,
        },
      ];

      final httpOn = settings['localProxyEnable'] == true ||
          settings['httpInbound'] == true;
      if (httpOn) {
        final httpPort =
            (settings['localProxyPort'] as num?)?.toInt() ??
                (settings['httpPort'] as num?)?.toInt() ??
                10809;
        final user = settings['localProxyUser']?.toString() ?? '';
        final pass = settings['localProxyPass']?.toString() ?? '';
        final httpSettings = <String, dynamic>{};
        if (user.isNotEmpty) {
          httpSettings['accounts'] = [
            {'user': user, 'pass': pass},
          ];
        }
        inbounds.add({
          'tag': 'http-in',
          'port': httpPort,
          'listen': listen,
          'protocol': 'http',
          'settings': httpSettings,
          'sniffing': sniffingBlock,
        });
      }

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
          if (httpOn) {
            final hasHttp = existing.any(
              (e) => e is Map && e['protocol']?.toString() == 'http',
            );
            if (!hasHttp) existing.add(inbounds.last);
          }
          map['inbounds'] = existing;
        }
      } else {
        map['inbounds'] = inbounds;
      }

      // DNS
      final dns = <String, dynamic>{};
      final vpnDns = (settings['vpnDns']?.toString() ?? '1.1.1.1,8.8.8.8')
          .split(',')
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toList();
      final servers = <dynamic>[];
      final proto = settings['dnsProtocol']?.toString() ?? 'udp';
      final doh = settings['dohUrl']?.toString() ?? '';
      if (proto == 'https' && doh.isNotEmpty) {
        servers.add({'address': doh});
      } else {
        servers.addAll(vpnDns);
      }
      final directDns = settings['directDns']?.toString() ?? '';
      if (directDns.isNotEmpty) {
        for (final d in directDns.split(',')) {
          final t = d.trim();
          if (t.isNotEmpty) servers.add(t);
        }
      }
      if (settings['localDns'] == true) {
        servers.insert(0, 'localhost');
      }
      if (settings['fakeDns'] == true) {
        servers.insert(0, {'address': 'fakedns'});
        map['fakedns'] = {
          'ipPool': '198.18.0.0/15',
          'poolSize': 65535,
        };
      }
      dns['servers'] = servers;
      // DNS leak prevention: هیچ DNS query‌ای نباید مستقیم بره.
      // Xray DNS module خودش جواب می‌ده و query‌ها را از تونل می‌فرستد.
      if (settings['dnsLeakProtection'] != false) {
        final inbounds = List<Map<String, dynamic>>.from(
          (map['inbounds'] as List? ?? const [])
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e)),
        );
        // مطمئن شو dns-out outbound هست.
        final outs = List<Map<String, dynamic>>.from(
          (map['outbounds'] as List? ?? const [])
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e)),
        );
        final hasDnsOut = outs.any((o) => o['tag'] == 'dns-out');
        if (!hasDnsOut) {
          outs.add({'tag': 'dns-out', 'protocol': 'dns'});
        }
        map['outbounds'] = outs;

        // rule پورت 53 → dns-out (بالای همه rules)
        final existing = map['routing'] is Map
            ? Map<String, dynamic>.from(map['routing'] as Map)
            : <String, dynamic>{};
        final rules = List<Map<String, dynamic>>.from(
          (existing['rules'] as List? ?? const [])
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e)),
        );
        // حذف rule تکراری قبلی اگر وجود داره
        rules.removeWhere((r) =>
            r['outboundTag'] == 'dns-out' &&
            (r['port'] == 53 || r['port'] == '53'));
        rules.insert(0, <String, dynamic>{
          'type': 'field',
          'port': 53,
          'network': 'udp',
          'outboundTag': 'dns-out',
        });
        rules.insert(1, <String, dynamic>{
          'type': 'field',
          'port': 53,
          'network': 'tcp',
          'outboundTag': 'dns-out',
        });
        existing['rules'] = rules;
        map['routing'] = existing;
      }
      if (settings['preferIpv6'] == true) {
        dns['queryStrategy'] = 'UseIPv6';
      } else if (settings['enableIpv6'] != true) {
        dns['queryStrategy'] = 'UseIPv4';
      } else {
        dns['queryStrategy'] = 'UseIP';
      }
      final hostsRaw = settings['dnsHosts']?.toString() ?? '';
      if (hostsRaw.isNotEmpty) {
        final hosts = <String, String>{};
        for (final part in hostsRaw.split(',')) {
          final kv = part.trim().split(':');
          if (kv.length >= 2) {
            hosts[kv[0].trim()] = kv.sublist(1).join(':').trim();
          }
        }
        if (hosts.isNotEmpty) dns['hosts'] = hosts;
      }
      map['dns'] = dns;

      final strategy = settings['domainStrategy']?.toString() ?? 'AsIs';
      if (map['routing'] is Map) {
        final routing = Map<String, dynamic>.from(map['routing'] as Map);
        routing['domainStrategy'] = strategy;
        map['routing'] = routing;
      } else {
        map['routing'] = {
          'domainStrategy': strategy,
          'rules': <dynamic>[],
        };
      }

      if (settings['muxEnable'] == true) {
        final mux = <String, dynamic>{
          'enabled': true,
          'concurrency':
              (settings['muxConcurrency'] as num?)?.toInt() ?? 8,
          'xudpConcurrency':
              (settings['muxXudpConcurrency'] as num?)?.toInt() ?? 8,
          'xudpProxyUDP443':
              settings['muxXudpQuic']?.toString() ?? 'reject',
        };
        _applyToOutbounds(map, (ob) {
          ob['mux'] = mux;
        });
      } else {
        _applyToOutbounds(map, (ob) {
          if (ob.containsKey('mux')) {
            final m = Map<String, dynamic>.from(ob['mux'] as Map? ?? {});
            m['enabled'] = false;
            ob['mux'] = m;
          }
        });
      }

      // Reality overrides — اگه کاربر هر کدوم رو پر کرده باشه، روی همه
      // outbound های reality جایگزین می‌شه.
      final rPub = settings['realityPublicKey']?.toString() ?? '';
      final rSid = settings['realityShortId']?.toString() ?? '';
      final rFp = settings['realityFingerprint']?.toString() ?? '';
      final rSni = settings['realityServerName']?.toString() ?? '';
      final rSpider = settings['realitySpiderX']?.toString() ?? '';
      final hasRealityOverride = rPub.isNotEmpty ||
          rSid.isNotEmpty ||
          rFp.isNotEmpty ||
          rSni.isNotEmpty ||
          rSpider.isNotEmpty;
      if (hasRealityOverride) {
        _applyToOutbounds(map, (ob) {
          final stream = Map<String, dynamic>.from(
              ob['streamSettings'] as Map? ?? {});
          final security = stream['security']?.toString().toLowerCase() ?? '';
          if (security != 'reality') return;
          final rs = Map<String, dynamic>.from(
              stream['realitySettings'] as Map? ?? {});
          if (rPub.isNotEmpty) rs['publicKey'] = rPub;
          if (rSid.isNotEmpty) rs['shortId'] = rSid;
          if (rFp.isNotEmpty) rs['fingerprint'] = rFp;
          if (rSni.isNotEmpty) rs['serverName'] = rSni;
          if (rSpider.isNotEmpty) rs['spiderX'] = rSpider;
          stream['realitySettings'] = rs;
          ob['streamSettings'] = stream;
        });
      }

      // Skip cert verify: به همه outbound های TLS اجازه بده cert خودامضا
      // قبول کنن (برای سرورهای بدون cert معتبر یا با CDN شخصی).
      if (settings['skipCertVerify'] == true) {
        _applyToOutbounds(map, (ob) {
          final stream = Map<String, dynamic>.from(
              ob['streamSettings'] as Map? ?? {});
          final security = stream['security']?.toString().toLowerCase() ?? '';
          if (security == 'tls' || security == 'xtls' || security == 'reality') {
            final tls = Map<String, dynamic>.from(
                stream['tlsSettings'] as Map? ?? {});
            tls['allowInsecure'] = true;
            stream['tlsSettings'] = tls;
            ob['streamSettings'] = stream;
          }
        });
      }

      if (settings['fragmentEnable'] == true) {
        final frag = <String, dynamic>{
          'packets': settings['fragmentPackets']?.toString() ?? 'tlshello',
          'length': settings['fragmentLength']?.toString() ?? '100-200',
          'interval': settings['fragmentInterval']?.toString() ?? '10-20',
        };
        final maxSplit =
            (settings['fragmentMaxSplit'] as num?)?.toInt() ?? 0;
        if (maxSplit > 0) frag['maxSplit'] = maxSplit;
        _applyToOutbounds(map, (ob) {
          final stream = Map<String, dynamic>.from(
              ob['streamSettings'] as Map? ?? {});
          final sockopt =
              Map<String, dynamic>.from(stream['sockopt'] as Map? ?? {});
          sockopt['fragment'] = frag;
          stream['sockopt'] = sockopt;
          ob['streamSettings'] = stream;
        });
      }

      if (settings['observatoryEnable'] == true) {
        map['observatory'] = {
          'subjectSelector': <String>['proxy'],
          'probeInterval':
              '${(settings['leastPingInterval'] as num?)?.toInt() ?? 300}s',
          'probeUrl': 'https://www.google.com/generate_204',
        };
        map['burstObservatory'] = {
          'subjectSelector': <String>['proxy'],
          'pingConfig': {
            'destination': 'https://www.google.com/generate_204',
            'interval':
                '${(settings['leastLoadInterval'] as num?)?.toInt() ?? 300}s',
            'sampling':
                (settings['leastLoadSample'] as num?)?.toInt() ?? 3,
            'timeout':
                '${(settings['leastLoadTimeout'] as num?)?.toInt() ?? 5}s',
            'httpMethod':
                settings['leastLoadMethod']?.toString() ?? 'HEAD',
          },
          'maxFailedAttempts':
              (settings['maxFailedAttempts'] as num?)?.toInt() ?? 3,
        };
      }

      return jsonEncode(map);
    } catch (_) {
      return configJson;
    }
  }

  static void _applyToOutbounds(
    Map<String, dynamic> map,
    void Function(Map<String, dynamic> ob) fn,
  ) {
    final outs = map['outbounds'];
    if (outs is! List) return;
    for (var i = 0; i < outs.length; i++) {
      final o = outs[i];
      if (o is! Map) continue;
      final tag = o['tag']?.toString() ?? '';
      final proto = o['protocol']?.toString() ?? '';
      if (proto == 'freedom' ||
          proto == 'blackhole' ||
          proto == 'dns' ||
          tag == 'direct' ||
          tag == 'block') {
        continue;
      }
      final m = Map<String, dynamic>.from(o);
      fn(m);
      outs[i] = m;
    }
  }
}
