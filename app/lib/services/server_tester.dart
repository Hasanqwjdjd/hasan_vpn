import 'dart:async';
import 'dart:collection';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../models/server.dart';
import 'aether_service.dart';
import 'socks_probe.dart';
import 'test_budget.dart';
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

/// سیستم تست و رتبه‌بندی — بخش ۲.۲: تنظیمات از صفحه «تست و رتبه‌بندی»
/// (TestBudget) خوانده می‌شود؛ مقادیر پیش‌فرض همان مقادیر سخت‌گیرانهٔ قبلی:
///
///   • TCP Ping:  تایم‌اوت ۱.۵ ثانیه، هم‌زمانی ۶۴
///   • Real Ping: تایم‌اوت ۴ ثانیه، هم‌زمانی ۸، ۳ نمونه، آدرس
///     https://www.gstatic.com/generate_204
///   • حالت‌ها: turbo (فقط TCP) / balanced (Real فقط ۲۴ پاسخ‌دهندهٔ برتر)
///     / accurate (Real برای همهٔ پاسخ‌دهنده‌ها — پیش‌فرض)
///
/// منطق: ابتدا همه‌ی سرورها TCP می‌شوند (موازی)، هر کدام جواب دادند
/// تست واقعی می‌شوند و در نهایت لیست بر اساس کمترین پینگ مرتب می‌شود.///
/// سرورهای لوکال (127.0.0.1 / localhost) و سایفون تست نمی‌شوند — N/A.
/// سرورهای Aether (بخش ۵) TCP معنادار ندارند (host = auto-discover)؛
/// آن‌ها همیشه با AetherService.measureDelay تست واقعی می‌گیرند.
/// حالت realOnly (بخش ۳.۱): فاز TCP حذف و تست واقعی برای همه گرفته می‌شود.
class ServerTester {
  ServerTester._();

  /// لغو فعلی بودجهٔ تست (آخرین load) — برای لاگ.
  static TestBudget? lastBudget;

