// app/lib/screens/per_app_quality_screen.dart
//
// Per-App Quality & Data Usage — needs PACKAGE_USAGE_STATS.
// Reads from the native side via the `device` channel:
//   - perAppStats: returns list of {packageName, name, txBytes,
//     rxBytes, avgRttMs (may be null), packetLossPct (may be null)}
//   - openUsageSettings: opens the system permission screen.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/app_colors.dart';
import '../services/connection_log_service.dart';

class PerAppQualityScreen extends StatefulWidget {
  final String language;
  const PerAppQualityScreen({super.key, this.language = 'fa'});

  @override
  State<PerAppQualityScreen> createState() => _PerAppQualityScreenState();
}

class _PerAppQualityScreenState extends State<PerAppQualityScreen> {
  static const _deviceChannel = MethodChannel('com.hasan.hasan_vpn/device');

  bool _loading = true;
  bool _permissionGranted = true;
  List<Map<String, dynamic>> _appStats = [];

  // Session-level stats aggregated from ConnectionLogService (7-day
  // window). Per-app RTT would require foreground-app usage stats; the
  // session view is what we can reliably measure.
  double? _avgRttMs;
  int? _sampleCount;
  int _sessionCount = 0;

  bool get _isFa => widget.language == 'fa';
  String _t(String fa, String en) => _isFa ? fa : en;

  @override
  void initState() {
    super.initState();
    _loadStats();
  }

