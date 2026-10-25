import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../ui/theme/ios_palette.dart';

const double _kArcMs = 620;
const double _kMorphMs = 1000;
const double _kLaunchMs = 1100;
const double _kTotalMs = _kArcMs + _kMorphMs + _kLaunchMs + 340;

/// اسپلش — پورت `ui/SplashScreen.kt`: قوس → نقطه → موشک → پرواز.
/// فقط یک‌بار در هر process اجرا می‌شود.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3060),
    )..forward();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: AnimatedBuilder(
        animation: _c,
        builder: (context, child) {
          final t = _c.value * _kTotalMs;
          return CustomPaint(
            painter: _SplashPainter(t: t),
            child: const SizedBox.expand(),
          );
        },
      ),
    );
  }
}

class _SplashPainter extends CustomPainter {
  final double t; // ms from start
  _SplashPainter({required this.t});

  final List<Offset> _stars = List.generate(46, (i) {
    final r = (i * 7919) % 1000 / 1000;
    final r2 = (i * 104729) % 1000 / 1000;
    return Offset(r, r2);
  });

  @override
  void paint(Canvas canvas, Size size) {
    // گرادیان پس‌زمینه (0.90/0.72/0.90 روی #0A101C)
    final bg = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Ios.splashBase.withValues(alpha: 0.90),
          Ios.splashBase.withValues(alpha: 0.72),
          Ios.splashBase.withValues(alpha: 0.90),
        ],
      ).createShader(Offset.zero & size);
    canvas.drawRect(Offset.zero & size, bg);

    // ستاره‌ها با پارالاکس
    final drift = (t / 100) % 1.0;
    for (var i = 0; i < _stars.length; i++) {
      final y =
          ((_stars[i].dy + drift * (0.2 + (i % 5) * 0.1)) % 1.0) *
              size.height;
      canvas.drawCircle(
          Offset(_stars[i].dx * size.width, y),
          (i % 3) * 0.5 + 0.6,
          Paint()
            ..color = Colors.white
                .withValues(alpha: 0.18 + (i % 4) * 0.08));
    }

    final center = Offset(size.width / 2, size.height * 0.42);
    final accent = IosPal.darkPal.blue;

    if (t < _kArcMs) {
      // قوس — sweep تا 270°
      final p = (t / _kArcMs).clamp(0.0, 1.0);
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 6
        ..strokeCap = StrokeCap.round
        ..color = accent;
      canvas.drawArc(
          Rect.fromCircle(center: center, radius: 44),
          -math.pi / 2,
          2 * math.pi * 0.75 * Curves.easeOut.transform(p),
          false,
          paint);
    } else if (t < _kArcMs + _kMorphMs) {
      // نقطه → موشک
      final p = ((t - _kArcMs) / _kMorphMs).clamp(0.0, 1.0);
      final e = Curves.easeInOutBack.transform(p);
      final rocket = Paint()..color = accent;
      final bodyH = 34 * e;
      final rect = RRect.fromRectAndRadius(
        Rect.fromCenter(
            center: Offset(center.dx, center.dy - 4 * e),
            width: 18,
            height: bodyH),
        const Radius.circular(9),
      );
      canvas.drawRRect(rect, rocket);
      if (e > 0.6) {
        canvas.drawCircle(
            Offset(center.dx, center.dy - 2 * e),
            4.5 * (e - 0.6) / 0.4,
            Paint()..color = Colors.white.withValues(alpha: 0.9));
      }
    } else if (t < _kArcMs + _kMorphMs + _kLaunchMs) {
      // پرواز
      final p = ((t - _kArcMs - _kMorphMs) / _kLaunchMs).clamp(0.0, 1.0);
      final e = Curves.easeInCubic.transform(p);
      final y = center.dy - 220 * e;
      final rocket = Paint()
        ..color =
            accent.withValues(alpha: (1 - e * 0.9).clamp(0.0, 1.0));
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(
              center: Offset(center.dx, y), width: 18, height: 34),
          const Radius.circular(9),
        ),
        rocket,
      );
      if (e < 0.9) {
        canvas.drawCircle(
          Offset(center.dx, y + 26),
          8 * (1 - e),
          Paint()
            ..color = Ios.warnOrange.withValues(alpha: 0.7 * (1 - e)),
        );
      }
    }
  }

  @override
  bool shouldRepaint(_SplashPainter oldDelegate) => oldDelegate.t != t;
}
