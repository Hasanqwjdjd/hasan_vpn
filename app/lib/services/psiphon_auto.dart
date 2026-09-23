import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// ترکیب «SponsorId + PropagationChannelId (+ کلیدهای اضافه)».
class PsiphonProfile {
  final String id;
  final String sponsorId;
  final String channelId;

  /// کلیدهای اضافه‌ی کانفیگ که فقط برای همین پروفایل لازم است.
  final Map<String, dynamic> extra;

  const PsiphonProfile({
    required this.id,
    required this.sponsorId,
    required this.channelId,
    this.extra = const <String, dynamic>{},
  });
}

/// یک تلاش اتصال: کانفیگ آماده + مهلت.
class PsiphonAttempt {
  final String label;
  final String profileId;
  final String mode; // 'auto' | 'stealth' | 'narrow' | 'region'
  final String configJson;
  final int timeoutSec;

  const PsiphonAttempt({
    required this.label,
    required this.profileId,
    required this.mode,
    required this.configJson,
    required this.timeoutSec,
  });
}

/// حالت «خودکار» سایفون: برنامه خودش SponsorId، کانال، مجموعهٔ پروتکل و
/// (اختیاری) کشور را انتخاب می‌کند و کانفیگ را می‌سازد.
///
/// روش کار:
///  ۱) چند پروفایل آماده (SponsorId/Channel) داریم.
///  ۲) برای هر پروفایل چند حالت: همهٔ پروتکل‌ها، مخفی‌کار، فقط SSH/OSSH، فقط meek.
///  ۳) تلاش‌ها به ترتیب امتحان می‌شوند؛ آخرین ترکیبِ موفق ذخیره می‌شود و
///     دفعهٔ بعد اول همان امتحان می‌شود.
///  ۴) چند منطقه و timeout مختلف برای افزایش شانس روی WiFi.
class PsiphonAuto {
  PsiphonAuto._();

  static const String clientPlatform = 'Android_4.0.4_com.hasan.hasan_vpn';

  static const String remoteServerListUrl =
      'https://s3.amazonaws.com//psiphon/web/mjr4-p23r-puwl/server_list_compressed';

  static const String remoteServerListSigKey =
      'MIICIDANBgkqhkiG9w0BAQEFAAOCAg0AMIICCAKCAgEAt7Ls+/39r+T6zNW7GiVpJfzq/'
      'xvL9SBH5rIFnk0RXYEYavax3WS6HOD35eTAqn8AniOwiH+DOkvgSKF2caqk/y1dfq47P'
      'dymtwzp9ikpB1C5OfAysXzBiwVJlCdajBKvBZDerV1cMvRzCKvKwRmvDmHgphQQ7WfXI'
      'GbRbmmk6opMBh3roE42KcotLFtqp0RRwLtcBRNtCdsrVsjiI1Lqz/lH+T61sGjSjQ3CH'
      'MuZYSQJZo/KrvzgQXpkaCTdbObxHqb6/+i1qaVOfEsvjoiyzTxJADvSytVtcTjijhPEV'
      '6XskJVHE1Zgl+7rATr/pDQkw6DPCNBS1+Y6fy7GstZALQXwEDN/qhQI9kWkHijT8ns+i'
      '1vGg00Mk/6J75arLhqcodWsdeG/M/moWgqQAnlZAGVtJI1OgeF5fsPpXu4kctOfuZlGj'
      'VZXQNW34aOzm8r8S0eVZitPlbhcPiR4gT/aSMz/wd8lZlzZYsje/Jr8u/YtlwjjreZrG'
      'RmG8KMOzukV3lLmMppXFMvl4bxv6YFEmIuTsOhbLTwFgh7KYNjodLj/LsqRVfwz31PgW'
      'QFTEPICV7GCvgVlPRxnofqKSjgTWI4mxDhBpVcATvaoBl1L/6WLbFvBsoAUBItWwctO2'
      'xalKxF5szhGm8lccoc5MZr8kfE0uxMgsxz4er68iCID+rsCAQM=';

  /// پروفایل‌ها به ترتیب اولویت پیش‌فرض.
  static const List<PsiphonProfile> profiles = <PsiphonProfile>[
    // تست رسمی
    PsiphonProfile(
      id: 'test',
      sponsorId: '0000000000000000',
      channelId: '0000000000000000',
    ),
    // oblivion / bepass style
    PsiphonProfile(
      id: 'oblivion',
      sponsorId: 'FFFFFFFFFFFFFFFF',
      channelId: 'FFFFFFFFFFFFFFFF',
    ),
    // aether style
    PsiphonProfile(
      id: 'aether',
      sponsorId: '1111111111111111',
      channelId: 'FFFFFFFFFFFFFFFF',
      extra: <String, dynamic>{
        'ServerEntrySignaturePublicKey':
            'sHuUVTWaRyh5pZwy4UguSgkwmBe0EHtJJkoF5WrxmvA=',
        'ExchangeObfuscationKey':
            'DpXzloJk1Hw6aSzmKKky0xcahsEHubch81Mi6K0XMlU=',
      },
    ),
    // alternate common values
    PsiphonProfile(
      id: 'alt1',
      sponsorId: '0000000000000001',
      channelId: '0000000000000001',
    ),
  ];

