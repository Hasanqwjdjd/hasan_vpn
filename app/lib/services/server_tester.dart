import 'dart:async';
import 'dart:collection';
import 'dart:io';

import '../models/server.dart';
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
  static int get _concurrency {
    final cores = Platform.numberOfProcessors;
    return (cores ~/ 2 + 2).clamp(4, 10).toInt();
  }

  // ------------------------------------------------------------------- API

  static Future<TestSummary> testAll(
    List<VpnServer> servers, {
    required TestSession session,
    void Function(VpnServer server)? onServerDone,
    void Function()? onChanged,
  }) async {
    final targets = servers.where((s) => !s.isAether && !s.isPsiphon).toList();
    final summary = TestSummary()..total = targets.length;
    final gate = _Semaphore(_concurrency);

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

  /// تست یک سرور (دکمه‌ی رعد): با تلاش مجدد بیشتر.
  static Future<TestSummary> testOne(
    VpnServer server, {
    required TestSession session,
    void Function()? onChanged,
  }) async {
    final summary = TestSummary()..total = 1;

    await _testServer(
      server,
      session: session,
      retries: 2,
      gate: _Semaphore(1),
      summary: summary,
      notify: () => onChanged?.call(),
    );
    return summary;
  }

  // ---------------------------------------------------------------- engine

  static Future<void> _testServer(
    VpnServer server, {
    required TestSession session,
    required int retries,
    required _Semaphore gate,
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

      // فقط تست واقعی.
      var attempt = 0;
      var result = -1;
      while (true) {
        final watch = Stopwatch()..start();
        result = await V2RayEngine.realDelay(server);
        if (result != -1 || session.cancelled) break;
        if (attempt >= retries || watch.elapsedMilliseconds >= _fastFailMs) {
          break;
        }
        attempt++;
      }

      if (session.cancelled) return;

      if (result > 0) {
        server.ping = result;
        server.jitter = null;
        server.pingKind = PingKind.real;
        server.status = ServerStatus.online;
        summary.online++;
      } else if (result == -2) {
        summary.realUnavailable = true;
        server.ping = null;
        server.jitter = null;
        server.pingKind = PingKind.none;
        server.status = ServerStatus.unknown;
        summary.unknown++;
      } else {
        // اتصال واقعی برقرار نشد.
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
