import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../fx/fx.dart';
import '../theme/ios_palette.dart';

/// تایل‌ها و داک — پورت `ui/home/AppIcon.kt`، `GlassDock.kt`،
/// `HomeScreen.kt` (نوار وضعیت) و `TransportScreen.kt` (DialCore) از MLM VPN.

// ─────────────────────────────────────────────────────────── آیکون تایل

enum TileArtKind { svg, png, glyph }

class TileArt {
  final TileArtKind kind;
  final String asset; // برای svg/png
  final IconData? icon; // برای glyph
  const TileArt.svg(this.asset)
      : kind = TileArtKind.svg,
        icon = null;
  const TileArt.png(this.asset)
      : kind = TileArtKind.png,
        icon = null;
  const TileArt.glyph(this.icon)
      : kind = TileArtKind.glyph,
        asset = '';
}

/// خود تایل مربعی + زیرنویس — اندازه = اندازه آیکون (زیرنویس جدا رندر می‌شود).
class AppIconTile extends StatelessWidget {
  final double size;
  final TileArt art;
  final Color tint;
  final double glyphScale;
  final bool running;
  final int? badgeCount;

  const AppIconTile({
    super.key,
    required this.size,
    required this.art,
    required this.tint,
    this.glyphScale = 0.52,
    this.running = false,
    this.badgeCount,
  });

  @override
  Widget build(BuildContext context) {
    Widget inner;
    switch (art.kind) {
      case TileArtKind.svg:
        inner = Padding(
          padding: EdgeInsets.all(size * 0.05),
          child: SvgPicture.asset(art.asset, fit: BoxFit.contain),
        );
        break;
      case TileArtKind.png:
        inner = Padding(
          padding: EdgeInsets.all(size * 0.05),
          child: Image.asset(art.asset, fit: BoxFit.contain),
        );
        break;
      case TileArtKind.glyph:
        // گرادیان عمودی lerp(tint, White, .18) → lerp(tint, Black, .14)
        inner = DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Color.lerp(tint, Colors.white, 0.18)!,
                Color.lerp(tint, Colors.black, 0.14)!,
              ],
            ),
          ),
          child: Center(
            child: Icon(
              art.icon,
              color: Colors.white,
              size: size * glyphScale,
            ),
          ),
        );
        break;
    }

    final squircle = BorderRadius.circular(size * 0.26);
    Widget tile = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: squircle,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.30),
            blurRadius: 6,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: squircle,
        child: inner,
      ),
    );

    // لامپ سبز اجرا — دات 26% (coerce 9..16)، بیرون گوشه با −22%
    if (running) {
      final d = (size * 0.26).clamp(9.0, 16.0);
      tile = Stack(
        clipBehavior: Clip.none,
        children: [
          tile,
          Positioned.directional(
            textDirection: Directionality.of(context),
            top: -d * 0.22,
            end: -d * 0.22,
            child: Container(
              width: d,
              height: d,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Ios.lampRing,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.5),
                    blurRadius: 3,
                  ),
                ],
              ),
              padding: EdgeInsets.all(d * 0.16),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: const LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Ios.lampGreen1, Ios.lampGreen2],
                  ),
                ),
              ),
            ),
          ),
        ],
      );
    }

    // نشان قرمز — 36% (coerce 18..24)، بیرون گوشه مقابل
    if (badgeCount != null && badgeCount! > 0) {
      final d = (size * 0.36).clamp(18.0, 24.0);
      final text = badgeCount! > 99 ? '99+' : '$badgeCount';
      tile = Stack(
        clipBehavior: Clip.none,
        children: [
          tile,
          Positioned.directional(
            textDirection: Directionality.of(context),
            top: -d * 0.34,
            start: -d * 0.34,
            child: Container(
              width: d,
              height: d,
              alignment: Alignment.center,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: Ios.badgeRed,
              ),
              child: Text(
                text,
                textDirection: TextDirection.ltr,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: d * 0.58,
                  fontWeight: FontWeight.w600,
                  height: 1.0,
                ),
              ),
            ),
          ),
        ],
      );
    }

    return tile;
  }
}

