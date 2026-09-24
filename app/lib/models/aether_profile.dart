/// یک مرحله‌ی تلاش برای اتصال Aether (پروتکل + حالت اسکن + ...).
class AetherAttempt {
  /// masque | wg | gool | mim
  final String protocol;

  /// فقط برای masque و mim: HTTP/2 روی TCP (شبیه HTTPS) به‌جای HTTP/3 روی QUIC.
  final bool h2;

  /// turbo | balanced | thorough | verified | ironclad
  final String scan;

  /// null یعنی پیش‌فرض خود Aether.
  final String? noize;

  final Duration timeout;

  const AetherAttempt({
    required this.protocol,
    this.h2 = false,
    required this.scan,
    this.noize,
    required this.timeout,
  });

  String get label {
    final proto = switch (protocol) {
      'masque' => h2 ? 'MASQUE/H2' : 'MASQUE/H3',
      'wg' => 'WireGuard',
      'gool' => 'Gool',
      'mim' => h2 ? 'MIM/H2' : 'MIM/H3',
      _ => protocol,
    };
    return '$proto · $scan';
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'protocol': protocol,
        'h2': h2,
        'scan': scan,
        'noize': noize,
        'timeout': timeout.inSeconds,
      };

  static AetherAttempt? fromJson(dynamic json) {
    if (json is! Map) return null;
    final protocol = json['protocol']?.toString();
    final scan = json['scan']?.toString();
    if (protocol == null || scan == null) return null;
    if (!AetherProfile.enginesOf.contains(protocol)) return null;
    if (!AetherProfile.scanEngines.contains(scan)) return null;
    final seconds = int.tryParse(json['timeout']?.toString() ?? '') ?? 40;
    return AetherAttempt(
      protocol: protocol,
      h2: json['h2'] == true,
      scan: scan,
      noize: json['noize']?.toString(),
      timeout: Duration(seconds: seconds.clamp(10, 180).toInt()),
    );
  }

  bool sameAs(AetherAttempt other) =>
      protocol == other.protocol && h2 == other.h2 && scan == other.scan;
}

/// تنظیمات یک سرور Aether. به‌شکل لینک `aether://config?...` ذخیره می‌شود
/// (سازگار با لینک‌های نسخه‌های قبل).
class AetherProfile {
  /// auto | masque | masque_h2 | wg | gool | mim
  final String protocol;

  /// smart | turbo | balanced | thorough | verified | ironclad
  final String scan;

  /// auto | off | light | firewall | balanced | gfw | aggressive
  final String noize;

  /// v4 | v6 | both
  final String ip;

  /// لیست DNS داخل تونل، با کاما. خالی = پیش‌فرض Aether.
  final String dns;

  /// نقطه‌ی اتصال دستی ip:port (اختیاری) — masque/wg.
  final String peer;

  /// هاپ بیرونی GOOL/WIW (ip:port) — از لینک outer=
  final String outer;

  /// هاپ داخلی GOOL/WIW (ip:port) — از لینک inner=
  final String inner;

  /// پراکسی بالادستی مثل socks5://127.0.0.1:1080 (اختیاری).
  final String upstream;

  /// استفاده‌ی مجدد از آخرین گیت‌وی سالم (اتصال مجدد سریع‌تر).
  final bool quickReconnect;

  /// مسدودکردن QUIC (UDP/443) تا مرورگرها سریع به TCP برگردند.
  final bool blockQuic;

  /// auto | low | medium | high  (AETHER_PERF_PROFILE؛ auto = تشخیص خودکار)
  final String perf;

  // ---------------------------------------------------------- Zero Trust
  // Cloudflare Zero Trust enrollment. Verified against CluvexStudio/Aether
  // Docs/DOCS.en.md + aether/src/cli.rs + release notes v1.5.0:
  //   AETHER_TEAM, AETHER_ACCESS_EMAIL, AETHER_ACCESS_ID,
  //   AETHER_ACCESS_SECRET, AETHER_ACCESS_TOKEN, AETHER_GATEWAY
  final String teamName;
  final String accessEmail;
  final String accessId;
  final String accessSecret;
  final String accessToken;
  final bool gatewayEnabled;

