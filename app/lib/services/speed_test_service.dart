import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';

import 'tools_tunnel_service.dart';
import 'v2ray_engine.dart';

/// تست سرعت دانلود از داخل تونل (پروکسی محلی).
///
/// بخش ۱.۲ — قبلاً این سرویس دو باگ داشت:
///   1. کاندید پورت‌ها [localSocksPort, 10808, 9050] بود در حالی که SOCKS
///      واقعی هسته در بیلد فعلی روی 10807 است → خطای «no SOCKS port
///      listening».
///   2. بعد از پیدا شدن پورت، دانلود «مستقیم» انجام می‌شد (findProxy با
///      SOCKS در Dart کار نمی‌کند) → عدد نشان‌داده‌شده سرعت تونل نبود.
///
/// حالا: دانلود واقعی از مسیر HTTP proxy محلی (CONNECT — پشتیبانی کامل
/// https در Dart) و در نبود آن از مسیر خام SOCKS5 برای لینک‌های http.
class SpeedTestResult {
  final double mbps;
  final int bytes;
  final Duration elapsed;

  /// مسیر واقعی اندازه‌گیری: 'http-proxy' | 'socks' | 'direct-fallback'
  final String via;
  final String? error;

  const SpeedTestResult({
    this.mbps = 0,
    this.bytes = 0,
    this.elapsed = Duration.zero,
    this.via = '',
    this.error,
  });

  String get summary => error != null
      ? 'خطا: $error'
      : '${mbps.toStringAsFixed(2)} Mbps (${via == 'http-proxy'
          ? 'HTTP proxy'
          : via == 'socks'
              ? 'SOCKS'
              : 'direct'})';
}

class SpeedTestService {
  SpeedTestService._();

  /// URL های تست به ترتیب اولویت — اگه اولی fail داد، بعدی.
  /// هم HTTPS هم HTTP (بعضی تونل‌ها HTTP رو سریع‌تر رد می‌کنن)، و
  /// چند endpoint مختلف تا اگه یکی مسدود بود، بعدی جواب بده.
  static const List<String> _testUrls = <String>[
    'https://speed.cloudflare.com/__down?bytes=20000000',
    'http://speedtest.tele2.net/10MB.zip',
    'https://proof.ovh.net/files/10Mb.dat',
    'http://ipv4.download.thinkbroadband.com/10MB.zip',
    'https://cachefly.cachefly.net/10mb.test',
    'http://cachefly.cachefly.net/10mb.test',
    'https://ash-speed.hetzner.com/10MB.bin',
  ];

  /// اجرای تست سرعت. اگر پورت‌ها داده نشوند، خودش پورت‌های زنده را پیدا
  /// می‌کند (بدون بالا آوردن تونل موقت — برای آن از ToolsTunnelService.ensure
  /// در صفحه‌ی ابزارها استفاده می‌شود).
  static Future<SpeedTestResult> run({
    int? socksPort,
    int? httpPort,
    Duration timeout = const Duration(seconds: 20),
    void Function(int bytes, double mbps)? onProgress,
  }) async {
    int? hp = httpPort;
    int? sp = socksPort;
    if (hp == null || hp <= 0) {
      hp = await ToolsTunnelService.findHttpPort();
    }
    if (sp == null || sp <= 0) {
      sp = await ToolsTunnelService.findSocksPort();
    }
    debugPrint('[SpeedTest] ports: http=$hp socks=$sp');

    final errors = <String>[];

    // ─── مسیر ۱: HTTP proxy محلی (CONNECT — https هم کار می‌کند) ───
    if (hp != null && hp > 0) {
      for (final url in _testUrls) {
        final r = await _downloadViaHttpProxy(url, hp, timeout, onProgress);
        if (r.error == null && r.bytes > 0) return r;
        if (r.error != null) errors.add('${Uri.parse(url).host}: ${r.error}');
      }
    }

    // ─── مسیر ۲: SOCKS5 خام (فقط http:// — TLS دستی نداریم) ───
    if (sp != null && sp > 0) {
      for (final url in _testUrls.where((u) => u.startsWith('http://'))) {
        final r = await _downloadViaRawSocks(url, sp, timeout, onProgress);
        if (r.error == null && r.bytes > 0) return r;
        if (r.error != null) errors.add('${Uri.parse(url).host}: ${r.error}');
      }
    }

    if ((hp == null || hp <= 0) && (sp == null || sp <= 0)) {
      final tried = V2RayEngine.localSocksPort > 0
          ? 'localSocks=${V2RayEngine.localSocksPort}'
          : 'no tunnel';
      return SpeedTestResult(
        error: 'no local proxy listening — connect a server first ($tried)',
      );
    }
    final tail = errors.length > 2
        ? errors.sublist(errors.length - 2).join(' | ')
        : errors.join(' | ');
    return SpeedTestResult(error: 'all urls failed — $tail');
  }