/// زیرنویس تایل — 11sp Medium سفید با سایه (AppIcon.kt L60-64).
class TileCaption extends StatelessWidget {
  final String label;
  final double labelScale; // 1.0 = 100%
  final bool emphasized; // حالت ویرایش — سفید پررنگ‌تر
  const TileCaption(this.label,
      {super.key, this.labelScale = 1.0, this.emphasized = false});

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      textAlign: TextAlign.center,
      style: TextStyle(
        color: Colors.white,
        fontSize: 11 * labelScale,
        fontWeight: FontWeight.w500,
        height: 1.0,
        shadows: [
          Shadow(
            color: Colors.black.withValues(alpha: emphasized ? 0.8 : 0.65),
            offset: const Offset(0, 1),
            blurRadius: 4,
          ),
        ],
      ),
    );
  }
}

/// چرخش لرزان حالت ویرایش — ±1.7°، 170ms رفت‌وبرگشت با فاز متناوب.
class Jiggle extends StatefulWidget {
  final Widget child;
  final bool enabled;
  final int index;
  const Jiggle(
      {super.key, required this.child, required this.enabled, this.index = 0});

  @override
  State<Jiggle> createState() => _JiggleState();
}

class _JiggleState extends State<Jiggle> with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 170),
    );
  }

  @override
  void didUpdateWidget(Jiggle oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.enabled && !_c.isAnimating) {
      _c.repeat(reverse: true);
    } else if (!widget.enabled && _c.isAnimating) {
      _c.stop();
      _c.value = 0.5;
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) return widget.child;
    final dir = widget.index.isEven ? 1.0 : -1.0;
    return AnimatedBuilder(
      animation: _c,
      builder: (context, child) {
        final v = (_c.value - 0.5) * 2.0; // −1..1
        return Transform.rotate(
          angle: v * 1.7 * dir * 3.14159265 / 180.0,
          child: child,
        );
      },
      child: widget.child,
    );
  }
}

// ─────────────────────────────────────────────────────────── داک شیشه‌ای

/// `GlassDock` — ۴ تایل ثابت 56dp، گوشه 30، فقط روی صفحه‌خانه.
class GlassDock extends StatelessWidget {
  final List<Widget> tiles;
  final bool showLabels;
  final Future<void> Function(double size)? onTileSizeResolved;

