import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n/s.dart';
import '../ui/kit/ios_kit.dart';
import '../ui/theme/ios_palette.dart';

/// گزارش اتصال — پورت `ui/tunnel/TunnelLogScreen.kt`.
/// SafeLogهای Dart+Kotlin در حافظهٔ Kotlin نگه داشته می‌شوند و اینجا
/// با polling هر ۱ ثانیه نمایش داده می‌شوند.
class LogScreen extends StatefulWidget {
  const LogScreen({super.key});

  @override
  State<LogScreen> createState() => _LogScreenState();
}

class _LogScreenState extends State<LogScreen> {
  static const MethodChannel _ch =
      MethodChannel('com.hasan.hasan_vpn/logs');

  List<Map<String, dynamic>> _logs = [];
  Timer? _timer;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _load());
  }

  @override
  void dispose() {
    _timer?.cancel();
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
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _fmtLine(Map<String, dynamic> e) {
    final ts = DateTime.fromMillisecondsSinceEpoch(e['ts'] as int? ?? 0);
    final hh = ts.hour.toString().padLeft(2, '0');
    final mm = ts.minute.toString().padLeft(2, '0');
    final ss = ts.second.toString().padLeft(2, '0');
    return '$hh:$mm:$ss [${e['level']}] ${e['tag']}: ${e['msg']}';
  }

  String _t(String fa, String en) => S.isFa ? fa : en;

  @override
  Widget build(BuildContext context) {
    final pal = IosPal.of(context);
    return IosScreen(
      title: _t('گزارش اتصال', 'Connection report'),
      onBack: () => Navigator.pop(context),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: const Icon(Icons.copy_all, size: 20,
                color: Colors.white),
            onPressed: () {
              Clipboard.setData(
                  ClipboardData(text: _logs.map(_fmtLine).join('\n')));
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                backgroundColor: pal.card,
                content: Text(_t('کپی شد', 'Copied'),
                    style: const TextStyle(color: Colors.white)),
              ));
            },
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline, size: 20,
                color: Colors.white),
            onPressed: () async {
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
        else if (_logs.isEmpty)
          Padding(
            padding: const EdgeInsets.all(32),
            child: Text(
              _t('گزارشی موجود نیست', 'No log entries yet'),
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
                  for (final e in _logs)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 2),
                      child: Text(
                        _fmtLine(e),
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 11,
                          color: Colors.white,
                          height: 1.35,
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
