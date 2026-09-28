import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/server.dart';

/// تست لینک — کیفیت مسیر به هر سرور.
///
/// روش از BackPack docs/choosing-a-transport.md گرفته شده: روی TCP handshake
/// (SYN → SYN-ACK) اندازه می‌گیره، نه ICMP — چون خیلی از مسیرهای ایران پینگ
/// ICMP رو drop می‌کنن ولی ترافیک TCP رو بی‌مشکل عبور می‌دهند. سروری که
/// ping توش dead ئه ممکنه یه تونل عالی حمل کنه.
///
/// هر sample = RTT کامل TCP handshake به host:port. جیتر = میانگین قدرمطلق
/// اختلاف نمونه‌های متوالی. loss = نسبت اتصال‌های timeout شده.
class LinkTest {
  LinkTest._();

  static const int defaultSamples = 8;
  static const Duration sampleSpacing = Duration(milliseconds: 80);
  static const Duration perSampleTimeout = Duration(seconds: 3);
  static const String _prefKey = 'link_test_results_v1';

  /// تعیین تیربندی از روی median RTT، jitter و loss.
  static LinkGrade gradeFor({
    required int? medianRtt,
    required int jitter,
    required double loss,
  }) {
    if (medianRtt == null || loss >= 0.30) return LinkGrade.f;
    if (loss >= 0.15 || medianRtt > 1000 || jitter > 200) return LinkGrade.d;
    if (loss >= 0.05 || medianRtt > 500 || jitter > 100) return LinkGrade.c;
    if (loss >= 0.01 || medianRtt > 300 || jitter > 60) return LinkGrade.b;
    if (medianRtt > 150 || jitter > 30) return LinkGrade.b;
    return LinkGrade.a;
  }

  /// یک سرور را اندازه می‌گیرد.
  static Future<LinkTestResult> run(
    VpnServer server, {
    int samples = defaultSamples,
    bool Function()? isCancelled,
  }) async {
    final rtts = <int>[];
    var sent = 0;
    var received = 0;

    for (var i = 0; i < samples; i++) {
      if (isCancelled?.call() == true) break;
      sent++;
      final rtt = await _tcpRtt(server.host, server.port);
      if (rtt != null) {
        rtts.add(rtt);
        received++;
      }
      if (i < samples - 1) await Future<void>.delayed(sampleSpacing);
    }

    if (rtts.isEmpty) {
      return LinkTestResult(
        serverId: server.id,
        serverName: server.displayName,
        host: server.host,
        port: server.port,
        sent: sent,
        received: 0,
        rtts: const [],
        medianRtt: null,
        jitter: 0,
        loss: sent == 0 ? 1.0 : 1.0,
        grade: LinkGrade.f,
        at: DateTime.now(),
      );
    }

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
    final loss = sent == 0 ? 0.0 : (sent - received) / sent;

    return LinkTestResult(
      serverId: server.id,
      serverName: server.displayName,
      host: server.host,
      port: server.port,
      sent: sent,
      received: received,
      rtts: rtts,
      medianRtt: median,
      jitter: jitter,
      loss: loss,
      grade: gradeFor(medianRtt: median, jitter: jitter, loss: loss),
      at: DateTime.now(),
    );
  }

