import 'package:shared_preferences/shared_preferences.dart';

import 'fast_probe.dart';

/// Quick Connect: probe current server list, pick best by score, remember last 3.
/// Does NOT call connect itself — returns winner for the existing connect flow.
class QuickConnect {
  QuickConnect._();

  static const _prefsKey = 'quick_connect_winners_v1';

  /// score = rtt + 2*jitter + 20*loss_pct  (lower is better)
  static double score(ProbeResult r) {
    final rtt = (r.rttMs ?? 9999).toDouble();
    return rtt + 2.0 * r.jitterMs + 20.0 * r.lossPct;
  }

  /// [servers] each: {id?, host, port?, protocol?, name?}
  static Future<Map<String, dynamic>?> pickBest(
    List<Map<String, dynamic>> servers, {
    int workers = 8,
  }) async {
    if (servers.isEmpty) return null;
    final items = servers.map((s) {
      return {
        'host': s['host']?.toString() ?? '',
        'port': s['port'] ?? 443,
        'protocol': s['protocol'] ?? 'tcp',
      };
    }).toList();

    final results = await FastProbe.probeMany(items, workers: workers);
    ProbeResult? best;
    var bestScore = double.infinity;
    for (final r in results) {
      if (!r.ok) continue;
      final sc = score(r);
      if (sc < bestScore) {
        bestScore = sc;
        best = r;
      }
    }
    if (best == null) return null;

    Map<String, dynamic>? winner;
    for (final s in servers) {
      if (s['host']?.toString() == best.host) {
        winner = Map<String, dynamic>.from(s);
        break;
      }
    }
    winner ??= {'host': best.host, 'port': best.port};
    winner['rttMs'] = best.rttMs;
    winner['jitterMs'] = best.jitterMs;
    winner['lossPct'] = best.lossPct;
    winner['score'] = bestScore;

    await _remember(winner);
    return winner;
  }

  static Future<void> _remember(Map<String, dynamic> winner) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_prefsKey) ?? <String>[];
    final id = winner['id']?.toString() ??
        '\( {winner['host']}: \){winner['port'] ?? 443}';
    final next = <String>[id, ...raw.where((e) => e != id)].take(3).toList();
    await prefs.setStringList(_prefsKey, next);
  }

  static Future<List<String>> lastWinners() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(_prefsKey) ?? <String>[];
  }
}
