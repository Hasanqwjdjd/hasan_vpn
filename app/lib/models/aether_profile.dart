/// یک مرحله‌ی تلاش برای اتصال Aether (پروتکل + حالت اسکن + ...).
class AetherAttempt {
  /// masque | wg | gool | mim
  final String protocol;

  /// فقط برای masque و mim: HTTP/2 روی TCP (شبیه HTTPS) به‌جای HTTP/3 روی QUIC.
  final bool h2;

  /// turbo | balanced | thorough | stealth | ironclad
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

  /// smart | turbo | balanced | thorough | stealth | ironclad
  final String scan;

  /// auto | off | light | firewall | balanced | gfw | aggressive
  final String noize;

  /// v4 | v6 | both
  final String ip;

  /// لیست DNS داخل تونل، با کاما. خالی = پیش‌فرض Aether.
  final String dns;

  /// نقطه‌ی اتصال دستی ip:port (اختیاری).
  final String peer;

  /// پراکسی بالادستی مثل socks5://127.0.0.1:1080 (اختیاری).
  final String upstream;

  /// استفاده‌ی مجدد از آخرین گیت‌وی سالم (اتصال مجدد سریع‌تر).
  final bool quickReconnect;

  /// مسدودکردن QUIC (UDP/443) تا مرورگرها سریع به TCP برگردند.
  final bool blockQuic;

  /// auto | low | medium | high  (AETHER_PERF_PROFILE؛ auto = تشخیص خودکار)
  final String perf;

  const AetherProfile({
    this.protocol = 'auto',
    this.scan = 'smart',
    this.noize = 'auto',
    this.ip = 'v4',
    this.dns = '',
    this.peer = '',
    this.upstream = '',
    this.quickReconnect = true,
    this.blockQuic = true,
    this.perf = 'auto',
  });

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
    'stealth',
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
  static const List<String> scanEngines = <String>[
    'turbo',
    'balanced',
    'thorough',
    'stealth',
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
      upstream: (query['upstream'] ?? '').trim(),
      quickReconnect: query['qr'] != '0',
      blockQuic: query['quic'] != 'allow',
      perf: _pick(query['perf'], perfs, 'auto'),
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
      if (upstream.isNotEmpty) 'upstream': upstream,
      if (!quickReconnect) 'qr': '0',
      if (!blockQuic) 'quic': 'allow',
      if (perf != 'auto') 'perf': perf,
    };
    return Uri(scheme: 'aether', host: 'config', queryParameters: query)
        .toString();
  }

  // ------------------------------------------------------------ attempt plan

  static Duration _timeoutFor(String scan) {
    switch (scan) {
      case 'turbo':
        return const Duration(seconds: 25);
      case 'balanced':
        return const Duration(seconds: 40);
      case 'ironclad':
        return const Duration(seconds: 75);
      default: // thorough, stealth
        return const Duration(seconds: 80);
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

    if (protocol == 'auto') {
      final fixedScan = scan == 'smart' ? null : scan;
      attempts.add(_attempt('masque', false, fixedScan ?? 'turbo'));
      attempts.add(_attempt('masque', true, fixedScan ?? 'balanced'));
      attempts.add(_attempt('wg', false, fixedScan ?? 'balanced',
          forceNoize: 'gfw'));
      attempts.add(_attempt('gool', false, fixedScan ?? 'ironclad',
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
        // failover چندمرحله‌ای مثل Auto mode در ZedSecure
        if (proto == 'gool') {
          attempts.add(_attempt(proto, h2, 'balanced', forceNoize: 'gfw'));
          attempts.add(_attempt(proto, h2, 'thorough', forceNoize: 'gfw'));
          attempts.add(_attempt(proto, h2, 'ironclad', forceNoize: 'aggressive'));
        } else {
          attempts.add(_attempt(proto, h2, 'turbo'));
          attempts.add(_attempt(proto, h2, 'balanced'));
          attempts.add(_attempt(proto, h2, 'thorough'));
          attempts.add(_attempt(proto, h2, 'stealth', forceNoize: 'gfw'));
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
  Map<String, String> buildEnv(AetherAttempt attempt, int socksPort) {
    final env = <String, String>{
      'AETHER_SOCKS': '127.0.0.1:$socksPort',
      'AETHER_PROTOCOL': attempt.protocol,
      'AETHER_SCAN': attempt.scan,
      'AETHER_IP': ip,
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

    if (upstream.isNotEmpty) env['AETHER_UPSTREAM'] = upstream;

    if (perf != 'auto') env['AETHER_PERF_PROFILE'] = perf;

    return env;
  }
}