  /// پروتکل‌های مناسب فیلتر سخت (نام‌ها از خود کتابخانهٔ Psiphon).
  static const List<String> stealthProtocols = <String>[
    'FRONTED-MEEK-OSSH',
    'FRONTED-MEEK-HTTP-OSSH',
    'UNFRONTED-MEEK-HTTPS-OSSH',
    'UNFRONTED-MEEK-SESSION-TICKET-OSSH',
  ];

  static const List<String> sshOnly = <String>['SSH', 'OSSH'];
  static const List<String> meekOnly = <String>[
    'FRONTED-MEEK-OSSH',
    'FRONTED-MEEK-HTTP-OSSH',
  ];
  static const List<String> quicOnly = <String>['QUICv1'];

  static const String _lastOkKey = 'psiphon_auto_last_ok_v1';
  static const String _regionsKey = 'psiphon_regions_cache_v1';

  // --------------------------------------------------------- ساخت کانفیگ

  /// مپ کانفیگ برای یک پروفایل. [region] خالی = خودکار (سریع‌ترین).
  static Map<String, dynamic> buildConfig(
    PsiphonProfile profile, {
    String region = '',
    List<String>? limitProtocols,
    int establishTimeoutSec = 60,
    int workerPool = 8,
    bool disableHttpProxy = true,
    int localSocksPort = 0,
    String? networkId,
    bool emptyRemoteList = false,
  }) {
    final map = <String, dynamic>{
      'SponsorId': profile.sponsorId,
      'PropagationChannelId': profile.channelId,
      'ClientPlatform': clientPlatform,
      'ClientVersion': '1',
      'LocalSocksProxyPort': localSocksPort,
      'LocalHttpProxyPort': 0,
      'DisableLocalHTTPProxy': disableHttpProxy,
      'EgressRegion': normalizeRegion(region),
      'ConnectionWorkerPoolSize': workerPool,
      'EstablishTunnelTimeoutSeconds': establishTimeoutSec,
      'AllowDefaultDNSResolverWithBindToDevice': true,
    };
    if (networkId != null && networkId.isNotEmpty) {
      map['NetworkID'] = networkId;
    } else {
      map['NetworkID'] = 'hasan_vpn';
    }
    if (!emptyRemoteList) {
      map['RemoteServerListUrl'] = remoteServerListUrl;
      map['RemoteServerListSignaturePublicKey'] = remoteServerListSigKey;
      map['RemoteServerListDownloadFilename'] = 'remote_server_list';
    }
    map.addAll(profile.extra);
    if (limitProtocols != null && limitProtocols.isNotEmpty) {
      map['LimitTunnelProtocols'] = limitProtocols;
    }
    return map;
  }

  /// فهرست تلاش‌ها برای حالت خودکار (به ترتیب امتحان).
  /// Expanded: more protocols, regions, timeouts, worker sizes for WiFi reliability.
  static Future<List<PsiphonAttempt>> attempts({String region = ''}) async {
    final reg = normalizeRegion(region);
    final out = <PsiphonAttempt>[];

    void add(
      PsiphonProfile p,
      String mode,
      String label, {
      List<String>? protocols,
      int timeout = 50,
      String r = '',
      int workers = 8,
      bool emptyRemote = false,
    }) {
      final cfg = buildConfig(
        p,
        region: r.isEmpty ? reg : r,
        limitProtocols: protocols,
        establishTimeoutSec: timeout,
        workerPool: workers,
        emptyRemoteList: emptyRemote,
      );
      out.add(PsiphonAttempt(
        label: label,
        profileId: p.id,
        mode: mode,
        configJson: jsonEncode(cfg),
        timeoutSec: timeout + 15,
      ));
    }

    // Prefer last successful first.
    final last = await _loadLastOk();
    final preferredProfile = last != null
        ? profiles.cast<PsiphonProfile?>().firstWhere(
              (p) => p!.id == last[0],
              orElse: () => null,
            )
        : null;

    final ordered = <PsiphonProfile>[
      if (preferredProfile != null) preferredProfile,
      ...profiles.where((p) => p.id != preferredProfile?.id),
    ];

    // 1) Preferred / first profile, auto + stealth with user region
    for (final p in ordered.take(2)) {
      add(p, 'auto', '${p.id}·auto', timeout: 45);
      add(p, 'stealth', '${p.id}·stealth', protocols: stealthProtocols, timeout: 55);
    }

    // 2) Specific regions on first two profiles (WiFi often works with DE/NL/US)
    const tryRegions = ['DE', 'NL', 'US', 'GB', 'JP', 'CA'];
    for (final p in ordered.take(2)) {
      for (final rr in tryRegions) {
        if (reg == rr) continue;
        add(p, 'region', '${p.id}·$rr', r: rr, timeout: 50);
      }
    }

    // 3) Narrow protocol sets
    for (final p in ordered.take(2)) {
      add(p, 'narrow', '${p.id}·ssh', protocols: sshOnly, timeout: 40, workers: 4);
      add(p, 'narrow', '${p.id}·meek', protocols: meekOnly, timeout: 60, workers: 4);
      add(p, 'narrow', '${p.id}·quic', protocols: quicOnly, timeout: 40, workers: 4);
    }

    // 4) Longer timeout + different workers
    for (final p in ordered.take(1)) {
      add(p, 'auto', '${p.id}·long', timeout: 120, workers: 4);
      add(p, 'auto', '${p.id}·pool1', timeout: 60, workers: 1);
      add(p, 'auto', '${p.id}·pool16', timeout: 45, workers: 16);
    }

    // 5) Empty remote list (force SDK download / use any embedded)
    for (final p in ordered.take(1)) {
      add(p, 'auto', '${p.id}·no-remote', timeout: 90, emptyRemote: true);
    }

    // Re-order so last success is first if present.
    if (last != null) {
      final idx = out.indexWhere((a) => a.profileId == last[0] && a.mode == last[1]);
      if (idx > 0) {
        final a = out.removeAt(idx);
        out.insert(0, a);
      }
    }

    return out;
  }

