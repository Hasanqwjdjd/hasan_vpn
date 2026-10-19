import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../services/app_colors.dart';
import '../services/exit_ip_service.dart';
import '../services/speed_test_service.dart';
import '../services/tools_tunnel_service.dart';

/// صفحه «تست و امنیت»: IP خروجی، تست سرعت، تست نشت DNS.
///
/// بخش ۱.۲ — هر سه ابزار حالا خودشان تونل را آماده می‌کنند:
///   • اگر VPN روشن باشد از تونل فعال استفاده می‌شود.
///   • اگر خاموش باشد یک تونل proxy-only موقت از سرور انتخابی/آخر بالا
///     می‌آید (بدون مجوز VPN) و بعد از بستن صفحه پایین کشیده می‌شود.
///   • همه‌ی نتایج برچسب «از داخل تونل / مستقیم» دارند و هر قدم لاگ [Tools]
///     تولید می‌کند.
class SecurityTestScreen extends StatefulWidget {
  final String language;
  const SecurityTestScreen({super.key, required this.language});

  @override
  State<SecurityTestScreen> createState() => _SecurityTestScreenState();
}

class _SecurityTestScreenState extends State<SecurityTestScreen> {
  String _t(String fa, String en) =>
      widget.language == 'fa' ? fa : en;

  ExitIpInfo? _ipInfo;
  bool _ipLoading = false;

  SpeedTestResult? _speedResult;
  bool _speedLoading = false;
  double _speedLiveMbps = 0;
  int _speedLiveBytes = 0;

  bool _dnsLoading = false;

