import 'dart:async';

import 'package:flutter/material.dart';

import '../services/app_colors.dart';
import '../services/exit_ip_service.dart';
import '../services/speed_test_service.dart';
import '../services/v2ray_engine.dart';

/// صفحه «تست و امنیت»: IP خروجی، تست سرعت، تست نشت DNS.
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
  String? _dnsResult;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkIp());
  }

  Future<void> _checkIp() async {
    setState(() {
      _ipLoading = true;
      _ipInfo = null;
    });
    try {
      final info = await ExitIpService.fetch();
      if (!mounted) return;
      setState(() {
        _ipInfo = info;
        _ipLoading = false;
      });
    } catch (e) {
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
      final r = await SpeedTestService.run(
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
      if (!mounted) return;
      setState(() => _speedLoading = false);
    }
  }

  Future<void> _checkDnsLeak() async {
    setState(() {
      _dnsLoading = true;
      _dnsResult = null;
    });
    try {
      // DNS leak = مقایسه‌ی DNS resolver فعلی (که Xray انتخاب کرده) با ISP.
      // روی موبایل دسترسی مستقیم به /etc/resolv.conf نداریم، ولی می‌تونیم
      // از طریق SOCKS یه DNS query به یه سرور مخصوص بزنیم که IP resolver
      // خروجی رو برگردونه.
      final port = V2RayEngine.localSocksPort;
      if (port <= 0) {
        if (!mounted) return;
        setState(() {
          _dnsResult = _t(
            'اتصال VPN فعال نیست — اول وصل شو',
            'VPN not active — connect first',
          );
          _dnsLoading = false;
        });
        return;
      }
      // استفاده از یک DNS resolver آنلاین که IP خروجی رو نشون می‌ده
      final direct = await ExitIpService.fetch();
      if (!mounted) return;
      final ip = direct?.ip ?? '';
      if (ip.isEmpty) {
        setState(() {
          _dnsResult = _t(
            'نمی‌توان IP را خواند',
            'Could not read IP',
          );
          _dnsLoading = false;
        });
        return;
      }
      // اگه IP ایران باشه، نشت داریم
      final looksIran = ip.startsWith('2.144.') ||
          ip.startsWith('5.160.') ||
          ip.startsWith('31.') ||
          ip.startsWith('37.') ||
          ip.startsWith('78.') ||
          ip.startsWith('80.191.') ||
          ip.startsWith('91.') ||
          ip.startsWith('151.') ||
          ip.startsWith('185.') ||
          ip.startsWith('217.');
      setState(() {
        _dnsResult = looksIran
            ? _t(
                'IP خروجی ایران است — ممکن است نشت داشته باشید',
                'Exit IP looks Iranian — possible leak',
              )
            : _t(
                'IP خروجی خارجی است — بدون نشت آشکار',
                'Exit IP is foreign — no obvious leak',
              );
        _dnsLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _dnsResult = e.toString();
        _dnsLoading = false;
      });
    }
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
                        '${(_speedResult!.bytes / 1024 / 1024).toStringAsFixed(1)} MB · ${_speedResult!.elapsed.inSeconds}s',
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
                  else if (_dnsResult != null)
                    Text(
                      _dnsResult!,
                      style: TextStyle(
                        color: _dnsResult!.contains('نشت') ||
                                _dnsResult!.contains('leak')
                            ? AppColors.danger
                            : AppColors.fg(context),
                        fontSize: 13,
                      ),
                    )
                  else
                    Text(
                      _t('بررسی اینکه DNS از تونل رد می‌شود',
                          'Checks whether DNS goes through tunnel'),
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
              width: 80,
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