  // --------------------------------------------------------- ذخیره‌سازی

  static Future<List<String>?> _loadLastOk() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_lastOkKey);
      if (raw == null) return null;
      final parts = raw.split('|');
      if (parts.length != 2) return null;
      return parts;
    } catch (_) {
      return null;
    }
  }

  static Future<void> rememberSuccess(PsiphonAttempt a) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_lastOkKey, '${a.profileId}|${a.mode}');
    } catch (_) {}
  }

  // --------------------------------------------------------- کشورها

  /// فهرست پیش‌فرض تا وقتی هسته فهرست واقعی را نداده.
  static const List<String> fallbackRegions = <String>[
    'AT', 'BE', 'CA', 'CH', 'CZ', 'DE', 'DK', 'ES', 'FI', 'FR', 'GB', 'IE',
    'IN', 'IT', 'JP', 'NL', 'NO', 'PL', 'RO', 'SE', 'SG', 'US',
  ];

  static String normalizeRegion(String v) {
    final s = v.trim().toUpperCase();
    return RegExp(r'^[A-Z]{2}$').hasMatch(s) ? s : '';
  }

  /// کشورهایی که هستهٔ Psiphon خودش گزارش داده (اگر موجود باشد).
  static Future<List<String>> loadRegions() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final list = prefs.getStringList(_regionsKey);
      if (list != null && list.isNotEmpty) return list;
    } catch (_) {}
    return fallbackRegions;
  }

  static Future<void> cacheRegions(dynamic regions) async {
    if (regions is! List) return;
    final clean = regions
        .map((e) => normalizeRegion(e.toString()))
        .where((e) => e.isNotEmpty)
        .toSet()
        .toList()
      ..sort();
    if (clean.isEmpty) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_regionsKey, clean);
    } catch (_) {}
  }

  static const Map<String, String> _faNames = <String, String>{
    'AT': 'اتریش',
    'BE': 'بلژیک',
    'CA': 'کانادا',
    'CH': 'سوئیس',
    'CZ': 'چک',
    'DE': 'آلمان',
    'DK': 'دانمارک',
    'ES': 'اسپانیا',
    'FI': 'فنلاند',
    'FR': 'فرانسه',
    'GB': 'انگلیس',
    'IE': 'ایرلند',
    'IN': 'هند',
    'IT': 'ایتالیا',
    'JP': 'ژاپن',
    'NL': 'هلند',
    'NO': 'نروژ',
    'PL': 'لهستان',
    'RO': 'رومانی',
    'SE': 'سوئد',
    'SG': 'سنگاپور',
    'US': 'آمریکا',
  };

  static String flagEmoji(String cc) {
    final s = normalizeRegion(cc);
    if (s.isEmpty) return '🌐';
    return String.fromCharCodes(
      s.codeUnits.map((c) => 0x1F1E6 + (c - 0x41)),
    );
  }

  static String regionLabel(String cc, {required bool fa}) {
    final s = normalizeRegion(cc);
    if (s.isEmpty) return fa ? 'خودکار (سریع‌ترین)' : 'Auto (fastest)';
    final name = fa ? (_faNames[s] ?? s) : s;
    return '${flagEmoji(s)}  $name';
  }
}
