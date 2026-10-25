import 'dart:async';

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../theme/ios_palette.dart';

/// کیت افکت‌های بصری — پورت `ui/home/Wallpapers.kt`، `Glass.kt`،
/// `DriftingLights.kt` از MLM VPN.

// ─────────────────────────────────────────────────────────── کاغذدیواری

class WallpaperPreset {
  final String id;
  final String fa;
  final String en;
  final Color base;
  final List<Color> blobs; // ۳ لکه
  const WallpaperPreset(this.id, this.fa, this.en, this.base, this.blobs);
}

/// ۱۰ پریست procedural — رنگ‌ها عیناً از Wallpapers.kt.
const List<WallpaperPreset> kWallpaperPresets = [
  WallpaperPreset('dusk', 'شامگاه', 'Dusk', Color(0xFF241A16),
      [Color(0xFF5C4033), Color(0xFF4A2F26), Color(0xFF1A1210)]),
  WallpaperPreset('amber', 'کهربا', 'Amber', Color(0xFF2A1E12),
      [Color(0xFF7A5320), Color(0xFF4B331A), Color(0xFF1C1409)]),
  WallpaperPreset('indigo', 'نیلی', 'Indigo', Color(0xFF161A2E),
      [Color(0xFF33407A), Color(0xFF283155), Color(0xFF0E1120)]),
  WallpaperPreset('charcoal', 'زغالی', 'Charcoal', Color(0xFF1A1A1C),
      [Color(0xFF3A3A3F), Color(0xFF2A2A2E), Color(0xFF101012)]),
  WallpaperPreset('mist', 'مه صبح', 'Morning Mist', Color(0xFF1E2626),
      [Color(0xFF44585A), Color(0xFF35494B), Color(0xFF141A1A)]),
  WallpaperPreset('violet', 'ارغوانی', 'Violet', Color(0xFF221831),
      [Color(0xFF56317A), Color(0xFF3A2352), Color(0xFF150F1F)]),
  WallpaperPreset('ocean', 'اقیانوس', 'Ocean', Color(0xFF10222B),
      [Color(0xFF1F4E63), Color(0xFF17394A), Color(0xFF0A161C)]),
  WallpaperPreset('slate', 'خاکستری', 'Slate', Color(0xFF1C2024),
      [Color(0xFF3B444E), Color(0xFF2C333B), Color(0xFF111417)]),
  WallpaperPreset('sunset', 'غروب', 'Sunset', Color(0xFF2B1720),
      [Color(0xFF7B3446), Color(0xFF4C2130), Color(0xFF1A0E14)]),
  WallpaperPreset('forest', 'جنگل', 'Forest', Color(0xFF15231A),
      [Color(0xFF2C4E36), Color(0xFF203A28), Color(0xFF0C150F)]),
];

WallpaperPreset wallpaperById(String id) =>
    kWallpaperPresets.firstWhere((p) => p.id == id,
        orElse: () => kWallpaperPresets.first);

/// موقعیت لکه‌ها (کسر از اندازه صفحه) — جای‌گذاری ثابت و متقارن مثل
/// چیدمان procedural این نسخه (BlobRender: stops 0/0.55/1).
const List<Offset> kBlobPositions = [
  Offset(0.18, 0.16), // بالا-آغازین
  Offset(0.86, 0.42), // میانه-پایانی
  Offset(0.38, 0.92), // پایین-آغازین
];
const List<double> kBlobRadii = [0.55, 0.62, 0.70];

class WallpaperPainter extends CustomPainter {
  final WallpaperPreset preset;
  WallpaperPainter(this.preset);

  @override
  void paint(Canvas canvas, Size size) {
    final base = Paint()..color = preset.base;
    canvas.drawRect(Offset.zero & size, base);
    for (var i = 0; i < preset.blobs.length && i < 3; i++) {
      final tone = preset.blobs[i];
      final c = Offset(
        kBlobPositions[i].dx * size.width,
        kBlobPositions[i].dy * size.height,
      );
      final r = kBlobRadii[i] * size.longestSide;
      final paint = Paint()
        ..shader = ui.Gradient.radial(c, r, [
          tone,
          tone.withValues(alpha: 0.45),
          tone.withValues(alpha: 0.0),
        ], [0.0, 0.55, 1.0]);
      canvas.drawCircle(c, r, paint);
    }
  }

  @override
  bool shouldRepaint(WallpaperPainter oldDelegate) =>
      oldDelegate.preset.id != preset.id;
}

/// پس‌زمینه کاغذدیواری + تاری اختیاری (اسلایدر ۰..۱۰۰).
class WallpaperView extends StatelessWidget {
  final WallpaperPreset preset;
  final int blur; // 0..100
  final Widget? child;

  const WallpaperView({
    super.key,
    required this.preset,
    this.blur = 0,
    this.child,
  });

