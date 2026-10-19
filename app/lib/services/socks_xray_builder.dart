// app/lib/services/socks_xray_builder.dart
//
// Xray config generator for the "app -> TUN -> Xray -> socks -> Psiphon
// (or any local SOCKS) -> internet" chain — the "Over Xray" chain of
// NekoBox Plus (qr243vbi/nekobox).
//
// SOCKS -> Xray config builder used by PsiphonService (and Tor over Xray).
//
// Critical constraints of the upstream local SOCKS (Psiphon / Tor / …):
//   - TCP CONNECT only, no UDP ASSOCIATE
//   - so UDP:53 must NOT go to the 'proxy' outbound
//   - catch-all MUST send TCP to 'proxy'; without it Xray defaults to
//     direct and the user sees "connected but nothing loads"
//   - NekoBox "Over Xray" semantics: route TCP traffic from inside the
//     tunnel and BLOCK all UDP except DNS (53). Any UDP that slips out
//     as 'direct' is a leak (QUIC/H3 stalls apps like Instagram that
//     would otherwise fall back to TCP).

import 'dart:convert';

import 'package:flutter/foundation.dart' show debugPrint;

class SocksXrayBuilder {
  SocksXrayBuilder._();

  static const List<String> _privateRanges = <String>[
    '10.0.0.0/8',
    '100.64.0.0/10',
    '127.0.0.0/8',
    '169.254.0.0/16',
    '172.16.0.0/12',
    '192.168.0.0/16',
    '224.0.0.0/4',
  ];

  static String buildXrayConfig({
    required int socksPort,
    bool blockQuic = true,
    bool overXray = true,
  }) {
    // بخش ۴ — لاگ اجباری: بلاک UDP/443 (QUIC) برای مجبور کردن
    // Instagram/Telegram به افت‌باک TCP. بدون این، Psiphon وصل می‌شود
    // ولی ترافیک رد می‌شود (QUIC از تونل SOCKS رد نمی‌شود).
    if (blockQuic) {
      debugPrint('[Xray] UDP 443 blocked to force TCP');
    }
    // Over Xray (NekoBox semantics): TCP از داخل تونل، UDP همه بلاک به‌جز DNS.
    // قبلاً بقیه‌ی UDP «direct» می‌شد که یعنی نشت ترافیک UDP بیرون از تونل —
    // اکنون مطابق NekoBox همه‌ی UDP (به‌جز 53) بلاک می‌شود.
    debugPrint('[Xray] Over Xray chain: TCP -> socks://127.0.0.1:$socksPort, '
        'UDP blocked except DNS(53)');
    // بخش ۴.۱ — دو حالت مسیریابی:
    //  overXray=true  (پیش‌فرض، مکانیزم NekoBox): TCP از داخل تونل،
    //                 همه‌ی UDP به‌جز DNS(53) بلاک.
    //  overXray=false (سازگاری): UDP/443 بلاک، بقیه UDP مستقیم.
    if (!overXray) {
      debugPrint('[Xray] Over Xray OFF — compatibility mode '
          '(UDP direct except 443)');
    }
    final rules = <Map<String, dynamic>>[
      <String, dynamic>{
        'type': 'field',
        'port': '53',
        'network': 'udp',
        'outboundTag': 'dns-out',
      },
      if (overXray)
        <String, dynamic>{
          'type': 'field',
          'network': 'udp',
          'outboundTag': 'block',
        }
      else ...[
        <String, dynamic>{
          'type': 'field',
          'port': '443',
          'network': 'udp',
          'outboundTag': 'block',
        },
        <String, dynamic>{
          'type': 'field',
          'network': 'udp',
          'outboundTag': 'direct',
        },
      ],
      <String, dynamic>{
        'type': 'field',
        'ip': _privateRanges,
        'outboundTag': 'direct',
      },
      <String, dynamic>{
        'type': 'field',
        'network': 'tcp',
        'outboundTag': 'proxy',
      },
    ];

    final config = <String, dynamic>{
      'log': <String, dynamic>{'loglevel': 'warning'},
      'stats': <String, dynamic>{},
      'policy': <String, dynamic>{
        'levels': <String, dynamic>{
          '8': <String, dynamic>{
            'connIdle': 300,
            'downlinkOnly': 1,
            'handshake': 4,
            'uplinkOnly': 1,
          },
        },
        'system': <String, dynamic>{
          'statsOutboundUplink': true,
          'statsOutboundDownlink': true,
        },
      },
      'inbounds': <Map<String, dynamic>>[
        <String, dynamic>{
          'tag': 'socks',
          'port': 10808,
          'listen': '127.0.0.1',
          'protocol': 'socks',
          'settings': <String, dynamic>{
            'auth': 'noauth',
            'udp': true,
            'userLevel': 8,
          },
          'sniffing': <String, dynamic>{
            'enabled': true,
            'destOverride': <String>['http', 'tls'],
            'routeOnly': false,
          },
        },
        <String, dynamic>{
          'tag': 'http',
          'port': 10809,
          'listen': '127.0.0.1',
          'protocol': 'http',
          'settings': <String, dynamic>{'userLevel': 8},
        },
      ],
      'outbounds': <Map<String, dynamic>>[
        <String, dynamic>{
          'tag': 'proxy',
          'protocol': 'socks',
          'settings': <String, dynamic>{
            'servers': <Map<String, dynamic>>[
              <String, dynamic>{
                'address': '127.0.0.1',
                'port': socksPort,
                'udp': false,
              },
            ],
          },
        },
        <String, dynamic>{
          'tag': 'direct',
          'protocol': 'freedom',
          'settings': <String, dynamic>{
            'domainStrategy': 'UseIPv4',
          },
        },
        <String, dynamic>{
          'tag': 'block',
          'protocol': 'blackhole',
          'settings': <String, dynamic>{
            'response': <String, dynamic>{'type': 'http'},
          },
        },
        <String, dynamic>{'tag': 'dns-out', 'protocol': 'dns'},
      ],
      'dns': <String, dynamic>{
        'servers': <dynamic>[
          <String, dynamic>{
            'address': 'https://1.1.1.1/dns-query',
            'skipFallback': false,
          },
          <String, dynamic>{
            'address': 'https://8.8.8.8/dns-query',
            'skipFallback': false,
          },
          '1.1.1.1',
          '8.8.8.8',
        ],
        'queryStrategy': 'UseIPv4',
        'disableCache': false,
      },
      'routing': <String, dynamic>{
        // AsIs (مثل حالت Over Xray در NekoBox): دامنه‌ها بدون resolve محلی
        // به outbound پروکسی (SOCKS سایفون/تور) فرستاده می‌شوند تا «داخل
        // تونل» resolve شوند. IPIfNonMatch قبلی برای هر دامنه یک کوئری DoH
        // محلی می‌خواست که اگر DoH از داخل تونل کند/خراب بود نتیجه‌اش
        // «وصل ولی هیچ‌چیز بالا نمی‌آید» بود.
        'domainStrategy': 'AsIs',
        'domainMatcher': 'hybrid',
        'rules': rules,
      },
    };

    return jsonEncode(config);
  }
}
