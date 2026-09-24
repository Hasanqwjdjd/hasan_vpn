import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../services/live_monitor_service.dart';

/// E1: lightweight up/down sparkline from LiveMonitorService.snapshot.
class TrafficSparkline extends StatefulWidget {
  const TrafficSparkline({super.key, this.height = 48});
  final double height;

  @override
  State<TrafficSparkline> createState() => _TrafficSparklineState();
}

class _TrafficSparklineState extends State<TrafficSparkline> {
  final _mon = LiveMonitorService();
  final _down = <double>[];
  final _up = <double>[];
  StreamSubscription? _sub;
  int _totalDown = 0;
  int _totalUp = 0;

  @override
  void initState() {
    super.initState();
    _mon.start(interval: const Duration(seconds: 1));
    _sub = _mon.stream.listen((m) {
      final d = (m['downBps'] as num?)?.toDouble() ??
          (m['rxBps'] as num?)?.toDouble() ??
          0;
      final u = (m['upBps'] as num?)?.toDouble() ??
          (m['txBps'] as num?)?.toDouble() ??
          0;
      _totalDown = (m['totalDown'] as num?)?.toInt() ?? _totalDown;
      _totalUp = (m['totalUp'] as num?)?.toInt() ?? _totalUp;
      setState(() {
        _down.add(d);
        _up.add(u);
        if (_down.length > 30) _down.removeAt(0);
        if (_up.length > 30) _up.removeAt(0);
      });
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    _mon.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: widget.height,
          width: double.infinity,
          child: CustomPaint(
            painter: _SparkPainter(down: _down, up: _up),
          ),
        ),
        Text(
          '↓ ${_fmt(_totalDown)}   ↑ ${_fmt(_totalUp)}',
          style: TextStyle(
            fontSize: 11,
            color: Theme.of(context).textTheme.bodySmall?.color,
          ),
        ),
      ],
    );
  }

  static String _fmt(int b) {
    if (b >= 1000000000) return '${(b / 1e9).toStringAsFixed(1)} GB';
    if (b >= 1000000) return '${(b / 1e6).toStringAsFixed(1)} MB';
    if (b >= 1000) return '${(b / 1e3).toStringAsFixed(0)} KB';
    return '$b B';
  }
}

class _SparkPainter extends CustomPainter {
  _SparkPainter({required this.down, required this.up});
  final List<double> down;
  final List<double> up;

  @override
  void paint(Canvas canvas, Size size) {
    final maxV = math.max(
      1.0,
      math.max(
        down.isEmpty ? 0 : down.reduce(math.max),
        up.isEmpty ? 0 : up.reduce(math.max),
      ),
    );
    void draw(List<double> data, Color c) {
      if (data.length < 2) return;
      final p = Paint()
        ..color = c
        ..strokeWidth = 1.5
        ..style = PaintingStyle.stroke;
      final path = Path();
      for (var i = 0; i < data.length; i++) {
        final x = size.width * i / (data.length - 1);
        final y = size.height - (data[i] / maxV) * size.height;
        if (i == 0) {
          path.moveTo(x, y);
        } else {
          path.lineTo(x, y);
        }
      }
      canvas.drawPath(path, p);
    }

    draw(down, const Color(0xFF42A5F5));
    draw(up, const Color(0xFF66BB6A));
  }

  @override
  bool shouldRepaint(covariant _SparkPainter old) =>
      old.down != down || old.up != up;
}
