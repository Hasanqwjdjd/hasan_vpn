import 'dart:async';
import 'dart:collection';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../models/server.dart';
import 'socks_probe.dart';
import 'v2ray_engine.dart';

/// توکن لغو برای یک دور تست.
class TestSession {
  bool _cancelled = false;
  bool get cancelled => _cancelled;
  void cancel() => _cancelled = true;
}

class TestSummary {
  int total = 0;
  int online = 0;
  int offline = 0;
  int unknown = 0;

  /// true اگر هسته‌ی برنامه «پینگ واقعی» را پشتیبانی نکرد.
  bool realUnavailable = false;
}

class _Semaphore {
  _Semaphore(this.max);
  final int max;
  int _current = 0;
  final Queue<Completer<void>> _waiters = Queue<Completer<void>>();

  Future<void> acquire() {
    if (_current < max) {
      _current++;
      return Future<void>.value();
    }
    final completer = Completer<void>();
    _waiters.add(completer);
    return completer.future;
  }

  void release() {
    if (_waiters.isNotEmpty) {
      _waiters.removeFirst().complete();
    } else {
      _current--;
    }
  }
}

/// بخش ۷ — سیستم تست و رتبه‌بندی با مقادیر هاردکد:
///
/// صفحه «تنظیمات تست و رتبه‌بندی» حذف شده است؛ این مقادیر ثابت و
/// غیرقابل‌تغییرند تا رتبه‌بندی سرورها همیشه قابل مقایسه باشد:
///
///   • TCP Ping:  تایم‌اوت ۱.۵ ثانیه، هم‌زمانی ۶۴
///   • Real Ping: تایم‌اوت ۴ ثانیه، هم‌زمانی ۸، آدرس
///     https://www.gstatic.com/generate_204 (در v2ray_engine.loadDelayUrl)
///   • منطق: ابتدا همه‌ی سرورها TCP می‌شوند (موازی)، هر کدام جواب دادند
///     تست واقعی می‌شوند و در نهایت لیست بر اساس کمترین پینگ مرتب می‌شود.
///
/// سرورهای لوکال (127.0.0.1 / localhost) تست نمی‌شوند — پینگ آن‌ها N/A است.
class ServerTester {
  ServerTester._();

  /// بخش ۷ — TCP ping timeout: ۱.۵ ثانیه (هاردکد).
  static const int _tcpTimeoutMs = 1500;
  /// بخش ۷ — هم‌زمانی فاز TCP: ۶۴ (هاردکد).
  static const int _tcpConcurrency = 64;
  /// بخش ۷ — تایم‌اوت Real Ping: ۴ ثانیه (هاردکد).
  static const int _realTimeoutSec = 4;
  /// بخش ۷ — هم‌زمانی فاز Real: ۸ (هاردکد).
  static const int _realConcurrency = 8;
  /// تعداد نمونه‌ی Real برای median (MarbleNG PingBudget).
  static const int _realSamples = 3;
  /// فاصله‌ی نمونه‌ها (MarbleNG SAMPLE_SPACING_MS).
  static const int _sampleSpacingMs = 60;
  /// بعد از ۲ شکست متوالی اولیه، Real را رها کن.
  static const int _consecutiveFailuresBeforeAbandon = 2;

  static Future<TestSummary> testAll(
    List<VpnServer> servers, {
    required TestSession session,
    void Function(VpnServer server)? onServerDone,
    void Function()? onChanged,
    bool onlyTcp = false,
  }) async {
    await V2RayEngine.loadDelayUrl();

    final regular = servers
        .where((s) => !s.isPsiphon && !s.isLocal)
        .toList();
    final summary = TestSummary()..total = regular.length;

    final skippedLocal = servers.where((s) => s.isLocal && !s.isPsiphon).length;
    if (skippedLocal > 0) {
      debugPrint('[ServerTester] skipped $skippedLocal local (127.0.0.1) server(s) — ping N/A');
    }

    Timer? throttle;
    var dirty = false;
    void notify() {
      if (session.cancelled) return;
      dirty = true;
      if (throttle != null) return;
      throttle = Timer(const Duration(milliseconds: 120), () {
        throttle = null;
        if (dirty && !session.cancelled) {
          dirty = false;
          onChanged?.call();
        }
      });
    }

    // ═══ فاز ۱: TCP برای همه — موازی با هم‌زمانی ۶۴ ═══
    debugPrint('[ServerTester] phase 1/2: TCP ping — n=${regular.length} '
        'timeout=${_tcpTimeoutMs}ms concurrency=$_tcpConcurrency');
    final tcpGate = _Semaphore(_tcpConcurrency);
    final responders = <VpnServer>[];

    await Future.wait(<Future<void>>[
      for (final server in regular) _tcpPhase(server, session, tcpGate, responders, notify),
    ]);
    if (session.cancelled) {
      throttle?.cancel();
      return summary;
    }
    debugPrint('[ServerTester] phase 1 done — responders=${responders.length}');

    // ═══ فاز ۲: تست واقعی برای همه‌ی پاسخ‌دهنده‌ها ═══
    if (!onlyTcp && responders.isNotEmpty) {
      debugPrint('[ServerTester] phase 2/2: real ping — n=${responders.length} '
          'timeout=${_realTimeoutSec}s concurrency=$_realConcurrency '
          'url=${V2RayEngine.delayUrl}');
      final realGate = _Semaphore(_realConcurrency);
      await Future.wait(<Future<void>>[
        for (final server in responders)
          _realPhase(server, session, realGate, summary, notify),
      ]);
      debugPrint('[ServerTester] phase 2 done — online=${summary.online} '
          'tcpOnly=${summary.unknown} offline=${summary.offline}');
    } else {
      // فقط TCP — کسانی که جواب دادند «نامشخص» حساب می‌شوند.
      for (final server in responders) {
        summary.unknown++;
        onServerDone?.call(server);
      }
      debugPrint('[ServerTester] tcp-only mode — responders=${responders.length}');
    }

    throttle?.cancel();
    if (!session.cancelled) onChanged?.call();
    return summary;
  }

