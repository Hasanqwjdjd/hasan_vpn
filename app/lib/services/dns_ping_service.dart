// app/lib/services/dns_ping_service.dart
//
// Phase (b): real ping engine for the DNS Game directory.
//
// Design notes (per spec):
//  - Sends an actual DNS query (A record, default target
//    `example.com`) over UDP:53, not a bare TCP connect.
//  - Falls back to TCP:53 (RFC1035 2-byte length prefix) if UDP
//    times out or is blocked.
//  - Supports DoH (RFC8484 GET, application/dns-message) and DoT
//    (TLS on 853) for entries that advertise those protocols.
//  - Takes N samples (default 5, configurable 3..10) and reports
//    min/median/max; median is what's shown in the UI to reduce
//    noise from one-off spikes.
//  - jitter = max - min across successful samples.
//  - `autoSelectBest` prefers low jitter over raw speed, per spec.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import '../models/dns_entry.dart';

/// Result of pinging one DnsEntry N times.
class PingResult {
  final String entryId;
  final int? minMs;
  final int? medianMs;
  final int? maxMs;
  final int? jitterMs; // maxMs - minMs, over successful samples only
  final int successCount;
  final int failureCount;
  final DnsProtocol protocolUsed;

  const PingResult({
    required this.entryId,
    required this.minMs,
    required this.medianMs,
    required this.maxMs,
    required this.jitterMs,
    required this.successCount,
    required this.failureCount,
    required this.protocolUsed,
  });

  bool get isReachable => successCount > 0;

  /// green / yellow / red — mirrors DnsStats.stability so the UI can
  /// show a dot immediately after a fresh ping, before persisting.
  String get stability {
    final p = medianMs;
    final j = jitterMs;
    if (p == null) return 'unknown';
    if (p <= 60 && (j ?? 0) <= 15) return 'green';
    if (p <= 150 && (j ?? 0) <= 40) return 'yellow';
    return 'red';
  }
}

class DnsPingService {
  DnsPingService._();
  static final DnsPingService instance = DnsPingService._();

  /// Domain used for the liveness query. Chosen for being small,
  /// stable, and virtually always cached/resolvable — we don't care
  /// about the *answer*, only that a well-formed response comes back.
  static const String probeDomain = 'example.com';

  static const Duration _udpTimeout = Duration(milliseconds: 1500);
  static const Duration _tcpTimeout = Duration(milliseconds: 2000);
  static const Duration _dohTimeout = Duration(milliseconds: 2500);
  static const Duration _dotTimeout = Duration(milliseconds: 2000);

  // ---------------------------------------------------------- Query bytes

  /// Builds a minimal, valid DNS query for an A record, RFC1035 wire
  /// format. Random 16-bit transaction id so we can match the reply
  /// and detect spoofed/stale packets on the same socket.
  Uint8List _buildQuery(String domain, {required int id}) {
    final labels = domain.split('.');
    final qname = BytesBuilder();
    for (final label in labels) {
      final bytes = utf8.encode(label);
      qname.addByte(bytes.length);
      qname.add(bytes);
    }
    qname.addByte(0); // root terminator

    final b = BytesBuilder();
    b.addByte((id >> 8) & 0xFF);
    b.addByte(id & 0xFF);
    b.addByte(0x01); // flags hi: RD=1 (recursion desired)
    b.addByte(0x00); // flags lo
    b.addByte(0x00);
    b.addByte(0x01); // QDCOUNT=1
    b.addByte(0x00);
    b.addByte(0x00); // ANCOUNT=0
    b.addByte(0x00);
    b.addByte(0x00); // NSCOUNT=0
    b.addByte(0x00);
    b.addByte(0x00); // ARCOUNT=0
    b.add(qname.toBytes());
    b.addByte(0x00);
    b.addByte(0x01); // QTYPE=A
    b.addByte(0x00);
    b.addByte(0x01); // QCLASS=IN
    return b.toBytes();
  }

  bool _isValidReply(Uint8List data, int expectedId) {
    if (data.length < 12) return false;
    final id = (data[0] << 8) | data[1];
    if (id != expectedId) return false;
    final flagsHi = data[2];
    final qr = (flagsHi >> 7) & 0x1; // must be a response, not a query
    return qr == 1;
  }

  // ---------------------------------------------------------- Single-sample transports

