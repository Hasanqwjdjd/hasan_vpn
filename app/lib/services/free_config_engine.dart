import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/server.dart';
import 'link_parser.dart';
import 'native_delay_probe.dart';
import 'v2ray_engine.dart';

/// Two-stage free-config fetcher + real-connection tester.
///
/// Modeled on mlmvpn_android/engines/freeconfig/FreeConfigEngine.kt:
///
///   Stage 1 — cheap TCP reachability, high concurrency. Drops the (usually
///             large) fraction of candidates whose host:port is simply dead
///             before paying for an Xray spin-up.
///   Stage 2 — real proxied round-trip through a temporary Xray, same
///             primitive the app's "Real Delay" test uses. A dead or
///             hijacked node can still pass a bare TCP handshake, which is
///             why the second stage exists.
///
/// Stop early: returns whatever has been found so far instead of waiting for
/// the target or for candidates to run out.
class FreeConfigEngine {
  FreeConfigEngine._();

  static const String groupName = 'سرور رایگان';

  /// Sources merged into [BuiltinConfigs.dailySources].
  /// Some base64-encoded, some plain text; both are handled.
  static const List<({String url, bool base64})> sources = [
    // MLM VPN's set
    (
      url:
          'https://raw.githubusercontent.com/hello-world-1989/cn-news/main/end-gfw-together',
      base64: true,
    ),
    (
      url:
          'https://raw.githubusercontent.com/V2RayRoot/V2RayConfig/refs/heads/main/Config/vless.txt',
      base64: false,
    ),
    (
      url:
          'https://raw.githubusercontent.com/4n0nymou3/multi-proxy-config-fetcher/refs/heads/main/configs/proxy_configs_tested.txt',
      base64: false,
    ),
    (
      url:
          'https://raw.githubusercontent.com/kingowow/Kingo-vpn/refs/heads/main/server/KingoVpn.txt',
      base64: false,
    ),
    // Hasan's existing two
    (
      url:
          'https://raw.githubusercontent.com/barry-far/V2ray-Config/main/All_Configs_Sub.txt',
      base64: false,
    ),
    (
      url: 'https://raw.githubusercontent.com/mfuu/v2ray/master/v2ray',
      base64: false,
    ),
  ];

  static const List<String> _prefixes = [
    'vless://',
    'vmess://',
    'trojan://',
    'ss://',
  ];

  /// Short TCP probe timeout — most dead entries fail fast.
  static const Duration tcpProbeTimeout = Duration(milliseconds: 1800);

  /// Real-Xray delay test timeout.
  static const Duration realTestTimeout = Duration(seconds: 6);

  /// Concurrency for the cheap stage.
  static const int tcpConcurrency = 30;

  /// Concurrency for the expensive stage.
  static const int realConcurrency = 8;

  /// Download all sources and return deduplicated raw URIs.
  ///
  /// Dedupe key is protocol|host|port|uuid (method:password for ss) rather
  /// than the full string — the same server usually shows up across multiple
  /// lists with only its remark differing.
  static Future<List<String>> fetchCandidates({
    void Function(int done, int total)? onProgress,
  }) async {
    final all = <String>[];
    final client = http.Client();
    try {
      for (var i = 0; i < sources.length; i++) {
        final s = sources[i];
        try {
          final res = await client
              .get(Uri.parse(s.url))
              .timeout(const Duration(seconds: 15));
          if (res.statusCode == 200) {
            var body = res.body;
            if (s.base64) {
              try {
                body = utf8.decode(base64.decode(body.trim()));
              } catch (_) {
                // not valid base64 — keep as is
              }
            }
            for (final line in body.split(RegExp(r'[\r\n]+'))) {
              final t = line.trim();
              if (t.isEmpty) continue;
              if (_prefixes.any((p) => t.toLowerCase().startsWith(p))) {
                all.add(t);
              }
            }
          }
        } catch (e) {
          debugPrint('free_config: source ${s.url} failed: $e');
        }
        onProgress?.call(i + 1, sources.length);
      }
    } finally {
      client.close();
    }

    final seen = <String>{};
    final out = <String>[];
    for (final u in all) {
      final key = _dedupeKey(u);
      if (seen.add(key)) out.add(u);
    }
    return out;
  }

  /// Identity key that ignores remark differences.
  static String _dedupeKey(String uri) {
    try {
      final s = LinkParser.parse(uri, id: '_');
      if (s == null) return uri;
      final proto = s.protocol.name;
      // ss has no uuid; use method:password if available, else host:port
      final secret = s.shareLink.length > 60 ? s.shareLink : '';
      return '$proto|${s.host}|${s.port}|$secret';
    } catch (_) {
      return uri;
    }
  }