  // ---------------------------------------------------------- Psiphon chain
  // Aether v2.1.0 به‌صورت بومی Psiphon رو به‌عنوان یک لایه داخل/قبل/به‌جای
  // تونل خودش سوار می‌کنه (--psiphon / --psiphon-reverse / --psiphon-only).
  // این کاملاً جدا از PsiphonService.kt / psiphon_service.dart موجوده که
  // Psiphon مستقل (بدون Aether) رو اجرا می‌کنه.
  /// off | inside | reverse | only
  final String psiphonMode;

  /// خالی = خودکار. کد دو حرفی کشور مثل DE, NL, US.
  final String psiphonRegion;

  /// cdn | direct | '' (پیش‌فرض Aether)
  final String psiphonFront;

  // ---------------------------------------------------------- Tor chain
  // مشابه Psiphon chain، اما با Tor بومیِ خود Aether (پل‌ها به‌صورت خودکار
  // از bridgedb گرفته می‌شن، نیازی به تنظیم دستی نیست مگر بخوای override
  // کنی). این هم جدا از TorService.kt / TorScreen موجود در برنامه‌ست که
  // Tor مستقل (بدون Aether) رو اجرا می‌کنه.
  /// off | inside | reverse | only
  final String torMode;

  /// پل دستی (اختیاری) — خالی یعنی Aether خودش از bridgedb می‌گیره.
  final String torBridge;

  /// استفاده از رله‌های عمومی Tor به‌عنوان پل، وقتی bridgedb هم بسته است.
  final bool torRelays;

  // ---------------------------------------------------------- routing
  /// دامنه/کلیدواژه/IP که باید مستقیم (بدون تونل) بره — با کاما جدا.
  final String routeDirect;

  /// دامنه/کلیدواژه/IP که باید مسدود بشه — با کاما جدا.
  final String routeBlock;

  const AetherProfile({
    this.protocol = 'auto',
    this.scan = 'smart',
    this.noize = 'auto',
    this.ip = 'v4',
    this.dns = '',
    this.peer = '',
    this.outer = '',
    this.inner = '',
    this.upstream = '',
    this.quickReconnect = true,
    this.blockQuic = true,
    this.perf = 'auto',
    this.teamName = '',
    this.accessEmail = '',
    this.accessId = '',
    this.accessSecret = '',
    this.accessToken = '',
    this.gatewayEnabled = false,
    this.psiphonMode = 'off',
    this.psiphonRegion = '',
    this.psiphonFront = '',
    this.torMode = 'off',
    this.torBridge = '',
    this.torRelays = false,
    this.routeDirect = '',
    this.routeBlock = '',
  });

  static const List<String> chainModes = <String>['off', 'inside', 'reverse', 'only'];

  static const List<String> protocols = <String>[
    'auto',
    'masque',
    'masque_h2',
    'wg',
    'gool',
    'mim',
  ];

  static const List<String> scans = <String>[
    'smart',
    'turbo',
    'balanced',
    'thorough',
    'verified',
    'ironclad',
  ];

  static const List<String> noizes = <String>[
    'auto',
    'off',
    'light',
    'firewall',
    'balanced',
    'gfw',
    'aggressive',
  ];

  static const List<String> ips = <String>['v4', 'v6', 'both'];

  static const List<String> perfs = <String>['auto', 'low', 'medium', 'high'];

  /// مقدارهای معتبر برای AETHER_PROTOCOL و AETHER_SCAN
  static const List<String> enginesOf = <String>['masque', 'wg', 'gool', 'mim'];

  /// scan modes accepted by libaether.so v2.1.0 (--help)
  static const List<String> validScans = <String>[
    'turbo', 'balanced', 'thorough', 'verified', 'ironclad',
  ];
  static const List<String> scanEngines = <String>[
    'turbo',
    'balanced',
    'thorough',
    'verified',
    'ironclad',
  ];

  static String _pick(String? value, List<String> allowed, String fallback) {
    final v = value?.trim().toLowerCase();
    return (v != null && allowed.contains(v)) ? v : fallback;
  }