  Future<void> _loadStats() async {
    setState(() => _loading = true);
    try {
      final raw = await _deviceChannel
          .invokeMethod<List<dynamic>>('perAppStats');
      if (raw == null) {
        if (!mounted) return;
        setState(() {
          _permissionGranted = false;
          _loading = false;
        });
        return;
      }
      final parsed = raw
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
      // Aggregate session stats from the connection log (last 7 days).
      final stats = await _computeSessionStats();
      if (!mounted) return;
      setState(() {
        _appStats = parsed;
        _permissionGranted = true;
        _loading = false;
        _avgRttMs = stats.avgRttMs;
        _sampleCount = stats.sampleCount;
        _sessionCount = stats.sessionCount;
      });
    } on PlatformException catch (e) {
      if (!mounted) return;
      if (e.code == 'PERMISSION_DENIED' ||
          e.code == 'USAGE_STATS_NOT_GRANTED') {
        setState(() {
          _permissionGranted = false;
          _loading = false;
        });
      } else {
        setState(() => _loading = false);
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Parse the connection log for the last 7 days and compute
  /// average RTT and total sample count from disconnect records.
  Future<({double? avgRttMs, int? sampleCount, int sessionCount})>
      _computeSessionStats() async {
    try {
      final entries = await ConnectionLogService.load();
      final cutoff = DateTime.now().subtract(const Duration(days: 7));
      var totalRtt = 0;
      var samples = 0;
      var sessions = 0;
      final rttRe = RegExp(r'rtt\s+(\d+)ms');
      for (final e in entries) {
        if (e.timestamp.isBefore(cutoff)) continue;
        if (e.type == 'disconnect') {
          sessions++;
          final d = e.detail ?? '';
          final m = rttRe.firstMatch(d);
          if (m != null) {
            final v = int.tryParse(m.group(1)!);
            if (v != null && v > 0) {
              totalRtt += v;
              samples++;
            }
          }
        }
      }
      return (
        avgRttMs: samples > 0 ? totalRtt / samples : null,
        sampleCount: samples > 0 ? samples : null,
        sessionCount: sessions,
      );
    } catch (_) {
      return (avgRttMs: null, sampleCount: null, sessionCount: 0);
    }
  }

  Future<void> _openUsageSettings() async {
    try {
      await _deviceChannel.invokeMethod('openUsageSettings');
    } catch (_) {}
  }

  String _formatBytes(num bytes) {
    if (bytes < 1024) return '${bytes.toInt()} B';
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg(context),
      appBar: AppBar(
        backgroundColor: AppColors.surface(context),
        title: Text(
          _t('کیفیت و مصرف برنامه‌ها', 'Per-App Quality & Usage'),
          style: TextStyle(color: AppColors.fg(context), fontSize: 16),
        ),
        iconTheme: IconThemeData(color: AppColors.fg(context)),
        actions: [
          IconButton(
            icon: Icon(Icons.refresh, color: AppColors.fg(context)),
            onPressed: _loadStats,
            tooltip: _t('بازخوانی', 'Refresh'),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : !_permissionGranted
              ? _buildPermissionPrompt()
              : Column(
                  children: [
                    _buildSessionCard(),
                    Expanded(child: _buildStatsList()),
                  ],
                ),
    );
  }

  Widget _buildPermissionPrompt() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.security,
                size: 64, color: AppColors.muted2(context)),
            const SizedBox(height: 16),
            Text(
              _t('دسترسی به آمار مصرف نیاز است',
                  'Usage access permission required'),
              style: TextStyle(
                color: AppColors.fg(context),
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              _t(
                'برای نمایش میزان حجم مصرفی هر برنامه در ۷ روز گذشته، '
                'دسترسی Usage Access را فعال کنید.',
                'To view per-app data usage over the last 7 days, '
                'please grant Usage Access.',
              ),
              style: TextStyle(
                  color: AppColors.muted(context),
                  fontSize: 13,
                  height: 1.6),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.accent,
                padding: const EdgeInsets.symmetric(
                    horizontal: 24, vertical: 12),
              ),
              onPressed: _openUsageSettings,
              child: Text(
                _t('اعطای دسترسی', 'Grant Permission'),
                style: TextStyle(
                    color: AppColors.bg(context),
                    fontWeight: FontWeight.bold),
              ),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: _loadStats,
              child: Text(
                _t('بعد از اعطا، اینجا بزن', 'Tap after granting'),
                style: TextStyle(color: AppColors.muted(context)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSessionCard() {
    if (_sessionCount == 0 && _avgRttMs == null) {
      return const SizedBox.shrink();
    }
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.timeline,
                  color: AppColors.accent, size: 16),
              const SizedBox(width: 8),
              Text(
                _t('آمار ۷ روز اخیر (کل VPN)',
                    'Last 7 days (whole VPN)'),
                style: TextStyle(
                  color: AppColors.fg(context),
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _statCell(
                  _t('میانگین پینگ', 'Avg RTT'),
                  _avgRttMs != null
                      ? '${_avgRttMs!.toStringAsFixed(0)} ms'
                      : '—',
                  _avgRttMs != null && _avgRttMs! < 150
                      ? const Color(0xFF3DCF9A)
                      : (_avgRttMs != null && _avgRttMs! < 300
                          ? const Color(0xFFFFB74D)
                          : AppColors.danger),
                ),
              ),
              Expanded(
                child: _statCell(
                  _t('تعداد سشن', 'Sessions'),
                  '$_sessionCount',
                  AppColors.fg(context),
                ),
              ),
              Expanded(
                child: _statCell(
                  _t('نمونه‌ها', 'Samples'),
                  _sampleCount?.toString() ?? '—',
                  AppColors.muted(context),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            _t(
              'RTT در سطح session اندازه‌گیری می‌شود؛ نمایش per-app نیاز به دسترسی foreground دارد.',
              'RTT is session-level; per-app display needs foreground usage access.',
            ),
            style: TextStyle(
              color: AppColors.muted2(context),
              fontSize: 10,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }

  Widget _statCell(String label, String value, Color valueColor) {
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(
            color: valueColor,
            fontSize: 15,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: TextStyle(
              color: AppColors.muted2(context), fontSize: 10),
        ),
      ],
    );
  }

  Widget _buildStatsList() {
    if (_appStats.isEmpty) {
      return Center(
        child: Text(
          _t('هیچ داده‌ای ثبت نشده است',
              'No application stats recorded'),
          style: TextStyle(color: AppColors.muted(context)),
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: _appStats.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, i) {
        final item = _appStats[i];
        final name = item['name']?.toString() ??
            item['packageName']?.toString() ??
            'Unknown';
        final pkg = item['packageName']?.toString() ?? '';
        final tx = (item['txBytes'] as num?) ?? 0;
        final rx = (item['rxBytes'] as num?) ?? 0;
        final rtt = (item['avgRttMs'] as num?)?.toInt();
        final loss = (item['packetLossPct'] as num?)?.toDouble();
        return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.surface(context),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.border(context)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      name,
                      style: TextStyle(
                          color: AppColors.fg(context),
                          fontWeight: FontWeight.bold,
                          fontSize: 14),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (rtt != null && rtt > 0)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: rtt < 150
                            ? Colors.green.withValues(alpha: 0.2)
                            : Colors.amber.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        '${rtt}ms',
                        style: TextStyle(
                          color: rtt < 150
                              ? Colors.greenAccent
                              : Colors.amberAccent,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 4),
              Text(pkg,
                  style: TextStyle(
                      color: AppColors.muted2(context), fontSize: 11)),
              Divider(height: 16, color: AppColors.border(context)),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      '${_t('آپلود', 'Up')}: ${_formatBytes(tx)}  ·  '
                      '${_t('دانلود', 'Down')}: ${_formatBytes(rx)}',
                      style: TextStyle(
                          color: AppColors.muted(context), fontSize: 12),
                    ),
                  ),
                  if (loss != null)
                    Text(
                      '${_t('افت', 'Loss')}: ${loss.toStringAsFixed(1)}%',
                      style: TextStyle(
                        color: loss > 5.0
                            ? AppColors.danger
                            : AppColors.muted(context),
                        fontSize: 12,
                      ),
                    ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}
