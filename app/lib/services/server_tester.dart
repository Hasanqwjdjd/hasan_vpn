import 'dart:async';
import 'dart:collection';
import 'dart:io';

import '../models/server.dart';
import 'aether_service.dart';
import 'test_budget.dart';
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

/// پینگ به سبک PattNG (RealPingWorkerService):
///
/// 1) هم‌زمانی پیش‌فرض ۱۶ (سقف ۶۴)
/// 2) پیش‌چک TCP یک‌ثانیه‌ای — fail → آفلاین بدون realDelay
/// 3) realDelay با gstatic generate_204 و بودجه ~۱۲ث
/// 4) TCP-only فقط تقریبی است (online نمی‌شود)
/// 5) Aether: measureDelay جدا
/// Ping: TCP precheck + HTTP generate_204 (SocksProbe / realDelay).
/// concurrency from TestBudget; live updates via onChanged.
class ServerTester {
  ServerTester._();

  static const int _tcpTimeoutMs = 800;
  static const int _realBudgetSec = 8;

  static Future<TestSummary> testAll(
    List<VpnServer> servers, {
    required TestSession session,
    void Function(VpnServer server)? onServerDone,
    void Function()? onChanged,
    bool onlyTcp = false,
  }) async {
    await V2RayEngine.loadDelayUrl();
    final budget = await TestBudget.load();

    final regular = servers.where((s) => !s.isPsiphon).toList();
    final summary = TestSummary()..total = regular.length;

    final realGate = _Semaphore(budget.realConcurrency);
    final tcpGate = _Semaphore(
      onlyTcp ? budget.realConcurrency * 2 : budget.tcpConcurrency,
    );
    final aetherGate = _Semaphore(budget.aetherConcurrency);

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

    await Future.wait(
      regular.map(
        (server) => _testServer(
          server,
          session: session,
          onlyTcp: onlyTcp,
          gate: server.isAether ? aetherGate : realGate,
          tcpGate: tcpGate,
          budget: budget,
          summary: summary,
          notify: notify,
        ).then((_) {
          if (!session.cancelled) onServerDone?.call(server);
        }),
      ),
    );

    throttle?.cancel();
    if (!session.cancelled) onChanged?.call();
    return summary;
  }

  static Future<TestSummary> testOne(
    VpnServer server, {
    required TestSession session,
    void Function()? onChanged,
    bool onlyTcp = false,
  }) async {
    await V2RayEngine.loadDelayUrl();
    final budget = await TestBudget.load();
    final summary = TestSummary()..total = 1;

    await _testServer(
      server,
      session: session,
      onlyTcp: onlyTcp,
      gate: _Semaphore(1),
      tcpGate: _Semaphore(1),
      budget: budget,
      summary: summary,
      notify: () => onChanged?.call(),
    );
    return summary;
  }

  static (int, int?) _summarize(List<int> values, {required bool dropWarmup}) {
    if (values.isEmpty) return (-1, null);
    var used = List<int>.from(values);
    if (dropWarmup && used.length >= 2) used = used.sublist(1);
    used.sort();
    final mid = used.length ~/ 2;
    final ms =
        used.length.isOdd ? used[mid] : (used[mid - 1] + used[mid]) ~/ 2;
    final jitter = used.length >= 2 ? used.last - used.first : null;
    return (ms < 1 ? 1 : ms, jitter);
  }

  static bool _tcpPrecheckEligible(VpnServer server) {
    if (server.isAether || server.isPsiphon) return false;
    if (server.usesUdpTransport) return false;
    if (server.host.isEmpty || server.port <= 0) return false;
    if (server.host == 'serverless') return false;
    return true;
  }

