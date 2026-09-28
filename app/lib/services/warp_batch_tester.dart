import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/server.dart';

/// نتیجه تست یک سرور WARP/WARP+/MASQUE.
class WarpBatchResult {
  final VpnServer server;
  final String? bestEndpoint;
  final int latencyMs;
  final String? error;

  const WarpBatchResult({
    required this.server,
    required this.bestEndpoint,
    required this.latencyMs,
    this.error,
  });

  bool get ok => bestEndpoint != null && error == null;
}

/// تست دسته‌ای چند سرور WARP/WARP+/MASQUE به‌صورت موازی.
///
/// هر سرور رو با یه کول‌داون کوچیک ران می‌کنه تا از قطع شدن مکرر
/// session ها جلوگیری شه. حداکثر همزمانی پیش‌فرض ۲ (چون هر تست خودش
/// تونل کامل بالا می‌آره و منابع سیستم محدوده).
class WarpBatchTester {
  WarpBatchTester._();

  static const int defaultParallelism = 2;

  static bool _running = false;
  static bool get isRunning => _running;

  final ValueNotifier<WarpBatchState> state =
      ValueNotifier(const WarpBatchState());

  /// ران تست دسته‌ای روی سرورهای داده‌شده.
  ///
  /// [rescan] تابعی که برای هر سرور یه endpoint جدید پیدا می‌کنه
  /// (معمولاً WarpService.rescanEndpoints یا WarpMasqueService.rescanEndpoints).
  Future<List<WarpBatchResult>> run({
    required List<VpnServer> servers,
    required Future<({String? endpoint, int? ms, String? error})> Function(
            VpnServer server)
        rescan,
    int parallelism = defaultParallelism,
    bool Function()? isCancelled,
  }) async {
    if (_running) return const [];
    _running = true;

    final targets = servers
        .where((s) =>
            s.protocol == VpnProtocol.amneziaWg ||
            s.protocol == VpnProtocol.chain ||
            s.protocol == VpnProtocol.warpMasque)
        .toList();

    if (targets.isEmpty) {
      _running = false;
      return const [];
    }

    state.value = WarpBatchState(
      running: true,
      total: targets.length,
      tested: 0,
    );

    final results = <WarpBatchResult>[];
    var idx = 0;
    final workerCount = parallelism.clamp(1, 4);

    Future<void> worker() async {
      while (true) {
        if (isCancelled?.call() == true) return;
        final myIdx = idx++;
        if (myIdx >= targets.length) return;
        final server = targets[myIdx];

        state.value = state.value.copyWith(
          currentServer: server.displayName,
        );

        WarpBatchResult result;
        try {
          final r = await rescan(server);
          if (r.endpoint == null) {
            result = WarpBatchResult(
              server: server,
              bestEndpoint: null,
              latencyMs: 0,
              error: r.error ?? 'no endpoint',
            );
          } else {
            result = WarpBatchResult(
              server: server,
              bestEndpoint: r.endpoint,
              latencyMs: r.ms ?? 0,
            );
          }
        } catch (e) {
          result = WarpBatchResult(
            server: server,
            bestEndpoint: null,
            latencyMs: 0,
            error: e.toString(),
          );
        }

        results.add(result);
        state.value = state.value.copyWith(
          tested: results.length,
        );
        debugPrint('warp-batch: ${server.name} → '
            '${result.bestEndpoint ?? "✕"} (${result.latencyMs}ms)');

        // کول‌داون کوچیک تا session ها ریست شه
        await Future<void>.delayed(const Duration(milliseconds: 500));
      }
    }

    await Future.wait(
      List<Future<void>>.generate(workerCount, (_) => worker()),
    );

    // مرتب‌سازی: موفق‌ها اول بر اساس latency
    results.sort((a, b) {
      if (a.ok != b.ok) return a.ok ? -1 : 1;
      return a.latencyMs.compareTo(b.latencyMs);
    });

    state.value = WarpBatchState(
      running: false,
      total: targets.length,
      tested: results.length,
      results: List.unmodifiable(results),
    );

    _running = false;
    return results;
  }

  void cancel() {
    state.value = state.value.copyWith(cancelled: true);
    _running = false;
  }

  void reset() {
    state.value = const WarpBatchState();
    _running = false;
  }
}

class WarpBatchState {
  final bool running;
  final int total;
  final int tested;
  final String currentServer;
  final bool cancelled;
  final List<WarpBatchResult> results;

  const WarpBatchState({
    this.running = false,
    this.total = 0,
    this.tested = 0,
    this.currentServer = '',
    this.cancelled = false,
    this.results = const [],
  });

  WarpBatchState copyWith({
    bool? running,
    int? total,
    int? tested,
    String? currentServer,
    bool? cancelled,
    List<WarpBatchResult>? results,
  }) =>
      WarpBatchState(
        running: running ?? this.running,
        total: total ?? this.total,
        tested: tested ?? this.tested,
        currentServer: currentServer ?? this.currentServer,
        cancelled: cancelled ?? this.cancelled,
        results: results ?? this.results,
      );

  double get progress => total > 0 ? tested / total : 0.0;
}