  /// فاز ۱: TCP ping یک سرور. اگر جواب داد به [responders] اضافه می‌شود.
  static Future<void> _tcpPhase(
    VpnServer server,
    TestSession session,
    _Semaphore tcpGate,
    List<VpnServer> responders,
    void Function() notify,
  ) async {
    await tcpGate.acquire();
    try {
      if (session.cancelled) return;
      final tcp = await _tcpConnectMs(server);
      if (session.cancelled) return;
      if (tcp > 0) {
        server.ping = tcp;
        server.jitter = null;
        server.pingKind = PingKind.tcp;
        server.status = ServerStatus.idle;
        responders.add(server);
      } else {
        server.ping = null;
        server.jitter = null;
        server.pingKind = PingKind.none;
        server.status = ServerStatus.offline;
      }
      notify();
    } finally {
      tcpGate.release();
    }
  }

  /// فاز ۲: real HTTP برای سرورهای پاسخ‌دهنده.
  /// اگر real fail شد، مقدار TCP از فاز ۱ نگه داشته می‌شود.
  static Future<void> _realPhase(
    VpnServer server,
    TestSession session,
    _Semaphore gate,
    TestSummary summary,
    void Function() notify,
  ) async {
    await gate.acquire();
    try {
      if (session.cancelled) return;
      server.status = ServerStatus.testing;
      notify();

      final (ms, jitter) = await _measureReal(server, session);
      if (session.cancelled) return;
      if (ms > 0) {
        server.ping = ms;
        server.jitter = jitter;
        server.pingKind = PingKind.real;
        server.status = ServerStatus.online;
        summary.online++;
      } else {
        // مقدار TCP از فاز ۱ حفظ می‌شود — فقط وضعیت «نامشخص».
        if (server.ping != null && server.ping! > 0) {
          server.pingKind = PingKind.tcp;
          server.jitter = null;
          server.status = ServerStatus.idle;
          summary.unknown++;
        } else {
          server.ping = null;
          server.jitter = null;
          server.pingKind = PingKind.none;
          server.status = ServerStatus.offline;
          summary.offline++;
        }
      }
      notify();
    } finally {
      gate.release();
    }
  }

  static Future<TestSummary> testOne(
    VpnServer server, {
    required TestSession session,
    void Function()? onChanged,
    bool onlyTcp = false,
  }) async {
    // FIX: همه‌ی مسیرهای پینگ (⚡ لایتنینگ، 3-نقطه «پینگ»، پینگ خودکار
    // بعد از import) باید از *همون* pipeline پینگ از همه رد بشن. پس
    // testOne رو به testAll با یه لیست تک‌عضوی route می‌کنیم.
    return testAll(
      <VpnServer>[server],
      session: session,
      onChanged: onChanged,
      onlyTcp: onlyTcp,
    );
  }

  /// MarbleNG RouteProbe.summarize: median; warm-up dropped only when samples >= 3
  static (int, int?) _summarize(List<int> values, {required bool dropWarmup}) {
    if (values.isEmpty) return (-1, null);
    var used = List<int>.from(values);
    if (dropWarmup && used.length >= 3) used = used.sublist(1);
    used.sort();
    final mid = used.length ~/ 2;
    final ms =
        used.length.isOdd ? used[mid] : (used[mid - 1] + used[mid]) ~/ 2;
    final jitter = used.length >= 2 ? used.last - used.first : null;
    return (ms < 1 ? 1 : ms, jitter);
  }

  static bool _tcpEligible(VpnServer server) {
    if (server.isPsiphon) return false;
    // بخش ۸ — سرورهای لوکال (127.0.0.1) هرگز TCP ping نمی‌گیرند.
    if (server.isLocal) return false;
    if (server.usesUdpTransport) return false;
    if (server.host.isEmpty || server.port <= 0) return false;
    if (server.host == 'serverless') return false;
    return true;
  }

  static Future<int> _tcpConnectMs(VpnServer server) async {
    if (!_tcpEligible(server)) return -1;
    final watch = Stopwatch()..start();
    try {
      final socket = await Socket.connect(
        server.host,
        server.port,
        timeout: const Duration(milliseconds: _tcpTimeoutMs),
      );
      watch.stop();
      socket.destroy();
      final ms = watch.elapsedMilliseconds;
      return ms < 1 ? 1 : ms;
    } catch (_) {
      return -1;
    }
  }

