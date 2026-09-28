import 'dart:async';
import 'dart:collection';

/// Scheduler موازی برای prob کردن endpoint ها.
///
/// Port از WarpSearchCore.kt (PingNG). فقط orchestrator است — probe واقعی
/// رو caller می‌ده تا هم برای WARP Plus 2-hop هم MASQUE استفاده بشه.
///
///   - workers: حداکثر همزمانی (پیش‌فرض ۴)
///   - deadlineMs: کل بودجه زمان
///   - chooseFastest: true = همه رو اجرا کن و سریع‌ترین رو بده
///                   false = اولین موفق رو بده (early exit)
class WarpSearchCore {
  WarpSearchCore._();

  static const int defaultWorkers = 4;

  static Future<WarpSearchResult<T>?> search<T>({
    required List<T> candidates,
    required Duration timeout,
    required Duration deadline,
    required Future<int> Function(T candidate, Duration probeTimeout) probe,
    int workers = defaultWorkers,
    bool chooseFastest = false,
    void Function(int tested, int total)? onProgress,
  }) async {
    if (candidates.isEmpty) return null;

    final workerCount = workers.clamp(1, defaultWorkers);
    final startTime = DateTime.now();
    final results = Queue<WarpSearchResult<T>>();
    final completer = Completer<WarpSearchResult<T>?>();
    var completed = 0;
    var nextIndex = 0;
    var stopped = false;

    bool pastDeadline() =>
        DateTime.now().difference(startTime) >= deadline;

    void completeOnce(WarpSearchResult<T>? result) {
      if (!completer.isCompleted) completer.complete(result);
    }

    Future<void> worker() async {
      while (true) {
        if (stopped || pastDeadline()) return;
        final idx = nextIndex++;
        if (idx >= candidates.length) return;
        final candidate = candidates[idx];

        final remaining = deadline - DateTime.now().difference(startTime);
        if (remaining.isNegative) return;
        final effective = remaining < timeout ? remaining : timeout;

        int delay;
        try {
          delay = await probe(candidate, effective);
        } catch (_) {
          delay = -1;
        }
        if (stopped) return;

        completed++;
        onProgress?.call(completed, candidates.length);

        if (delay >= 0) {
          final result = WarpSearchResult<T>(
            candidate: candidate,
            delayMs: delay,
          );
          if (!chooseFastest) {
            stopped = true;
            completeOnce(result);
            return;
          }
          results.add(result);
        }
      }
    }

    final workerFutures =
        List<Future<void>>.generate(workerCount, (_) => worker());
    // ignore: unawaited_futures
    Future.wait(workerFutures).then((_) {
      if (chooseFastest) {
        WarpSearchResult<T>? best;
        for (final r in results) {
          if (best == null || r.delayMs < best.delayMs) best = r;
        }
        completeOnce(best);
      } else {
        completeOnce(null);
      }
    });

    return completer.future;
  }
}

class WarpSearchResult<T> {
  final T candidate;
  final int delayMs;
  const WarpSearchResult({
    required this.candidate,
    required this.delayMs,
  });
}
