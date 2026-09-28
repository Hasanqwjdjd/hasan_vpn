import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/app_colors.dart';
import '../services/quality_history_service.dart';
import '../services/connection_quality.dart';

/// صفحه‌ی تاریخچه کیفیت اتصال — نمودار امتیاز، پینگ و jitter.
class QualityHistoryScreen extends StatefulWidget {
  final String language;
  const QualityHistoryScreen({super.key, required this.language});

  @override
  State<QualityHistoryScreen> createState() => _QualityHistoryScreenState();
}

class _QualityHistoryScreenState extends State<QualityHistoryScreen> {
  String _t(String fa, String en) =>
      widget.language == 'fa' ? fa : en;

  List<QualitySample> _all = const [];
  List<QualitySample> _filtered = const [];
  Duration? _window = const Duration(hours: 24);
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final list = await QualityHistoryService.load();
    if (!mounted) return;
    setState(() {
      _all = list;
      _applyFilter();
      _loading = false;
    });
  }

  void _applyFilter() {
    _filtered = _window == null
        ? _all
        : _all
            .where((s) =>
                s.at.isAfter(DateTime.now().subtract(_window!)))
            .toList();
  }

  Future<void> _clear() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.elevated(ctx),
        title: Text(_t('پاک‌کردن تاریخچه؟', 'Clear history?'),
            style: TextStyle(color: AppColors.fg(ctx))),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(_t('لغو', 'Cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(_t('پاک', 'Clear'),
                style: const TextStyle(color: AppColors.danger)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await QualityHistoryService.clear();
    if (mounted) {
      setState(() {
        _all = const [];
        _filtered = const [];
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final stats = QualityHistoryService.stats(_filtered);

    return Scaffold(
      backgroundColor: AppColors.bg(context),
      appBar: AppBar(
        backgroundColor: AppColors.bg(context),
        elevation: 0,
        iconTheme: IconThemeData(color: AppColors.fg(context)),
        title: Text(
          _t('تاریخچه کیفیت', 'Quality history'),
          style: TextStyle(color: AppColors.fg(context)),
        ),
        actions: [
          IconButton(
            onPressed: _exportToClipboard,
            icon: const Icon(Icons.ios_share),
            tooltip: _t('خروجی', 'Export'),
          ),
          IconButton(
            onPressed: _importFromClipboard,
            icon: const Icon(Icons.download),
            tooltip: _t('ورودی', 'Import'),
          ),
          if (_all.isNotEmpty)
            IconButton(
              onPressed: _clear,
              icon: const Icon(Icons.delete_outline),
              tooltip: _t('پاک‌کردن', 'Clear'),
            ),
        ],
      ),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _all.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.timeline,
                            size: 48, color: AppColors.muted2(context)),
                        const SizedBox(height: 12),
                        Text(
                          _t('هنوز نمونه‌ای ثبت نشده',
                              'No samples recorded yet'),
                          style: TextStyle(
                              color: AppColors.muted(context),
                              fontSize: 13),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          _t('یه بار متصل شو تا شروع به ثبت کنه',
                              'Connect once to start recording'),
                          style: TextStyle(
                              color: AppColors.muted2(context),
                              fontSize: 11),
                        ),
                      ],
                    ),
                  )
                : ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      _buildWindowSelector(),
                      const SizedBox(height: 16),
                      _buildStatsRow(stats),
                      const SizedBox(height: 20),
                      _buildChart(
                        title: _t('امتیاز کیفیت', 'Quality score'),
                        values: _filtered
                            .map((s) => s.score.toDouble())
                            .toList(),
                        maxY: 100,
                        color: AppColors.accent,
                      ),
                      const SizedBox(height: 20),
                      _buildChart(
                        title: _t('پینگ (ms)', 'Ping (ms)'),
                        values: _filtered
                            .map((s) => s.pingMs.toDouble())
                            .toList(),
                        maxY: _filtered
                            .map((s) => s.pingMs)
                            .fold(100, (a, b) => a > b ? a : b)
                            .toDouble(),
                        color: AppColors.warn,
                      ),
                      const SizedBox(height: 20),
                      _buildChart(
                        title: _t('نوسان (ms)', 'Jitter (ms)'),
                        values: _filtered
                            .map((s) => s.jitterMs.toDouble())
                            .toList(),
                        maxY: _filtered
                            .map((s) => s.jitterMs)
                            .fold(20, (a, b) => a > b ? a : b)
                            .toDouble(),
                        color: AppColors.danger,
                      ),
                    ],
                  ),
      ),
    );
  }

  Widget _buildWindowSelector() {
    final opts = <String, Duration?>{
      _t('۱ ساعت', '1h'): const Duration(hours: 1),
      _t('۲۴ ساعت', '24h'): const Duration(hours: 24),
      _t('۷ روز', '7d'): const Duration(days: 7),
      _t('همه', 'All'): null,
    };
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: opts.entries.map((e) {
          final selected = _window == e.value;
          return Padding(
            padding: const EdgeInsets.only(right: 6),
            child: ChoiceChip(
              label: Text(
                e.key,
                style: TextStyle(
                  color: selected
                      ? Colors.black
                      : AppColors.fg(context),
                  fontSize: 11,
                ),
              ),
              selected: selected,
              selectedColor: AppColors.accent,
              backgroundColor: AppColors.surface(context),
              side: BorderSide(color: AppColors.border(context)),
              onSelected: (_) {
                setState(() {
                  _window = e.value;
                  _applyFilter();
                });
              },
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildStatsRow(QualityStats stats) {
    Widget cell(String label, String value) => Expanded(
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 4),
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              color: AppColors.surface(context),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.border(context)),
            ),
            child: Column(
              children: [
                Text(
                  value,
                  style: TextStyle(
                    color: AppColors.fg(context),
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  label,
                  style: TextStyle(
                    color: AppColors.muted2(context),
                    fontSize: 10,
                  ),
                ),
              ],
            ),
          ),
        );
    return Row(
      children: [
        cell(_t('میانگین', 'Avg'), '${stats.avgScore}'),
        cell(_t('حداقل', 'Min'), '${stats.minScore}'),
        cell(_t('حداکثر', 'Max'), '${stats.maxScore}'),
        cell(_t('تعداد', 'Count'), '${stats.count}'),
      ],
    );
  }

  Widget _buildChart({
    required String title,
    required List<double> values,
    required double maxY,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              color: AppColors.fg(context),
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 120,
            child: values.isEmpty
                ? Center(
                    child: Text(
                      _t('داده‌ای نیست', 'No data'),
                      style: TextStyle(
                          color: AppColors.muted2(context), fontSize: 11),
                    ),
                  )
                : CustomPaint(
                    painter: _LineChartPainter(
                      values: values,
                      maxY: maxY <= 0 ? 1 : maxY,
                      color: color,
                      gridColor:
                          AppColors.muted2(context).withOpacity(0.2),
                    ),
                    size: Size.infinite,
                  ),
          ),
        ],
      ),
    );
  }
}

