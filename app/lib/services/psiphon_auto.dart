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
  final String mode; // 'auto' | 'stealth' | 'narrow' | 'region' | 'mobile'
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

/// حالت «خودکار» سایفون — mobile-first.
///
/// شبکهٔ موبایل (Irancell/MCI) سخت‌تر از WiFi است ولی غیرممکن نیست.
/// هر پروتکل و SponsorId معقول را امتحان می‌کنیم؛ SkipServerEntry
/// (restricted provider) طبیعی است و فقط یعنی آن entry رد شده، نه کل شبکه.
class PsiphonAuto {
  PsiphonAuto._();

  static const String clientPlatform = 'Android_4.0.4_com.hasan.hasan_vpn';

  /// لیست رسمی Remote Server List (همیشه فعال — نه empty).
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

  /// پروفایل‌ها — SponsorIdهای رایج در کلاینت‌های متن‌باز + baseline رسمی.
  /// SkipServerEntry برای بعضی از این‌ها روی موبایل طبیعی است؛ بقیه را امتحان کن.
  static const List<PsiphonProfile> profiles = <PsiphonProfile>[
    PsiphonProfile(
      id: 'baseline',
      sponsorId: '0000000000000000',
      channelId: '0000000000000000',
    ),
    PsiphonProfile(
      id: 'oblivion',
      sponsorId: 'FFFFFFFFFFFFFFFF',
      channelId: 'FFFFFFFFFFFFFFFF',
    ),
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
    PsiphonProfile(
      id: 'alt1',
      sponsorId: '0000000000000001',
      channelId: '0000000000000001',
    ),
    // مقادیر رایج در فورک‌ها / تست‌ماتریس جامعه
    PsiphonProfile(
      id: 'alt2',
      sponsorId: 'AAAAAAAAAAAAAAAA',
      channelId: 'AAAAAAAAAAAAAAAA',
    ),
    PsiphonProfile(
      id: 'alt3',
      sponsorId: 'BBBBBBBBBBBBBBBB',
      channelId: 'BBBBBBBBBBBBBBBB',
    ),
    PsiphonProfile(
      id: 'alt4',
      sponsorId: 'CCCCCCCCCCCCCCCC',
      channelId: '0000000000000000',
    ),
    PsiphonProfile(
      id: 'psi_style',
      sponsorId: '1D090C0A999E4775',
      channelId: 'FFFFFFFFFFFFFFFF',
    ),
  ];

  /// پروتکل‌های معتبر در SupportedTunnelProtocols (psiphon-tunnel-core).
  /// FRONTED-MEEK-HTTPS-OSSH وجود ندارد — SDK فوری invalid می‌دهد (لاگ Irancell).
  static const List<String> stealthProtocols = <String>[
    'FRONTED-MEEK-OSSH',
    'FRONTED-MEEK-HTTP-OSSH',
    'UNFRONTED-MEEK-HTTPS-OSSH',
    'UNFRONTED-MEEK-SESSION-TICKET-OSSH',
    'UNFRONTED-MEEK-OSSH',
  ];

  static const List<String> sshOnly = <String>['SSH', 'OSSH'];
  static const List<String> osshOnly = <String>['OSSH'];
  static const List<String> meekOnly = <String>[
    'FRONTED-MEEK-OSSH',
    'FRONTED-MEEK-HTTP-OSSH',
  ];
  static const List<String> unfrontedMeek = <String>[
    'UNFRONTED-MEEK-HTTPS-OSSH',
    'UNFRONTED-MEEK-SESSION-TICKET-OSSH',
    'UNFRONTED-MEEK-OSSH',
  ];
  /// نام صحیح در SDK: QUIC-OSSH نه QUICv1
  static const List<String> quicOnly = <String>['QUIC-OSSH', 'FRONTED-MEEK-QUIC-OSSH'];

  static const String _lastOkKey = 'psiphon_auto_last_ok_v1';
  static const String _regionsKey = 'psiphon_regions_cache_v1';

  // --------------------------------------------------------- ساخت کانفیگ