  factory AetherProfile.fromQuery(Map<String, String> query) {
    // نام‌های قدیمی نسخه‌های قبلی برنامه
    const legacyProtocol = <String, String>{
      'masque_h3': 'masque',
      'h3': 'masque',
      'h2': 'masque_h2',
      'wireguard': 'wg',
      'warp': 'wg',
    };
    const legacyScan = <String, String>{
      'fast': 'turbo',
      'full': 'thorough',
    };

    final rawProtocol = (query['protocol'] ?? 'auto').trim().toLowerCase();
    final rawScan = (query['scan'] ?? 'smart').trim().toLowerCase();

    return AetherProfile(
      protocol: _pick(legacyProtocol[rawProtocol] ?? rawProtocol, protocols, 'auto'),
      scan: _pick(legacyScan[rawScan] ?? rawScan, scans, 'smart'),
      noize: _pick(query['noize'], noizes, 'auto'),
      ip: _pick(query['ip'], ips, 'v4'),
      dns: (query['dns'] ?? '').trim(),
      peer: (query['peer'] ?? '').trim(),
      outer: (query['outer'] ?? query['wiw_outer'] ?? '').trim(),
      inner: (query['inner'] ?? query['wiw_inner'] ?? '').trim(),
      upstream: (query['upstream'] ?? '').trim(),
      quickReconnect: query['qr'] != '0',
      blockQuic: query['quic'] != 'allow',
      perf: _pick(query['perf'], perfs, 'auto'),
      teamName: (query['team'] ?? '').trim(),
      accessEmail: (query['access_email'] ?? '').trim(),
      accessId: (query['access_id'] ?? '').trim(),
      accessSecret: (query['access_secret'] ?? '').trim(),
      accessToken: (query['access_token'] ?? '').trim(),
      gatewayEnabled: query['gateway'] == '1',
      psiphonMode: _pick(query['psiphon'], chainModes, 'off'),
      psiphonRegion: (query['psiphon_region'] ?? '').trim(),
      psiphonFront: (query['psiphon_front'] ?? '').trim(),
      torMode: _pick(query['tor'], chainModes, 'off'),
      torBridge: (query['tor_bridge'] ?? '').trim(),
      torRelays: query['tor_relays'] == '1',
      routeDirect: (query['route_direct'] ?? '').trim(),
      routeBlock: (query['route_block'] ?? '').trim(),
    );
  }

  factory AetherProfile.fromLink(String link) {
    try {
      final uri = Uri.parse(link);
      if (uri.scheme.toLowerCase() != 'aether') return const AetherProfile();
      return AetherProfile.fromQuery(uri.queryParameters);
    } catch (_) {
      return const AetherProfile();
    }
  }

  /// توضیح کوتاه برای نمایش زیر نام سرور.
  String get summary {
    final proto = switch (protocol) {
      'auto' => 'Auto',
      'masque' => 'MASQUE/H3',
      'masque_h2' => 'MASQUE/H2',
      'wg' => 'WireGuard',
      'gool' => 'Gool',
      'mim' => 'MIM',
      _ => protocol,
    };
    return '$proto · $scan';
  }

  String toLink() {
    final query = <String, String>{
      'protocol': protocol,
      'scan': scan,
      'noize': noize,
      'ip': ip,
      if (dns.isNotEmpty) 'dns': dns,
      if (peer.isNotEmpty) 'peer': peer,
    if (outer.isNotEmpty) 'outer': outer,
    if (inner.isNotEmpty) 'inner': inner,
      if (upstream.isNotEmpty) 'upstream': upstream,
      if (!quickReconnect) 'qr': '0',
      if (!blockQuic) 'quic': 'allow',
      if (perf != 'auto') 'perf': perf,
      if (teamName.isNotEmpty) 'team': teamName,
      if (accessEmail.isNotEmpty) 'access_email': accessEmail,
      if (accessId.isNotEmpty) 'access_id': accessId,
      if (accessSecret.isNotEmpty) 'access_secret': accessSecret,
      if (accessToken.isNotEmpty) 'access_token': accessToken,
      if (gatewayEnabled) 'gateway': '1',
      if (psiphonMode != 'off') 'psiphon': psiphonMode,
      if (psiphonRegion.isNotEmpty) 'psiphon_region': psiphonRegion,
      if (psiphonFront.isNotEmpty) 'psiphon_front': psiphonFront,
      if (torMode != 'off') 'tor': torMode,
      if (torBridge.isNotEmpty) 'tor_bridge': torBridge,
      if (torRelays) 'tor_relays': '1',
      if (routeDirect.isNotEmpty) 'route_direct': routeDirect,
      if (routeBlock.isNotEmpty) 'route_block': routeBlock,
    };
    return Uri(scheme: 'aether', host: 'config', queryParameters: query)
        .toString();
  }

  // ------------------------------------------------------------ attempt plan

