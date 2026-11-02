import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/app_colors.dart';

/// صفحه‌ی عیب‌یابی و لاگ‌ها.
///
/// همه‌ی SafeLog ها (Dart+Kotlin) در حافظه‌ی Kotlin نگه داشته می‌شوند
/// و اینجا با polling هر ۱ ثانیه نمایش داده می‌شوند.
class LogViewerScreen extends StatefulWidget {
  final String language;
  const LogViewerScreen({super.key, required this.language});

  @override
  State<LogViewerScreen> createState() => _LogViewerScreenState();
}

class _LogViewerScreenState extends State<LogViewerScreen> {
  static const MethodChannel _ch =
      MethodChannel('com.hasan.hasan_vpn/logs');

  List<Map<String, dynamic>> _logs = [];
  Timer? _timer;
  final ScrollController _scrollCtrl = ScrollController();
  bool _autoRefresh = true;
  bool _autoScroll = true;
  String _filter = '';

  bool get _isFa => widget.language == 'fa';
  String _t(String fa, String en) => _isFa ? fa : en;

  @override
  void initState() {
    super.initState();
    _load();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_autoRefresh) _load();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _scrollCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final list = await _ch.invokeListMethod<dynamic>('getLogs');
      if (!mounted) return;
      setState(() {
        _logs = (list ?? [])
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
      });
      if (_autoScroll && _scrollCtrl.hasClients) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_scrollCtrl.hasClients) {
            _scrollCtrl.jumpTo(_scrollCtrl.position.maxScrollExtent);
          }
        });
      }
    } catch (_) {}
  }

  Future<void> _clear() async {
    try {
      await _ch.invokeMethod('clearLogs');
    } catch (_) {}
    setState(() => _logs = []);
  }

  Future<void> _copyAll() async {
    final buf = StringBuffer();
    for (final e in _logs) {
      buf.writeln(_formatLine(e));
    }
    await Clipboard.setData(ClipboardData(text: buf.toString()));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(_t('${_logs.length} خط کپی شد', '${_logs.length} lines copied')),
      duration: const Duration(seconds: 2),
    ));
  }

  String _formatLine(Map<String, dynamic> e) {
    final ts = DateTime.fromMillisecondsSinceEpoch(e['ts'] as int? ?? 0);
    final hh = ts.hour.toString().padLeft(2, '0');
    final mm = ts.minute.toString().padLeft(2, '0');
    final ss = ts.second.toString().padLeft(2, '0');
    final ms = ts.millisecond.toString().padLeft(3, '0');
    return '$hh:$mm:$ss.$ms [${e['level']}] ${e['tag']}: ${e['msg']}';
  }

  Color _levelColor(String level, BuildContext c) {
    switch (level) {
      case 'e':
        return AppColors.danger;
      case 'w':
        return AppColors.warn;
      case 'i':
        return AppColors.accent;
      default:
        return AppColors.muted(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filter.isEmpty
        ? _logs
        : _logs.where((e) {
            final s = '${e['tag']} ${e['msg']} ${e['level']}'.toLowerCase();
            return s.contains(_filter.toLowerCase());
          }).toList();

    return Scaffold(
      backgroundColor: AppColors.bg(context),
      appBar: AppBar(
        backgroundColor: AppColors.bg(context),
        elevation: 0,
        iconTheme: IconThemeData(color: AppColors.fg(context)),
        title: Text(
          _t('عیب‌یابی و لاگ‌ها', 'Diagnostics & Logs'),
          style: TextStyle(color: AppColors.fg(context), fontSize: 16),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            tooltip: _autoRefresh ? _t('توقف', 'Pause') : _t('ادامه', 'Resume'),
            icon: Icon(
              _autoRefresh ? Icons.pause : Icons.play_arrow,
              color: AppColors.fg(context),
            ),
            onPressed: () => setState(() => _autoRefresh = !_autoRefresh),
          ),
          IconButton(
            tooltip: _autoScroll ? _t('اسکرول خودکار روشن', 'Auto-scroll ON') : _t('اسکرول خودکار خاموش', 'Auto-scroll OFF'),
            icon: Icon(
              _autoScroll ? Icons.vertical_align_bottom : Icons.vertical_align_center,
              color: _autoScroll ? AppColors.accent : AppColors.muted(context),
            ),
            onPressed: () => setState(() => _autoScroll = !_autoScroll),
          ),
        ],
      ),
      body: Column(
        children: [
          // Search + actions
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    style: TextStyle(color: AppColors.fg(context), fontSize: 13),
                    decoration: InputDecoration(
                      hintText: _t('جستجو در لاگ‌ها…', 'Search logs…'),
                      hintStyle: TextStyle(color: AppColors.muted2(context)),
                      isDense: true,
                      prefixIcon: Icon(Icons.search,
                          size: 18, color: AppColors.muted2(context)),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    onChanged: (v) => setState(() => _filter = v.trim()),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                Text(
                  _t('${filtered.length} از ${_logs.length} خط',
                      '${filtered.length} of ${_logs.length} lines'),
                  style: TextStyle(color: AppColors.muted2(context), fontSize: 11),
                ),
                const Spacer(),
                TextButton.icon(
                  onPressed: _copyAll,
                  icon: const Icon(Icons.copy_all, size: 16),
                  label: Text(_t('کپی همه', 'Copy all'),
                      style: const TextStyle(fontSize: 12)),
                ),
                TextButton.icon(
                  onPressed: _clear,
                  icon: const Icon(Icons.delete_outline, size: 16),
                  label: Text(_t('پاک', 'Clear'),
                      style: const TextStyle(fontSize: 12)),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: filtered.isEmpty
                ? Center(
                    child: Text(
                      _t('لاگی ثبت نشده', 'No logs yet'),
                      style: TextStyle(color: AppColors.muted2(context)),
                    ),
                  )
                : ListView.builder(
                    controller: _scrollCtrl,
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    itemCount: filtered.length,
                    itemBuilder: (_, i) {
                      final e = filtered[i];
                      final ts = DateTime.fromMillisecondsSinceEpoch(
                          e['ts'] as int? ?? 0);
                      final time =
                          '${ts.hour.toString().padLeft(2, '0')}:${ts.minute.toString().padLeft(2, '0')}:${ts.second.toString().padLeft(2, '0')}.${ts.millisecond.toString().padLeft(3, '0')}';
                      final level = e['level']?.toString() ?? 'd';
                      final tag = e['tag']?.toString() ?? '';
                      final msg = e['msg']?.toString() ?? '';
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Directionality(
                          textDirection: TextDirection.ltr,
                          child: SelectableText.rich(
                            TextSpan(children: [
                              TextSpan(
                                text: '$time ',
                                style: TextStyle(
                                  color: AppColors.muted2(context),
                                  fontSize: 11,
                                  fontFamily: 'monospace',
                                ),
                              ),
                              TextSpan(
                                text: '[$level] ',
                                style: TextStyle(
                                  color: _levelColor(level, context),
                                  fontSize: 11,
                                  fontFamily: 'monospace',
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              TextSpan(
                                text: '$tag: ',
                                style: TextStyle(
                                  color: AppColors.accent,
                                  fontSize: 11,
                                  fontFamily: 'monospace',
                                ),
                              ),
                              TextSpan(
                                text: msg,
                                style: TextStyle(
                                  color: AppColors.fg(context),
                                  fontSize: 11,
                                  fontFamily: 'monospace',
                                ),
                              ),
                            ]),
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
}
