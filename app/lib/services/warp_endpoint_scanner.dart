import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';

import 'wireguard_crypto.dart';

/// Endpoint ساده host:port.
class WarpEndpoint {
  final String host;
  final int port;
  const WarpEndpoint(this.host, this.port);

  @override
  String toString() => '$host:$port';

  @override
  bool operator ==(Object other) =>
      other is WarpEndpoint && other.host == host && other.port == port;

  @override
  int get hashCode => Object.hash(host, port);
}

class WarpEndpointHit {
  final WarpEndpoint endpoint;
  final int latencyMs;
  /// ترتیب کشف (کمتر = زودتر).
  final int discoveryOrder;
  const WarpEndpointHit({
    required this.endpoint,
    required this.latencyMs,
    this.discoveryOrder = 1 << 30,
  });
}

/// WARPSCOUT-style UDP scanner.
///
/// Port از WarpScoutEndpointScanner.kt (PingNG). با فرستادن یک
/// WireGuard initiation معتبر و گوش دادن به handshake response، یک
/// endpoint واقعاً قابل دسترس رو تشخیص می‌ده (بجای TCP-connect ساده).
class WarpEndpointScanner {
  WarpEndpointScanner._();

  static const int _defaultRate = 2000;
  static const int _defaultWorkers = 256;
  static const int _defaultTimeoutMs = 350;
  static const int _defaultMaxHits = 64;

  /// اسکن یک لیست endpoint با rate-limit و workers.
  static Future<List<WarpEndpointHit>> scan({
    required List<WarpEndpoint> endpoints,
    required Uint8List privateKey,
    required Uint8List peerPublicKey,
    int ratePerSecond = _defaultRate,
    int workers = _defaultWorkers,
    int timeoutMs = _defaultTimeoutMs,
    int maxHits = _defaultMaxHits,
    int? stopAfterHits,
    bool acceptCookieReplies = false,
    void Function(int tested, int total)? onProgress,
  }) async {
    if (endpoints.isEmpty) return const [];

    final prepared = WireGuardCrypto.prepare(
      privateKey: privateKey,
      peerPublicKey: peerPublicKey,
    );
    if (prepared == null) {
      debugPrint('warp_scout: invalid keys');
      return const [];
    }

    final rate = ratePerSecond <= 0 ? 0 : 1000000 ~/ ratePerSecond;
    final workerCount = workers.clamp(1, 256);
    final hitLimit = maxHits.clamp(1, 512);
    final stopAt = stopAfterHits?.clamp(1, hitLimit);

    final hits = <WarpEndpointHit>[];
    final testedCount = _AtomicInt();
    final discoveryOrder = _AtomicInt();
    var stopRequested = false;
    var nextIndex = 0;
    var lastProgressUs = 0;
    final startUs = DateTime.now().microsecondsSinceEpoch;

    Future<void> worker() async {
      while (true) {
        if (stopRequested) return;
        final idx = nextIndex++;
        if (idx >= endpoints.length) return;

        // rate-limit
        if (rate > 0) {
          final slot = idx * rate;
          final elapsed = DateTime.now().microsecondsSinceEpoch - startUs;
          if (slot > elapsed) {
            await Future<void>.delayed(
                Duration(microseconds: slot - elapsed));
          }
        }

        final endpoint = endpoints[idx];
        final hit = await _probe(
          endpoint: endpoint,
          prepared: prepared,
          timeoutMs: timeoutMs,
          acceptCookieReplies: acceptCookieReplies,
        );

        final tested = testedCount.increment();
        final nowUs = DateTime.now().microsecondsSinceEpoch;
        if (tested == endpoints.length || nowUs - lastProgressUs >= 100000) {
          lastProgressUs = nowUs;
          onProgress?.call(tested, endpoints.length);
        }

        if (hit != null) {
          hit.discoveryOrder;
          final order = discoveryOrder.increment();
          if (hits.length < hitLimit) {
            hits.add(WarpEndpointHit(
              endpoint: hit.endpoint,
              latencyMs: hit.latencyMs,
              discoveryOrder: order,
            ));
          }
          if (stopAt != null && hits.length >= stopAt) {
            stopRequested = true;
            return;
          }
        }
      }
    }

    await Future.wait(
      List<Future<void>>.generate(workerCount, (_) => worker()),
    );
    onProgress?.call(testedCount.value, endpoints.length);

    debugPrint('warp_scout: ${endpoints.length} tested, '
        '${hits.length} hits');
    return hits;
  }

