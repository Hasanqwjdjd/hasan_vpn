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
}
