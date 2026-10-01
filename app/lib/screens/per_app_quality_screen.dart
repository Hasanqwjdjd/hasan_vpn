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
      if (!mounted) return;
      setState(() {
        _appStats = parsed;
        _permissionGranted = true;
        _loading = false;
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
              : _buildStatsList(),
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
