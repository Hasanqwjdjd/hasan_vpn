import 'dart:async';
import 'dart:collection';
import 'dart:io';

import '../models/server.dart';
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

/// تست واقعی: یک درخواست HTTP از داخل پروکسی (Xray) فرستاده می‌شود.
/// این دقیقاً همان چیزی است که کاربر در عمل تجربه می‌کند.
///
/// سرورهای Aether اینجا تست نمی‌شوند (آدرس ثابت ندارند و پینگشان فقط وقتی
/// تونل بالاست معنا دارد).
class ServerTester {
  ServerTester._();

  /// اگر تلاش اول زودتر از این شکست خورد، احتمالاً خطای گذراست و یک‌بار
  /// دیگر امتحان می‌شود.
  static const int _fastFailMs = 2500;

  /// تعداد تست هم‌زمان؛ هر تست یک نمونه‌ی موقت از هسته می‌سازد، پس بر اساس
  /// تعداد هسته‌های گوشی تنظیم می‌شود (۴ تا ۱۰).
  // ------------------------------------------------------------------- API

  static Future<TestSummary> testAll(
    List<VpnServer> servers, {
    required TestSession session,
    void Function(VpnServer server)? onServerDone,
    void Function()? onChanged,
  }) async {
    await V2RayEngine.loadDelayUrl();
    final budget = await TestBudget.load();
    final targets = servers.where((s) => !s.isAether && !s.isPsiphon).toList();
    final summary = TestSummary()..total = targets.length;
    final gate = _Semaphore(budget.realConcurrency);
    final tcpGate = _Semaphore(budget.direct);

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
      targets.map(
        (server) => _testServer(
          server,
          session: session,
          retries: 1,
          gate: gate,
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
  }) async {
    await V2RayEngine.loadDelayUrl();
    final budget = await TestBudget.load();
    final summary = TestSummary()..total = 1;

    await _testServer(
      server,
      session: session,
      retries: 2,
      gate: _Semaphore(1),
      tcpGate: _Semaphore(1),
      budget: budget,
      summary: summary,
      notify: () => onChanged?.call(),
    );
    return summary;
  }

  // ---------------------------------------------------------------- engine

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

  /// (ms, jitter): ms=-1 ناموفق، ms=-2 پینگ واقعی پشتیبانی نمی‌شود.
  static Future<(int, int?)> _measure(
    VpnServer server,
    TestBudget budget,
    int retries,
    TestSession session,
  ) async {
    final timeout = Duration(seconds: budget.timeoutSec);
    final values = <int>[];
    var attempt = 0;

    for (var i = 0; i < budget.samples; i++) {
      if (session.cancelled) break;
      var result = -1;
      while (true) {
        final watch = Stopwatch()..start();
        result = await V2RayEngine.realDelay(server, timeout: timeout);
        if (result != -1 || session.cancelled) break;
        if (attempt >= retries || watch.elapsedMilliseconds >= _fastFailMs) {
          break;
        }
        attempt++;
      }
      if (result == -2) return (-2, null);
      if (result > 0) {
        values.add(result);
      } else if (values.isEmpty) {
        break;
      }
    }
    return _summarize(values, dropWarmup: budget.samples >= 2);
  }

  static Future<(int, int?)> _tcpProbe(
    VpnServer server,
    TestBudget budget,
    _Semaphore gate,
  ) async {
    if (server.host.isEmpty ||
        server.port <= 0 ||
        server.host == 'serverless' ||
        server.usesUdpTransport) {
      return (-1, null);
    }
    await gate.acquire();
    try {
      final times = <int>[];
      for (var i = 0; i < budget.samples; i++) {
        final watch = Stopwatch()..start();
        try {
          final socket = await Socket.connect(
            server.host,
            server.port,
            timeout: Duration(seconds: budget.timeoutSec),
          );
          watch.stop();
          socket.destroy();
          times.add(watch.elapsedMilliseconds);
        } catch (_) {
          if (times.isEmpty) break;
        }
      }
      return _summarize(times, dropWarmup: budget.samples >= 2);
    } finally {
      gate.release();
    }
  }

  static Future<void> _testServer(
    VpnServer server, {
    required TestSession session,
    required int retries,
    required _Semaphore gate,
    required _Semaphore tcpGate,
    required TestBudget budget,
    required TestSummary summary,
    required void Function() notify,
  }) async {
    if (session.cancelled) return;
    if (server.isAether || server.isPsiphon) return;

    await gate.acquire();
    try {
      if (session.cancelled) return;
      server.status = ServerStatus.testing;
      notify();

      var (ms, jitter) = await _measure(server, budget, retries, session);
      if (session.cancelled) return;

      var kind = PingKind.real;
      if (ms == -2 && budget.tcpFallback) {
        final tcp = await _tcpProbe(server, budget, tcpGate);
        if (session.cancelled) return;
        if (tcp.$1 > 0) {
          ms = tcp.$1;
          jitter = tcp.$2;
          kind = PingKind.tcp;
        }
      }

      if (ms > 0) {
        server.ping = ms;
        server.jitter = jitter;
        server.pingKind = kind;
        server.status = ServerStatus.online;
        summary.online++;
      } else if (ms == -2) {
        summary.realUnavailable = true;
        server.ping = null;
        server.jitter = null;
        server.pingKind = PingKind.none;
        server.status = ServerStatus.unknown;
        summary.unknown++;
      } else {
        server.ping = null;
        server.jitter = null;
        server.pingKind = PingKind.none;
        server.status = ServerStatus.offline;
        summary.offline++;
      }
    } finally {
      gate.release();
    }

    notify();
  }

  // --------------------------------------------------------------- sorting

  /// امتیاز ترکیبی (بالاتر = بهتر).
  /// - تأخیر کم → امتیاز بیشتر
  /// - وضعیت online الزامی
  /// - jitter در صورت وجود جریمه می‌شود
  static double scoreOf(VpnServer s) {
    if (s.status != ServerStatus.online || s.ping == null) return -1;
    if (s.isAether) return -1;

    // پایه: هرچه پینگ کمتر، امتیاز بیشتر (سقف نرم ~۳۰۰ms)
    final ping = s.ping!.clamp(1, 10000);
    var score = 10000.0 / ping;

    // جریمه jitter (اگر ثبت شده)
    final j = s.jitter;
    if (j != null && j > 0) {
      score *= (1.0 / (1.0 + j / 200.0));
    }

    // پاداش پینگ خیلی خوب
    if (ping < 200) score *= 1.25;
    if (ping < 100) score *= 1.15;

    return score;
  }

  /// مرتب‌سازی پایدار: پین‌شده‌ها ← امتیاز بالاتر ← بدون پینگ.
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
        if (cmp != 0) return descending ? cmp : -cmp; // پیش‌فرض: امتیاز بالاتر اول
      }

      return order[a]!.compareTo(order[b]!);
    });
  }

  /// بهترین سرور بر اساس امتیاز ترکیبی.
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

  /// رتبه‌بندی کامل: لیست را بر اساس امتیاز مرتب می‌کند و رتبه ۱-based می‌دهد.
  /// خروجی: map از serverId → رتبه (۱ = بهترین)
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
        result[s.id] = 0; // بدون رتبه
      } else {
        result[s.id] = rank++;
      }
    }
    return result;
  }
}