  static Future<SpeedTestResult> _downloadViaHttpProxy(
    String url,
    int proxyPort,
    Duration timeout,
    void Function(int bytes, double mbps)? onProgress,
  ) async {
    final uri = Uri.parse(url);
    final sw = Stopwatch()..start();
    HttpClient? client;
    try {
      client = HttpClient();
      // دانلود واقعی از داخل تونل: همه‌ی درخواست‌ها از HTTP proxy محلی
      // (Xray inbound) رد می‌شوند.
      client.findProxy = (uri) => 'PROXY 127.0.0.1:$proxyPort';
      client.connectionTimeout = const Duration(seconds: 15);
      client.badCertificateCallback = (_, __, ___) => true;

      final req = await client.getUrl(uri).timeout(timeout);
      final res = await req.close().timeout(timeout);
      debugPrint('[SpeedTest] via http-proxy $proxyPort → '
          '${uri.host} status=${res.statusCode}');

      final r = await _drainBody(res, sw, timeout, onProgress);
      client.close(force: true);
      return SpeedTestResult(
        mbps: r.$1,
        bytes: r.$2,
        elapsed: sw.elapsed,
        via: 'http-proxy',
      );
    } catch (e) {
      try {
        client?.close(force: true);
      } catch (_) {}
      return SpeedTestResult(error: e.toString());
    }
  }

