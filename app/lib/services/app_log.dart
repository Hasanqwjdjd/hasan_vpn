import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';

/// لاگ دقیق برنامه — هر عمل کوچک (اتصال‌ها، مسابقه‌ها، استور، ویجت، DNS-probe…)
/// با زمان‌بندی و سطح، در یک حلقه‌باز ۲۰۰۰تایی + استریم زنده برای صفحهٔ گزارش.
///
/// از سمت Kotlin هم SafeLog جداگانه کار می‌کند؛ صفحهٔ گزارش هر دو منبع را
/// ترکیب می‌کند تا هیچ اتفاقی در برنامه بی‌لاگ نماند.
class AppLog {
  AppLog._();

  static final AppLog instance = AppLog._();

  static const int _max = 2000;

  final Queue<LogEntry> _ring = Queue<LogEntry>();
  final _controller = StreamController<LogEntry>.broadcast();

  /// استریم زندهٔ لاگ‌ها (صفحهٔ گزارش گوش می‌دهد).
  Stream<LogEntry> get stream => _controller.stream;

  /// فهرست فعلی (کهن‌ترین → تازه‌ترین).
  List<LogEntry> get entries => List<LogEntry>.unmodifiable(_ring);

  static void d(String tag, String msg) => instance._add('D', tag, msg);
  static void i(String tag, String msg) => instance._add('I', tag, msg);
  static void w(String tag, String msg) => instance._add('W', tag, msg);
  static void e(String tag, String msg) => instance._add('E', tag, msg);

  void _add(String level, String tag, String msg) {
    final e = LogEntry(
      ts: DateTime.now(),
      level: level,
      tag: tag,
      msg: msg,
    );
    _ring.addLast(e);
    while (_ring.length > _max) {
      _ring.removeFirst();
    }
    if (!_controller.isClosed) {
      _controller.add(e);
    }
    // رد به logcat هم بشود (debugPrint در release خنثی است — SafeLog کاتلین
    // لاگ‌های واقعی را نگه می‌دارد؛ این فقط برایdevelop تجربی).
    debugPrint('[$level/$tag] $msg');
  }

  static String fmt(LogEntry e) {
    final t = e.ts;
    final hh = t.hour.toString().padLeft(2, '0');
    final mm = t.minute.toString().padLeft(2, '0');
    final ss = t.second.toString().padLeft(2, '0');
    final ms = t.millisecond.toString().padLeft(3, '0');
    return '$hh:$mm:$ss.$ms [${e.level}] ${e.tag}: ${e.msg}';
  }

  static void clear() {
    instance._ring.clear();
  }
}

class LogEntry {
  final DateTime ts;
  final String level;
  final String tag;
  final String msg;
  const LogEntry({
    required this.ts,
    required this.level,
    required this.tag,
    required this.msg,
  });
}
