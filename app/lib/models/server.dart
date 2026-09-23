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

  int? ping;
  int? jitter;
  PingKind pingKind;
  int? speedKbps;
  ServerStatus status;

  VpnServer({
    required this.id,
    required this.name,
    required this.flag,
    required this.shareLink,
    required this.protocol,
    required this.host,
    required this.port,
    this.sniOrHost,
    this.isDeletable = true,
    this.isPinned = false,
    this.nameOverride,
    this.ping,
    this.jitter,
    this.pingKind = PingKind.none,
    this.speedKbps,
    this.status = ServerStatus.idle,
  });

  /// true اگر این سرور از نوع Aether (سیستم دور زدن فیلترینگ با اسکن خودکار) باشد.
  bool get isAether => protocol == VpnProtocol.aether;
  bool get isPsiphon => protocol == VpnProtocol.psiphon;

  /// پروتکل‌هایی که روی UDP/QUIC کار می‌کنند؛ TCP-connect روی آن‌ها بی‌معناست.
  bool get usesUdpTransport => protocol == VpnProtocol.hysteria2;

  /// نام نهایی برای نمایش (شامل override کاربر).
  String get displayName => (nameOverride == null || nameOverride!.isEmpty)
      ? name
      : nameOverride!;

  /// کپی با فیلدهای اختیاری جدید (فیلدهای final را نمی‌شود مستقیم عوض کرد).
  VpnServer copyWith({
    String? name,
    String? flag,
    String? shareLink,
    String? host,
    int? port,
    String? nameOverride,
    bool? isPinned,
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
      );

  /// پاک‌کردن نتیجه‌ی تست قبلی.
  void resetPing() {
    ping = null;
    jitter = null;
    pingKind = PingKind.none;
    status = ServerStatus.idle;
  }
}

