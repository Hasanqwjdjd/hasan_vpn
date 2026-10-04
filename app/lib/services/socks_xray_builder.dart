// app/lib/services/socks_xray_builder.dart
//
// Xray config generator for the "app -> TUN -> Xray -> socks -> Psiphon
// (or any local SOCKS) -> internet" chain.
//
// Extracted from AetherService when Aether was removed. PsiphonService
// is the only remaining consumer.
//
// Critical constraints of Psiphon LocalSocksProxyPort:
//   - TCP CONNECT only, no UDP ASSOCIATE
//   - so UDP:53 must NOT go to the 'proxy' outbound
//   - catch-all MUST send TCP to 'proxy'; without it Xray defaults to
//     direct and the user sees "connected but nothing loads"

import 'dart:convert';

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
  }) {
    final rules = <Map<String, dynamic>>[
      <String, dynamic>{
        'type': 'field',
        'port': '53',
        'network': 'udp',
        'outboundTag': 'dns-out',
      },
      if (blockQuic)
        <String, dynamic>{
          'type': 'field',
          'port': '443',
          'network': 'udp',
          'outboundTag': 'block',
        },
      <String, dynamic>{
        'type': 'field',
        'ip': _privateRanges,
        'outboundTag': 'direct',
      },
      <String, dynamic>{
        'type': 'field',
        'network': 'udp',
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
        'domainStrategy': 'IPIfNonMatch',
        'domainMatcher': 'hybrid',
        'rules': rules,
      },
    };

    return jsonEncode(config);
  }
}