  static Duration _timeoutFor(String scan) {
    switch (scan) {
      case 'turbo':
        return const Duration(seconds: 15);
      case 'balanced':
        return const Duration(seconds: 25);
      case 'ironclad':
        return const Duration(seconds: 45);
      default: // thorough, verified
        return const Duration(seconds: 45);
    }
  }

  AetherAttempt _attempt(String proto, bool h2, String scanMode,
      {String? forceNoize}) {
    return AetherAttempt(
      protocol: proto,
      h2: h2,
      scan: scanMode,
      noize: noize == 'auto' ? forceNoize : noize,
      timeout: _timeoutFor(scanMode),
    );
  }

  /// فهرست تلاش‌ها به ترتیب. اگر [lastGood] داده شود (آخرین ترکیبی که کار کرده)
  /// اول از همه امتحان می‌شود تا اتصال‌های بعدی سریع‌تر شوند.
  List<AetherAttempt> plan({AetherAttempt? lastGood}) {
    final attempts = <AetherAttempt>[];

    // لینک pattng با outer/inner: مستقیم GOOL با همان endpointها
    if (outer.isNotEmpty && inner.isNotEmpty &&
        (protocol == 'auto' || protocol == 'gool')) {
      attempts.add(_attempt('gool', false, scan == 'smart' ? 'balanced' : scan,
          forceNoize: noize == 'auto' ? 'balanced' : null));
      if (protocol == 'gool') {
        // فقط gool با endpoint ثابت — بدون اسکن طولانی ironclad
        if (lastGood != null && quickReconnect) {
          attempts.removeWhere((a) => a.sameAs(lastGood));
          attempts.insert(0, lastGood);
        }
        return attempts;
      }
    }

    if (protocol == 'auto') {
      // mobile-first: TCP/443 (MASQUE H2) و تودرتو (GOOL/MIM) قبل از H3/QUIC.
      // روی Irancell/MCI اغلب UDP/QUIC سخت‌تر است ولی HTTPS-مانند شانس دارد.
      final fixedScan = scan == 'smart' ? null : scan;
      attempts.add(_attempt('masque', true, fixedScan ?? 'balanced',
          forceNoize: 'gfw')); // H2 / TCP 443
      attempts.add(_attempt('masque', true, fixedScan ?? 'thorough',
          forceNoize: 'aggressive'));
      attempts.add(_attempt('gool', false, fixedScan ?? 'balanced',
          forceNoize: 'gfw')); // WG-in-WG for hostile nets
      attempts.add(_attempt('mim', true, fixedScan ?? 'balanced',
          forceNoize: 'gfw')); // MASQUE-in-MASQUE over H2
      attempts.add(_attempt('masque', false, fixedScan ?? 'turbo')); // H3
      attempts.add(_attempt('wg', false, fixedScan ?? 'balanced',
          forceNoize: 'gfw'));
      attempts.add(_attempt('gool', false, fixedScan ?? 'ironclad',
          forceNoize: 'aggressive'));
      attempts.add(_attempt('mim', false, fixedScan ?? 'thorough',
          forceNoize: 'gfw'));
    } else {
      final String proto;
      final bool h2;
      switch (protocol) {
        case 'masque_h2':
          proto = 'masque';
          h2 = true;
          break;
        case 'wg':
          proto = 'wg';
          h2 = false;
          break;
        case 'gool':
          proto = 'gool';
          h2 = false;
          break;
        case 'mim':
          proto = 'mim';
          h2 = false;
          break;
        default:
          proto = 'masque';
          h2 = false;
      }

      if (scan == 'smart') {
        // failover چندمرحله‌ای — موبایل هم داخل همین زنجیره است
        if (proto == 'gool' || proto == 'mim') {
          attempts.add(_attempt(proto, h2, 'balanced', forceNoize: 'gfw'));
          attempts.add(_attempt(proto, h2, 'thorough', forceNoize: 'gfw'));
          attempts.add(_attempt(proto, h2, 'ironclad', forceNoize: 'aggressive'));
          attempts.add(_attempt(proto, h2, 'verified', forceNoize: 'aggressive'));
        } else if (h2) {
          // MASQUE/H2: TCP 443 — اولویت برای 4G
          attempts.add(_attempt(proto, true, 'balanced', forceNoize: 'gfw'));
          attempts.add(_attempt(proto, true, 'thorough', forceNoize: 'aggressive'));
          attempts.add(_attempt(proto, true, 'verified', forceNoize: 'gfw'));
          attempts.add(_attempt(proto, false, 'turbo')); // H3 fallback
        } else {
          attempts.add(_attempt(proto, h2, 'turbo'));
          attempts.add(_attempt(proto, h2, 'balanced'));
          attempts.add(_attempt(proto, h2, 'thorough'));
          attempts.add(_attempt(proto, h2, 'verified', forceNoize: 'gfw'));
        }
      } else {
        attempts.add(_attempt(proto, h2, scan));
        // یک پشتیبان با noize قوی‌تر
        if (scan != 'ironclad') {
          attempts.add(_attempt(proto, h2, 'ironclad', forceNoize: 'gfw'));
        }
      }
    }

    if (lastGood != null && quickReconnect) {
      final String family;
      if (lastGood.protocol == 'masque') {
        family = lastGood.h2 ? 'masque_h2' : 'masque';
      } else {
        family = lastGood.protocol;
      }

      if (protocol == 'auto' || protocol == family) {
        attempts.removeWhere((a) => a.sameAs(lastGood));
        attempts.insert(0, lastGood);
      }
    }

    return attempts;
  }