class _LineChartPainter extends CustomPainter {
  final List<double> values;
  final double maxY;
  final Color color;
  final Color gridColor;

  _LineChartPainter({
    required this.values,
    required this.maxY,
    required this.color,
    required this.gridColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty) return;

    // grid (۴ خط افقی)
    final gridPaint = Paint()
      ..color = gridColor
      ..strokeWidth = 0.5;
    for (var i = 0; i <= 4; i++) {
      final y = size.height * i / 4;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    if (values.length < 2) {
      // یه نقطه
      final dot = Paint()..color = color;
      canvas.drawCircle(
        Offset(size.width / 2, size.height / 2),
        3,
        dot,
      );
      return;
    }

    final dx = size.width / (values.length - 1);
    final linePaint = Paint()
      ..color = color
      ..strokeWidth = 1.8
      ..style = PaintingStyle.stroke;
    final fillPaint = Paint()
      ..color = color.withOpacity(0.15)
      ..style = PaintingStyle.fill;

    final linePath = Path();
    final fillPath = Path()..moveTo(0, size.height);

    for (var i = 0; i < values.length; i++) {
      final v = values[i];
      final x = i * dx;
      final normalized = (v / maxY).clamp(0.0, 1.0);
      final y = size.height * (1 - normalized);
      if (i == 0) {
        linePath.moveTo(x, y);
      } else {
        linePath.lineTo(x, y);
      }
      fillPath.lineTo(x, y);
    }
    fillPath.lineTo(size.width, size.height);
    fillPath.close();

    canvas.drawPath(fillPath, fillPaint);
    canvas.drawPath(linePath, linePaint);
  }

  @override
  bool shouldRepaint(_LineChartPainter old) =>
      old.values != values ||
      old.maxY != maxY ||
      old.color != color;
}