  Future<int?> _pingUdp(String host, {int port = 53}) async {
    RawDatagramSocket? socket;
    try {
      final id = Random().nextInt(0xFFFF);
      final query = _buildQuery(probeDomain, id: id);
      final sw = Stopwatch()..start();
      socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      socket.send(query, InternetAddress(host), port);

      final completer = Completer<int?>();
      late StreamSubscription sub;
      sub = socket.listen((event) {
        if (event == RawSocketEvent.read) {
          final dg = socket!.receive();
          if (dg != null && _isValidReply(dg.data, id)) {
            sw.stop();
            if (!completer.isCompleted) completer.complete(sw.elapsedMilliseconds);
          }
        }
      });

      final result = await completer.future.timeout(_udpTimeout, onTimeout: () => null);
      await sub.cancel();
      return result;
    } catch (_) {
      return null;
    } finally {
      socket?.close();
    }
  }

  Future<int?> _pingTcp(String host, {int port = 53}) async {
    Socket? socket;
    try {
      final id = Random().nextInt(0xFFFF);
      final query = _buildQuery(probeDomain, id: id);
      final framed = BytesBuilder();
      framed.addByte((query.length >> 8) & 0xFF);
      framed.addByte(query.length & 0xFF);
      framed.add(query);

      final sw = Stopwatch()..start();
      socket = await Socket.connect(host, port, timeout: _tcpTimeout);
      socket.add(framed.toBytes());
      await socket.flush();

      final completer = Completer<int?>();
      final buf = BytesBuilder();
      late StreamSubscription sub;
      sub = socket.listen((chunk) {
        buf.add(chunk);
        final bytes = buf.toBytes();
        if (bytes.length >= 2) {
          final msgLen = (bytes[0] << 8) | bytes[1];
          if (bytes.length >= 2 + msgLen) {
            final msg = Uint8List.sublistView(bytes, 2, 2 + msgLen);
            sw.stop();
            if (_isValidReply(msg, id) && !completer.isCompleted) {
              completer.complete(sw.elapsedMilliseconds);
            } else if (!completer.isCompleted) {
              completer.complete(null);
            }
          }
        }
      });

      final result = await completer.future.timeout(_tcpTimeout, onTimeout: () => null);
      await sub.cancel();
      return result;
    } catch (_) {
      return null;
    } finally {
      socket?.destroy();
    }
  }

  Future<int?> _pingDoh(String dohUrl) async {
    HttpClient? client;
    try {
      final id = Random().nextInt(0xFFFF);
      final query = _buildQuery(probeDomain, id: id);
      final b64 = base64Url.encode(query).replaceAll('=', '');
      final uri = Uri.parse(dohUrl).replace(queryParameters: {'dns': b64});

      client = HttpClient()..connectionTimeout = _dohTimeout;
      final sw = Stopwatch()..start();
      final req = await client.getUrl(uri).timeout(_dohTimeout);
      req.headers.set('accept', 'application/dns-message');
      final resp = await req.close().timeout(_dohTimeout);
      final bytes = await consolidateHttpBody(resp);
      sw.stop();
      if (resp.statusCode == 200 && bytes.length >= 12) {
        return sw.elapsedMilliseconds;
      }
      return null;
    } catch (_) {
      return null;
    } finally {
      client?.close(force: true);
    }
  }

  Future<int?> _pingDot(String host, {int port = 853}) async {
    SecureSocket? socket;
    try {
      final id = Random().nextInt(0xFFFF);
      final query = _buildQuery(probeDomain, id: id);
      final framed = BytesBuilder();
      framed.addByte((query.length >> 8) & 0xFF);
      framed.addByte(query.length & 0xFF);
      framed.add(query);

      final sw = Stopwatch()..start();
      socket = await SecureSocket.connect(host, port, timeout: _dotTimeout);
      socket.add(framed.toBytes());
      await socket.flush();

      final completer = Completer<int?>();
      final buf = BytesBuilder();
      late StreamSubscription sub;
      sub = socket.listen((chunk) {
        buf.add(chunk);
        final bytes = buf.toBytes();
        if (bytes.length >= 2) {
          final msgLen = (bytes[0] << 8) | bytes[1];
          if (bytes.length >= 2 + msgLen) {
            final msg = Uint8List.sublistView(bytes, 2, 2 + msgLen);
            sw.stop();
            if (_isValidReply(msg, id) && !completer.isCompleted) {
              completer.complete(sw.elapsedMilliseconds);
            } else if (!completer.isCompleted) {
              completer.complete(null);
            }
          }
        }
      });

      final result = await completer.future.timeout(_dotTimeout, onTimeout: () => null);
      await sub.cancel();
      return result;
    } catch (_) {
      return null;
    } finally {
      socket?.destroy();
    }
  }

