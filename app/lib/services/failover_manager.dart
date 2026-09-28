import 'dart:async';
import 'dart:io';

/// Multi-address failover with health scoring.
///
/// Ported from BackPack docs/failover-load-balancing.md:
/// a client can hold more than one address for the same server, so a single
/// filtered IP or blocked port does not take the connection down.
///
/// Score formula (lower is better):
///     score = mean_rtt + 2 * jitter + 20 * loss%
///
/// Jitter and loss are weighted far above raw latency because a steady 90 ms
/// exit beats a 60 ms one that stutters - a stutter is a lost frame, latency
/// alone is not.
///
/// A new exit only takes over when it is at least 15% better for three checks
/// in a row, so the choice does not flap.
class FailoverManager {
  FailoverManager._();

  /// How many consecutive wins a challenger needs before it takes over.
  static const int checksBeforeSwitch = 3;

  /// How much better (fraction) a challenger must be to count as a win.
  static const double switchThreshold = 0.15;

  /// Score one address. Lower is better.
  static double score({
    required int meanRtt,
    required int jitter,
    required double lossPercent,
  }) {
    return meanRtt + 2 * jitter + 20 * lossPercent;
  }

  /// Probe one address and return its health.
  ///
  /// [address] is "host:port" or "host" (defaults to port 443).
  /// Returns null when the address never answered.
  static Future<AddressHealth?> probe(
    String address, {
    int samples = 4,
    Duration timeout = const Duration(seconds: 3),
  }) async {
    final parts = address.split(':');
    final host = parts[0].trim();
    final port = parts.length > 1
        ? int.tryParse(parts[1].trim()) ?? 443
        : 443;
    if (host.isEmpty) return null;

    final rtts = <int>[];
    var sent = 0;
    var received = 0;
    for (var i = 0; i < samples; i++) {
      sent++;
      final rtt = await _tcpRtt(host, port, timeout);
      if (rtt != null) {
        rtts.add(rtt);
        received++;
      }
      if (i < samples - 1) {
        await Future<void>.delayed(const Duration(milliseconds: 60));
      }
    }
    if (rtts.isEmpty) return null;

    rtts.sort();
    final median = rtts[rtts.length ~/ 2];
    var jitter = 0;
    if (rtts.length > 1) {
      var sum = 0;
      for (var i = 1; i < rtts.length; i++) {
        sum += (rtts[i] - rtts[i - 1]).abs();
      }
      jitter = sum ~/ (rtts.length - 1);
    }
    final loss = sent == 0 ? 0.0 : (sent - received) / sent * 100;
    return AddressHealth(
      address: address,
      host: host,
      port: port,
      meanRtt: median,
      jitter: jitter,
      lossPercent: loss,
      score: score(meanRtt: median, jitter: jitter, lossPercent: loss),
      at: DateTime.now(),
    );
  }

  static Future<int?> _tcpRtt(
    String host,
    int port,
    Duration timeout,
  ) async {
    if (port <= 0 || port > 65535) return null;
    Socket? sock;
    try {
      final sw = Stopwatch()..start();
      sock = await Socket.connect(host, port, timeout: timeout);
      sw.stop();
      return sw.elapsedMilliseconds;
    } catch (_) {
      return null;
    } finally {
      try {
        sock?.destroy();
      } catch (_) {}
    }
  }

  /// Rank all addresses by score, best first. Unhealthy addresses dropped.
  static Future<List<AddressHealth>> rank(
    List<String> addresses, {
    bool Function()? isCancelled,
  }) async {
    final out = <AddressHealth>[];
    for (final a in addresses) {
      if (isCancelled?.call() == true) break;
      final h = await probe(a);
      if (h != null) out.add(h);
    }
    out.sort((a, b) => a.score.compareTo(b.score));
    return out;
  }

  /// Pick the best healthy address. Returns null if none are healthy.
  static Future<AddressHealth?> pickBest(
    List<String> addresses, {
    bool Function()? isCancelled,
  }) async {
    final ranked = await rank(addresses, isCancelled: isCancelled);
    return ranked.isEmpty ? null : ranked.first;
  }

  /// Select the address to use, honouring the 15%/3-checks hysteresis.
  ///
  /// [currentAddress] may be null when starting fresh - the best is chosen
  /// immediately. Otherwise a challenger only wins after
  /// [checksBeforeSwitch] consecutive checks where it is at least
  /// [switchThreshold] better.
  static Future<AddressHealth?> select({
    required List<String> addresses,
    required String? currentAddress,
    required Map<String, int> challengerStreak,
    bool Function()? isCancelled,
  }) async {
    final ranked = await rank(addresses, isCancelled: isCancelled);
    if (ranked.isEmpty) return null;
    final best = ranked.first;

    if (currentAddress == null || currentAddress.isEmpty) {
      challengerStreak.clear();
      return best;
    }
    final current = ranked.firstWhere(
      (h) => h.address == currentAddress,
      orElse: () => ranked.first,
    );
    if (best.address == current.address) {
      challengerStreak.clear();
      return current;
    }
    final better = current.score > 0
        ? (current.score - best.score) / current.score
        : 1.0;
    if (better >= switchThreshold) {
      final n = (challengerStreak[best.address] ?? 0) + 1;
      challengerStreak[best.address] = n;
      if (n >= checksBeforeSwitch) {
        challengerStreak.clear();
        return best;
      }
    } else {
      challengerStreak.clear();
    }
    return current;
  }

  /// Split a comma-separated backup-address string into a clean list.
  static List<String> parseAddressList(String raw) {
    if (raw.trim().isEmpty) return const [];
    return raw
        .split(',')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
  }
}

class AddressHealth {
  final String address;
  final String host;
  final int port;
  final int meanRtt;
  final int jitter;
  final double lossPercent;
  final double score;
  final DateTime at;
  const AddressHealth({
    required this.address,
    required this.host,
    required this.port,
    required this.meanRtt,
    required this.jitter,
    required this.lossPercent,
    required this.score,
    required this.at,
  });
}
