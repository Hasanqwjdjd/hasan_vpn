import 'package:flutter/services.dart';

/// پل Flutter به TorService بومی.
/// اتصال واقعی Tor توسط libtor.so انجام می‌شود که در پس‌زمینه اجرا می‌شود.
class TorService {
  static const MethodChannel _channel = MethodChannel('com.hasan.hasan_vpn/tor');

  /// شروع Tor. bridgeType یکی از: vanilla, obfs4, snowflake, meek_lite, conjure, dnstt
  static Future<Map<String, dynamic>> start({
    String bridgeType = 'vanilla',
    List<String>? customBridges,
  }) async {
    try {
      final result = await _channel.invokeMapMethod<String, dynamic>('start', {
        'bridgeType': bridgeType,
        'customBridges': customBridges,
      });
      return result ?? {'ok': false, 'error': 'no response'};
    } catch (e) {
      return {'ok': false, 'error': e.toString()};
    }
  }

  static Future<void> stop() async {
    try {
      await _channel.invokeMethod('stop');
    } catch (_) {}
  }

  static Future<Map<String, dynamic>> status() async {
    try {
      final result = await _channel.invokeMapMethod<String, dynamic>('status');
      return result ??
          {
            'running': false,
            'bootstrapPercent': 0,
            'bootstrapMessage': '',
            'socksPort': 0,
            'error': null,
          };
    } catch (_) {
      return {
        'running': false,
        'bootstrapPercent': 0,
        'bootstrapMessage': '',
        'socksPort': 0,
        'error': null,
      };
    }
  }

  static Future<bool> isRunning() async {
    final s = await status();
    return s['running'] == true;
  }
}
