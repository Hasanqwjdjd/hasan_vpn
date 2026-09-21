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
  final String mode; // 'auto' | 'stealth'
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
///  ۲) برای هر پروفایل دو حالت داریم: «همهٔ پروتکل‌ها» و «مخفی‌کار»
///     (فقط مسیرهای meek/fronted که برای فیلتر سخت مناسب‌ترند).
///  ۳) تلاش‌ها به ترتیب امتحان می‌شوند؛ آخرین ترکیبِ موفق ذخیره می‌شود و
///     دفعهٔ بعد اول همان امتحان می‌شود.
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
  ///  - oblivion: مقادیر bepass-org/warp-plus (همان پیش‌فرض قبلی این برنامه)
  ///  - aether:   مقادیر AetherST
  static const List<PsiphonProfile> profiles = <PsiphonProfile>[
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
  ];

  /// پروتکل‌های مناسب فیلتر سخت (نام‌ها از خود کتابخانهٔ Psiphon).
  static const List<String> stealthProtocols = <String>[
    'FRONTED-MEEK-OSSH',
    'FRONTED-MEEK-HTTP-OSSH',
    'UNFRONTED-MEEK-HTTPS-OSSH',
    'UNFRONTED-MEEK-SESSION-TICKET-OSSH',
  ];

  static const String _lastOkKey = 'psiphon_auto_last_ok_v1';
  static const String _regionsKey = 'psiphon_regions_cache_v1';

  // --------------------------------------------------------- ساخت کانفیگ

  /// مپ کانفیگ برای یک پروفایل. [region] خالی = خودکار (سریع‌ترین).
  static Map<String, dynamic> buildConfig(
    PsiphonProfile profile, {
    String region = '',
    List<String>? limitProtocols,
    int establishTimeoutSec = 60,
  }) {
    final map = <String, dynamic>{
      'SponsorId': profile.sponsorId,
      'PropagationChannelId': profile.channelId,
      'RemoteServerListUrl': remoteServerListUrl,
      'RemoteServerListSignaturePublicKey': remoteServerListSigKey,
      'RemoteServerListDownloadFilename': 'remote_server_list',
      'ClientPlatform': clientPlatform,
      'ClientVersion': '1',
      'LocalSocksProxyPort': 0,
      'LocalHttpProxyPort': 0,
      'DisableLocalHTTPProxy': true,
      'EgressRegion': normalizeRegion(region),
      'ConnectionWorkerPoolSize': 8,
      'EstablishTunnelTimeoutSeconds': establishTimeoutSec,
      'NetworkID': 'hasan_vpn',
      'AllowDefaultDNSResolverWithBindToDevice': true,
    };
    map.addAll(profile.extra);
    if (limitProtocols != null && limitProtocols.isNotEmpty) {
      map['LimitTunnelProtocols'] = limitProtocols;
    }
    return map;
  }

  /// فهرست تلاش‌ها برای حالت خودکار (به ترتیب امتحان).
  static Future<List<PsiphonAttempt>> attempts({String region = ''}) async {
    final reg = normalizeRegion(region);
    final regLabel = reg.isEmpty ? '' : ' · $reg';

    final combos = <List<String>>[];
    for (final p in profiles) {
      combos.add(<String>[p.id, 'auto']);
      combos.add(<String>[p.id, 'stealth']);
    }

    // آخرین ترکیب موفق اول امتحان شود.
    final last = await _loadLastOk();
    if (last != null) {
      final idx = combos.indexWhere((c) => c[0] == last[0] && c[1] == last[1]);
      if (idx > 0) {
        final c = combos.removeAt(idx);
        combos.insert(0, c);
      }
    }

    final out = <PsiphonAttempt>[];
    for (final c in combos) {
      final profile = profiles.firstWhere((p) => p.id == c[0]);
      final stealth = c[1] == 'stealth';
      final timeout = stealth ? 55 : 40;
      final cfg = buildConfig(
        profile,
        region: reg,
        limitProtocols: stealth ? stealthProtocols : null,
        establishTimeoutSec: timeout,
      );
      out.add(PsiphonAttempt(
        label: '${stealth ? 'stealth' : 'auto'}$regLabel',
        profileId: profile.id,
        mode: c[1],
        configJson: jsonEncode(cfg),
        // کمی بیشتر از مهلت داخلی هسته، تا خود هسته اول تمام کند.
        timeoutSec: timeout + 10,
      ));
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
