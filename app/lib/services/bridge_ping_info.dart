import 'network_prober.dart';

/// اطلاعات پینگ یک پل Tor.
class BridgePingInfo {
  final ProbeResult? result;
  final DateTime? at;
  final String? error;

  const BridgePingInfo({
    this.result,
    this.at,
    this.error,
  });

  bool get ok => result?.isReachable == true;
  int get avgMs => result?.avgMs ?? 99999;
  int? get jitterMs => result?.jitterMs;
  int get lossPct => result?.lossPct ?? 100;

  /// امتیاز کیفیت ترکیبی (کمتر = بهتر).
  /// ping + jitter * 2 + loss * 20
  int get score {
    if (!ok) return 99999;
    final p = avgMs;
    final j = jitterMs ?? 0;
    final l = lossPct;
    return p + (j * 2) + (l * 20);
  }

  /// رنگ برای نمایش (بر اساس avgMs).
  int get colorTier {
    final s = score;
    if (s >= 99999) return 4; // بد
    if (s < 300) return 0; // عالی
    if (s < 800) return 1; // خوب
    if (s < 2000) return 2; // متوسط
    return 3; // ضعیف
  }

  String get label {
    if (error != null) return error!;
    if (!ok) return '✕';
    final parts = <String>['${avgMs}ms'];
    final j = jitterMs;
    if (j != null && j > 0) parts.add('±${j}');
    if (lossPct > 0) parts.add('${lossPct}%↓');
    return parts.join(' · ');
  }
}
