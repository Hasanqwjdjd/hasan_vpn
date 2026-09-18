import 'dart:io';
import '../models/server.dart';

class ServerTester {
  static const String testUrl = 'https://www.gstatic.com/generate_204';

  static Future<int?> testPing(VpnServer server, {int timeoutMs = 5000}) async {
    final results = <int>[];
    for (int i = 0; i < 3; i++) {
      final ping = await _singleHttpPing(server, timeoutMs);
      if (ping != null) results.add(ping);
      if (i < 2) await Future.delayed(const Duration(milliseconds: 150));
    }
    if (results.isEmpty) return null;
    results.sort();
    return results.first;
  }

  static Future<int?> _singleHttpPing(VpnServer server, int timeoutMs) async {
    final sw = Stopwatch()..start();
    HttpClient? client;
    try {
      client = HttpClient();
      client.connectionTimeout = Duration(milliseconds: timeoutMs);
      client.badCertificateCallback = (cert, host, port) => true;

      final request = await client
          .getUrl(Uri.parse('https://${server.host}:${server.port}/'))
          .timeout(Duration(milliseconds: timeoutMs));

      if (server.sniOrHost != null) {
        request.headers.set('Host', server.sniOrHost!);
      }

      final response = await request
          .close()
          .timeout(Duration(milliseconds: timeoutMs));

      sw.stop();
      await response.drain();
      return sw.elapsedMilliseconds;
    } catch (_) {
      return await _tcpPing(server, timeoutMs);
    } finally {
      client?.close(force: true);
    }
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
      socket?.destroy();
      return null;
    }
  }

  static Future<int> testSpeed({int durationMs = 4000}) async {
    final sw = Stopwatch()..start();
    int bytes = 0;
    HttpClient? client;
    try {
      client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 5);
      final req = await client.getUrl(
        Uri.parse('https://speed.cloudflare.com/__down?bytes=10000000'),
      );
      final res = await req.close();
      await for (final chunk in res) {
        bytes += chunk.length;
        if (sw.elapsedMilliseconds >= durationMs) break;
      }
      sw.stop();
    } catch (_) {
      return 0;
    } finally {
      client?.close(force: true);
    }
    final sec = sw.elapsedMilliseconds / 1000.0;
    if (sec <= 0) return 0;
    return ((bytes * 8) / sec / 1000).round();
  }

  static Future<List<VpnServer>> testAll(
    List<VpnServer> servers, {
    void Function(int done, int total)? onProgress,
  }) async {
    int done = 0;
    await Future.wait(servers.map((s) async {
      s.status = ServerStatus.testing;
      s.ping = await testPing(s);
      s.status = s.ping != null ? ServerStatus.online : ServerStatus.offline;
      done++;
      onProgress?.call(done, servers.length);
    }));
    servers.sort((a, b) => (a.ping ?? 99999).compareTo(b.ping ?? 99999));
    return servers;
  }

  static VpnServer? fastest(List<VpnServer> servers) {
    final online = servers.where((s) => s.status == ServerStatus.online).toList();
    if (online.isEmpty) return null;
    online.sort((a, b) => (a.ping ?? 99999).compareTo(b.ping ?? 99999));
    return online.first;
  }
}
