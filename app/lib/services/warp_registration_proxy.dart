import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_vless/flutter_vless.dart';

import '../models/server.dart';
import 'v2ray_engine.dart';

/// Proxy داخلی برای register WARP/WARP+ از داخل ایران.
///
/// Cloudflare API (`api.cloudflareclient.com`) در ایران فیلتر است. این
/// سرویس یک VLESS WebSocket/TLS داخلی را در حالت proxy-only بالا می‌آورد
/// و از پورت SOCKS محلی آن برای register استفاده می‌کند.
///
/// از PingNG (rezakhosh78/PingNG) — محتوای `warp_registration_proxy_1.txt`
/// به‌عنوان لینک bundled.
class WarpRegistrationProxy {
  WarpRegistrationProxy._();

  /// VLESS WebSocket/TLS — از منابع PingNG. نباید در UI منتشر بشه.
  static const String bundledVlessLink =
      'vless://667ef0e4-2a1f-479e-a924-6138fae98401@'
      '104.17.71.206:443?path=%2Fvl%2FVhUzrJSK2tMhgryGTPJqfR'
      '%3Fed%3D2560&security=tls&alpn=http%2F1.1&encryption=none'
      '&insecure=0&host=n5ympfftwt17mzqjb9tfv.woudhb.workers.dev'
      '&fp=chrome&type=ws&allowInsecure=0'
      '&sni=n5YmPfFTwt17MZQjB9tfv.WOUDhB.workERs.dEV';

  static bool _running = false;
  static bool get isRunning => _running;

  /// Xray را در حالت proxy-only با VLESS داخلی بالا می‌آورد و پورت SOCKS
  /// محلی را برمی‌گرداند. اگر راه‌اندازی موفق نبود، `null`.
  static Future<int?> ensureStarted({
    Duration timeout = const Duration(seconds: 20),
    void Function(String msg)? onProgress,
  }) async {
    if (_running && V2RayEngine.isConnected) {
      final p = V2RayEngine.localSocksPort;
      if (p > 0) return p;
    }

    try {
      onProgress?.call('Starting internal registration proxy...');
      final parser = FlutterVless.parse(bundledVlessLink);
      final config = parser.getFullConfiguration();
      if (config.isEmpty) {
        debugPrint('WarpRegistrationProxy: empty config from link');
        return null;
      }

      final fakeServer = VpnServer(
        id: 'warp-reg-proxy-internal',
        name: 'Warp Registration Proxy',
        flag: '\u{1F6E1}',
        shareLink: bundledVlessLink,
        protocol: VpnProtocol.vless,
        host: '104.17.71.206',
        port: 443,
        isDeletable: false,
      );

      final ok = await V2RayEngine.startConfig(
        remark: fakeServer.name,
        config: config,
        server: fakeServer,
        forceProxyOnly: true,
      );
      if (!ok) {
        debugPrint('WarpRegistrationProxy: start failed: '
            '${V2RayEngine.lastError}');
        return null;
      }

      // انتظار برای SOCKS ready + تست واقعی
      final deadline = DateTime.now().add(timeout);
      while (DateTime.now().isBefore(deadline)) {
        final p = V2RayEngine.localSocksPort;
        if (p > 0 && V2RayEngine.isConnected) {
          try {
            final s = await Socket.connect(
              '127.0.0.1',
              p,
              timeout: const Duration(milliseconds: 300),
            );
            s.destroy();
            _running = true;
            debugPrint('WarpRegistrationProxy: SOCKS ready on $p');
            return p;
          } catch (_) {}
        }
        await Future<void>.delayed(const Duration(milliseconds: 300));
      }
      debugPrint('WarpRegistrationProxy: timeout waiting for SOCKS');
      return null;
    } catch (e) {
      debugPrint('WarpRegistrationProxy: error: $e');
      return null;
    }
  }

  static Future<void> stop() async {
    if (!_running) return;
    _running = false;
    try {
      await V2RayEngine.disconnect();
    } catch (_) {}
  }
}
