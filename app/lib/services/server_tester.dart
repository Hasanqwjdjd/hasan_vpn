import 'dart:io';
import '../models/server.dart';

class ServerTester {
  /// پینگ واقعی با TCP Socket (مثل V2RayNG)
  static Future<int?> testPing(VpnServer server, {int timeoutMs = 3000}) async {
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

  /// تست سرعت دانلود (Kbps)
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

  /// تست همه سرورها
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

  /// سریع‌ترین سرور
  static VpnServer? fastest(List<VpnServer> servers) {
    final online = servers.where((s) => s.status == ServerStatus.online).toList();
    if (online.isEmpty) return null;
    online.sort((a, b) => (a.ping ?? 99999).compareTo(b.ping ?? 99999));
    return online.first;
  }
}