  static Future<WarpEndpointHit?> _probe({
    required WarpEndpoint endpoint,
    required PreparedHandshake prepared,
    required int timeoutMs,
    required bool acceptCookieReplies,
  }) async {
    final sw = Stopwatch()..start();
    final init = WireGuardCrypto.createInitiation(prepared);
    if (init == null) return null;

    RawDatagramSocket? socket;
    try {
      socket = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        0,
      );
      socket.broadcastEnabled = false;

      final completer = Completer<Uint8List?>();
      late StreamSubscription<RawSocketEvent> sub;
      sub = socket.listen((event) {
        if (event == RawSocketEvent.read) {
          final dg = socket!.receive();
          if (dg != null && !completer.isCompleted) {
            completer.complete(dg.data);
          }
        }
      });

      final addr = InternetAddress.tryParse(endpoint.host);
      if (addr == null) {
        await sub.cancel();
        socket.close();
        return null;
      }

      socket.send(init.packet, addr, endpoint.port);

      final response = await completer.future
          .timeout(Duration(milliseconds: timeoutMs), onTimeout: () => null);
      await sub.cancel();
      socket.close();
      sw.stop();

      if (response == null) return null;
      if (!_isValidResponse(response, init.senderIndex, acceptCookieReplies)) {
        return null;
      }
      return WarpEndpointHit(
        endpoint: endpoint,
        latencyMs: sw.elapsedMilliseconds.clamp(0, 99999),
      );
    } catch (_) {
      socket?.close();
      return null;
    }
  }

  /// چک می‌کنه که پاسخ به initiation ما مربوطه.
  /// Type 2 = handshake response (≥92 بایت).
  /// Type 3 = cookie reply (64 بایت) — اگر acceptCookieReplies true.
  static bool _isValidResponse(
    Uint8List data,
    int senderIndex,
    bool acceptCookieReplies,
  ) {
    if (data.length < 8) return false;
    final bd = ByteData.sublistView(data);
    final type = bd.getUint32(0, Endian.little);
    final receiverIndex = bd.getUint32(4, Endian.little);
    if (receiverIndex != senderIndex) return false;
    if (type == 2) return data.length >= 92;
    if (type == 3) return acceptCookieReplies && data.length == 64;
    return false;
  }

  /// ساخت pool با یک زیرشبکه و لیست پورت.
  /// [sampleHostsPerSubnet] اگه غیر null، فقط نمونه رندوم برمی‌گردونه.
  static List<WarpEndpoint> buildPool({
    required List<String> subnets,
    required List<int> ports,
    int? sampleHostsPerSubnet,
    Random? random,
  }) {
    final rng = random ?? Random();
    final out = <WarpEndpoint>[];
    for (final subnet in subnets) {
      final hosts = List<int>.generate(256, (i) => i);
      if (sampleHostsPerSubnet != null) {
        hosts.shuffle(rng);
        hosts.removeRange(
            sampleHostsPerSubnet.clamp(1, 256), hosts.length);
      }
      for (final h in hosts) {
        for (final p in ports) {
          out.add(WarpEndpoint('$subnet.$h', p));
        }
      }
    }
    return out;
  }
}

class _AtomicInt {
  int _v = 0;
  int get value => _v;
  int increment() => ++_v;
}
