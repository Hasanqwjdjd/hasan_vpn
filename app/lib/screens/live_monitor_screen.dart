import 'dart:async';
import 'package:flutter/material.dart';
import '../services/app_colors.dart';
import '../services/live_monitor_service.dart';

class LiveMonitorScreen extends StatefulWidget {
  final String language;
  const LiveMonitorScreen({super.key, this.language = 'fa'});

  @override
  State<LiveMonitorScreen> createState() => _LiveMonitorScreenState();
}

class _LiveMonitorScreenState extends State<LiveMonitorScreen> {
  final _svc = LiveMonitorService();
  Map<String, dynamic> _data = {};
  int _prevRx = 0;
  int _prevTx = 0;
  double _dlSpeed = 0;
  double _ulSpeed = 0;
  DateTime _lastTick = DateTime.now();

  bool get _isFa => widget.language == 'fa';
  String _t(String fa, String en) => _isFa ? fa : en;

  @override
  void initState() {
    super.initState();
    _svc.stream.listen((d) {
      final now = DateTime.now();
      final dt = now.difference(_lastTick).inMilliseconds / 1000.0;
      _lastTick = now;
      final rx = (d['rxBytes'] as int?) ?? 0;
      final tx = (d['txBytes'] as int?) ?? 0;
      if (dt > 0 && _prevRx > 0) {
        _dlSpeed = (rx - _prevRx) / dt / 1024;
        _ulSpeed = (tx - _prevTx) / dt / 1024;
        if (_dlSpeed < 0) _dlSpeed = 0;
        if (_ulSpeed < 0) _ulSpeed = 0;
      }
      _prevRx = rx;
      _prevTx = tx;
      if (mounted) setState(() => _data = d);
    });
    _svc.start();
  }

  @override
  void dispose() {
    _svc.dispose();
    super.dispose();
  }

  String _formatSpeed(double kb) {
    if (kb < 1) return '0 KB/s';
    if (kb < 1024) return '${kb.toStringAsFixed(0)} KB/s';
    return '${(kb / 1024).toStringAsFixed(1)} MB/s';
  }

  Widget _card(String title, String value, String unit, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface(context),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 20),
              const SizedBox(width: 8),
              Text(title,
                  style: TextStyle(color: AppColors.muted(context), fontSize: 12)),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(value,
                  style: TextStyle(
                      color: AppColors.fg(context),
                      fontSize: 22,
                      fontWeight: FontWeight.w700)),
              const SizedBox(width: 4),
              if (unit.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 3),
                  child: Text(unit,
                      style: TextStyle(
                          color: AppColors.muted2(context), fontSize: 11)),
                ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cpu = (_data['cpu'] as num?)?.toDouble() ?? 0;
    final memUsed = _data['memUsedMb'] as int? ?? 0;
    final battery = _data['battery'] as int? ?? 0;
    final temp = (_data['temp'] as num?)?.toDouble() ?? 0;

    return Scaffold(
      backgroundColor: AppColors.bg(context),
      appBar: AppBar(
        backgroundColor: AppColors.bg(context),
        elevation: 0,
        iconTheme: IconThemeData(color: AppColors.fg(context)),
        title: Text(_t('مانیتور زنده', 'Live Monitor'),
            style: TextStyle(color: AppColors.fg(context))),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.surface(context),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.border(context)),
              ),
              child: Text(
                _t(
                  'آمار هر ۲ ثانیه به‌روز می‌شود. این صفحه مصرف منابع گوشی را نشان می‌دهد.',
                  'Stats update every 2 seconds. This page shows phone resource usage.',
                ),
                style: TextStyle(
                    color: AppColors.muted(context), fontSize: 12, height: 1.6),
              ),
            ),
            const SizedBox(height: 16),
            Row(children: [
              Expanded(child: _card(_t('پردازنده', 'CPU'), cpu.toStringAsFixed(1), '%',
                  Icons.memory, AppColors.accent)),
              const SizedBox(width: 10),
              Expanded(child: _card(_t('حافظه', 'RAM'), memUsed.toString(), 'MB',
                  Icons.storage, Colors.orange)),
            ]),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(child: _card(_t('باتری', 'Battery'), '$battery', '%',
                  Icons.battery_full, Colors.green)),
              const SizedBox(width: 10),
              Expanded(child: _card(_t('حرارت', 'Temp'), temp.toStringAsFixed(1), '°C',
                  Icons.thermostat, Colors.redAccent)),
            ]),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(child: _card(_t('دانلود', 'Download'), _formatSpeed(_dlSpeed), '',
                  Icons.download, AppColors.accent)),
              const SizedBox(width: 10),
              Expanded(child: _card(_t('آپلود', 'Upload'), _formatSpeed(_ulSpeed), '',
                  Icons.upload, Colors.purple)),
            ]),
            const SizedBox(height: 20),
            Text(
              _t(
                'نکته: مصرف CPU ممکن است با هر بار اندازه‌گیری کمی نوسان داشته باشد.',
                'Note: CPU usage may vary slightly with each measurement.',
              ),
              style: TextStyle(color: AppColors.muted2(context), fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }
}
