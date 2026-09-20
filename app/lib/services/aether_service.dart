import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../models/server.dart';

class AetherService {
  static const MethodChannel _channel =
      MethodChannel('com.hasan.hasan_vpn/aether');

  static bool _connected = false;
  static VpnServer? _current;
  static String? lastError;

  static bool get isConnected => _connected;
  static VpnServer? get current => _current;

  static const List<String> scanModes = <String>[
    'fast',
    'balanced',
    'full',
  ];

  static const List<String> protocolModes = <String>[
    'auto',
    'masque_h3',
    'masque_h2',
    'wireguard',
    'gool',
  ];

  static String buildConfigLink({
    required String scanMode,
    required String protocolMode,
    String upstreamProxy = '',
  }) {
    final safeScanMode = scanModes.contains(scanMode) ? scanMode : 'balanced';
    final safeProtocolMode =
        protocolModes.contains(protocolMode) ? protocolMode : 'auto';

    final query = <String, String>{
      'scan': safeScanMode,
      'protocol': safeProtocolMode,
    };

    if (upstreamProxy.trim().isNotEmpty) {
      query['upstream'] = upstreamProxy.trim();
    }

    return Uri(
      scheme: 'aether',
      host: 'config',
      queryParameters: query,
    ).toString();
  }

  static Map<String, String> parseConfigLink(String link) {
    try {
      final uri = Uri.parse(link);

      if (uri.scheme.toLowerCase() != 'aether') {
        return const <String, String>{};
      }

      return Map<String, String>.from(uri.queryParameters);
    } catch (_) {
      return const <String, String>{};
    }
  }

  static Future<bool> _waitUntilReady({
    Duration timeout = const Duration(seconds: 20),
  }) async {
    final deadline = DateTime.now().add(timeout);

    while (DateTime.now().isBefore(deadline)) {
      final status = await nativeStatus();

      if (status['connected'] == true) {
        return true;
      }

      final nativeError = status['error']?.toString();
      if (nativeError != null && nativeError.isNotEmpty) {
        lastError = nativeError;
        return false;
      }

      await Future<void>.delayed(const Duration(milliseconds: 400));
    }

    return false;
  }

  static Future<bool> connect(VpnServer server) async {
    lastError = null;
    _connected = false;
    _current = null;

    if (!server.isAether) {
      lastError = 'Selected server is not an Aether configuration';
      return false;
    }

    try {
      final config = parseConfigLink(server.shareLink);

      final scanMode = scanModes.contains(config['scan'])
          ? config['scan']!
          : 'balanced';

      final protocolMode = protocolModes.contains(config['protocol'])
          ? config['protocol']!
          : 'auto';

      final upstreamProxy = config['upstream'] ?? '';

      final allowed =
          await _channel.invokeMethod<bool>('prepare') ?? false;

      if (!allowed) {
        lastError = 'VPN permission denied';
        return false;
      }

      final started = await _channel.invokeMethod<bool>(
            'start',
            <String, dynamic>{
              'scanMode': scanMode,
              'protocolMode': protocolMode,
              'upstreamProxy': upstreamProxy,
              'remark': server.name,
            },
          ) ??
          false;

      if (!started) {
        lastError = 'Aether service could not be started';
        return false;
      }

      final ready = await _waitUntilReady();

      if (!ready) {
        await disconnect();
        lastError ??= 'Aether did not become ready';
        return false;
      }

      _connected = true;
      _current = server;
      return true;
    } on PlatformException catch (error) {
      lastError = '${error.code}: ${error.message ?? 'Native error'}';
      debugPrint('Aether PlatformException: $lastError');
      _connected = false;
      _current = null;
      return false;
    } catch (error) {
      lastError = error.toString();
      debugPrint('Aether connection error: $lastError');
      _connected = false;
      _current = null;
      return false;
    }
  }

  static Future<void> disconnect() async {
    try {
      await _channel.invokeMethod<void>('stop');
    } catch (error) {
      debugPrint('Aether disconnect error: $error');
    } finally {
      _connected = false;
      _current = null;
    }
  }

  static Future<Map<String, dynamic>> nativeStatus() async {
    try {
      final result =
          await _channel.invokeMapMethod<String, dynamic>('status');

      return result ?? const <String, dynamic>{};
    } on PlatformException catch (error) {
      debugPrint('Aether status error: ${error.message}');
      return const <String, dynamic>{};
    } catch (_) {
      return const <String, dynamic>{};
    }
  }

  static Future<bool> syncStatus() async {
    final status = await nativeStatus();
    final connected = status['connected'] == true;

    _connected = connected;

    if (!connected) {
      _current = null;
    }

    return connected;
  }
}