  @override
  Widget build(BuildContext context) {
    final body = CustomPaint(
      painter: WallpaperPainter(preset),
      child: child,
    );
    if (blur <= 0) return body;
    final sigma = (blur / 100.0) * 40.0;
    return ClipRect(
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
        child: body,
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────── شیشه مات

/// `frostedGlass()` — پورت Glass.kt: لایه‌های tint/wash/haze + لبه 0.7dp.
/// در Flutter، BackdropFilter واقعاً پس‌زمینه را تار می‌کند (معادل
/// تکنیک اسلایس بک‌دراپ MLM با کیفیت یکسان).
class FrostedGlass extends StatelessWidget {
  final Widget? child;
  final BorderRadius? borderRadius;
  final double blur; // سیگما
  final Color? tint;
  final Color? wash;
  final Color? rim;
  final EdgeInsetsGeometry? padding;

  const FrostedGlass({
    super.key,
    this.child,
    this.borderRadius,
    this.blur = 24,
    this.tint,
    this.wash,
    this.rim,
    this.padding,
  });

  @override
  Widget build(BuildContext context) {
    final pal = IosPal.of(context);
    final radius =
        borderRadius ?? BorderRadius.circular(22);
    return ClipRRect(
      borderRadius: radius,
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            // لایه‌بندی Glass.kt: tint (سیاه) زیر wash (سفید)
            color: Color.alphaBlend(
              wash ?? pal.glassWash,
              tint ?? pal.glassTint,
            ),
            borderRadius: radius,
            border: Border.all(
              color: rim ?? pal.glassRim,
              width: 0.7,
            ),
          ),
          child: child,
        ),
      ),
    );
  }
}

/// شیشه‌ی ساده بدون تاریِ backdrop (وقتی پس‌زمینه ثابت است، ارزان‌تر).
class GlassPlate extends StatelessWidget {
  final Widget? child;
  final BorderRadius? borderRadius;
  final EdgeInsetsGeometry? padding;

  const GlassPlate({super.key, this.child, this.borderRadius, this.padding});

  @override
  Widget build(BuildContext context) {
    final pal = IosPal.of(context);
    final radius = borderRadius ?? BorderRadius.circular(22);
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: pal.glassTint,
        borderRadius: radius,
        border: Border.all(color: pal.glassRim, width: 0.7),
      ),
      child: child,
    );
  }
}

// ─────────────────────────────────────────────────────────── نورهای رونده

/// `DriftingLights` — چهار نور شعاعی با drift نویزی (تقریباً ۱۵Hz).
/// روی نوار اتصال/تونل با رنگ هر موتور استفاده می‌شود.
class DriftingLights extends StatefulWidget {
  final List<Color> colors;
  final double opacity;
  final Duration interval;
  const DriftingLights({
    super.key,
    required this.colors,
    this.opacity = 0.16,
    this.interval = const Duration(milliseconds: 66),
  });

  @override
  State<DriftingLights> createState() => _DriftingLightsState();
}

class _DriftingLightsState extends State<DriftingLights> {
  late Timer _timer;
  double _t = 0;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(widget.interval, (_) {
      if (!mounted) return;
      setState(() => _t += 0.055);
    });
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: CustomPaint(
        painter: _LightsPainter(
          t: _t,
          colors: widget.colors.isEmpty
              ? const [Color(0xFF0A84FF)]
              : widget.colors,
          opacity: widget.opacity,
        ),
        child: const SizedBox.expand(),
      ),
    );
  }
}

class _LightsPainter extends CustomPainter {
  final double t;
  final List<Color> colors;
  final double opacity;
  _LightsPainter(
      {required this.t, required this.colors, required this.opacity});

  @override
  void paint(Canvas canvas, Size size) {
    for (var i = 0; i < 4; i++) {
      final c = colors[i % colors.length];
      final phase = t * (0.7 + 0.31 * i);
      final cx = size.width *
          (0.5 + 0.42 * math.sin(phase * 1.1 + i * 1.7) *
              math.cos(phase * 0.43 + i));
      final cy = size.height *
          (0.5 + 0.44 * math.cos(phase * 0.87 + i * 2.3));
      final r = size.shortestSide * (0.5 + 0.14 * math.sin(phase + i));
      final paint = Paint()
        ..shader = ui.Gradient.radial(
          Offset(cx, cy),
          r,
          [
            c.withValues(alpha: opacity),
            c.withValues(alpha: opacity * 0.35),
            c.withValues(alpha: 0),
          ],
          [0.0, 0.6, 1.0],
        );
      canvas.drawCircle(Offset(cx, cy), r, paint);
    }
  }

  @override
  bool shouldRepaint(_LightsPainter oldDelegate) =>
      oldDelegate.t != t || oldDelegate.colors != colors;
}

// ─────────────────────────────────────────────────────────── لبه‌های محو

/// `fadingEdges` — DstIn gradient بالای/پایین محتوا (روی همه صفحات اسکرولی).
class FadingEdges extends StatelessWidget {
  final Widget child;
  final double top;
  final double bottom;
  const FadingEdges(
      {super.key, required this.child, this.top = 0, this.bottom = 0});

  @override
  Widget build(BuildContext context) {
    if (top <= 0 && bottom <= 0) return child;
    return ShaderMask(
      shaderCallback: (bounds) {
        final stops = <double>[];
        final colors = <Color>[];
        if (top > 0) {
          colors.addAll([Colors.black, Colors.black.withValues(alpha: 0)]);
          stops.addAll([0.0, (top / bounds.height).clamp(0.0, 0.45)]);
        }
        if (bottom > 0) {
          colors.addAll([
            Colors.black.withValues(alpha: 0),
            Colors.black,
          ]);
          stops.addAll([
            1.0 - (bottom / bounds.height).clamp(0.0, 0.45),
            1.0,
          ]);
        }
        return LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: colors,
          stops: stops,
        ).createShader(bounds);
      },
      blendMode: BlendMode.dstIn,
      child: child,
    );
  }
}
