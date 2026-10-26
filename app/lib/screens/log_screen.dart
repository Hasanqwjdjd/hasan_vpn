import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n/s.dart';
import '../services/app_log.dart';
import '../ui/kit/ios_kit.dart';
import '../ui/theme/ios_palette.dart';

/// گزارش برنامه — ترکیب زندهٔ دو منبع:
///  ۱) SafeLog کاتلن (کانال com.hasan.hasan_vpn/logs) — همهٔ لاگ‌های نیتیو
///  ۲) AppLog دارت — هر عمل سطح بالا (اتصال، مسابقهٔ Flux، استور، ویجت…)
/// مرتب‌شده بر اساس زمان، با polling هر ۱ ثانیه + استریم زندهٔ دارت.
class LogScreen extends StatefulWidget {
  const LogScreen({super.key});

  @override
  State<LogScreen> createState() => _LogScreenState();
}

class _LogScreenState extends State<LogScreen> {
  static const MethodChannel _ch =
      MethodChannel('com.hasan.hasan_vpn/logs');

  List<LogEntry> _entries = [];
  Timer? _timer;
  bool _loading = true;
  StreamSubscription<LogEntry>? _sub;

  @override
  void initState() {
    super.initState();
    _load();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _load());
    _sub = AppLog.instance.stream.listen((_) => _load());
  }

  @override
  void dispose() {
    _timer?.cancel();
    _sub?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final now = DateTime.now();
    final dartEntries = List<LogEntry>.from(AppLog.instance.entries);
    List<LogEntry> native = const [];
    try {
      final list = await _ch.invokeListMethod<dynamic>('getLogs');
      native = (list ?? [])
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .map((e) => LogEntry(
                ts: DateTime.fromMillisecondsSinceEpoch(
                    e['ts'] as int? ?? 0),
                level: (e['level']?.toString() ?? 'd').toUpperCase(),
                tag: e['tag']?.toString() ?? '',
                msg: e['msg']?.toString() ?? '',
              ))
          .toList();
    } catch (_) {}
    if (!mounted) return;
    final all = [...dartEntries, ...native]..sort((a, b) => a.ts.compareTo(b.ts));
    setState(() {
      _entries = all.length > 1200 ? all.sublist(all.length - 1200) : all;
      _loading = false;
    });
    // logcat فقط برای مقایسهٔ زمانی — فاصلهٔ بیش از ۱ دقیقه در آینده یعنی
    // ساعت دستگاه جابه‌جا شده؛ بی‌خیال مرتب‌سازی.
    assert(() {
      for (final e in _entries) {
        if (e.ts.isAfter(now.add(const Duration(minutes: 1)))) return true;
      }
      return true;
    }());
  }

  String _fmtLine(LogEntry e) => AppLog.fmt(e);

  String _t(String fa, String en) => S.isFa ? fa : en;

  Color _levelColor(String level) {
    final pal = IosPal.of(context);
    switch (level) {
      case 'E':
        return pal.red;
      case 'W':
        return pal.orange;
      case 'I':
        return pal.green;
      default:
        return pal.textMuted;
    }
  }

  @override
  Widget build(BuildContext context) {
    final pal = IosPal.of(context);
    return IosScreen(
      title: _t('گزارش برنامه', 'App report'),
      onBack: () => Navigator.pop(context),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: const Icon(Icons.copy_all,
                size: 20, color: Colors.white),
            onPressed: () {
              Clipboard.setData(ClipboardData(
                  text: _entries.map(_fmtLine).join('\n')));
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                backgroundColor: pal.card,
                content: Text(_t('کپی شد', 'Copied'),
                    style: const TextStyle(color: Colors.white)),
              ));
            },
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline,
                size: 20, color: Colors.white),
            onPressed: () async {
              AppLog.clear();
              try {
                await _ch.invokeMethod('clearLogs');
              } catch (_) {}
              await _load();
            },
          ),
        ],
      ),
      children: [
        if (_loading)
          const Padding(
            padding: EdgeInsets.all(40),
            child: Center(
                child: CircularProgressIndicator(color: Colors.white)),
          )
        else if (_entries.isEmpty)
          Padding(
            padding: const EdgeInsets.all(32),
            child: Text(
              _t('هنوز رویدادی ثبت نشده', 'Nothing logged yet'),
              textAlign: TextAlign.center,
              style: TextStyle(color: pal.textMuted, fontSize: 14),
            ),
          )
        else
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.35),
                borderRadius:
                    BorderRadius.circular(IosRadius.control),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final e in _entries)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 2),
                      child: RichText(
                        text: TextSpan(
                          style: const TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 11,
                            height: 1.35,
                          ),
                          children: [
                            TextSpan(
                              text:
                                  '[${e.level}] ${e.tag}: ',
                              style: TextStyle(
                                  color: _levelColor(e.level)),
                            ),
                            TextSpan(
                              text: e.msg,
                              style: const TextStyle(
                                  color: Colors.white),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        const SizedBox(height: 20),
      ],
    );
  }
}
