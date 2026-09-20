import 'dart:async';
import 'dart:collection';
import 'dart:io';

import '../models/server.dart';
import 'v2ray_engine.dart';

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

class _TcpResult {
  final int ms;
  final int jitter;
  const _TcpResult(this.ms, this.jitter);
}

class ServerTester {
  ServerTester._();

  static const int _tcpConcurrency = 32;
  static const int _fastFailMs = 2500;

  static int get _realConcurrency {
    final cores = Platform.numberOfProcessors;
    return (cores ~/ 2 + 1).clamp(3, 8).toInt();
  }

  static final Map<String, Future<InternetAddress?>> _dnsCache =
      <String, Future<InternetAddress?>>{};
  static final Map<String, Future<_TcpResult?>> _tcpCache =
      <String, Future<_TcpResult?>>{};

  static void _resetCaches() {
    _dnsCache.clear();
    _tcpCache.clear();
  }

  static Future<TestSummary> testAll(
    List<VpnServer> servers, {
    required TestSession session,
    bool real = true,
    void Function(VpnServer server)? onServerDone,
    void Function()? onChanged,
  }) async {
    _resetCaches();

    final targets = servers.where((s) => !s.isAether).toList();
    final summary = TestSummary()..total = targets.length;
    final tcpGate = _Semaphore(_tcpConcurrency);
    final realGate = _Semaphore(_realConcurrency);

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
          real: real,
          retries: 1,
          tcpGate: tcpGate,
          realGate: realGate,
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
    bool real = true,
    void Function()? onChanged,
  }) async {
    _resetCaches();
    final summary = TestSummary()..total = 1;

    await _testServer(
      server,
      session: session,
      real: real,
      retries: 2,
      tcpGate: _Semaphore(1),
      realGate: _Semaphore(1),
      summary: summary,
      notify: () => onChanged?.call(),
    );
    return summary;
  }

  static Future<void> _testServer(
    VpnServer server, {
    required TestSession session,
    required bool real,
    required int retries,
    required _Semaphore tcpGate,
    required _Semaphore realGate,
    required TestSummary summary,
    required void Function() notify,
  }) async {
    if (session.cancelled) return;
    if (server.isAether) return;

    _TcpResult? tcp;
    final needsTcp = !server.usesUdpTransport;

    // ---- مرحله ۱: TCP
    if (needsTcp) {
      await tcpGate.acquire();
      try {
        if (session.cancelled) return;
        server.status = ServerStatus.testing;
        notify();
        tcp = await _tcpProbeCached(server);
      } finally {
        tcpGate.release();
      }

      if (session.cancelled) return;

      if (tcp == null) {
        server.ping = null;
        server.jitter = null;
        server.pingKind = PingKind.none;
        server.status = ServerStatus.offline;
        summary.offline++;
        notify();
        return;
      }

      server.ping = tcp.ms;
      server.jitter = tcp.jitter;
      server.pingKind = PingKind.tcp;
      notify();
    }

    // ---- مرحله ۲: پینگ واقعی
    if (real) {
      await realGate.acquire();
      try {
        if (session.cancelled) return;
        server.status = ServerStatus.testing;
        notify();

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
          if (tcp != null) {
            server.status = ServerStatus.online;
            summary.online++;
          } else {
            server.ping = null;
            server.pingKind = PingKind.none;
            server.status = ServerStatus.unknown;
            summary.unknown++;
          }
        } else {
          // پینگ واقعی شکست خورد (-1). اگر TCP جواب داده بود، همون رو نگه دار.
          if (tcp != null) {
            server.ping = tcp.ms;
            server.jitter = tcp.jitter;
            server.pingKind = PingKind.tcp;
            server.status = ServerStatus.online;
            summary.online++;
          } else {
            server.ping = null;
            server.jitter = null;
            server.pingKind = PingKind.none;
            server.status = ServerStatus.offline;
            summary.offline++;
          }
        }
      } finally {
        realGate.release();
      }
    } else {
      if (tcp != null) {
        server.status = ServerStatus.online;
        summary.online++;
      } else {
        server.status = ServerStatus.unknown;
        summary.unknown++;
      }
    }

    notify();
  }

  static Future<_TcpResult?> _tcpProbeCached(VpnServer server) {
    final key = '${server.host.trim().toLowerCase()}:${server.port}';
    return _tcpCache.putIfAbsent(key, () => _tcpProbe(server));
  }

  static Future<_TcpResult?> _tcpProbe(VpnServer server) async {
    final address = await _resolve(server.host);
    if (address == null) return null;

    var first = await _connectOnce(
      address,
      server.port,
      const Duration(milliseconds: 2500),
    );
    first ??= await _connectOnce(
      address,
      server.port,
      const Duration(milliseconds: 1500),
    );
    if (first == null) return null;

    final extra = await Future.wait<int?>(<Future<int?>>[
      _connectOnce(address, server.port, const Duration(milliseconds: 1500)),
      _connectOnce(address, server.port, const Duration(milliseconds: 1500)),
    ]);

    final samples = <int>[first, ...extra.whereType<int>()]..sort();
    return _TcpResult(
      samples[samples.length ~/ 2],
      samples.last - samples.first,
    );
  }

  static Future<int?> _connectOnce(
    InternetAddress address,
    int port,
    Duration timeout,
  ) async {
    final watch = Stopwatch()..start();
    Socket? socket;
    try {
      socket = await Socket.connect(address, port, timeout: timeout);
      watch.stop();
      final ms = watch.elapsedMilliseconds;
      return ms < 1 ? 1 : ms;
    } catch (_) {
      return null;
    } finally {
      socket?.destroy();
    }
  }

  static Future<InternetAddress?> _resolve(String host) {
    final name = host.trim();
    if (name.isEmpty || name == 'unknown' || name == 'auto-discover') {
      return Future<InternetAddress?>.value(null);
    }

    final literal = InternetAddress.tryParse(name);
    if (literal != null) return Future<InternetAddress?>.value(literal);

    return _dnsCache.putIfAbsent(name, () async {
      try {
        final list = await InternetAddress.lookup(name)
            .timeout(const Duration(seconds: 3));
        if (list.isEmpty) return null;
        return list.firstWhere(
          (a) => a.type == InternetAddressType.IPv4,
          orElse: () => list.first,
        );
      } catch (_) {
        return null;
      }
    });
  }

  static void sortServers(List<VpnServer> servers, {bool descending = false}) {
    final order = <VpnServer, int>{
      for (var i = 0; i < servers.length; i++) servers[i]: i,
    };

    servers.sort((a, b) {
      if (a.isPinned != b.isPinned) return a.isPinned ? -1 : 1;

      final aHas = a.ping != null;
      final bHas = b.ping != null;
      if (aHas != bHas) return aHas ? -1 : 1;

      if (aHas && bHas) {
        if (a.pingKind != b.pingKind) {
          return a.pingKind == PingKind.real ? -1 : 1;
        }
        final cmp = a.ping!.compareTo(b.ping!);
        if (cmp != 0) return descending ? -cmp : cmp;
      }

      return order[a]!.compareTo(order[b]!);
    });
  }

  static VpnServer? fastest(List<VpnServer> servers) {
    VpnServer? best;
    for (final server in servers) {
      if (server.ping == null || server.status != ServerStatus.online) continue;
      if (server.isAether) continue;

      if (best == null) {
        best = server;
        continue;
      }

      final bestReal = best.pingKind == PingKind.real;
      final serverReal = server.pingKind == PingKind.real;
      if (serverReal != bestReal) {
        if (serverReal) best = server;
        continue;
      }
      if (server.ping! < best.ping!) best = server;
    }
    return best;
  }
}
