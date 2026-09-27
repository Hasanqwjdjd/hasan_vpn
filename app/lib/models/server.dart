class TlsOptions {
  final String? fingerprint;
  final bool allowInsecure;
  final String? alpn;
  final String? cipherSuites;
  final String? echConfigList;
  final String? verifyPeerCertByName;
  final String? pinnedPeerCertSha256;
  final String? finalMask;
  final String? dialMode;
  final bool browserDialer;
  final String? targetStrategy;

  const TlsOptions({
    this.fingerprint,
    this.allowInsecure = false,
    this.alpn,
    this.cipherSuites,
    this.echConfigList,
    this.verifyPeerCertByName,
    this.pinnedPeerCertSha256,
    this.finalMask,
    this.dialMode,
    this.browserDialer = false,
    this.targetStrategy,
  });

  static const TlsOptions empty = TlsOptions();

  bool get isEmpty =>
      (fingerprint == null || fingerprint!.isEmpty) &&
      !allowInsecure &&
      (alpn == null || alpn!.isEmpty) &&
      (cipherSuites == null || cipherSuites!.isEmpty) &&
      (echConfigList == null || echConfigList!.isEmpty) &&
      (verifyPeerCertByName == null || verifyPeerCertByName!.isEmpty) &&
      (pinnedPeerCertSha256 == null || pinnedPeerCertSha256!.isEmpty) &&
      (finalMask == null || finalMask!.isEmpty) &&
      (dialMode == null || dialMode!.isEmpty) &&
      !browserDialer &&
      (targetStrategy == null || targetStrategy!.isEmpty);

  TlsOptions copyWith({
    String? fingerprint,
    bool? allowInsecure,
    String? alpn,
    String? cipherSuites,
    String? echConfigList,
    String? verifyPeerCertByName,
    String? pinnedPeerCertSha256,
    String? finalMask,
    String? dialMode,
    bool? browserDialer,
    String? targetStrategy,
  }) =>
      TlsOptions(
        fingerprint: fingerprint ?? this.fingerprint,
        allowInsecure: allowInsecure ?? this.allowInsecure,
        alpn: alpn ?? this.alpn,
        cipherSuites: cipherSuites ?? this.cipherSuites,
        echConfigList: echConfigList ?? this.echConfigList,
        verifyPeerCertByName: verifyPeerCertByName ?? this.verifyPeerCertByName,
        pinnedPeerCertSha256: pinnedPeerCertSha256 ?? this.pinnedPeerCertSha256,
        finalMask: finalMask ?? this.finalMask,
        dialMode: dialMode ?? this.dialMode,
        browserDialer: browserDialer ?? this.browserDialer,
        targetStrategy: targetStrategy ?? this.targetStrategy,
      );

  Map<String, dynamic> toJson() => {
        if (fingerprint != null && fingerprint!.isNotEmpty)
          'fingerprint': fingerprint,
        if (allowInsecure) 'allowInsecure': allowInsecure,
        if (alpn != null && alpn!.isNotEmpty) 'alpn': alpn,
        if (cipherSuites != null && cipherSuites!.isNotEmpty)
          'cipherSuites': cipherSuites,
        if (echConfigList != null && echConfigList!.isNotEmpty)
          'echConfigList': echConfigList,
        if (verifyPeerCertByName != null && verifyPeerCertByName!.isNotEmpty)
          'verifyPeerCertByName': verifyPeerCertByName,
        if (pinnedPeerCertSha256 != null && pinnedPeerCertSha256!.isNotEmpty)
          'pinnedPeerCertSha256': pinnedPeerCertSha256,
        if (finalMask != null && finalMask!.isNotEmpty) 'finalMask': finalMask,
        if (dialMode != null && dialMode!.isNotEmpty) 'dialMode': dialMode,
        if (browserDialer) 'browserDialer': browserDialer,
        if (targetStrategy != null && targetStrategy!.isNotEmpty)
          'targetStrategy': targetStrategy,
      };

  factory TlsOptions.fromJson(Map<String, dynamic> j) => TlsOptions(
        fingerprint: j['fingerprint']?.toString(),
        allowInsecure: j['allowInsecure'] == true,
        alpn: j['alpn']?.toString(),
        cipherSuites: j['cipherSuites']?.toString(),
        echConfigList: j['echConfigList']?.toString(),
        verifyPeerCertByName: j['verifyPeerCertByName']?.toString(),
        pinnedPeerCertSha256: j['pinnedPeerCertSha256']?.toString(),
        finalMask: j['finalMask']?.toString(),
        dialMode: j['dialMode']?.toString(),
        browserDialer: j['browserDialer'] == true,
        targetStrategy: j['targetStrategy']?.toString(),
      );
}

enum VpnProtocol {
  trojan,
  vless,
  vmess,
  hysteria2,
  aether,
  shadowsocks,
  custom,
  /// کانفیگ کامل JSON هسته Xray (مثلاً Patterniha و مشابه)
  xrayJson,
  /// هستهٔ واقعی Psiphon (کتابخانهٔ ca.psiphon)
  psiphon,
  /// تونل DNS (DNSTT / NoizDNS / VayDNS) — باینری native + SOCKS محلی
  tunnel,
  /// SSH tunnel — dartssh2 + forwardLocal به SOCKS5 روی سرور SSH
  ssh,
  /// پروکسی SOCKS5 از راه دور (بدون رمزنگاری اضافی)
  socks5,
  /// زنجیره دو سرور (multi-hop) — link با فرمت chain://
  chain,
}

