import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:http/http.dart' as http;

/// Result of one host probe.
class ProbeResult {
  final String host;
  final int port;
  final int? rttMs; // median of samples; null = all failed
  final int jitterMs;
  final double lossPct; // 0..100
  final String protocol; // tcp | udp | socks
  final DateTime at;

  const ProbeResult({
    required this.host,
    required this.port,
    required this.rttMs,
    required this.jitterMs,
    required this.lossPct,
    required this.protocol,
    required this.at,
  });

  bool get ok => rttMs != null && rttMs! >= 0;

  Map<String, dynamic> toJson() => {
        'host': host,
        'port': port,
        'rttMs': rttMs,
        'jitterMs': jitterMs,
        'lossPct': lossPct,
        'protocol': protocol,
        'at': at.toIso8601String(),
      };
}

/// Fast parallel probe with worker pool, 3-sample median, jitter/loss,
/// 5-minute per-host cache, and optional exit-IP check after connect.
class FastProbe {
  FastProbe._();

  static int poolSize = 8;
  static const Duration sampleTimeout = Duration(seconds: 3);
  static const int samples = 3;
  static const Duration cacheTtl = Duration(minutes: 5);

  static final Map<String, ProbeResult> _cache = {};

  static String _key(String host, int port, String protocol) =>
      '$protocol|$host|$port';

  /// Probe many endpoints in parallel (worker pool).
  /// [items] each: {host, port?, protocol?} protocol: tcp|udp|socks
  static Future<List<ProbeResult>> probeMany(
    List<Map<String, dynamic>> items, {
    int? workers,
  }) async {
    final w = workers ?? poolSize;
    final results = List<ProbeResult?>.filled(items.length, null);
    var next = 0;

    Future<void> worker() async {
      while (true) {
        final i = next++;
        if (i >= items.length) return;
        final it = items[i];
        final host = it['host']?.toString() ?? '';
        final port = int.tryParse('${it['port'] ?? 443}') ?? 443;
        final protocol = (it['protocol']?.toString() ?? 'tcp').toLowerCase();
        results[i] = await probeOne(host, port: port, protocol: protocol);
      }
    }

    await Future.wait(List.generate(w, (_) => worker()));
    return results.whereType<ProbeResult>().toList();
  }

  /// Same public shape many callers expect: list of hosts → map host→rttMs
  static Future<Map<String, int>> testAll(
    List<String> hosts, {
    int port = 443,
    String protocol = 'tcp',
  }) async {
    final items = hosts
        .map((h) => {'host': h, 'port': port, 'protocol': protocol})
        .toList();
    final list = await probeMany(items);
    final out = <String, int>{};
    for (final r in list) {
      out[r.host] = r.rttMs ?? -1;
    }
    return out;
  }

  static Future<ProbeResult> probeOne(
    String host, {
    int port = 443,
    String protocol = 'tcp',
    bool useCache = true,
  }) async {
    final key = _key(host, port, protocol);
    if (useCache) {
      final c = _cache[key];
      if (c != null && DateTime.now().difference(c.at) < cacheTtl) {
        return c;
      }
    }

    final rtts = <int>[];
    var fail = 0;
    for (var i = 0; i < samples; i++) {
      final ms = await _oneSample(host, port, protocol);
      if (ms == null) {
        fail++;
      } else {
        rtts.add(ms);
      }
      if (i < samples - 1) {
        await Future<void>.delayed(const Duration(milliseconds: 40));
      }
    }

    final loss = (fail / samples) * 100.0;
    int? median;
    var jitter = 0;
    if (rtts.isNotEmpty) {
      rtts.sort();
      median = rtts[rtts.length \~/ 2];
      jitter = rtts.length >= 2 ? (rtts.last - rtts.first) : 0;
    }

    final result = ProbeResult(
      host: host,
      port: port,
      rttMs: median,
      jitterMs: jitter,
      lossPct: loss,
      protocol: protocol,
      at: DateTime.now(),
    );
    _cache[key] = result;
    return result;
  }

  static Future<int?> _oneSample(String host, int port, String protocol) async {
    switch (protocol) {
      case 'udp':
        return _udpSample(host, port);
      case 'socks':
        return _socksSample(host, port);
      case 'tcp':
      default:
        return _tcpSample(host, port);
    }
  }

  static Future<int?> _tcpSample(String host, int port) async {
    final sw = Stopwatch()..start();
    try {
      final s = await Socket.connect(host, port, timeout: sampleTimeout);
      final ms = sw.elapsedMilliseconds;
      await s.close();
      return max(1, ms);
    } catch (_) {
      return null;
    }
  }

  static Future<int?> _udpSample(String host, int port) async {
    final sw = Stopwatch()..start();
    RawDatagramSocket? sock;
    try {
      sock = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      sock.send([0, 0, 0, 0], InternetAddress(host), port);
      // Many hosts won't reply; treat successful send + short wait as weak signal.
      await Future<void>.delayed(const Duration(milliseconds: 200));
      return max(1, sw.elapsedMilliseconds);
    } catch (_) {
      return null;
    } finally {
      sock?.close();
    }
  }

  /// Minimal SOCKS5 connect handshake timing to [host]:[port] as proxy itself.
  static Future<int?> _socksSample(String proxyHost, int proxyPort) async {
    final sw = Stopwatch()..start();
    try {
      final s = await Socket.connect(proxyHost, proxyPort, timeout: sampleTimeout);
      s.add([0x05, 0x01, 0x00]); // greeting, no-auth
      final resp = await s.first.timeout(sampleTimeout);
      await s.close();
      if (resp.isEmpty) return null;
      return max(1, sw.elapsedMilliseconds);
    } catch (_) {
      return null;
    }
  }

  /// After VPN/proxy is up: fetch public IP (and optional country) via HTTPS.
  static Future<Map<String, dynamic>> verifyEgress({
    String url = 'https://api.ipify.org?format=json',
  }) async {
    try {
      final res = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 8));
      if (res.statusCode < 200 || res.statusCode >= 300) {
        return {'ok': false, 'error': 'HTTP ${res.statusCode}'};
      }
      final body = res.body.trim();
      try {
        final j = jsonDecode(body);
        if (j is Map && j['ip'] != null) {
          return {'ok': true, 'ip': j['ip'].toString()};
        }
      } catch (_) {}
      // plain text IP
      if (RegExp(r'^\d+\.\d+\.\d+\.\d+$').hasMatch(body)) {
        return {'ok': true, 'ip': body};
      }
      return {'ok': true, 'raw': body};
    } catch (e) {
      return {'ok': false, 'error': e.toString()};
    }
  }

  static void clearCache() => _cache.clear();
}
