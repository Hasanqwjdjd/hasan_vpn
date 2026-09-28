import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// MTU probe — کاربردی، بدون root.
///
/// منطق از BackPack internal/tunnel/l3/mtuprobe.go گرفته شده: binary search
/// برای پیدا کردن بزرگترین بسته‌ای که مسیر عبور می‌دهد. آنجا داخل تونل خود
/// BackPack اندازه می‌گیرد؛ اینجا از مسیر کاربر به یک DNS عمومی.
///
/// روش:
///   1. یه DNS query استاندارد A (type 1) برای یه دامنه ساخته می‌شه
///   2. با یه پدینگ تا اندازه هدف پد می‌شه (بایتها صفر بعد EDNS)
///   3. UDP به 1.1.1.1:53 (یا fallback) فرستاده می‌شه
///   4. اگه جواب اومد → مسیر تحمل می‌کند؛ اگه نه → خیلی بزرگه
///   5. binary search بین حد پایین (512) و بالا (1472)
///
/// هیچ root یا config سرور لازم نیست. فقط یه UDP socket از Dart.
class MtuProbe {
  MtuProbe._();

  /// حداقل و حداکثر اندازه‌ی payload برای probe.
  /// کمتر از 512 = بی‌معنی، بیشتر از 1472 = قطعاً fragment می‌شود.
  static const int minPayload = 512;
  static const int maxPayload = 1472;

  /// سرورهای DNS که probe به آن‌ها می‌رود. اولین که جواب دهد برنده.
  static const List<String> probeServers = <String>[
    '1.1.1.1',
    '8.8.8.8',
    '9.9.9.9',
  ];

  /// پورت probe.
  static const int probePort = 53;

  /// timeout هر probe.
  static const Duration probeTimeout = Duration(seconds: 2);

  /// تعداد تلاش در هر اندازه (برای اینکه یه lost datagram اشتباه تفسیر نشه).
  static const int probeAttempts = 2;

  /// کلید ذخیره‌سازی per-server.
  static const String _prefPrefix = 'mtu_probe_';

  /// MTU نهایی — payload + 28 (20 IPv4 + 8 UDP).
  static int mtuFromPayload(int payload) => payload + 28;

  /// MSS توصیه‌شده — MTU - 40.
  static int mssFromMtu(int mtu) {
    final mss = mtu - 40;
    if (mss < 524) return 524;
    if (mss > 1460) return 1460;
    return mss;
  }

  /// یه DNS query A استاندارد می‌سازد به اندازه‌ی targetPayload.
  static Uint8List _buildQuery(int targetPayload) {
    const header = <int>[
      0x12, 0x34, // ID
      0x01, 0x00, // flags: RD
      0x00, 0x01, // qdcount
      0x00, 0x00, // ancount
      0x00, 0x00, // nscount
      0x00, 0x00, // arcount
    ];
    const label = <int>[
      0x0a, 0x63, 0x6c, 0x6f, 0x75, 0x64, 0x66, 0x6c, 0x61, 0x72, 0x65, // "cloudflare"
      0x03, 0x63, 0x6f, 0x6d, // "com"
      0x00, // root
      0x00, 0x01, // type A
      0x00, 0x01, // class IN
    ];
    final fixed = header.length + label.length;
    if (targetPayload < fixed) return Uint8List.fromList([...header, ...label]);
    final out = Uint8List(targetPayload);
    out.setRange(0, header.length, header);
    out.setRange(header.length, header.length + label.length, label);
    // بقیه صفر — گرچه سرور ممکنه query malformed ببینه، ولی برای probe
    // اندازه مهمه نه معنی. پاسخ still may come back or get dropped.
    return out;
  }

  /// یه probe در اندازه‌ی مشخص به یه سرور.
  static Future<bool> _probeOnce(String server, int targetPayload) async {
    RawDatagramSocket? sock;
    try {
      sock = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0)
          .timeout(probeTimeout);
      final data = _buildQuery(targetPayload);
      final addr = InternetAddress(server);
      sock.send(data, addr, probePort);
      final completer = Completer<bool>();
      late StreamSubscription sub;
      sub = sock.listen((event) {
        if (event == RawSocketEvent.read) {
          final dg = sock!.receive();
          if (dg != null && !completer.isCompleted) {
            completer.complete(true);
          }
        }
      });
      final result = await completer.future.timeout(
        probeTimeout,
        onTimeout: () => false,
      );
      await sub.cancel();
      sock.close();
      return result;
    } catch (e) {
      debugPrint('MtuProbe._probeOnce($server, $targetPayload): $e');
      try {
        sock?.close();
      } catch (_) {}
      return false;
    }
  }

  /// با تلاش چندباره — یه بار lost datagram یعنی success نیست.
  static Future<bool> _probeWithRetry(String server, int targetPayload) async {
    for (var i = 0; i < probeAttempts; i++) {
      if (await _probeOnce(server, targetPayload)) return true;
    }
    return false;
  }

  /// binary search + return MTU نهایی.
  ///
  /// برمی‌گرداند: MTU نهایی یا null اگر حتی کوچک‌ترین probe جواب نداد.
  static Future<int?> probePath({
    void Function(int current)? onProgress,
  }) async {
    String? live;
    for (final s in probeServers) {
      if (await _probeWithRetry(s, minPayload)) {
        live = s;
        break;
      }
    }
    if (live == null) {
      debugPrint('MtuProbe: no DNS server answered min-payload probe');
      return null;
    }
    debugPrint('MtuProbe: using $live');

    // ceiling — اول امتحان کن
    if (await _probeWithRetry(live, maxPayload)) {
      onProgress?.call(maxPayload);
      return mtuFromPayload(maxPayload);
    }

    var best = minPayload;
    var lo = minPayload + 1;
    var hi = maxPayload - 1;
    while (lo <= hi) {
      final mid = (lo + hi) ~/ 2;
      onProgress?.call(mid);
      if (await _probeWithRetry(live, mid)) {
        best = mid;
        lo = mid + 1;
      } else {
        hi = mid - 1;
      }
    }
    return mtuFromPayload(best);
  }

  /// ذخیره‌ی نتیجه per-server.
  static Future<void> save(String serverId, int mtu) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('$_prefPrefix$serverId', mtu);
  }

  /// خوندن نتیجه‌ی ذخیره‌شده.
  static Future<int?> load(String serverId) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt('$_prefPrefix$serverId');
  }

  /// حذف نتیجه.
  static Future<void> clear(String serverId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('$_prefPrefix$serverId');
  }
}