/// idle: تست نشده | testing: در حال تست | online: سالم | offline: از کار افتاده
/// unknown: نتیجه قابل تشخیص نیست (مثلاً پروتکل UDP که TCP-ping روی آن معنا ندارد)
enum ServerStatus { idle, testing, online, offline, unknown }

/// نوع پینگ ثبت‌شده:
///  - none: هنوز تست نشده
///  - tcp:  فقط زمان دست‌دادن TCP تا سرور (تقریبی؛ برای سرورهای پشت CDN معمولاً خوش‌بینانه است)
///  - real: زمان واقعی یک درخواست HTTP از داخل خود پروکسی/تونل (پینگ واقعی)
enum PingKind { none, tcp, real }

class VpnServer {
  /// Strip Dart record/tuple leaks like this,'حسن' or (this, 'حسن').
  static String sanitizeServerName(String raw) {
    var v = raw.trim();
    final m1 = RegExp(
      r"""(?:^|\b)this\s*,\s*['"]([^'"]+)['"]""",
      caseSensitive: false,
    ).firstMatch(v);
    if (m1 != null && (m1.group(1) ?? '').isNotEmpty) {
      v = m1.group(1)!;
    } else {
      final m2 = RegExp(
        r"""^\(\s*(?:this\s*,\s*)?['"]([^'"]*)['"]\s*\)$""",
        caseSensitive: false,
      ).firstMatch(v);
      if (m2 != null && (m2.group(1) ?? '').isNotEmpty) {
        v = m2.group(1)!;
      } else {
        v = v.replaceFirst(RegExp(r'^this\s*,\s*', caseSensitive: false), '');
        v = v.replaceAll(RegExp(r"""^['"]|['"]$"""), '');
      }
    }
    v = v.replaceAll(RegExp(r'\s+'), ' ').trim();
    return v.isEmpty ? raw.trim() : (v.length > 80 ? v.substring(0, 80) : v);
  }

  final String id;
  final String name;
  final String flag;
  final String shareLink;
  final VpnProtocol protocol;
  final String host;
  final int port;
  String? sniOrHost;
  bool isDeletable;
  bool isPinned;

  /// نام سفارشی که کاربر جایگزین نام اصلی کرده. null = نام اصلی.
  String? nameOverride;

  /// تنظیمات TLS سفارشی کاربر (fingerprint, allowInsecure, finalMask, ...)
  TlsOptions tls;

  /// DNS سفارشی این سرور. null = از تنظیمات کلی استفاده کن.
  String? dns;

  int? ping;
  int? jitter;
  PingKind pingKind;
  int? speedKbps;
  ServerStatus status;

  VpnServer({
    required this.id,
    required String name,
    required this.flag,
    required this.shareLink,
    required this.protocol,
    required this.host,
    required this.port,
    this.sniOrHost,
    this.isDeletable = true,
    this.isPinned = false,
    this.nameOverride,
    this.tls = TlsOptions.empty,
    this.dns,
    this.ping,
    this.jitter,
    this.pingKind = PingKind.none,
    this.speedKbps,
    this.status = ServerStatus.idle,
  }) : name = sanitizeServerName(name);

  /// true اگر این سرور از نوع Aether (سیستم دور زدن فیلترینگ با اسکن خودکار) باشد.
  bool get isAether => protocol == VpnProtocol.aether;
  bool get isPsiphon => protocol == VpnProtocol.psiphon;

  /// پروتکل‌هایی که روی UDP/QUIC کار می‌کنند؛ TCP-connect روی آن‌ها بی‌معناست.
  bool get usesUdpTransport => protocol == VpnProtocol.hysteria2;

  /// نام نهایی برای نمایش (شامل override کاربر).
  String get displayName => sanitizeServerName(
        (nameOverride == null || nameOverride!.isEmpty)
            ? name
            : nameOverride!,
      );

  /// کپی با فیلدهای اختیاری جدید (فیلدهای final را نمی‌شود مستقیم عوض کرد).
  VpnServer copyWith({
    String? name,
    String? flag,
    String? shareLink,
    String? host,
    int? port,
    String? nameOverride,
    bool? isPinned,
    TlsOptions? tls,
    String? dns,
  }) =>
      VpnServer(
        id: id,
        name: name ?? this.name,
        flag: flag ?? this.flag,
        shareLink: shareLink ?? this.shareLink,
        protocol: protocol,
        host: host ?? this.host,
        port: port ?? this.port,
        sniOrHost: sniOrHost,
        isDeletable: isDeletable,
        isPinned: isPinned ?? this.isPinned,
        nameOverride: nameOverride ?? this.nameOverride,
        tls: tls ?? this.tls,
        dns: dns ?? this.dns,
      );

  /// پاک‌کردن نتیجه‌ی تست قبلی.
  void resetPing() {
    ping = null;
    jitter = null;
    pingKind = PingKind.none;
    status = ServerStatus.idle;
  }
}

