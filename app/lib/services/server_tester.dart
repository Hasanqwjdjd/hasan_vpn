import 'dart:async';
import 'dart:io';
import '../models/server.dart';

class ServerTester {
  static const int _maxConcurrent = 8;
  static const int _attemptsPerServer = 2;
  static const int _timeoutMs = 4000;

  static Future<int?> testPing(VpnServer server) async {
    final results = <int>[];
    for (int i = 0; i < _attemptsPerServer; i++) {
      final ping = await _tcpPing(server, _timeoutMs);
      if (ping != null) results.add(ping);
      if (i < _attemptsPerServer - 1) {
        await Future.delayed(const Duration(milliseconds: 80));
      }
    }
    if (results.isEmpty) return null;
    results.sort();
    return results.first;
  }

  static Future<int?> _tcpPing(VpnServer server, int timeoutMs) async {
    final sw = Stopwatch()..start();
    Socket? socket;
    try {
      socket = await Socket.connect(
        server.host,
        server.port,
        timeout: Duration(milliseconds: timeoutMs),
      );
      sw.stop();
      socket.destroy();
      return sw.elapsedMilliseconds;
    } catch (_) {
      try {
        socket?.destroy();
      } catch (_) {}
      return null;
    }
  }

  static Future<void> testAllStreaming(
    List<VpnServer> servers, {
    required void Function(VpnServer) onServerTested,
    required void Function() onListUpdated,
    bool Function()? isCancelled,
    int maxConcurrent = _maxConcurrent,
  }) async {
    final queue = List<VpnServer>.from(servers);
    int active = 0;
    int index = 0;
    final completer = Completer<void>();

    void tryLaunchNext() {
      if (isCancelled?.call() ?? false) {
        if (active == 0 && !completer.isCompleted) completer.complete();
        return;
      }

      while (active < maxConcurrent && index < queue.length) {
        final server = queue[index++];
        active++;
        server.status = ServerStatus.testing;

        testPing(server).then((ping) {
          server.ping = ping;
          server.status =
              ping != null ? ServerStatus.online : ServerStatus.offline;
          onServerTested(server);
          onListUpdated();
        }).catchError((_) {
          server.ping = null;
          server.status = ServerStatus.offline;
          onListUpdated();
        }).whenComplete(() {
          active--;
          if (index < queue.length) {
            tryLaunchNext();
          } else if (active == 0 && !completer.isCompleted) {
            completer.complete();
          }
        });
      }

      if (active == 0 && index >= queue.length && !completer.isCompleted) {
        completer.complete();
      }
    }

    tryLaunchNext();
    return completer.future;
  }

  static void sortServers(List<VpnServer> servers) {
    servers.sort((a, b) {
      final aValid = a.ping != null;
      final bValid = b.ping != null;
      if (aValid && !bValid) return -1;
      if (!aValid && bValid) return 1;
      if (aValid && bValid) {
        return (a.ping ?? 0).compareTo(b.ping ?? 0);
      }
      return 0;
    });
  }

  static int removeInvalid(List<VpnServer> servers) {
    final before = servers.length;
    servers.removeWhere((s) =>
        s.isDeletable &&
        s.status == ServerStatus.offline &&
        s.ping == null);
    return before - servers.length;
  }

  static VpnServer? fastest(List<VpnServer> servers) {
    final online = servers
        .where((s) => s.ping != null && s.status == ServerStatus.online)
        .toList();
    if (online.isEmpty) return null;
    online.sort((a, b) => (a.ping ?? 99999).compareTo(b.ping ?? 99999));
    return online.first;
  }
}