  static Future<int> _tcpConnectMs(VpnServer server) async {
    if (!_tcpPrecheckEligible(server)) return -1;
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

  static Future<(int, int?)> _measureReal(
    VpnServer server,
    TestBudget budget,
    TestSession session,
  ) async {
    final timeout = Duration(
      seconds: budget.timeoutSec.clamp(5, _realBudgetSec),
    );
    final values = <int>[];
    final samples = budget.samples.clamp(1, 3);

    for (var i = 0; i < samples; i++) {
      if (session.cancelled) break;
      // C1: if VPN already up, measure real HTTP through local SOCKS (v2rayNG-style).
      // Otherwise fall back to engine realDelay (spawns/uses core for that config).
      int result;
      if (V2RayEngine.isConnected &&
          V2RayEngine.localSocksPort > 0 &&
          V2RayEngine.current?.id == server.id) {
        final probe = await SocksProbe.measure(
          port: V2RayEngine.localSocksPort,
          samples: budget.samples,
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
      } else if (values.isEmpty) {
        break;
      }
    }
    return _summarize(values, dropWarmup: samples >= 2);
  }

  static Future<void> _testServer(
    VpnServer server, {
    required TestSession session,
    required bool onlyTcp,
    required _Semaphore gate,
    required _Semaphore tcpGate,
    required TestBudget budget,
    required TestSummary summary,
    required void Function() notify,
  }) async {
    if (session.cancelled) return;
    if (server.isPsiphon) return;

    await gate.acquire();
    try {
      if (session.cancelled) return;
      server.status = ServerStatus.testing;
      notify();

      if (server.isAether) {
        final ms = await AetherService.measureDelay(
          server,
          budget: Duration(seconds: budget.timeoutSec.clamp(8, _realBudgetSec)),
        );
        if (session.cancelled) return;
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
        return;
      }

      if (onlyTcp) {
        await tcpGate.acquire();
        try {
          final tcp = await _tcpConnectMs(server);
          if (session.cancelled) return;
          if (tcp > 0) {
            server.ping = tcp;
            server.jitter = null;
            server.pingKind = PingKind.tcp;
            server.status = ServerStatus.idle;
            summary.unknown++;
          } else {
            server.ping = null;
            server.jitter = null;
            server.pingKind = PingKind.none;
            server.status = ServerStatus.offline;
            summary.offline++;
          }
        } finally {
          tcpGate.release();
        }
        return;
      }

      // PattNG fail-fast TCP pre-check (1s)
      if (_tcpPrecheckEligible(server) && budget.tcpPrecheck) {
        await tcpGate.acquire();
        final tcp = await _tcpConnectMs(server);
        tcpGate.release();
        if (session.cancelled) return;
        if (tcp <= 0) {
          server.ping = null;
          server.jitter = null;
          server.pingKind = PingKind.none;
          server.status = ServerStatus.offline;
          summary.offline++;
          return;
        }
      }

      var (ms, jitter) = await _measureReal(server, budget, session);
      if (session.cancelled) return;

      if (ms > 0) {
        server.ping = ms;
        server.jitter = jitter;
        server.pingKind = PingKind.real;
        server.status = ServerStatus.online;
        summary.online++;
        return;
      }

      if (ms == -2) {
        summary.realUnavailable = true;
        if (budget.tcpFallback && _tcpPrecheckEligible(server)) {
          await tcpGate.acquire();
          final tcp = await _tcpConnectMs(server);
          tcpGate.release();
          if (tcp > 0) {
            server.ping = tcp;
            server.jitter = null;
            server.pingKind = PingKind.tcp;
            server.status = ServerStatus.idle;
            summary.unknown++;
            return;
          }
        }
        server.ping = null;
        server.jitter = null;
        server.pingKind = PingKind.none;
        server.status = ServerStatus.unknown;
        summary.unknown++;
        return;
      }

      if (budget.tcpFallback && _tcpPrecheckEligible(server)) {
        await tcpGate.acquire();
        final tcp = await _tcpConnectMs(server);
        tcpGate.release();
        if (tcp > 0) {
          server.ping = tcp;
          server.jitter = null;
          server.pingKind = PingKind.tcp;
          server.status = ServerStatus.idle;
          summary.unknown++;
          return;
        }
      }

      server.ping = null;
      server.jitter = null;
      server.pingKind = PingKind.none;
      server.status = ServerStatus.offline;
      summary.offline++;
    } finally {
      gate.release();
    }

    notify();
  }

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

  static void sortServers(List<VpnServer> servers, {bool descending = false}) {
    final order = <VpnServer, int>{
      for (var i = 0; i < servers.length; i++) servers[i]: i,
    };

    servers.sort((a, b) {
      if (a.isPinned != b.isPinned) return a.isPinned ? -1 : 1;

      final sa = scoreOf(a);
      final sb = scoreOf(b);
      final aHas = sa >= 0;
      final bHas = sb >= 0;
      if (aHas != bHas) return aHas ? -1 : 1;

      if (aHas && bHas) {
        final cmp = sa.compareTo(sb);
        if (cmp != 0) return descending ? cmp : -cmp;
      }

      return order[a]!.compareTo(order[b]!);
    });
  }

  static VpnServer? fastest(List<VpnServer> servers) {
    VpnServer? best;
    double bestScore = -1;
    for (final server in servers) {
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