  /// Real delay: هر نمونه تایم‌اوت کامل خودش را دارد (بخش ۷: ۴ ثانیه)،
  /// فاصله‌ی ۶۰ms بین نمونه‌ها، abandon بعد از ۲ شکست متوالی، median با
  /// حذف warm-up وقتی نمونه‌ها >= 3.
  static Future<(int, int?)> _measureReal(
    VpnServer server,
    TestSession session,
  ) async {
    final timeout = const Duration(seconds: _realTimeoutSec);
    final values = <int>[];
    var consecutiveFailures = 0;

    for (var i = 0; i < _realSamples; i++) {
      if (session.cancelled) break;
      if (i > 0) {
        await Future<void>.delayed(const Duration(milliseconds: _sampleSpacingMs));
      }
      int result;
      if (V2RayEngine.isConnected &&
          V2RayEngine.localSocksPort > 0 &&
          V2RayEngine.current?.id == server.id) {
        // One sample per loop iteration (session reuse is inside SocksProbe when samples=1).
        final probe = await SocksProbe.measure(
          port: V2RayEngine.localSocksPort,
          samples: 1,
          timeout: timeout,
        );
        result = probe.ok ? (probe.ms ?? -1) : -1;
        if (probe.jitter != null) server.jitter = probe.jitter;
      } else {
        result = await V2RayEngine.realDelay(server, timeout: timeout);
      }
      if (result == -2) return (-2, null);
      if (result > 0) {
        values.add(result);
        consecutiveFailures = 0;
      } else {
        consecutiveFailures++;
        if (values.isEmpty &&
            consecutiveFailures >= _consecutiveFailuresBeforeAbandon) {
          break;
        }
        if (values.isEmpty) break;
      }
    }
    return _summarize(values, dropWarmup: _realSamples >= 3);
  }

  /// امتیاز رتبه‌بندی برای انتخاب «بهترین سرور» (fastest) — ترکیب پینگ و
  /// نوسان. رتبه‌بندیِ لیست (sortServers) مستقیم بر اساس پینگ صعودی است.
  static double scoreOf(VpnServer s) {
    if (s.status != ServerStatus.online || s.ping == null) return -1;

    final ping = s.ping!.clamp(1, 10000);
    var score = 10000.0 / ping;

    final j = s.jitter;
    if (j != null && j > 0) {
      score *= (1.0 / (1.0 + j / 200.0));
    }

    if (ping < 200) score *= 1.25;
    if (ping < 100) score *= 1.15;

    return score;
  }

  /// بخش ۷ — مرتب‌سازی نهایی: سنجاق‌شده‌ها اول، سپس کمترین پینگ (صعودی).
  /// سرورهای بدون پینگ در انتها قرار می‌گیرند؛ ترتیب آن‌ها حفظ می‌شود.
  static void sortServers(List<VpnServer> servers, {bool descending = false}) {
    final order = <VpnServer, int>{
      for (var i = 0; i < servers.length; i++) servers[i]: i,
    };

    servers.sort((a, b) {
      if (a.isPinned != b.isPinned) return a.isPinned ? -1 : 1;

      final pa = (a.ping != null && a.ping! > 0) ? a.ping! : null;
      final pb = (b.ping != null && b.ping! > 0) ? b.ping! : null;
      if (pa != null && pb != null) {
        final cmp = pa.compareTo(pb);
        if (cmp != 0) return descending ? -cmp : cmp;
      } else if (pa != null) {
        return -1;
      } else if (pb != null) {
        return 1;
      }

      return order[a]!.compareTo(order[b]!);
    });
  }

  static VpnServer? fastest(List<VpnServer> servers) {
    VpnServer? best;
    double bestScore = -1;
    for (final server in servers) {
      // FIX: ssh/tunnel نمی‌تونن از مسیر Connect/auto-fastest وصل شن —
      // session سرویس اختصاصی لازم دارن. اگه انتخاب شن، کاربر پیام
      // «روی سرور ضربه بزن» می‌گیره و اتصال خودکار شکست می‌خوره.
      if (server.protocol == VpnProtocol.ssh ||
          server.protocol == VpnProtocol.tunnel) {
        continue;
      }
      final s = scoreOf(server);
      if (s < 0) continue;
      if (best == null || s > bestScore) {
        best = server;
        bestScore = s;
      }
    }
    return best;
  }

  static Map<String, int> rankAll(List<VpnServer> servers) {
    final ranked = List<VpnServer>.from(servers)
      ..sort((a, b) {
        final sa = scoreOf(a);
        final sb = scoreOf(b);
        if (sa < 0 && sb < 0) return 0;
        if (sa < 0) return 1;
        if (sb < 0) return -1;
        return sb.compareTo(sa);
      });

    final result = <String, int>{};
    var rank = 1;
    for (final s in ranked) {
      if (scoreOf(s) < 0) {
        result[s.id] = 0;
      } else {
        result[s.id] = rank++;
      }
    }
    return result;
  }
}