  const GlassDock({
    super.key,
    required this.tiles,
    this.showLabels = false,
    this.onTileSizeResolved,
  });

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.bottomCenter,
      child: Padding(
        padding: const EdgeInsets.only(left: 14, right: 14, bottom: 10),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: FrostedGlass(
            borderRadius: BorderRadius.circular(30),
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: tiles,
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────── نوار وضعیت

/// نوار وضعیت صفحه‌خانه — سپر + ترافیک زنده (HomeScreen.kt L410-483).
class StatusStrip extends StatelessWidget {
  final bool running;
  final String download;
  final String upload;
  const StatusStrip({
    super.key,
    required this.running,
    required this.download,
    required this.upload,
  });

  @override
  Widget build(BuildContext context) {
    final pal = IosPal.of(context);
    final mono = TextStyle(
      fontFamily: 'monospace',
      fontSize: 12,
      color: Colors.white,
      height: 1.0,
    );
    return SizedBox(
      height: 40,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Row(
          children: [
            Icon(
              Icons.shield_outlined,
              size: 16,
              color: running
                  ? Ios.shieldOn
                  : const Color(0xFFB9BDC2).withValues(alpha: 0.55),
            ),
            const Spacer(),
            Icon(Icons.south, size: 13,
                color: running ? Ios.shieldOn : pal.textMuted),
            const SizedBox(width: 4),
            Text(download, style: mono),
            const SizedBox(width: 12),
            Icon(Icons.north, size: 13, color: Ios.upTeal),
            const SizedBox(width: 4),
            Text(upload, style: mono),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────── دیال اتصال

enum DialStage { idle, connecting, connected, failed }

/// `ConnectDial`/`DialCore` — دایره‌های 196/168/134 با کمان پیشرفت 3dp.
class ConnectDial extends StatelessWidget {
  final String label;
  final DialStage stage;
  final int? progress; // 0..100 واقعی؛ null = نامعین
  final Color accent;
  final Widget? face;
  final VoidCallback? onTap;

  const ConnectDial({
    super.key,
    required this.label,
    required this.stage,
    this.progress,
    required this.accent,
    this.face,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final connecting = stage == DialStage.connecting;
    final size = 196.0;
    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: size,
        height: size,
        child: Stack(
          alignment: Alignment.center,
          children: [
            // پرکننده شعاعی 196dp — accent α.07 → .16
            Container(
              width: size,
              height: size,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    accent.withValues(alpha: 0.07),
                    accent.withValues(alpha: 0.16),
                  ],
                ),
              ),
            ),
            // حلقه 168dp
            SizedBox(
              width: 168,
              height: 168,
              child: CustomPaint(
                painter: _DialRingPainter(
                  accent: accent,
                  showArc: connecting,
                  progress: progress,
                  connected: stage == DialStage.connected,
                ),
              ),
            ),
            // دکمه گرادیانی 134dp
            Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: onTap,
                customBorder: const CircleBorder(),
                child: Container(
                  width: 134,
                  height: 134,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        accent.withValues(alpha: 0.95),
                        accent.withValues(alpha: 0.62),
                      ],
                    ),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (face != null) ...[
                        SizedBox(width: 44, height: 44, child: face),
                        const SizedBox(height: 6),
                      ],
                      Text(
                        label,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DialRingPainter extends CustomPainter {
  final Color accent;
  final bool showArc;
  final int? progress;
  final bool connected;
  _DialRingPainter({
    required this.accent,
    required this.showArc,
    required this.progress,
    required this.connected,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final r = size.width / 2 - 1;
    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = accent.withValues(alpha: 0.28);
    canvas.drawCircle(c, r, ring);

    if (showArc) {
      final sweep = (progress != null && progress! > 0)
          ? 2 * 3.14159265 * (progress!.clamp(0, 100) / 100.0)
          : 2 * 3.14159265 * 0.266; // کمان نامعین 96°
      final arc = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round
        ..color = accent;
      // شروع از بالا
      canvas.drawArc(Rect.fromCircle(center: c, radius: r), -1.5708,
          sweep, false, arc);
    }
    if (connected) {
      final dot = Paint()..color = Ios.shieldOn;
      canvas.drawCircle(Offset(c.dx + r * 0.7071, c.dy - r * 0.7071), 3, dot);
    }
  }

  @override
  bool shouldRepaint(_DialRingPainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.showArc != showArc ||
      oldDelegate.connected != connected ||
      oldDelegate.accent != accent;
}

// ─────────────────────────────────────────────────────────── خط وضعیت

/// StatusLine — رنگ‌بندی عیناً از TransportScreen.kt.
class TransportStatusLine extends StatelessWidget {
  final DialStage stage;
  final String headline;
  final String? message;
  final Color accent;
  const TransportStatusLine({
    super.key,
    required this.stage,
    required this.headline,
    this.message,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    Color c;
    switch (stage) {
      case DialStage.connected:
        c = IosPal.of(context).green;
        break;
      case DialStage.connecting:
        c = accent;
        break;
      case DialStage.failed:
        c = IosPal.of(context).red;
        break;
      case DialStage.idle:
        c = IosPal.of(context).textMuted;
        break;
    }
    return Column(
      children: [
        Text(
          headline,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: c,
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
        if (message != null && message!.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            message!,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: IosPal.of(context).textMuted,
              fontSize: 13,
            ),
          ),
        ],
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────── کارت شیشه‌ای

/// کارت شیشه‌ای «چطور کار می‌کند» — بدنه 13sp/20.
class HowItWorksCard extends StatelessWidget {
  final String text;
  const HowItWorksCard({super.key, required this.text});

  @override
  Widget build(BuildContext context) {
    return FrostedGlass(
      borderRadius: BorderRadius.circular(22),
      padding: const EdgeInsets.all(16),
      child: Text(
        text,
        style: TextStyle(
          color: Colors.white,
          fontSize: 13,
          height: 20 / 13,
        ),
      ),
    );
  }
}