  /// مپ کانفیگ. همیشه RemoteServerListUrl رسمی ست می‌شود مگر emptyRemoteList.
  static Map<String, dynamic> buildConfig(
    PsiphonProfile profile, {
    String region = '',
    List<String>? limitProtocols,
    int establishTimeoutSec = 90,
    int workerPool = 12,
    bool disableHttpProxy = true,
    int localSocksPort = 0,
    String? networkId,
    bool emptyRemoteList = false,
    String? platformOverride,
  }) {
    final map = <String, dynamic>{
      'SponsorId': profile.sponsorId,
      'PropagationChannelId': profile.channelId,
      'ClientPlatform': platformOverride ?? clientPlatform,
      'ClientVersion': '1',
      'LocalSocksProxyPort': localSocksPort,
      'LocalHttpProxyPort': 0,
      'DisableLocalHTTPProxy': disableHttpProxy,
      'EgressRegion': normalizeRegion(region),
      // موبایل: worker بیشتر برای جبران RTT بالا روی 4G
      'ConnectionWorkerPoolSize': workerPool,
      'EstablishTunnelTimeoutSeconds': establishTimeoutSec,
      'AllowDefaultDNSResolverWithBindToDevice': true,
    };
    if (networkId != null && networkId.isNotEmpty) {
      map['NetworkID'] = networkId;
    } else {
      map['NetworkID'] = 'hasan_vpn';
    }
    // همیشه لیست رسمی — embedded 427 entry ممکن است کهنه باشد.
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

  /// فهرست تلاش‌ها — mobile-first: meek/fronted اول، timeout تا ۱۲۰ثانیه،
  /// worker بالاتر، RemoteServerList همیشه روشن در مسیر اصلی.
  static Future<List<PsiphonAttempt>> attempts({String region = ''}) async {
    final reg = normalizeRegion(region);
    final out = <PsiphonAttempt>[];

    void add(
      PsiphonProfile p,
      String mode,
      String label, {
      List<String>? protocols,
      int timeout = 90,
      String r = '',
      int workers = 12,
      bool emptyRemote = false,
      int socksPort = 0,
      bool disableHttp = true,
      String? platform,
    }) {
      final cfg = buildConfig(
        p,
        region: r.isEmpty ? reg : r,
        limitProtocols: protocols,
        establishTimeoutSec: timeout,
        workerPool: workers,
        emptyRemoteList: emptyRemote,
        localSocksPort: socksPort,
        disableHttpProxy: disableHttp,
        platformOverride: platform,
      );
      out.add(PsiphonAttempt(
        label: label,
        profileId: p.id,
        mode: mode,
        configJson: jsonEncode(cfg),
        // Dart-side wait = establish + margin (شبکهٔ موبایل کند است)
        timeoutSec: timeout + 30,
      ));
    }

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

    // ─── 1) Meek/fronted اول — شبیه HTTPS، بهترین شانس روی 4G ایران ───
    for (final p in ordered.take(3)) {
      // همیشه اول یک پروتکل معتبر (نه نام ساختگی)
      add(p, 'mobile', '${p.id}·fronted-meek',
          protocols: const ['FRONTED-MEEK-OSSH'],
          timeout: 100,
          workers: 16);
      add(p, 'mobile', '${p.id}·meek-http',
          protocols: const ['FRONTED-MEEK-HTTP-OSSH'],
          timeout: 100,
          workers: 16);
      add(p, 'stealth', '${p.id}·stealth-all',
          protocols: stealthProtocols, timeout: 110, workers: 14);
    }

    // ─── 2) auto کامل با timeout بلند (Irancell کند است) ───
    for (final p in ordered.take(3)) {
      add(p, 'auto', '${p.id}·auto-long', timeout: 120, workers: 16);
      add(p, 'auto', '${p.id}·auto-mid', timeout: 90, workers: 12);
    }

    // ─── 3) مناطق پرتکرار روی موبایل ایران ───
    const tryRegions = ['DE', 'NL', 'US', 'GB', 'TR', 'AE', 'JP', 'CA'];
    for (final p in ordered.take(2)) {
      for (final rr in tryRegions) {
        if (reg == rr) continue;
        add(p, 'region', '${p.id}·$rr',
            r: rr, timeout: 100, workers: 12);
      }
    }

    // ─── 4) پروتکل‌های باریک ───
    for (final p in ordered.take(2)) {
      add(p, 'narrow', '${p.id}·unfronted-meek',
          protocols: unfrontedMeek, timeout: 100, workers: 10);
      add(p, 'narrow', '${p.id}·ossh',
          protocols: osshOnly, timeout: 90, workers: 10);
      add(p, 'narrow', '${p.id}·ssh',
          protocols: sshOnly, timeout: 80, workers: 8);
      add(p, 'narrow', '${p.id}·quic',
          protocols: quicOnly, timeout: 70, workers: 8);
    }

    // ─── 5) worker / platform alternate ───
    for (final p in ordered.take(2)) {
      add(p, 'auto', '${p.id}·pool24', timeout: 100, workers: 24);
      add(p, 'auto', '${p.id}·pool4', timeout: 120, workers: 4);
      add(p, 'auto', '${p.id}·http-on',
          timeout: 100, disableHttp: false, workers: 12);
      add(p, 'auto', '${p.id}·plat-psi',
          timeout: 100, platform: 'Android_11_com.psiphon3', workers: 12);
      add(p, 'auto', '${p.id}·plat-obv',
          timeout: 100,
          platform: 'Android_10_com.android.psiphon',
          workers: 12);
    }

    // ─── 6) فقط به‌عنوان آخرین راه: بدون remote list (embedded) ───
    for (final p in ordered.take(1)) {
      add(p, 'auto', '${p.id}·embedded-only',
          timeout: 120, emptyRemote: true, workers: 8);
    }

    if (last != null) {
      final idx =
          out.indexWhere((a) => a.profileId == last[0] && a.mode == last[1]);
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

  static const List<String> fallbackRegions = <String>[
    'AT', 'BE', 'CA', 'CH', 'CZ', 'DE', 'DK', 'ES', 'FI', 'FR', 'GB', 'IE',
    'IN', 'IT', 'JP', 'NL', 'NO', 'PL', 'RO', 'SE', 'SG', 'TR', 'AE', 'US',
  ];

  static String normalizeRegion(String v) {
    final s = v.trim().toUpperCase();
    return RegExp(r'^[A-Z]{2}$').hasMatch(s) ? s : '';
  }

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
    'TR': 'ترکیه',
    'AE': 'امارات',
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
