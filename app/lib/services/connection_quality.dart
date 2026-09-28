import 'dart:async';

import 'package:flutter/foundation.dart';

/// محاسبه امتیاز کیفیت اتصال از ping/jitter/loss.
///
/// امتیاز نهایی 0-100:
///   100 = عالی، 70+ = خوب، 40-70 = متوسط، <40 = ضعیف
class ConnectionQuality {
  ConnectionQuality._();

  /// محاسبه امتیاز نهایی از سه پارامتر:
  ///   pingMs: تأخیر به میلی‌ثانیه
  ///   jitterMs: نوسان تأخیر
  ///   lossPct: درصد بسته‌های گم‌شده (0-100)
  static QualityScore compute({
    required int pingMs,
    int jitterMs = 0,
    double lossPct = 0.0,
  }) {
    // ping component: ایده آل <۵۰ms، بد >۵۰۰ms
    final pingScore = _clampScore(
      100 - ((pingMs - 50) / 4.5).clamp(0, 100),
    );

    // jitter component: ایده آل <۵ms، بد >۵۰ms
    final jitterScore = _clampScore(
      100 - ((jitterMs - 5) / 0.45).clamp(0, 100),
    );

    // loss component: ایده آل 0%، بد 10%+
    final lossScore = _clampScore(
      100 - (lossPct * 10).clamp(0, 100),
    );

    // وزن‌ها: ping 50%, jitter 30%, loss 20%
    final final_ = (pingScore * 0.5 +
            jitterScore * 0.3 +
            lossScore * 0.2)
        .round()
        .clamp(0, 100);

    final grade = _gradeFor(final_);

    return QualityScore(
      score: final_,
      grade: grade,
      pingMs: pingMs,
      jitterMs: jitterMs,
      lossPct: lossPct,
      computedAt: DateTime.now(),
    );
  }

  static int _clampScore(num v) => v.clamp(0, 100).round();

  static QualityGrade _gradeFor(int score) {
    if (score >= 85) return QualityGrade.excellent;
    if (score >= 70) return QualityGrade.good;
    if (score >= 50) return QualityGrade.fair;
    if (score >= 30) return QualityGrade.poor;
    return QualityGrade.bad;
  }
}

enum QualityGrade { excellent, good, fair, poor, bad }

extension QualityGradeInfo on QualityGrade {
  String get emoji => switch (this) {
        QualityGrade.excellent => '🟢',
        QualityGrade.good => '🟢',
        QualityGrade.fair => '🟡',
        QualityGrade.poor => '🟠',
        QualityGrade.bad => '🔴',
      };

  String label(bool fa) => switch (this) {
        QualityGrade.excellent => fa ? 'عالی' : 'Excellent',
        QualityGrade.good => fa ? 'خوب' : 'Good',
        QualityGrade.fair => fa ? 'متوسط' : 'Fair',
        QualityGrade.poor => fa ? 'ضعیف' : 'Poor',
        QualityGrade.bad => fa ? 'خیلی ضعیف' : 'Bad',
      };
}

class QualityScore {
  final int score;
  final QualityGrade grade;
  final int pingMs;
  final int jitterMs;
  final double lossPct;
  final DateTime computedAt;
  final int? prevScore;

  const QualityScore({
    required this.score,
    required this.grade,
    required this.pingMs,
    required this.jitterMs,
    required this.lossPct,
    required this.computedAt,
    this.prevScore,
  });

  /// نسخه ساده برای log.
  String get summary =>
      'score=\$score (\${grade.name}) ping=\${pingMs}ms '
      'jitter=\${jitterMs}ms loss=\${lossPct.toStringAsFixed(1)}%';

  /// روند — تغییر نسبت به نمونه قبلی.
  int? get delta => prevScore == null ? null : score - prevScore!;

  /// آیا روند بهبودی داره؟
  bool get improving => (delta ?? 0) > 3;

  /// آیا روند بدتر داره؟
  bool get degrading => (delta ?? 0) < -3;
}

/// مانیتور زنده‌ی کیفیت — چند نمونه ping رو جمع می‌کنه و امتیاز می‌ده.
class QualityMonitor {
  /// constructor عمومی — از home_screen ساخته می‌شه.
  QualityMonitor();

  /// میانگین متحرک — چند نمونه آخر.
  static const int sampleWindow = 10;

  final List<int> _samples = [];
  final ValueNotifier<QualityScore?> latest =
      ValueNotifier<QualityScore?>(null);

  void addSample({required int pingMs, int jitterMs = 0}) {
    _samples.add(pingMs);
    while (_samples.length > sampleWindow) {
      _samples.removeAt(0);
    }
    if (_samples.length >= 3) {
      final mean = _samples.reduce((a, b) => a + b) / _samples.length;
      // محاسبه jitter: میانگین تفاوت‌های مطلق
      var diffSum = 0;
      for (var i = 1; i < _samples.length; i++) {
        diffSum += (_samples[i] - _samples[i - 1]).abs();
      }
      final avgJitter = (diffSum / (_samples.length - 1)).round();
      final prev = latest.value?.score;
      final score = ConnectionQuality.compute(
        pingMs: mean.round(),
        jitterMs: avgJitter > 0 ? avgJitter : jitterMs,
      );
      latest.value = QualityScore(
        score: score.score,
        grade: score.grade,
        pingMs: score.pingMs,
        jitterMs: score.jitterMs,
        lossPct: score.lossPct,
        computedAt: score.computedAt,
        prevScore: prev,
      );
    }
  }

  void reset() {
    _samples.clear();
    latest.value = null;
  }
}
