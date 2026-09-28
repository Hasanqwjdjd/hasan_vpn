import 'dart:async';

import 'package:flutter/services.dart';

/// Wrapper for `DesyncEngine.kt` — runs `libPingNG.so` as an in-process
/// SOCKS5 listener that Xray can dial via `sockopt.dialerProxy`.
///
/// Flow:
///   1. Dart builds the ciadpi-style argument list (see [PingNgArgs])
///   2. Dart picks a free localhost port and calls [start]
///   3. Kotlin prepares the JNI socket and spawns a daemon thread
///   4. Xray's proxy outbound points its dialerProxy at socks://127.0.0.1:port
class DesyncService {
  DesyncService._();

  static const MethodChannel _ch =
      MethodChannel('com.hasan.hasan_vpn/desync');

  static int _activePort = 0;
  static bool get isRunning => _activePort > 0;
  static int get activePort => _activePort;

  /// Starts the native listener on [port].
  ///
  /// Returns the bound port on success, or `null` when the native engine
  /// refused the command line. Callers should treat `null` as a soft failure
  /// and continue without Desync rather than aborting the whole connection.
  static Future<int?> start({
    required List<String> args,
    required int port,
  }) async {
    if (port < 1 || port > 65535) return null;
    try {
      final actualPort = await _ch.invokeMethod<int>('start', {
        'args': args,
        'port': port,
      });
      _activePort = actualPort ?? 0;
      return _activePort > 0 ? _activePort : null;
    } on PlatformException {
      _activePort = 0;
      return null;
    } on MissingPluginException {
      _activePort = 0;
      return null;
    }
  }

  static Future<void> stop() async {
    _activePort = 0;
    try {
      await _ch.invokeMethod('stop');
    } catch (_) {
      // Best-effort: if the channel is gone, the native side already stopped.
    }
  }

  static Future<int> currentPort() async {
    try {
      final result = await _ch.invokeMethod<Map<Object?, Object?>>('status');
      final port = (result?['port'] as num?)?.toInt() ?? 0;
      _activePort = port;
      return port;
    } catch (_) {
      return 0;
    }
  }
}
