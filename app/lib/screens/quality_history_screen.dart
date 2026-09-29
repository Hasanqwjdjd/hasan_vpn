import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/server.dart';
import '../services/app_colors.dart';
import '../services/quality_history_service.dart';
import '../services/quality_insights.dart';
import '../services/connection_quality.dart';

/// صفحه‌ی تاریخچه کیفیت اتصال — نمودار امتیاز، پینگ و jitter.
class QualityHistoryScreen extends StatefulWidget {
  final String language;
  const QualityHistoryScreen({super.key, required this.language});

  @override
  State<QualityHistoryScreen> createState() => _QualityHistoryScreenState();
}

class _QualityHistoryScreenState extends State<QualityHistoryScreen>
    with TickerProviderStateMixin {
  String _t(String fa, String en) =>
      widget.language == 'fa' ? fa : en;

  /// Drives the live line charts. Each chart grows in from left to right
  /// on open, and redraws smoothly when the underlying values change —
  /// "line moves like a wave" instead of a static picture.
  late final AnimationController _chartAnim;
  List<double> _lastQualityValues = const [];
  List<double> _lastPingValues = const [];
  List<double> _lastJitterValues = const [];

  List<QualitySample> _all = const [];
  List<QualitySample> _filtered = const [];
  Duration? _window = const Duration(hours: 24);
  String _selectedServerId = ''; // '' = all
  bool _loading = true;
  // insights
  QualityInsightsResult _insights = const QualityInsightsResult.empty();
  List<VpnServer> _servers = const [];

  @override
  void initState() {
    super.initState();
    _chartAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..forward();
    _load();
  }

  /// خواندن لیست سرورها از cache export که home_screen آماده کرده.
  Future<List<VpnServer>> _loadServersFromCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('quick_export_servers_v1');
      if (raw == null || raw.isEmpty) return const [];
      final doc = jsonDecode(raw);
      if (doc is! Map) return const [];
      final list = doc['servers'];
      if (list is! List) return const [];
      final out = <VpnServer>[];
      for (final e in list) {
        if (e is! Map) continue;
        final protoStr = e['protocol']?.toString() ?? '';
        final proto = VpnProtocol.values.firstWhere(
          (p) => p.name == protoStr,
          orElse: () => VpnProtocol.custom,
        );
        out.add(VpnServer(
          id: e['id']?.toString() ?? '',
          name: e['name']?.toString() ?? '',
          flag: e['flag']?.toString() ?? '🌐',
          shareLink: e['shareLink']?.toString() ?? '',
          protocol: proto,
          host: e['host']?.toString() ?? '',
          port: (e['port'] as num?)?.toInt() ?? 0,
          isDeletable: e['isDeletable'] == true,
        ));
      }
      return out;
    } catch (_) {
      return const [];
    }
  }

  /// محاسبه insights جدید.
  void _recomputeInsights() {
    _insights = QualityInsights.compute(
      _servers,
      window: _window,
    );
  }

  Future<void> _load() async {
    final list = await QualityHistoryService.load();
    final servers = await _loadServersFromCache();
    if (!mounted) return;
    setState(() {
      _all = list;
      _servers = servers;
      _applyFilter();
      _recomputeInsights();
      _loading = false;
    });
  }

  void _applyFilter() {
    // Sweep the line charts in again on every refresh so the
    // graphs read as live data instead of a frozen image.
    try { _chartAnim.forward(from: 0); } catch (_) {}

    var list = _all;
    if (_selectedServerId.isNotEmpty) {
      list = list.where((s) => s.serverId == _selectedServerId).toList();
    }
    if (_window != null) {
      final cutoff = DateTime.now().subtract(_window!);
      list = list.where((s) => s.at.isAfter(cutoff)).toList();
    }
    _filtered = list;
    _recomputeInsights();
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

  Future<void> _exportToClipboard() async {
    try {
      final json = await QualityHistoryService.export();
      final samples = QualityHistoryService.cached;
      if (samples.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_t('تاریخچه خالی است', 'History is empty')),
            duration: const Duration(seconds: 2),
          ),
        );
        return;
      }
      await Clipboard.setData(ClipboardData(text: json));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_t(
            'تاریخچه (' + samples.length.toString() + ' نمونه) کپی شد',
            'History (' + samples.length.toString() + ' samples) copied',
          )),
          duration: const Duration(seconds: 2),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_t('خطا: ' + e.toString(), 'Error: ' + e.toString())),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> _importFromClipboard() async {
    try {
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      final text = data?.text?.trim() ?? '';
      if (text.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_t('کلیپ‌بورد خالی است', 'Clipboard is empty')),
            duration: const Duration(seconds: 2),
          ),
        );
        return;
      }
      final n = await QualityHistoryService.import(text);
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(n > 0
              ? _t(n.toString() + ' نمونه اضافه شد', n.toString() + ' samples imported')
              : _t('نمونه جدیدی نبود', 'No new samples')),
          duration: const Duration(seconds: 2),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_t('خطا: ' + e.toString(), 'Error: ' + e.toString())),
          duration: const Duration(seconds: 2),
        ),
      );
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
                      _buildServerSelector(),
                      _buildWindowSelector(),
                      const SizedBox(height: 16),
                      _buildStatsRow(stats),
                      const SizedBox(height: 20),
                      _buildInsightsSection(),
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

  Widget _buildServerSelector() {
    final counts = QualityHistoryService.serverIdsWithCounts;
    if (counts.isEmpty) return const SizedBox.shrink();

    final entries = <MapEntry<String, int>>[
      const MapEntry('', 0), // all
      ...counts.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value)),
    ];

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: DropdownButtonFormField<String>(
        value: _selectedServerId,
        dropdownColor: AppColors.elevated(context),
        style: TextStyle(color: AppColors.fg(context), fontSize: 12),
        decoration: InputDecoration(
          labelText: _t('فیلتر سرور', 'Filter server'),
          labelStyle:
              TextStyle(color: AppColors.muted(context), fontSize: 11),
          isDense: true,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
        items: entries.map((e) {
          final isAll = e.key.isEmpty;
          final label = isAll
              ? _t('همه سرورها', 'All servers')
              : '${e.key.substring(0, e.key.length > 12 ? 12 : e.key.length)}… · ${e.value}';
          return DropdownMenuItem<String>(
            value: e.key,
            child: Text(label),
          );
        }).toList(),
        onChanged: (v) {
          if (v == null) return;
          setState(() {
            _selectedServerId = v;
            _applyFilter();
          });
        },
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

  Widget _buildInsightsSection() {
    final ins = _insights;
    if (ins.isEmpty) return const SizedBox.shrink();

    // بهترین ساعت
    final best = QualityInsights.bestHour(ins);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (best != null)
          Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.accent.withOpacity(0.12),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                  color: AppColors.accent.withOpacity(0.4), width: 1),
            ),
            child: Row(
              children: [
                Icon(Icons.tips_and_updates,
                    color: AppColors.accent, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _t(
                      'بهترین زمان: ساعت ' + best.hour.toString() + ':00 با میانگین ' + best.avgScore.toString(),
                      'Best time: ' + best.hour.toString() + ':00 with avg ' + best.avgScore.toString(),
                    ),
                    style: TextStyle(
                        color: AppColors.fg(context),
                        fontSize: 12,
                        fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ),
        if (ins.protocolBuckets.isNotEmpty)
          _buildBucketList(
            title: _t('بر اساس پروتکل', 'By protocol'),
            buckets: ins.protocolBuckets.values
                .map((v) => v.first)
                .toList(),
          ),
        if (ins.countryBuckets.isNotEmpty)
          _buildBucketList(
            title: _t('بر اساس کشور', 'By country'),
            buckets: ins.countryBuckets.values
                .map((v) => v.first)
                .toList(),
          ),
      ],
    );
  }

  Widget _buildBucketList({
    required String title,
    required List<InsightBucket> buckets,
  }) {
    if (buckets.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        padding: const EdgeInsets.all(12),
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
            ...buckets.take(8).map((b) => Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 90,
                        child: Text(
                          b.label,
                          style: TextStyle(
                              color: AppColors.fg(context),
                              fontSize: 11),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(3),
                          child: LinearProgressIndicator(
                            value: (b.avgScore / 100).clamp(0.0, 1.0),
                            backgroundColor:
                                AppColors.border(context),
                            color: _scoreColor(b.avgScore),
                            minHeight: 6,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      SizedBox(
                        width: 55,
                        child: Text(
                          b.avgScore.toString() + ' · ' + b.count.toString(),
                          textAlign: TextAlign.right,
                          style: TextStyle(
                            color: AppColors.muted2(context),
                            fontSize: 10.5,
                          ),
                        ),
                      ),
                    ],
                  ),
                )),
          ],
        ),
      ),
    );
  }

  Color _scoreColor(int score) {
    if (score >= 85) return AppColors.accent;
    if (score >= 70) return const Color(0xFF8BC34A);
    if (score >= 50) return AppColors.warn;
    if (score >= 30) return const Color(0xFFFF7043);
    return AppColors.danger;
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
                : AnimatedBuilder(
                    animation: _chartAnim,
                    builder: (_, __) {
                      // Grow the wave from the left when it first appears.
                      final t = Curves.easeOut.transform(_chartAnim.value);
                      return ClipRect(
                        child: Align(
                          alignment: Alignment.centerLeft,
                          widthFactor: t.clamp(0.02, 1.0),
                          child: CustomPaint(
                            painter: _LineChartPainter(
                              values: values,
                              maxY: maxY <= 0 ? 1 : maxY,
                              color: color,
                              gridColor:
                                  AppColors.muted2(context).withOpacity(0.2),
                              reveal: t,
                            ),
                            size: Size.infinite,
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
  @override
  void dispose() {
    try { _chartAnim.dispose(); } catch (_) {}
    super.dispose();
  }
}

class _LineChartPainter extends CustomPainter {
  final List<double> values;
  final double maxY;
  final Color color;
  final Color gridColor;

  /// 0..1 — how much of the wave to draw. The caller animates this from 0 to 1
  /// so a fresh chart sweeps in from the left instead of appearing whole.
  final double reveal;

  _LineChartPainter({
    required this.values,
    required this.maxY,
    required this.color,
    required this.gridColor,
    this.reveal = 1.0,
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

    // Glowing dot on the newest value so the eye lands on "now".
    if (values.isNotEmpty) {
      final vLast = values.last;
      final xLast = (values.length - 1) * dx;
      final normLast = (vLast / maxY).clamp(0.0, 1.0);
      final yLast = size.height * (1 - normLast);
      final glow = Paint()
        ..color = color.withOpacity(0.25 * reveal)
        ..style = PaintingStyle.fill;
      canvas.drawCircle(Offset(xLast, yLast), 6, glow);
      final dot = Paint()..color = color;
      canvas.drawCircle(Offset(xLast, yLast), 2.5, dot);
    }
  }

  @override
  bool shouldRepaint(_LineChartPainter old) =>
      old.values != values ||
      old.maxY != maxY ||
      old.color != color ||
      old.reveal != reveal;
}
