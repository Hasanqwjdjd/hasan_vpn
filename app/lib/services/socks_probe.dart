import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// نتیجه‌ی اندازه‌گیری تأخیر واقعی از داخل یک پروکسی SOCKS5.
class ProbeResult {
  /// میانه‌ی زمان رفت‌وبرگشت یک درخواست HTTP روی اتصال برقرارشده (میلی‌ثانیه).
  final int? ms;

  /// اختلاف بیشترین و کمترین نمونه.
  final int? jitter;

  /// زمان کامل‌شدن CONNECT (شامل بازکردن مسیر تا مقصد از داخل تونل).
  final int? connectMs;

  final String? error;

  const ProbeResult({this.ms, this.jitter, this.connectMs, this.error});

  bool get ok => ms != null;
}

class _Target {
  final String host;
  final int port;
  final String path;
  const _Target(this.host, this.port, this.path);
}

class _Reader {
  final StreamIterator<Uint8List> _it;
  final List<int> _buf = <int>[];

  _Reader(Stream<Uint8List> stream) : _it = StreamIterator<Uint8List>(stream);

  int get buffered => _buf.length;

  Future<void> _fill(Duration timeout) async {
    final has = await _it.moveNext().timeout(timeout);
    if (!has) {
      throw const SocketException('connection closed by peer');
    }
    _buf.addAll(_it.current);
  }

  Future<List<int>> readExactly(int n, Duration timeout) async {
    while (_buf.length < n) {
      await _fill(timeout);
    }
    final out = List<int>.from(_buf.sublist(0, n));
    _buf.removeRange(0, n);
    return out;
  }

  Future<String> readHead(Duration timeout) async {
    while (true) {
      final end = _headEnd();
      if (end >= 0) {
        final head = utf8.decode(_buf.sublist(0, end), allowMalformed: true);
        _buf.removeRange(0, end + 4);
        return head;
      }
      if (_buf.length > 16384) {
        throw const FormatException('http response head too large');
      }
      await _fill(timeout);
    }
  }

  int _headEnd() {
    for (var i = 0; i + 3 < _buf.length; i++) {
      if (_buf[i] == 13 &&
          _buf[i + 1] == 10 &&
          _buf[i + 2] == 13 &&
          _buf[i + 3] == 10) {
        return i;
      }
    }
    return -1;
  }

  Future<void> close() async {
    try {
      await _it.cancel();
    } catch (_) {}
  }
}

/// اندازه‌گیری «پینگ واقعی»: از طریق پروکسی SOCKS5 محلی یک اتصال به مقصد
/// باز می‌کند و چند درخواست `generate_204` می‌فرستد. عددِ برگشتی زمان واقعی
/// عبور داده از کل مسیر (اپ ← تونل ← اینترنت) است، نه فقط زمان رسیدن به سرور.
class SocksProbe {
  SocksProbe._();

  static const List<_Target> _targets = <_Target>[
    _Target('www.gstatic.com', 443, '/generate_204'),
    _Target('www.gstatic.com', 80, '/generate_204'),
    _Target('cp.cloudflare.com', 80, '/generate_204'),
  ];

  static Future<bool> isPortOpen(int port,
      {String host = '127.0.0.1',
      Duration timeout = const Duration(milliseconds: 500)}) async {
    Socket? socket;
    try {
      socket = await Socket.connect(host, port, timeout: timeout);
      return true;
    } catch (_) {
      return false;
    } finally {
      socket?.destroy();
    }
  }

  static Future<ProbeResult> measure({
    required int port,
    String host = '127.0.0.1',
    int samples = 3,
    Duration timeout = const Duration(seconds: 8),
  }) async {
    String? lastError;

    for (final target in _targets) {
      final result = await _measureOnce(
        host: host,
        port: port,
        target: target,
        samples: samples,
        timeout: timeout,
      );
      if (result.ok) return result;
      lastError = result.error;
    }

    return ProbeResult(error: lastError ?? 'probe failed');
  }

  static Future<ProbeResult> _measureOnce({
    required String host,
    required int port,
    required _Target target,
    required int samples,
    required Duration timeout,
  }) async {
    Socket? socket;
    _Reader? reader;

    try {
      socket = await Socket.connect(
        host,
        port,
        timeout: const Duration(seconds: 2),
      );
      socket.setOption(SocketOption.tcpNoDelay, true);
      reader = _Reader(socket);

      // --- SOCKS5 greeting (بدون احراز هویت)
      socket.add(const <int>[0x05, 0x01, 0x00]);
      final greeting = await reader.readExactly(2, timeout);
      if (greeting[0] != 0x05 || greeting[1] != 0x00) {
        throw const FormatException('socks5 greeting rejected');
      }

      // --- CONNECT با نام دامنه (تا DNS داخل تونل حل شود)
      final connectWatch = Stopwatch()..start();
      final hostBytes = utf8.encode(target.host);
      socket.add(<int>[
        0x05,
        0x01,
        0x00,
        0x03,
        hostBytes.length,
        ...hostBytes,
        (target.port >> 8) & 0xFF,
        target.port & 0xFF,
      ]);

      final head = await reader.readExactly(4, timeout);
      if (head[1] != 0x00) {
        throw FormatException('socks5 connect failed (code ${head[1]})');
      }

      final int remaining;
      switch (head[3]) {
        case 0x01:
          remaining = 4 + 2;
          break;
        case 0x04:
          remaining = 16 + 2;
          break;
        case 0x03:
          final len = await reader.readExactly(1, timeout);
          remaining = len[0] + 2;
          break;
        default:
          throw const FormatException('socks5 bad address type');
      }
      await reader.readExactly(remaining, timeout);
      final connectMs = connectWatch.elapsedMilliseconds;

      // --- چند نمونه‌ی HTTP روی همان اتصال
      final times = <int>[];
      final request = ascii.encode(
        'GET ${target.path} HTTP/1.1\r\n'
        'Host: ${target.host}\r\n'
        'User-Agent: Mozilla/5.0\r\n'
        'Accept: */*\r\n'
        'Connection: keep-alive\r\n'
        '\r\n',
      );

      for (var i = 0; i < samples; i++) {
        final watch = Stopwatch()..start();
        socket.add(request);
        final responseHead = await reader.readHead(timeout);
        final elapsed = watch.elapsedMilliseconds;

        if (!responseHead.startsWith('HTTP/1.')) {
          throw const FormatException('unexpected http response');
        }

        times.add(elapsed < 1 ? 1 : elapsed);

        final is204 = responseHead.startsWith('HTTP/1.1 204') ||
            responseHead.startsWith('HTTP/1.0 204');
        // فقط پاسخ 204 بدون بدنه را می‌شود روی همان اتصال تکرار کرد.
        if (!is204 || reader.buffered > 0) break;
      }

      if (times.isEmpty) {
        return const ProbeResult(error: 'no samples');
      }

      times.sort();
      return ProbeResult(
        ms: times[times.length ~/ 2],
        jitter: times.last - times.first,
        connectMs: connectMs,
      );
    } on TimeoutException {
      return const ProbeResult(error: 'timeout');
    } catch (error) {
      return ProbeResult(error: error.toString());
    } finally {
      await reader?.close();
      socket?.destroy();
    }
  }
}
