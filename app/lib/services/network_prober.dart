import 'dart:async';
import 'dart:io';

/// نتیجه‌ی اندازه‌گیری کیفیت اتصال به یک میزبان: میانگین تأخیر، جیتر
/// (نوسان بین نمونه‌ها) و درصد پکت‌لاس (نمونه‌هایی که پاسخ نگرفتن).
class ProbeResult {
  final int? avgMs;
  final int? jitterMs;
  final int lossPct;
  final int attempts;
  final int successful;

  const ProbeResult({
    required this.avgMs,
    required this.jitterMs,
    required this.lossPct,
    required this.attempts,
    required this.successful,
  });

  bool get isReachable => avgMs != null;
}

/// اندازه‌گیری چندنمونه‌ای کیفیت اتصال (تأخیر/جیتر/لاس) + امتیازدهی،
/// بازنویسی‌شده به Dart از منطق NetworkProber / DnsData موجود در
/// پروژه‌ی متن‌باز WhiteGame (https://github.com/TaJirax/WhiteGame).
class NetworkProber {
  NetworkProber._();

  /// به‌جای یک تلاش تکی، چند بار به [host]:[port] وصل می‌شود (بدون نگه
  /// داشتن اتصال) و از روی نمونه‌ها میانگین/جیتر/لاس واقعی حساب می‌کند.
  /// دقیق‌تر از یک پینگ تکی، چون نوسان شبکه و پکت‌لاس رو هم نشون می‌ده.
  static Future<ProbeResult> probeTcp(
    String host, {
    int port = 53,
    int samples = 3,
    Duration timeout = const Duration(seconds: 2),
    Duration gap = const Duration(milliseconds: 40),
  }) async {
    final rtts = <int>[];
    for (var i = 0; i < samples; i++) {
      final watch = Stopwatch()..start();
      try {
        final socket = await Socket.connect(host, port, timeout: timeout);
        watch.stop();
        socket.destroy();
        rtts.add(watch.elapsedMilliseconds.clamp(1, 9999));
      } catch (_) {
        // بدون پاسخ یا رد اتصال؛ به‌عنوان یک نمونه‌ی ناموفق شمرده می‌شود
        // (برای محاسبه‌ی درصد پکت‌لاس لازم است).
      }
      if (i != samples - 1) await Future.delayed(gap);
    }
    if (rtts.isEmpty) {
      return ProbeResult(
        avgMs: null,
        jitterMs: null,
        lossPct: 100,
        attempts: samples,
        successful: 0,
      );
    }
    final avg = rtts.reduce((a, b) => a + b) ~/ rtts.length;
    final jitter = rtts.length >= 2
        ? rtts.reduce((a, b) => a > b ? a : b) -
            rtts.reduce((a, b) => a < b ? a : b)
        : 0;
    final loss = ((samples - rtts.length) * 100) ~/ samples;
    return ProbeResult(
      avgMs: avg,
      jitterMs: jitter,
      lossPct: loss,
      attempts: samples,
      successful: rtts.length,
    );
  }

  /// نمره‌ی ۰ تا ۱۰۰ برای کیفیت یک DNS/سرور با ترکیب تأخیر + جیتر + لاس
  /// (اقتباس از فرمول DnsData.scoreDns در WhiteGame).
  static ProbeScore score(int? avgMs, int lossPct, int? jitterMs) {
    if (avgMs == null) return const ProbeScore(0, 'نامعتبر');
    var s = 100.0;
    s -= lossPct * 1.6;
    s -= (jitterMs ?? 0) / 2;
    if (avgMs > 120) {
      s -= 35;
    } else if (avgMs > 80) {
      s -= 20;
    } else if (avgMs > 50) {
      s -= 10;
    } else if (avgMs > 30) {
      s -= 4;
    }
    final value = s.clamp(0, 100).round();
    final label = value >= 85
        ? 'عالی'
        : value >= 70
            ? 'خوب'
            : value >= 50
                ? 'قابل قبول'
                : value >= 30
                    ? 'ضعیف'
                    : 'نامناسب';
    return ProbeScore(value, label);
  }

  /// اجرای [task] روی همه‌ی [items] به‌صورت دسته‌ای با هم‌زمانی محدود
  /// [concurrency] (دقیقاً مثل chunked(8)+awaitAll در WhiteGame).
  ///
  /// برای لیست‌هایی با صدها/هزاران آیتم، به‌جای تست یکی‌یکی (که با تایم‌اوت
  /// چندثانیه‌ای روی هر آیتم به‌شدت کند می‌شه)، چند تا رو هم‌زمان تست
  /// می‌کنه و UI هم قفل نمی‌شه.
  static Future<void> runBatched<T>(
    List<T> items,
    int concurrency,
    Future<void> Function(T item) task, {
    bool Function()? isCancelled,
  }) async {
    if (concurrency < 1) concurrency = 1;
    for (var i = 0; i < items.length; i += concurrency) {
      if (isCancelled?.call() == true) return;
      final chunk = items.skip(i).take(concurrency);
      await Future.wait(chunk.map(task));
    }
  }
}

class ProbeScore {
  final int value;
  final String label;
  const ProbeScore(this.value, this.label);
}
