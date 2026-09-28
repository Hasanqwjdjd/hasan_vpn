import 'package:flutter/material.dart';

import '../services/app_colors.dart';
import '../services/connection_quality.dart';

/// نمایش فشرده‌ی امتیاز کیفیت اتصال.
///
/// استایل: یه badge با رنگ و عدد، به‌همراه tooltip که جزئیات (ping/jitter/loss)
/// رو نشون می‌ده. در state card وقتی متصل هستیم نمایش داده می‌شه.
class QualityBadge extends StatelessWidget {
  final QualityScore? score;
  final bool compact;
  final String language;

  const QualityBadge({
    super.key,
    required this.score,
    this.compact = false,
    this.language = 'fa',
  });

  bool get _isFa => language == 'fa';

  Color _colorFor(BuildContext ctx) {
    if (score == null) return AppColors.muted2(ctx);
    switch (score!.grade) {
      case QualityGrade.excellent:
      case QualityGrade.good:
        return AppColors.accent;
      case QualityGrade.fair:
        return AppColors.warn;
      case QualityGrade.poor:
      case QualityGrade.bad:
        return AppColors.danger;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (score == null) {
      return const SizedBox.shrink();
    }
    final color = _colorFor(context);
    final s = score!;

    if (compact) {
      // trend arrow
      String trend = '';
      Color trendColor = color;
      if (s.improving) {
        trend = '↑';
        trendColor = AppColors.accent;
      } else if (s.degrading) {
        trend = '↓';
        trendColor = AppColors.danger;
      }
      return Tooltip(
        message: s.summary,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: color.withOpacity(0.15),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: color.withOpacity(0.5), width: 0.8),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '${s.grade.emoji} ${s.score}',
                style: TextStyle(
                  color: color,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (trend.isNotEmpty) ...[
                const SizedBox(width: 2),
                Text(
                  trend,
                  style: TextStyle(
                    color: trendColor,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ],
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(0.4), width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            s.grade.emoji,
            style: const TextStyle(fontSize: 14),
          ),
          const SizedBox(width: 6),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Text(
                    '${s.score} · ${s.grade.label(_isFa)}',
                    style: TextStyle(
                      color: color,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (s.delta != null && s.delta!.abs() > 3) ...[
                    const SizedBox(width: 4),
                    Text(
                      s.improving ? '↑' : '↓',
                      style: TextStyle(
                        color: s.improving
                            ? AppColors.accent
                            : AppColors.danger,
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 1),
              Text(
                _isFa
                    ? 'پینگ ${s.pingMs}ms · نوسان ${s.jitterMs}ms'
                    : 'ping ${s.pingMs}ms · jitter ${s.jitterMs}ms',
                style: TextStyle(
                  color: AppColors.muted2(context),
                  fontSize: 9.5,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// نمودار میله‌ای کوچک از نمونه‌های ping اخیر — برای state card.
class QualitySparkline extends StatelessWidget {
  final List<int> samples;
  final double width;
  final double height;

  const QualitySparkline({
    super.key,
    required this.samples,
    this.width = 100,
    this.height = 24,
  });

  @override
  Widget build(BuildContext context) {
    if (samples.length < 2) return SizedBox(width: width, height: height);

    final maxV = samples.reduce((a, b) => a > b ? a : b).toDouble();
    final minV = samples.reduce((a, b) => a < b ? a : b).toDouble();
    final range = (maxV - minV).clamp(1.0, 9999.0);

    return SizedBox(
      width: width,
      height: height,
      child: CustomPaint(
        painter: _SparkPainter(
          samples: samples,
          minV: minV,
          range: range,
          color: AppColors.accent,
          bg: AppColors.muted2(context).withOpacity(0.15),
        ),
      ),
    );
  }
}

class _SparkPainter extends CustomPainter {
  final List<int> samples;
  final double minV;
  final double range;
  final Color color;
  final Color bg;

  _SparkPainter({
    required this.samples,
    required this.minV,
    required this.range,
    required this.color,
    required this.bg,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (samples.length < 2) return;
    final dx = size.width / (samples.length - 1);
    final barWidth = dx * 0.7;

    final barPaint = Paint()
      ..color = color.withOpacity(0.6)
      ..style = PaintingStyle.fill;
    final linePaint = Paint()
      ..color = color
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    final path = Path();
    for (var i = 0; i < samples.length; i++) {
      final v = samples[i].toDouble();
      final norm = 1.0 - ((v - minV) / range).clamp(0.0, 1.0);
      final x = i * dx;
      final y = norm * (size.height - 4) + 2;

      // bar
      canvas.drawRect(
        Rect.fromLTWH(x - barWidth / 2, y, barWidth, size.height - y),
        barPaint,
      );

      // path
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    canvas.drawPath(path, linePaint);
  }

  @override
  bool shouldRepaint(_SparkPainter old) =>
      old.samples != samples ||
      old.color != color ||
      old.range != range;
}