  Future<Uint8List> consolidateHttpBody(HttpClientResponse resp) async {
    final b = BytesBuilder();
    await for (final chunk in resp) {
      b.add(chunk);
    }
    return b.toBytes();
  }

  /// One sample against a single DnsEntry, using the best transport it
  /// advertises: UDP first (cheapest, most representative of in-game
  /// latency), then TCP, then DoT, then DoH.
  Future<({int? ms, DnsProtocol proto})> _pingOnce(DnsEntry entry) async {
    if (entry.primary != null) {
      final udp = await _pingUdp(entry.primary!);
      if (udp != null) return (ms: udp, proto: DnsProtocol.udp);
      final tcp = await _pingTcp(entry.primary!);
      if (tcp != null) return (ms: tcp, proto: DnsProtocol.tcp);
    }
    if (entry.primaryV6 != null) {
      final udp = await _pingUdp(entry.primaryV6!);
      if (udp != null) return (ms: udp, proto: DnsProtocol.udp);
    }
    if (entry.dotHost != null) {
      final dot = await _pingDot(entry.dotHost!);
      if (dot != null) return (ms: dot, proto: DnsProtocol.dot);
    }
    if (entry.dohUrl != null) {
      final doh = await _pingDoh(entry.dohUrl!);
      if (doh != null) return (ms: doh, proto: DnsProtocol.doh);
    }
    return (ms: null, proto: DnsProtocol.udp);
  }

  // ---------------------------------------------------------- Multi-sample

  /// Pings [entry] [samples] times (default 5, clamped 3..10) and
  /// returns min/median/max + jitter. Samples run sequentially with a
  /// small stagger so a burst doesn't look like one lucky round-trip.
  Future<PingResult> pingEntry(DnsEntry entry, {int samples = 5}) async {
    final n = samples.clamp(3, 10);
    final results = <int>[];
    DnsProtocol lastProto = DnsProtocol.udp;
    int failures = 0;

    for (var i = 0; i < n; i++) {
      final r = await _pingOnce(entry);
      if (r.ms != null) {
        results.add(r.ms!);
        lastProto = r.proto;
      } else {
        failures++;
      }
      if (i < n - 1) {
        await Future.delayed(const Duration(milliseconds: 60));
      }
    }

    if (results.isEmpty) {
      return PingResult(
        entryId: entry.id,
        minMs: null,
        medianMs: null,
        maxMs: null,
        jitterMs: null,
        successCount: 0,
        failureCount: failures,
        protocolUsed: lastProto,
      );
    }

    results.sort();
    final min = results.first;
    final max = results.last;
    final median = results[results.length ~/ 2];

    return PingResult(
      entryId: entry.id,
      minMs: min,
      medianMs: median,
      maxMs: max,
      jitterMs: max - min,
      successCount: results.length,
      failureCount: failures,
      protocolUsed: lastProto,
    );
  }

  /// Pings a batch of entries concurrently, with a cap on parallelism
  /// so we don't open hundreds of sockets at once on a phone.
  Future<Map<String, PingResult>> pingBatch(
    List<DnsEntry> entries, {
    int samples = 5,
    int concurrency = 12,
    void Function(int done, int total)? onProgress,
  }) async {
    final out = <String, PingResult>{};
    var index = 0;
    var done = 0;

    Future<void> worker() async {
      while (true) {
        final i = index++;
        if (i >= entries.length) return;
        final entry = entries[i];
        out[entry.id] = await pingEntry(entry, samples: samples);
        done++;
        onProgress?.call(done, entries.length);
      }
    }

    await Future.wait(List.generate(min(concurrency, entries.length), (_) => worker()));
    return out;
  }

  // ---------------------------------------------------------- Auto-select

  /// "انتخاب بهترین خودکار": pings the given candidates (caller passes
  /// in region-filtered entries — e.g. same country as the user) and
  /// returns the one with the lowest jitter among the 3 fastest by
  /// median ping. Stability over raw speed, per spec.
  Future<DnsEntry?> autoSelectBest(
    List<DnsEntry> candidates, {
    int samples = 5,
  }) async {
    if (candidates.isEmpty) return null;
    final results = await pingBatch(candidates, samples: samples);

    final reachable = candidates.where((e) => results[e.id]?.isReachable == true).toList();
    if (reachable.isEmpty) return null;

    reachable.sort((a, b) => results[a.id]!.medianMs!.compareTo(results[b.id]!.medianMs!));
    final fastestThree = reachable.take(3).toList();

    fastestThree.sort((a, b) => (results[a.id]!.jitterMs ?? 0).compareTo(results[b.id]!.jitterMs ?? 0));
    return fastestThree.first;
  }
}