  /// RTT یک TCP handshake به host:port.
  static Future<int?> _tcpRtt(String host, int port) async {
    if (host.isEmpty || port <= 0 || port > 65535) return null;
    Socket? sock;
    try {
      final sw = Stopwatch()..start();
      sock = await Socket.connect(host, port, timeout: perSampleTimeout);
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

  /// اجرای موازی چند سرور با worker pool.
  static Future<List<LinkTestResult>> runMany(
    List<VpnServer> servers, {
    int samples = defaultSamples,
    int workers = 4,
    void Function(LinkTestResult)? onResult,
    bool Function()? isCancelled,
  }) async {
    if (servers.isEmpty) return const [];
    final out = <LinkTestResult>[];
    var next = 0;

    Future<void> worker() async {
      while (true) {
        if (isCancelled?.call() == true) return;
        final i = next++;
        if (i >= servers.length) return;
        final r = await run(
          servers[i],
          samples: samples,
          isCancelled: isCancelled,
        );
        out.add(r);
        onResult?.call(r);
      }
    }

    final w = workers.clamp(1, 8);
    await Future.wait(List<Future<void>>.generate(w, (_) => worker()));

    out.sort((a, b) {
      final c = a.grade.index.compareTo(b.grade.index);
      if (c != 0) return c;
      return (a.medianRtt ?? 99999).compareTo(b.medianRtt ?? 99999);
    });
    return out;
  }

  static Future<void> saveResults(List<LinkTestResult> results) async {
    final prefs = await SharedPreferences.getInstance();
    final list = results.map((r) => r.toJson()).toList();
    await prefs.setString(
      _prefKey,
      jsonEncode({
        'at': DateTime.now().toIso8601String(),
        'results': list,
      }),
    );
  }

  static Future<List<LinkTestResult>> loadResults() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefKey);
    if (raw == null || raw.isEmpty) return const [];
    try {
      final doc = jsonDecode(raw);
      if (doc is! Map) return const [];
      final list = doc['results'];
      if (list is! List) return const [];
      return list
          .whereType<Map>()
          .map((e) => LinkTestResult.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    } catch (_) {
      return const [];
    }
  }
}

enum LinkGrade { a, b, c, d, f }

class LinkTestResult {
  final String serverId;
  final String serverName;
  final String host;
  final int port;
  final int sent;
  final int received;
  final List<int> rtts;
  final int? medianRtt;
  final int jitter;
  final double loss;
  final LinkGrade grade;
  final DateTime at;

  const LinkTestResult({
    required this.serverId,
    required this.serverName,
    required this.host,
    required this.port,
    required this.sent,
    required this.received,
    required this.rtts,
    required this.medianRtt,
    required this.jitter,
    required this.loss,
    required this.grade,
    required this.at,
  });

  String get gradeLetter {
    switch (grade) {
      case LinkGrade.a:
        return 'A';
      case LinkGrade.b:
        return 'B';
      case LinkGrade.c:
        return 'C';
      case LinkGrade.d:
        return 'D';
      case LinkGrade.f:
        return 'F';
    }
  }

  Map<String, dynamic> toJson() => {
        'serverId': serverId,
        'serverName': serverName,
        'host': host,
        'port': port,
        'sent': sent,
        'received': received,
        'rtts': rtts,
        'medianRtt': medianRtt,
        'jitter': jitter,
        'loss': loss,
        'grade': grade.name,
        'at': at.toIso8601String(),
      };

  factory LinkTestResult.fromJson(Map<String, dynamic> j) {
    final g = j['grade']?.toString() ?? 'f';
    final grade = LinkGrade.values.firstWhere(
      (e) => e.name == g,
      orElse: () => LinkGrade.f,
    );
    return LinkTestResult(
      serverId: j['serverId']?.toString() ?? '',
      serverName: j['serverName']?.toString() ?? '',
      host: j['host']?.toString() ?? '',
      port: (j['port'] as num?)?.toInt() ?? 0,
      sent: (j['sent'] as num?)?.toInt() ?? 0,
      received: (j['received'] as num?)?.toInt() ?? 0,
      rtts: ((j['rtts'] as List?) ?? const [])
          .whereType<num>()
          .map((e) => e.toInt())
          .toList(),
      medianRtt: (j['medianRtt'] as num?)?.toInt(),
      jitter: (j['jitter'] as num?)?.toInt() ?? 0,
      loss: (j['loss'] as num?)?.toDouble() ?? 1.0,
      grade: grade,
      at: DateTime.tryParse(j['at']?.toString() ?? '') ?? DateTime.now(),
    );
  }
}