  // ------------------------------------------------------------ environment

  /// متغیرهای محیطی Aether. همه‌ی سؤال‌های تعاملی Aether (پروتکل، اسکن، IP،
  /// نوع MASQUE) با متغیر پاسخ داده می‌شوند تا پردازه هرگز منتظر ورودی نماند.

  static String _normalizeScan(String s) {
    switch (s) {
      case 'verified':
        return 'verified';
      case 'smart':
        return 'balanced';
      case 'turbo':
      case 'balanced':
      case 'thorough':
      case 'verified':
      case 'ironclad':
        return s;
      default:
        return 'balanced';
    }
  }

  Map<String, String> buildEnv(AetherAttempt attempt, int socksPort) {
    // Verified against CluvexStudio/Aether Docs/DOCS.en.md + cli.rs help:
    // AETHER_SOCKS, AETHER_PROTOCOL, AETHER_SCAN, AETHER_IP (v4|v6|both),
    // AETHER_QUICK_RECONNECT, AETHER_LOG_LEVEL, AETHER_MASQUE_RECONNECT_SECS,
    // AETHER_WG_RECONNECT_SECS. AETHER_TCP_* appear in proxy-limits docs.
    final env = <String, String>{
      'AETHER_SOCKS': '127.0.0.1:$socksPort',
      'AETHER_PROTOCOL': attempt.protocol,
      'AETHER_SCAN': _normalizeScan(attempt.scan),
      'AETHER_IP': ip, // v4 | v6 | both  (cli --ip)
      'AETHER_QUICK_RECONNECT': quickReconnect ? '1' : '0',
      'AETHER_LOG_LEVEL': 'info',
      'AETHER_MASQUE_RECONNECT_SECS': '1',
      'AETHER_WG_RECONNECT_SECS': '1',
      'AETHER_TCP_CONNECT_SECS': '20',
      'AETHER_TCP_KEEPALIVE_SECS': '30',
    };

    if (attempt.protocol == 'masque' || attempt.protocol == 'mim') {
      env['AETHER_MASQUE_HTTP2'] = attempt.h2 ? '1' : '0';
    }

    final nz = attempt.noize;
    if (nz != null && nz.isNotEmpty) env['AETHER_NOIZE'] = nz;

    if (dns.isNotEmpty) env['AETHER_DNS'] = dns;

    if (peer.isNotEmpty &&
        (attempt.protocol == 'masque' || attempt.protocol == 'wg')) {
      env['AETHER_PEER'] = peer;
    }

    // GOOL / WARP-in-WARP — real --help env names (libaether.so 2.1.0)
    // Link: aether://?protocol=gool&outer=IP:PORT&inner=IP:PORT
    // CLI:  --gool --wiw-outer IP:PORT --wiw-inner IP:PORT
    if (attempt.protocol == 'gool') {
      final o = outer.isNotEmpty ? outer : peer;
      if (o.isNotEmpty) env['AETHER_WIW_OUTER_PEER'] = o;
      if (inner.isNotEmpty) env['AETHER_WIW_INNER_PEER'] = inner;
      if (o.isNotEmpty && inner.isNotEmpty) {
        env['AETHER_WIW_PEERS'] = '$o,$inner';
      }
    }
    if (attempt.protocol == 'mim') {
      final o = outer.isNotEmpty ? outer : peer;
      if (o.isNotEmpty) env['AETHER_MIM_OUTER_PEER'] = o;
      if (inner.isNotEmpty) env['AETHER_MIM_INNER_PEER'] = inner;
      if (o.isNotEmpty && inner.isNotEmpty) {
        env['AETHER_MIM_PEERS'] = '$o,$inner';
      }
    }

    if (upstream.isNotEmpty) env['AETHER_UPSTREAM'] = upstream;

    // AETHER_PERF_PROFILE: not in official public help table; kept for
    // AetherST compatibility. If the binary ignores it, no harm.
    if (perf != 'auto') env['AETHER_PERF_PROFILE'] = perf;

    // ---- Zero Trust (Cloudflare Teams) — verified names ----
    if (teamName.isNotEmpty) {
      env['AETHER_TEAM'] = teamName;
      if (accessToken.isNotEmpty) {
        env['AETHER_ACCESS_TOKEN'] = accessToken;
      } else if (accessId.isNotEmpty && accessSecret.isNotEmpty) {
        env['AETHER_ACCESS_CLIENT_ID'] = accessId;
        env['AETHER_ACCESS_CLIENT_SECRET'] = accessSecret;
      } else if (accessEmail.isNotEmpty) {
        env['AETHER_ACCESS_EMAIL'] = accessEmail;
      }
      if (gatewayEnabled) env['AETHER_GATEWAY'] = '1';
    }

    // ---- Psiphon chain (بومیِ خود Aether، نه PsiphonService.kt) ----
    if (psiphonMode != 'off') {
      switch (psiphonMode) {
        case 'inside':
          env['AETHER_PSIPHON'] = '1';
          break;
        case 'reverse':
          env['AETHER_PSIPHON_REVERSE'] = '1';
          break;
        case 'only':
          env['AETHER_PSIPHON_ONLY'] = '1';
          break;
      }
      if (psiphonRegion.isNotEmpty) env['AETHER_PSIPHON_REGION'] = psiphonRegion;
      if (psiphonFront.isNotEmpty) env['AETHER_PSIPHON_MODE'] = psiphonFront;
    }

    // ---- Tor chain (بومیِ خود Aether، نه TorService.kt) ----
    if (torMode != 'off') {
      switch (torMode) {
        case 'inside':
          env['AETHER_TOR'] = '1';
          break;
        case 'reverse':
          env['AETHER_TOR_REVERSE'] = '1';
          break;
        case 'only':
          env['AETHER_TOR_ONLY'] = '1';
          break;
      }
      // AETHER_TOR_BRIDGE / AETHER_TOR_RELAYS: used by AetherST; official
      // help lists Tor modes as --tor / --tor-reverse / --tor-only. Bridge
      // override may be accepted as AETHER_TOR_BRIDGE when present.
      if (torBridge.isNotEmpty) {
        env['AETHER_TOR_BRIDGES'] = torBridge;
      } else {
        env['AETHER_TOR_BRIDGES'] = 'auto';
      }
      if (torRelays) env['AETHER_TOR_RELAYS'] = 'only';
      // Bridgedb country — Iran mobile
      env['AETHER_TOR_COUNTRY'] = 'ir';
    }

    // ---- Routing ----
    if (routeDirect.isNotEmpty) env['AETHER_ROUTE_DIRECT'] = routeDirect;
    if (routeBlock.isNotEmpty) env['AETHER_ROUTE_BLOCK'] = routeBlock;

    // ---- Lower-level knobs (GAP #6; names from Docs/DOCS.en.md) ----
    // AETHER_ROUTE_SNIFF / AETHER_ROUTE_SNIFF_MS: name-based routing behind tun
    env['AETHER_ROUTE_SNIFF'] = '1';
    env['AETHER_ROUTE_SNIFF_MS'] = '400';
    // Proxy session limits (proxy-limits section in upstream docs / help)
    env['AETHER_MAX_CLIENTS'] = '2048';
    env['AETHER_HALF_CLOSE_SECS'] = '30';
    // TCP timeouts already set above (CONNECT/KEEPALIVE). AETHER_MARK needs
    // root on Android; intentionally not set here.

    return env;
  }
}