  static Future<SpeedTestResult> _downloadViaRawSocks(
    String url,
    int socksPort,
    Duration timeout,
    void Function(int bytes, double mbps)? onProgress,
  ) async {
    final uri = Uri.parse(url);
    final host = uri.host;
    final port = uri.port == 0 ? 80 : uri.port;
    final sw = Stopwatch()..start();
    Socket? socket;
    StreamIterator<Uint8List>? reader;
    try {
      socket = await Socket.connect(
        InternetAddress.loopbackIPv4,
        socksPort,
        timeout: const Duration(seconds: 5),
      );
      socket.setOption(SocketOption.tcpNoDelay, true);
      reader = StreamIterator<Uint8List>(socket);

      Future<List<int>> readAtLeast(int n) async {
        final buf = <int>[];
        while (buf.length < n) {
          if (!await reader!.moveNext().timeout(timeout)) {
            throw const SocketException('connection closed by peer');
          }
          buf.addAll(reader.current);
        }
        return buf;
      }

      // SOCKS5 greeting
      socket.add(const <int>[0x05, 0x01, 0x00]);
      final greeting = await readAtLeast(2);
      if (greeting.length < 2 || greeting[0] != 0x05 || greeting[1] != 0x00) {
        return SpeedTestResult(error: 'socks5 greeting rejected on $socksPort');
      }
      // CONNECT host:port با نام دامنه
      final hostBytes = ascii.encode(host);
      socket.add(<int>[
        0x05, 0x01, 0x00, 0x03, hostBytes.length, ...hostBytes,
        (port >> 8) & 0xff, port & 0xff,
      ]);
      final replyHead = await readAtLeast(4);
      if (replyHead[1] != 0x00) {
        return SpeedTestResult(error: 'socks5 connect failed (${replyHead[1]})');
      }
      final int atype = replyHead[3];
      final int restLen = atype == 0x01 ? 6 : (atype == 0x04 ? 18 : -1);
      if (restLen < 0) {
        final l = (await readAtLeast(1))[0];
        await readAtLeast(l + 2);
      } else {
        await readAtLeast(restLen);
      }

      final path = uri.path.isEmpty ? '/' : uri.path;
      socket.add(ascii.encode(
        'GET $path HTTP/1.1\r\nHost: $host\r\nUser-Agent: Mozilla/5.0\r\n'
        'Accept: */*\r\nConnection: close\r\n\r\n',
      ));
      await socket.flush();

      // header تا \r\n\r\n + شمارش body روی همان reader
      final head = <int>[];
      List<int> bodyTail = const <int>[];
      var headerDone = false;
      while (!headerDone) {
        if (!await reader.moveNext().timeout(timeout)) {
          throw const SocketException('connection closed before header');
        }
        head.addAll(reader.current);
        final s = ascii.decode(head, allowMalformed: true);
        final idx = s.indexOf('\r\n\r\n');
        if (idx >= 0) {
          debugPrint('[SpeedTest] via socks $socksPort → $host '
              '${s.split('\r\n').first}');
          bodyTail = head.sublist(idx + 4);
          headerDone = true;
        } else if (head.length > 32768) {
          return SpeedTestResult(error: 'http head too large');
        }
      }

      int bytes = bodyTail.length;
      final completer = Completer<void>();
      void count(List<int> chunk) {
        bytes += chunk.length;
        final secs = sw.elapsedMilliseconds / 1000.0;
        if (secs > 0.5) {
          final mbps = (bytes * 8) / secs / 1000000;
          onProgress?.call(bytes, mbps);
        }
        if (bytes >= 10000000 && !completer.isCompleted) {
          completer.complete();
        }
      }

      count(const <int>[]); // تا progress اولیه هم اعمال شود
      while (!completer.isCompleted) {
        if (!await reader.moveNext().timeout(timeout)) break;
        count(reader.current);
      }
      sw.stop();
      final secs = sw.elapsedMilliseconds / 1000.0;
      final mbps = secs > 0 ? (bytes * 8) / secs / 1000000 : 0.0;
      return SpeedTestResult(
        mbps: mbps,
        bytes: bytes,
        elapsed: sw.elapsed,
        via: 'socks',
      );
    } catch (e) {
      return SpeedTestResult(error: e.toString());
    } finally {
      try {
        await reader?.cancel();
      } catch (_) {}
      try {
        socket?.destroy();
      } catch (_) {}
    }
  }

  /// خواندن body و شمارش بایت‌ها برای HTTP proxy مسیر.
  static Future<(double, int)> _drainBody(
    HttpClientResponse res,
    Stopwatch sw,
    Duration timeout,
    void Function(int bytes, double mbps)? onProgress,
  ) async {
    int bytes = 0;
    final completer = Completer<void>();
    late final StreamSubscription<List<int>> sub;
    sub = res.listen(
      (chunk) {
        bytes += chunk.length;
        final secs = sw.elapsedMilliseconds / 1000.0;
        if (secs > 0.5) {
          final mbps = (bytes * 8) / secs / 1000000;
          onProgress?.call(bytes, mbps);
        }
        if (bytes >= 10000000 && !completer.isCompleted) {
          completer.complete();
        }
      },
      onDone: () {
        if (!completer.isCompleted) completer.complete();
      },
      onError: (e) {
        if (!completer.isCompleted) completer.completeError(e);
      },
      cancelOnError: true,
    );
    await completer.future.timeout(timeout, onTimeout: () {
      sub.cancel();
    });
    sw.stop();
    final secs = sw.elapsedMilliseconds / 1000.0;
    final mbps = secs > 0 ? (bytes * 8) / secs / 1000000 : 0.0;
    return (mbps, bytes);
  }
}