  static Future<TestSummary> testAll(
    List<VpnServer> servers, {
    required TestSession session,
    void Function(VpnServer server)? onServerDone,
    void Function()? onChanged,
    bool onlyTcp = false,
  }) async {
    // بخش ۲.۲ — تنظیمات تست از صفحه «تست و رتبه‌بندی».
    final budget = await TestBudget.load();
    lastBudget = budget;
    // آدرس تست واقعی از تنظیمات کاربر (پیش‌فرض gstatic).
    V2RayEngine.delayUrl = budget.delayUrl;
    final tcpTimeoutMs = budget.tcpTimeoutMs;
    final tcpConcurrency = budget.tcpConcurrency;
    final realTimeoutSec = budget.realTimeoutSec;
    final realSamples = budget.realSamples;
    final turbo = budget.mode == TestMode.turbo;
    final balanced = budget.mode == TestMode.balanced;
    final isTcpOnly = onlyTcp || turbo;
    debugPrint('[ServerTester] budget: mode=${budget.mode.name} '
        'tcp=${tcpTimeoutMs}ms/$tcpConcurrency '
        'real=${realTimeoutSec}s/${budget.effectiveRealConcurrency}x$realSamples '
        'url=${budget.delayUrl}');

    // بخش ۵ — سرورهای Aether از فاز TCP خارج می‌شوند و همیشه تست واقعی
    // (measureDelay روی هسته‌ی native) می‌گیرند.
    final regular = servers
        .where((s) => !s.isPsiphon && !s.isLocal && !s.isAether)
        .toList();
    final aetherServers = servers.where((s) => s.isAether).toList();
    final summary = TestSummary()
      ..total = regular.length + aetherServers.length;
    if (aetherServers.isNotEmpty) {
      debugPrint('[ServerTester] ${aetherServers.length} aether server(s) '
          'routed to native measureDelay (concurrency '
          '${budget.aetherConcurrency})');
    }

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

    // ═══ فاز ۱: TCP برای همه — موازی (در حالت realOnly حذف می‌شود) ═══
    final responders = <VpnServer>[];
    if (budget.tcpPhaseEnabled) {
      debugPrint('[ServerTester] phase 1/2: TCP ping — n=${regular.length} '
          'timeout=${tcpTimeoutMs}ms concurrency=$tcpConcurrency');
      final tcpGate = _Semaphore(tcpConcurrency);

      await Future.wait(<Future<void>>[
        for (final server in regular)
          _tcpPhase(server, session, tcpGate, responders, notify,
              timeoutMs: tcpTimeoutMs),
      ]);
      if (session.cancelled) {
        throttle?.cancel();
        return summary;
      }
      debugPrint('[ServerTester] phase 1 done — responders=${responders.length}');
    } else {
      debugPrint('[ServerTester] realOnly mode — TCP phase skipped '
          '(بخش ۳.۱ فقط Real Ping)');
    }

    // ═══ فاز ۲: تست واقعی برای پاسخ‌دهنده‌ها (+ همیشه سرورهای Aether) ═══
    // Phase 4 QA fix: in realOnly mode responders is empty (TCP skipped),
    // so the gate must also open when realForAll and there are regular servers.
    final shouldRealPhase = !isTcpOnly &&
        (budget.realForAll
            ? (regular.isNotEmpty || aetherServers.isNotEmpty)
            : (responders.isNotEmpty || aetherServers.isNotEmpty));
    if (shouldRealPhase) {
      // balanced: فقط ۲۴ پاسخ‌دهندهٔ برتر (کمترین TCP ping) تست واقعی می‌گیرند.
      // realOnly: همه‌ی سرورها مستقیماً تست واقعی می‌گیرند.
      var realTargets = budget.realForAll ? regular : responders;
      if (balanced && responders.length > TestBudget.balancedRealLimit) {
        realTargets = List<VpnServer>.from(responders)
          ..sort((a, b) => (a.ping ?? 9999).compareTo(b.ping ?? 9999));
        realTargets = realTargets.take(TestBudget.balancedRealLimit).toList();
        debugPrint('[ServerTester] balanced mode — real test limited to top '
            '${TestBudget.balancedRealLimit} responders');
      }
      final gate = _Semaphore(budget.effectiveRealConcurrency);
      final aetherGate = _Semaphore(budget.aetherConcurrency);
      debugPrint('[ServerTester] phase 2/2: real ping — n=${realTargets.length} '
          '+${aetherServers.length} aether, '
          'timeout=${realTimeoutSec}s '
          'concurrency=${budget.effectiveRealConcurrency} '
          'url=${V2RayEngine.delayUrl}');
      await Future.wait(<Future<void>>[
        for (final server in realTargets)
          _realPhase(server, session, gate, summary, notify,
              timeoutSec: realTimeoutSec,
              samples: realSamples,
              onDone: onServerDone),
        for (final server in aetherServers)
          _realPhase(server, session, aetherGate, summary, notify,
              timeoutSec: realTimeoutSec,
              samples: 1,
              onDone: onServerDone),
      ]);
      // سرورهای responder که در حالت balanced تست واقعی نگرفتند:
      // وضعیت «نامشخص» با مقدار TCP می‌مانند.
      for (final server in responders) {
        if (!realTargets.contains(server)) {
          summary.unknown++;
          onServerDone?.call(server);
        }
      }
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
    void Function() notify, {
    required int timeoutMs,
  }) async {
    await tcpGate.acquire();
    try {
      if (session.cancelled) return;
      final tcp = await _tcpConnectMs(server, timeoutMs: timeoutMs);
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
    void Function() notify, {
    required int timeoutSec,
    required int samples,
    void Function(VpnServer server)? onDone,
  }) async {
    await gate.acquire();
    try {
      if (session.cancelled) return;
      server.status = ServerStatus.testing;
      notify();

      // بخش ۵ — Aether: تست واقعی از طریق هسته‌ی native (بدون TCP).
      if (server.isAether) {
        final ms = await AetherService.measureDelay(
          server,
          budget: Duration(seconds: timeoutSec < 8 ? 8 : timeoutSec),
        );
        if (session.cancelled) return;
        debugPrint('[ServerTester] aether ${server.displayName} '
            'measureDelay=${ms > 0 ? '${ms}ms' : 'FAIL'}');
        if (ms > 0) {
          server.ping = ms;
          server.jitter = null;
          server.pingKind = PingKind.real;
          server.status = ServerStatus.online;
          summary.online++;
        } else {
          server.ping = null;
          server.jitter = null;
          server.pingKind = PingKind.none;
          server.status = ServerStatus.offline;
          summary.offline++;
        }
        notify();
        onDone?.call(server);
        return;
      }

      final (ms, jitter) = await _measureReal(
        server,
        session,
        timeoutSec: timeoutSec,
        samples: samples,
      );
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
      onDone?.call(server);
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
    // بخش ۵ — Aether: TCP ping معنا ندارد (host = auto-discover).
    if (server.isAether) return false;
    // بخش ۸ — سرورهای لوکال (127.0.0.1) هرگز TCP ping نمی‌گیرند.
    if (server.isLocal) return false;
    if (server.usesUdpTransport) return false;
    if (server.host.isEmpty || server.port <= 0) return false;
    if (server.host == 'serverless') return false;
    return true;
  }

  static Future<int> _tcpConnectMs(
    VpnServer server, {
    required int timeoutMs,
  }) async {
    if (!_tcpEligible(server)) return -1;
    final watch = Stopwatch()..start();
    try {
      final socket = await Socket.connect(
        server.host,
        server.port,
        timeout: Duration(milliseconds: timeoutMs),
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
    TestSession session, {
    required int timeoutSec,
    required int samples,
  }) async {
    final timeout = Duration(seconds: timeoutSec);
    final values = <int>[];
    var consecutiveFailures = 0;
    const abandonAfter = 2;
    const sampleSpacingMs = 60;

    for (var i = 0; i < samples; i++) {
      if (session.cancelled) break;
      if (i > 0) {
        await Future<void>.delayed(const Duration(milliseconds: sampleSpacingMs));
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
        if (values.isEmpty && consecutiveFailures >= abandonAfter) {
          break;
        }
        if (values.isEmpty) break;
      }
    }
    return _summarize(values, dropWarmup: samples >= 3);
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
      if (server.protocol == VpnProtocol.ssh) {
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