  /// نتیجه‌ی تست نشت DNS — رزولور دیده‌شده از داخل تونل و مستقیم.
  String? _dnsTunnelResolver;
  String? _dnsDirectResolver;
  String? _dnsResult;
  bool _dnsLeak = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkIp());
  }

  @override
  void dispose() {
    // تونل موقتی که فقط برای ابزارها بالا آمده را ببند.
    ToolsTunnelService.releaseOwned();
    super.dispose();
  }

  Future<ToolsProxy?> _ensureTunnel(String why) async {
    final proxy = await ToolsTunnelService.ensure();
    if (proxy == null) {
      debugPrint('[Tools] tunnel unavailable for $why');
    }
    return proxy;
  }

  Future<void> _checkIp() async {
    setState(() {
      _ipLoading = true;
      _ipInfo = null;
    });
    try {
      await _ensureTunnel('exit-ip');
      final info = await ExitIpService.fetch();
      if (!mounted) return;
      setState(() {
        _ipInfo = info;
        _ipLoading = false;
      });
    } catch (e) {
      debugPrint('[Tools] exit-ip failed: $e');
      if (!mounted) return;
      setState(() => _ipLoading = false);
    }
  }

  Future<void> _runSpeedTest() async {
    setState(() {
      _speedLoading = true;
      _speedResult = null;
      _speedLiveMbps = 0;
      _speedLiveBytes = 0;
    });
    try {
      final proxy = await _ensureTunnel('speed-test');
      final r = await SpeedTestService.run(
        socksPort: proxy?.socksPort,
        httpPort: proxy?.httpPort,
        onProgress: (bytes, mbps) {
          if (!mounted) return;
          setState(() {
            _speedLiveBytes = bytes;
            _speedLiveMbps = mbps;
          });
        },
      );
      if (!mounted) return;
      setState(() {
        _speedResult = r;
        _speedLoading = false;
      });
    } catch (e) {
      debugPrint('[Tools] speed test failed: $e');
      if (!mounted) return;
      setState(() {
        _speedResult = SpeedTestResult(error: e.toString());
        _speedLoading = false;
      });
    }
  }

  /// IP رزولور DNS دیده‌شده — از مسیر [viaTunnel] یا مستقیم.
  /// منبع: whoami.akamai.net (plain HTTP) که IP رزولور را برمی‌گرداند.
  Future<String?> _resolverIp({
    int? httpProxyPort,
    int? socksPort,
    required bool viaTunnel,
  }) async {
    const host = 'whoami.akamai.net';

    // ── مسیر HTTP proxy (CONNECT — ترجیحی) ──
    if (viaTunnel && (httpProxyPort ?? 0) > 0) {
      try {
        final client = HttpClient();
        client.findProxy = (uri) => 'PROXY 127.0.0.1:$httpProxyPort';
        client.connectionTimeout = const Duration(seconds: 6);
        final req = await client
            .getUrl(Uri.parse('http://$host/'))
            .timeout(const Duration(seconds: 8));
        final res = await req.close().timeout(const Duration(seconds: 8));
        final body = await res.transform(utf8DecoderSafe).join();
        client.close(force: true);
        final ip = _extractIp(body);
        debugPrint('[DnsLeak] tunnel resolver (http-proxy): $ip');
        return ip;
      } catch (e) {
        debugPrint('[DnsLeak] http-proxy probe failed: $e');
      }
    }

    // ── مسیر SOCKS خام ──
    if (viaTunnel && (socksPort ?? 0) > 0) {
      try {
        final body = await _httpGetViaSocks(
            host, 80, '/', socksPort!, const Duration(seconds: 8));
        final ip = _extractIp(body);
        debugPrint('[DnsLeak] tunnel resolver (socks): $ip');
        return ip;
      } catch (e) {
        debugPrint('[DnsLeak] socks probe failed: $e');
      }
    }

    // ── مسیر مستقیم (baseline) ──
    if (!viaTunnel) {
      try {
        final client = HttpClient();
        client.connectionTimeout = const Duration(seconds: 6);
        final req = await client
            .getUrl(Uri.parse('http://$host/'))
            .timeout(const Duration(seconds: 8));
        final res = await req.close().timeout(const Duration(seconds: 8));
        final body = await res.transform(utf8DecoderSafe).join();
        client.close(force: true);
        final ip = _extractIp(body);
        debugPrint('[DnsLeak] direct resolver: $ip');
        return ip;
      } catch (e) {
        debugPrint('[DnsLeak] direct probe failed: $e');
      }
    }
    return null;
  }

  static const utf8DecoderSafe = Utf8Decoder(allowMalformed: true);

  String? _extractIp(String body) {
    final m =
        RegExp(r'\b(\d{1,3}(?:\.\d{1,3}){3})\b').firstMatch(body.trim());
    return m?.group(1);
  }

  /// GET ساده از داخل SOCKS5 (پلاین HTTP — بدون TLS).
  Future<String> _httpGetViaSocks(
    String host,
    int port,
    String path,
    int socksPort,
    Duration timeout,
  ) async {
    final socket = await Socket.connect(
      InternetAddress.loopbackIPv4,
      socksPort,
      timeout: const Duration(seconds: 5),
    );
    final reader = StreamIterator<Uint8List>(socket);
    try {
      Future<List<int>> readAtLeast(int n) async {
        final buf = <int>[];
        while (buf.length < n) {
          if (!await reader.moveNext().timeout(timeout)) {
            throw const SocketException('connection closed by peer');
          }
          buf.addAll(reader.current);
        }
        return buf;
      }

      socket.add(const <int>[0x05, 0x01, 0x00]);
      final greeting = await readAtLeast(2);
      if (greeting.length < 2 || greeting[0] != 0x05 || greeting[1] != 0x00) {
        throw const SocketException('socks5 greeting rejected');
      }
      final hostBytes = ascii.encode(host);
      socket.add(<int>[
        0x05, 0x01, 0x00, 0x03, hostBytes.length, ...hostBytes,
        (port >> 8) & 0xff, port & 0xff,
      ]);
      final reply = await readAtLeast(4);
      if (reply[1] != 0x00) {
        throw SocketException('socks5 connect failed (${reply[1]})');
      }
      final int atype = reply[3];
      if (atype == 0x01) {
        await readAtLeast(6);
      } else if (atype == 0x04) {
        await readAtLeast(18);
      } else {
        final l = (await readAtLeast(1))[0];
        await readAtLeast(l + 2);
      }
      socket.add(ascii.encode(
        'GET $path HTTP/1.1\r\nHost: $host\r\nConnection: close\r\n\r\n',
      ));
      await socket.flush();
      final body = <int>[];
      while (body.length <= 8192) {
        if (!await reader.moveNext().timeout(timeout)) break;
        body.addAll(reader.current);
      }
      return String.fromCharCodes(body);
    } finally {
      try {
        await reader.cancel();
      } catch (_) {}
      try {
        socket.destroy();
      } catch (_) {}
    }
  }

  Future<void> _checkDnsLeak() async {
    setState(() {
      _dnsLoading = true;
      _dnsResult = null;
      _dnsTunnelResolver = null;
      _dnsDirectResolver = null;
      _dnsLeak = false;
    });
    try {
      final proxy = await _ensureTunnel('dns-leak');
      if (proxy == null) {
        if (!mounted) return;
        setState(() {
          _dnsResult = _t(
            'هیچ تونلی در دسترس نیست — اول یک سرور اضافه/انتخاب کن',
            'No tunnel available — add/select a server first',
          );
          _dnsLoading = false;
        });
        return;
      }

      // baseline مستقیم (رزولور ISP)
      final direct = await _resolverIp(viaTunnel: false);
      if (!mounted) return;
      setState(() => _dnsDirectResolver = direct);

      // رزولور دیده‌شده از داخل تونل
      final tunnel = await _resolverIp(
        httpProxyPort: proxy.httpPort,
        socksPort: proxy.socksPort,
        viaTunnel: true,
      );
      if (!mounted) return;
      setState(() => _dnsTunnelResolver = tunnel);

      String verdict;
      bool leak = false;
      if (tunnel == null) {
        verdict = _t(
          'رزولور DNS تونل خوانده نشد — تونل پاسخگو نبود',
          'Could not read the tunnel DNS resolver — tunnel not answering',
        );
        leak = true;
      } else if (direct == null) {
        verdict = _t(
          'رزولور تونل: $tunnel — baseline مستقیم خوانده نشد؛ مقایسه ممکن نیست',
          'Tunnel resolver: $tunnel — direct baseline unavailable; comparison skipped',
        );
      } else {
        final same = tunnel == direct || _sameSlash24(tunnel, direct);
        leak = same;
        verdict = same
            ? _t(
                'نشت DNS: رزولور تونل و مستقیم یکسان است ($tunnel)',
                'DNS leak: tunnel and direct resolvers are identical ($tunnel)',
              )
            : _t(
                'بدون نشت آشکار — DNS از داخل تونل resolve می‌شود '
                '($tunnel ≠ $direct)',
                'No obvious leak — DNS resolves inside the tunnel '
                '($tunnel ≠ $direct)',
              );
      }
      debugPrint('[DnsLeak] verdict=$verdict leak=$leak');
      setState(() {
        _dnsResult = verdict;
        _dnsLeak = leak;
        _dnsLoading = false;
      });
    } catch (e) {
      debugPrint('[DnsLeak] failed: $e');
      if (!mounted) return;
      setState(() {
        _dnsResult = e.toString();
        _dnsLoading = false;
      });
    }
  }

  bool _sameSlash24(String a, String b) {
    final pa = a.split('.');
    final pb = b.split('.');
    if (pa.length != 4 || pb.length != 4) return false;
    return pa[0] == pb[0] && pa[1] == pb[1] && pa[2] == pb[2];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg(context),
      appBar: AppBar(
        backgroundColor: AppColors.bg(context),
        elevation: 0,
        iconTheme: IconThemeData(color: AppColors.fg(context)),
        title: Text(
          _t('تست و امنیت', 'Test & Security'),
          style: TextStyle(color: AppColors.fg(context)),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _sectionTitle(_t('IP خروجی', 'Exit IP')),
            _card(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (_ipLoading)
                    const Center(
                      child: Padding(
                        padding: EdgeInsets.all(12),
                        child: CircularProgressIndicator(),
                      ),
                    )
                  else if (_ipInfo != null) ...[
                    _kv('IP', _ipInfo!.ip),
                    if (_ipInfo!.country != null)
                      _kv(_t('کشور', 'Country'), _ipInfo!.country!),
                    if (_ipInfo!.city != null)
                      _kv(_t('شهر', 'City'), _ipInfo!.city!),
                    if (_ipInfo!.org != null)
                      _kv(_t('سازمان', 'Org'), _ipInfo!.org!),
                    const SizedBox(height: 6),
                    _tunnelBadge(_ipInfo!.viaTunnel),
                  ] else
                    Text(
                      _t('خطا در خواندن IP', 'Failed to read IP'),
                      style: TextStyle(color: AppColors.danger),
                    ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _ipLoading ? null : _checkIp,
                      icon: const Icon(Icons.refresh, size: 18),
                      label: Text(_t('خواندن مجدد', 'Refresh')),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            _sectionTitle(_t('تست سرعت', 'Speed test')),
            _card(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (_speedLoading) ...[
                    Center(
                      child: Text(
                        '${_speedLiveMbps.toStringAsFixed(2)} Mbps',
                        style: TextStyle(
                          color: AppColors.accent,
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '${(_speedLiveBytes / 1024 / 1024).toStringAsFixed(1)} MB',
                      style: TextStyle(
                        color: AppColors.muted(context),
                        fontSize: 12,
                      ),
                    ),
                  ] else if (_speedResult != null) ...[
                    if (_speedResult!.error != null)
                      Text(
                        _speedResult!.error!,
                        style: const TextStyle(color: Colors.red),
                      )
                    else ...[
                      Text(
                        '${_speedResult!.mbps.toStringAsFixed(2)} Mbps',
                        style: TextStyle(
                          color: AppColors.accent,
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        '${(_speedResult!.bytes / 1024 / 1024).toStringAsFixed(1)} MB · '
                            '${_speedResult!.elapsed.inSeconds}s · ${_speedResult!.via}',
                        style: TextStyle(
                          color: AppColors.muted(context),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ] else
                    Text(
                      _t('برای شروع تست دکمه را بزن',
                          'Tap the button to start'),
                      style: TextStyle(color: AppColors.muted(context)),
                    ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _speedLoading ? null : _runSpeedTest,
                      icon: const Icon(Icons.speed, size: 18),
                      label: Text(_t('شروع تست', 'Start test')),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            _sectionTitle(_t('تست نشت DNS', 'DNS leak check')),
            _card(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (_dnsLoading)
                    const Center(
                      child: Padding(
                        padding: EdgeInsets.all(12),
                        child: CircularProgressIndicator(),
                      ),
                    )
                  else if (_dnsResult != null) ...[
                    if (_dnsTunnelResolver != null)
                      _kv(_t('رزولور تونل', 'Tunnel resolver'),
                          _dnsTunnelResolver!),
                    if (_dnsDirectResolver != null)
                      _kv(_t('رزولور مستقیم', 'Direct resolver'),
                          _dnsDirectResolver!),
                    const SizedBox(height: 6),
                    Text(
                      _dnsResult!,
                      style: TextStyle(
                        color: _dnsLeak ? AppColors.danger : AppColors.good,
                        fontSize: 13,
                      ),
                    ),
                  ] else
                    Text(
                      _t(
                          'مقایسه‌ی واقعی رزولور DNS از داخل تونل و مستقیم',
                          'Real resolver comparison: tunnel vs direct'),
                      style: TextStyle(color: AppColors.muted(context)),
                    ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _dnsLoading ? null : _checkDnsLeak,
                      icon: const Icon(Icons.security, size: 18),
                      label: Text(_t('بررسی', 'Check')),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// برچسب مسیر نتیجه‌ی IP: داخل تونل یا مستقیم.
  Widget _tunnelBadge(bool viaTunnel) {
    final fa = viaTunnel ? 'از داخل تونل' : 'مستقیم — بدون تونل';
    final en = viaTunnel ? 'via tunnel' : 'direct — no tunnel';
    final color = viaTunnel ? AppColors.good : AppColors.warn;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Text(
        _t(fa, en),
        style: TextStyle(color: color, fontSize: 11),
      ),
    );
  }

  Widget _sectionTitle(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(
          text,
          style: TextStyle(
            color: AppColors.muted(context),
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
      );

  Widget _card({required Widget child}) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.surface(context),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border(context)),
        ),
        child: child,
      );

  Widget _kv(String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          children: [
            SizedBox(
              width: 110,
              child: Text(
                k,
                style: TextStyle(
                  color: AppColors.muted(context),
                  fontSize: 12,
                ),
              ),
            ),
            Expanded(
              child: Text(
                v,
                style: TextStyle(
                  color: AppColors.fg(context),
                  fontSize: 13,
                  fontFamily: 'monospace',
                ),
              ),
            ),
          ],
        ),
      );
}
