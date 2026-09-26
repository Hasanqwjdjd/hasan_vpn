/// مدل تنظیمات تونل DNS/QUIC (DNSTT / NoizDNS / VayDNS / Slipstream).
///
/// هر نوع تونل روی یک باینری native جدا اجرا می‌شود و یک SOCKS5 روی پورت
/// محلی باز می‌کند. برنامه این SOCKS را به Xray می‌دهد تا VPN سیستم از
/// داخل تونل رد شود (دقیقاً مثل Tor).
class TunnelProfile {
  /// dnstt | noizdns | vaydns | slipstream
  final String kind;

  /// دامنه‌ای که تونل از DNS آن استفاده می‌کند (مثلاً t.example.com).
  final String domain;

  /// pubkey hex — برای DNSTT/NoizDNS/VayDNS. برای Slipstream خالی.
  final String pubkey;

  /// resolver DNS — ip:port (مثلاً 8.8.8.8:53).
  final String resolver;

  /// نوع DNS transport برای dnstt:
  ///   udp → plaintext UDP DNS (resolver = "8.8.8.8:53")
  ///   dot → DNS over TLS (resolver = "dot.example:853")
  ///   doh → DNS over HTTPS (resolver = "https://resolver/dns-query")
  final String transport;

  /// پورت SOCKS محلی. 0 = خودکار (اختصاص پورت آزاد).
  final int listenPort;

  /// نام نمایشی (اختیاری).
  final String name;

  const TunnelProfile({
    this.kind = 'dnstt',
    this.domain = '',
    this.pubkey = '',
    this.resolver = '8.8.8.8:53',
    this.transport = 'udp',
    this.listenPort = 0,
    this.name = '',
  });

  static const List<String> kinds = <String>[
    'dnstt',
    'noizdns',
    'vaydns',
    'slipstream',
  ];

  static const Map<String, String> kindLabels = <String, String>{
    'dnstt': 'DNSTT (DNS tunnel)',
    'noizdns': 'NoizDNS',
    'vaydns': 'VayDNS',
    'slipstream': 'Slipstream (QUIC)',
  };

  /// باینری‌هایی که از jniLibs اجرا می‌شوند (نام فایل .so).
  static const Map<String, String> kindBinaries = <String, String>{
    'dnstt': 'libdnstt_client.so',
    'noizdns': 'libnoizdns.so',
    'vaydns': 'libvaydns.so',
    'slipstream': 'libslipstream_client.so',
  };

  String get binary => kindBinaries[kind] ?? 'libdnstt.so';

  String get summary {
    final p = kindLabels[kind] ?? kind;
    if (domain.isEmpty) return p;
    return '$p · $domain';
  }

  /// آرگومان‌های باینری بر اساس نوع. (Dart سازندهٔ argv است تا اگر CLI
  /// upstream تغییر کرد، فقط اینجا patch شود.)
  ///
  /// dnstt-client مستقل: `dnstt-client [-udp|-dot|-doh] ... -pubkey HEX DOMAIN LOCALADDR`
  /// این یک TCP forward شفاف می‌سازد، نه SOCKS. سرور dnstt باید به یک
  /// SOCKS5 سمت سرور وصل باشد. برنامه Xray را با outbound=socks به
  /// `127.0.0.1:<socksPort>` می‌چیند.
  List<String> buildArgs(int socksPort) {
    switch (kind) {
      case 'slipstream':
        // CLI واقعی slipstream-client (از --help باینری arm64):
        //   libslipstream_client.so [-l PORT] [--tcp-listen-host HOST]
        //      -r RESOLVER -d DOMAIN [-c bbr|dcubic]
        return <String>[
          '--tcp-listen-host', '127.0.0.1',
          '-l', '$socksPort',
          '-r', resolver,
          '-d', domain,
          '-c', 'bbr',
        ];
      case 'noizdns':
      case 'vaydns':
      case 'dnstt':
      default:
        final parts = <String>[];
        // انتخاب transport: udp (پیش‌فرض) / dot / doh
        if (transport == 'dot') {
          parts.addAll(['-dot', resolver]);
        } else if (transport == 'doh') {
          parts.addAll(['-doh', resolver]);
        } else {
          parts.addAll(['-udp', resolver]);
        }
        if (pubkey.isNotEmpty) {
          parts.addAll(['-pubkey', pubkey]);
        }
        parts.add(domain);
        parts.add('127.0.0.1:$socksPort');
        return parts;
    }
  }

  /// env اضافی برای باینری. اکثر باینری‌ها نیاز ندارند، ولی VayDNS
  /// پیکربندی wire format را از env می‌خواند.
  Map<String, String> buildEnv() {
    final env = <String, String>{};
    if (kind == 'vaydns') {
      env['VAYDNS_DNSTT_COMPAT'] = '1';
      env['VAYDNS_RECORD_TYPE'] = 'txt';
      env['VAYDNS_MAX_QNAME_LEN'] = '255';
      env['VAYDNS_CLIENT_ID_SIZE'] = '8';
    }
    return env;
  }

  String toLink() {
    final q = <String, String>{
      'kind': kind,
      'domain': domain,
      if (pubkey.isNotEmpty) 'pubkey': pubkey,
      if (resolver.isNotEmpty) 'resolver': resolver,
      if (transport != 'udp') 'transport': transport,
      if (listenPort > 0) 'port': '$listenPort',
      if (name.isNotEmpty) 'name': name,
    };
    return Uri(scheme: 'tunnel', host: 'config', queryParameters: q).toString();
  }

  factory TunnelProfile.fromLink(String link) {
    try {
      final uri = Uri.parse(link);
      if (uri.scheme.toLowerCase() != 'tunnel') {
        return const TunnelProfile();
      }
      return TunnelProfile.fromQuery(uri.queryParameters);
    } catch (_) {
      return const TunnelProfile();
    }
  }

  factory TunnelProfile.fromQuery(Map<String, String> q) {
    return TunnelProfile(
      kind: kinds.contains(q['kind']) ? q['kind']! : 'dnstt',
      domain: (q['domain'] ?? '').trim(),
      pubkey: (q['pubkey'] ?? '').trim(),
      resolver: (q['resolver'] ?? '8.8.8.8:53').trim(),
      transport: (q['transport'] ?? 'udp').trim(),
      listenPort: int.tryParse(q['port'] ?? '') ?? 0,
      name: (q['name'] ?? '').trim(),
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'kind': kind,
        'domain': domain,
        'pubkey': pubkey,
        'resolver': resolver,
        'transport': transport,
        'listenPort': listenPort,
        'name': name,
      };

  factory TunnelProfile.fromJson(Map<String, dynamic> j) => TunnelProfile(
        kind: j['kind']?.toString() ?? 'dnstt',
        domain: j['domain']?.toString() ?? '',
        pubkey: j['pubkey']?.toString() ?? '',
        resolver: j['resolver']?.toString() ?? '8.8.8.8:53',
        transport: j['transport']?.toString() ?? 'udp',
        listenPort: (j['listenPort'] as num?)?.toInt() ?? 0,
        name: j['name']?.toString() ?? '',
      );
}