  /// Identity for comparing against already-saved servers.
  static String serverKey(String uri) => _dedupeKey(uri);

  /// Cheap reachability: just open a TCP socket to host:port.
  static Future<bool> _tcpReachable(String host, int port) async {
    if (host.isEmpty || port <= 0 || port > 65535) return false;
    Socket? sock;
    try {
      sock = await Socket.connect(host, port, timeout: tcpProbeTimeout);
      return true;
    } catch (_) {
      return false;
    } finally {
      try {
        sock?.destroy();
      } catch (_) {}
    }
  }

  /// Stage 1: filter out the dead. Concurrency-limited.
  static Future<List<String>> _tcpFilter(
    List<String> candidates, {
    bool Function()? isCancelled,
  }) async {
    final out = <String>[];
    var next = 0;
    Future<void> worker() async {
      while (true) {
        if (isCancelled?.call() == true) return;
        final i = next++;
        if (i >= candidates.length) return;
        try {
          final s = LinkParser.parse(candidates[i], id: '_');
          if (s == null) continue;
          if (await _tcpReachable(s.host, s.port)) {
            out.add(candidates[i]);
          }
        } catch (_) {}
      }
    }

    await Future.wait(
      List<Future<void>>.generate(tcpConcurrency, (_) => worker()),
    );
    return out;
  }

  /// Stage 2: real proxied round-trip. Uses NativeDelayProbe (temp Xray).
  static Future<bool> _realTest(String uri) async {
    try {
      final s = LinkParser.parse(uri, id: '_');
      if (s == null) return false;
      final cfg = await V2RayEngine.buildConfigOnly(s);
      if (cfg.isEmpty) return false;
      final delay = await NativeDelayProbe.probeWithFallback(
        cfg,
        timeout: realTestTimeout,
      );
      return delay >= 0;
    } catch (_) {
      return false;
    }
  }

  /// Two-stage funnel that stops as soon as [targetCount] working configs
  /// are found or [isCancelled] returns true.
  static Future<List<VpnServer>> collectWorking({
    required List<String> candidates,
    required int targetCount,
    void Function(int tested, int working, int target)? onProgress,
    bool Function()? isCancelled,
  }) async {
    final shuffled = List<String>.from(candidates)..shuffle();
    final working = <VpnServer>[];
    var tested = 0;

    // Stage 1 in chunks so the stop check is responsive.
    const chunkSize = 60;
    for (var i = 0;
        i < shuffled.length &&
            working.length < targetCount &&
            isCancelled?.call() != true;
        i += chunkSize) {
      final chunk = shuffled.sublist(
        i,
        (i + chunkSize).clamp(0, shuffled.length),
      );
      final survivors = await _tcpFilter(chunk, isCancelled: isCancelled);
      tested += chunk.length - survivors.length;
      onProgress?.call(tested, working.length, targetCount);
      if (isCancelled?.call() == true) break;

      // Stage 2 — small chunks so stop is instant.
      for (var j = 0;
          j < survivors.length &&
              working.length < targetCount &&
              isCancelled?.call() != true;
          j += realConcurrency) {
        final realChunk = survivors.sublist(
          j,
          (j + realConcurrency).clamp(0, survivors.length),
        );
        final results = await Future.wait(
          realChunk.map(_realTest),
        );
        for (var k = 0; k < results.length; k++) {
          tested++;
          if (results[k] && working.length < targetCount) {
            final s = LinkParser.parse(
              realChunk[k],
              id: 'free_${DateTime.now().microsecondsSinceEpoch}_${working.length}',
            );
            if (s != null) working.add(s);
          }
        }
        onProgress?.call(tested, working.length, targetCount);
      }
    }

    return working;
  }

  /// Split fetched servers into (new, alreadyOwned) by comparing against
  /// the URIs of servers the user already has.
  static (List<VpnServer>, int) splitAlreadyOwned(
    List<VpnServer> fresh,
    List<VpnServer> existing,
  ) {
    final existingKeys = existing.map((s) => serverKey(s.shareLink)).toSet();
    final out = <VpnServer>[];
    var owned = 0;
    for (final s in fresh) {
      if (existingKeys.contains(serverKey(s.shareLink))) {
        owned++;
      } else {
        out.add(s);
      }
    }
    return (out, owned);
  }
}
