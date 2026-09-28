import 'package:flutter/material.dart';

import '../services/app_colors.dart';
import '../services/connection_log_service.dart';

/// صفحه‌ی تاریخچه‌ی اتصال‌ها.
class ConnectionLogScreen extends StatefulWidget {
  final String language;
  const ConnectionLogScreen({super.key, required this.language});

  @override
  State<ConnectionLogScreen> createState() => _ConnectionLogScreenState();
}

class _ConnectionLogScreenState extends State<ConnectionLogScreen> {
  String _t(String fa, String en) =>
      widget.language == 'fa' ? fa : en;

  List<ConnectionLogEntry> _entries = [];
  bool _loading = true;
  String _filterType = 'all'; // all | connect | disconnect | error | warp

  List<ConnectionLogEntry> get _filtered {
    if (_filterType == 'all') return _entries;
    if (_filterType == 'warp') {
      return _entries
          .where((e) =>
              e.type == 'warp_scan' || e.type == 'warp_rescan')
          .toList();
    }
    return _entries.where((e) => e.type == _filterType).toList();
  }

  /// آمار خلاصه از لاگ.
  _ConnectionStats get _stats {
    var connectCount = 0;
    var disconnectCount = 0;
    var errorCount = 0;
    final durations = <Duration>[];
    DateTime? lastConnect;

    // _entries new به old مرتب شدن (اول جدیدترین)
    // برای محاسبه duration باید از قدیم به جدید iterate کنیم
    final sorted = List<ConnectionLogEntry>.from(_entries)
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp));

    for (final e in sorted) {
      switch (e.type) {
        case 'connect':
          connectCount++;
          lastConnect = e.timestamp;
          break;
        case 'disconnect':
          disconnectCount++;
          if (lastConnect != null) {
            durations.add(e.timestamp.difference(lastConnect));
            lastConnect = null;
          }
          break;
        case 'error':
          errorCount++;
          break;
      }
    }

    Duration? avgDuration;
    Duration? maxDuration;
    if (durations.isNotEmpty) {
      var totalMs = 0;
      var maxMs = 0;
      for (final d in durations) {
        totalMs += d.inMilliseconds;
        if (d.inMilliseconds > maxMs) maxMs = d.inMilliseconds;
      }
      avgDuration = Duration(milliseconds: totalMs ~/ durations.length);
      maxDuration = Duration(milliseconds: maxMs);
    }

    return _ConnectionStats(
      total: _entries.length,
      connectCount: connectCount,
      disconnectCount: disconnectCount,
      errorCount: errorCount,
      sessionsCompleted: durations.length,
      avgDuration: avgDuration,
      maxDuration: maxDuration,
    );
  }

  Widget _buildStatsCard() {
    if (_entries.isEmpty) return const SizedBox.shrink();
    final stats = _stats;
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 6),
      padding: const EdgeInsets.all(14),
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
              Icon(Icons.analytics_outlined,
                  color: AppColors.accent, size: 18),
              const SizedBox(width: 8),
              Text(
                _t('آمار اتصال', 'Connection stats'),
                style: TextStyle(
                  color: AppColors.fg(context),
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _statChip(
                _t('کل', 'Total'),
                '${stats.total}',
                AppColors.muted(context),
              ),
              _statChip(
                _t('اتصال', 'Connect'),
                '${stats.connectCount}',
                AppColors.accent,
              ),
              _statChip(
                _t('قطع', 'Disconnect'),
                '${stats.disconnectCount}',
                AppColors.warn,
              ),
              if (stats.errorCount > 0)
                _statChip(
                  _t('خطا', 'Errors'),
                  '${stats.errorCount}',
                  AppColors.danger,
                ),
            ],
          ),
          if (stats.avgDuration != null) ...[
            const SizedBox(height: 10),
            Divider(color: AppColors.border(context), height: 1),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: _durationCell(
                    _t('میانگین session', 'Avg session'),
                    _formatDuration(stats.avgDuration!),
                  ),
                ),
                Expanded(
                  child: _durationCell(
                    _t('بلندترین', 'Longest'),
                    _formatDuration(stats.maxDuration ?? Duration.zero),
                  ),
                ),
                Expanded(
                  child: _durationCell(
                    _t('سشن‌ها', 'Sessions'),
                    '${stats.sessionsCompleted}',
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _statChip(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withOpacity(0.4), width: 0.8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$label: ',
            style: TextStyle(color: AppColors.muted2(context), fontSize: 10),
          ),
          Text(
            value,
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _durationCell(String label, String value) {
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(
            color: AppColors.fg(context),
            fontSize: 14,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style:
              TextStyle(color: AppColors.muted2(context), fontSize: 10),
        ),
      ],
    );
  }

  String _formatDuration(Duration d) {
    if (d.inHours > 0) {
      return '${d.inHours}h ${d.inMinutes % 60}m';
    }
    if (d.inMinutes > 0) {
      return '${d.inMinutes}m ${d.inSeconds % 60}s';
    }
    return '${d.inSeconds}s';
  }

  Widget _buildFilterRow() {
    final filterLabels = <String, String>{
      'all': _t('همه', 'All'),
      'connect': _t('اتصال', 'Connect'),
      'disconnect': _t('قطع', 'Disconnect'),
      'error': _t('خطا', 'Error'),
      'warp': _t('WARP scan', 'WARP scan'),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: filterLabels.entries.map((e) {
            final selected = _filterType == e.key;
            return Padding(
              padding: const EdgeInsets.only(right: 6),
              child: ChoiceChip(
                label: Text(
                  e.value,
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
                onSelected: (_) =>
                    setState(() => _filterType = e.key),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    ConnectionLogService.revision.addListener(_onLogChanged);
    _load();
  }

  void _onLogChanged() {
    if (!mounted) return;
    // ignore: unawaited_futures
    _load();
  }

  @override
  void dispose() {
    ConnectionLogService.revision.removeListener(_onLogChanged);
    super.dispose();
  }

  Future<void> _load() async {
    final list = await ConnectionLogService.load();
    if (!mounted) return;
    setState(() {
      _entries = list;
      _loading = false;
    });
  }

  Future<void> _clear() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.elevated(ctx),
        title: Text(_t('پاک‌کردن لاگ؟', 'Clear log?'),
            style: TextStyle(color: AppColors.fg(ctx))),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(_t('لغو', 'Cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(_t('پاک‌کردن', 'Clear'),
                style: const TextStyle(color: AppColors.danger)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await ConnectionLogService.clear();
    if (mounted) setState(() => _entries = []);
  }

  Color _typeColor(BuildContext c, String type) {
    switch (type) {
      case 'connect':
        return AppColors.accent;
      case 'error':
        return AppColors.danger;
      case 'disconnect':
        return AppColors.warn;
      default:
        return AppColors.muted(c);
    }
  }

  String _typeLabel(String type) {
    switch (type) {
      case 'connect':
        return _t('اتصال', 'Connect');
      case 'disconnect':
        return _t('قطع', 'Disconnect');
      case 'error':
        return _t('خطا', 'Error');
      default:
        return type;
    }
  }

  String _fmt(DateTime dt) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${dt.year}-${two(dt.month)}-${two(dt.day)} '
        '${two(dt.hour)}:${two(dt.minute)}:${two(dt.second)}';
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
          _t('تاریخچه اتصال', 'Connection history'),
          style: TextStyle(color: AppColors.fg(context)),
        ),
        actions: [
          if (_entries.isNotEmpty)
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
            : _entries.isEmpty
                ? Center(
                    child: Text(
                      _t('هنوز اتصالی ثبت نشده',
                          'No connections logged yet'),
                      style: TextStyle(
                          color: AppColors.muted(context), fontSize: 13),
                    ),
                  )
                : Column(
                    children: [
                      _buildStatsCard(),
                      _buildFilterRow(),
                      Expanded(
                        child: ListView.builder(
                    padding: const EdgeInsets.all(12),
                    itemCount: _filtered.length,
                    itemBuilder: (ctx, i) {
                      final e = _filtered[i];
                      return Container(
                        margin: const EdgeInsets.only(bottom: 6),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: AppColors.surface(context),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                              color: AppColors.border(context)),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 6,
                              height: 6,
                              decoration: BoxDecoration(
                                color: _typeColor(context, e.type),
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment:
                                    CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Text(
                                        _typeLabel(e.type),
                                        style: TextStyle(
                                          color: _typeColor(
                                              context, e.type),
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          e.target,
                                          style: TextStyle(
                                            color:
                                                AppColors.fg(context),
                                            fontSize: 12,
                                          ),
                                          maxLines: 1,
                                          overflow:
                                              TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ],
                                  ),
                                  if (e.detail != null) ...[
                                    const SizedBox(height: 2),
                                    Text(
                                      e.detail!,
                                      style: TextStyle(
                                        color: AppColors.muted2(context),
                                        fontSize: 10.5,
                                      ),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                  const SizedBox(height: 2),
                                  Text(
                                    _fmt(e.timestamp),
                                    style: TextStyle(
                                      color: AppColors.muted2(context),
                                      fontSize: 10,
                                      fontFamily: 'monospace',
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                      ),
                    ],
                  ),
      ),
    );
  }


class _ConnectionStats {
  final int total;
  final int connectCount;
  final int disconnectCount;
  final int errorCount;
  final int sessionsCompleted;
  final Duration? avgDuration;
  final Duration? maxDuration;

  const _ConnectionStats({
    required this.total,
    required this.connectCount,
    required this.disconnectCount,
    required this.errorCount,
    required this.sessionsCompleted,
    this.avgDuration,
    this.maxDuration,
  });
}
}
