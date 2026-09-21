import 'dart:async';
import 'package:flutter/services.dart';

/// سرویس مانیتور زنده — CPU، حافظه، باتری و سرعت شبکه.
/// داده‌ها از LiveMonitorService.kt بومی می‌آید.
class LiveMonitorService {
  static const MethodChannel _channel =
      MethodChannel('com.hasan.hasan_vpn/monitor');

  Timer? _timer;
  final _controller = StreamController<Map<String, dynamic>>.broadcast();

  Stream<Map<String, dynamic>> get stream => _controller.stream;

  void start({Duration interval = const Duration(seconds: 2)}) {
    _timer?.cancel();
    _timer = Timer.periodic(interval, (_) => _tick());
    _tick();
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  Future<void> _tick() async {
    try {
      final raw = await _channel.invokeMapMethod<String, dynamic>('snapshot');
      if (raw != null) {
        _controller.add(Map<String, dynamic>.from(raw));
      }
    } catch (_) {}
  }

  void dispose() {
    stop();
    _controller.close();
  }
}
