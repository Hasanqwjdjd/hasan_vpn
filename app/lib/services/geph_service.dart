import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/server.dart';
import 'connection_log_service.dart';
import 'socks_probe.dart';
import 'socks_xray_builder.dart';
import 'store_service.dart';
import 'v2ray_engine.dart';

/// هستهٔ Geph (geph5-client) — پورت «GephConfig/GephEngine» از MLM VPN.
///
/// معماری: هستهٔ Rust با گوش SOCKS5 بالا می‌آید (socks5_listen) و Xray
/// همان‌طور که Psiphon/Tor را می‌بندد، ترافیک TUN را به آن می‌رساند.
/// Config حتماً فقط کلیدهای مجاز Config در geph5-client را دارد
/// (#[serde(deny_unknown_fields)]) — پین‌شده در GephConfig.kt MLM.
class GephServiceDart {
  GephServiceDart._();

  static const MethodChannel _ch = MethodChannel('com.hasan.hasan_vpn/geph');
  static const MethodChannel _storeCh =
      MethodChannel('com.hasan.hasan_vpn/store');

  static String? lastError;
  static bool _connected = false;
  static int _socksPort = 0;

  static bool get isConnected => _connected;
  static int get socksPort => _socksPort;

  static Future<Directory> _dataDir() async {
    final base = await getApplicationSupportDirectory();
    return Directory('${base.path}/geph');
  }

  static Future<int> _freePort() async {
    final s = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final port = s.port;
    await s.close();
    return port;
  }

  /// ساخت config — کلیدها ۱:۱ از GephConfig.build در MLM (v1.2.42).
  static Future<Map<String, dynamic>> buildConfig({
    required int socksPort,
    required String controlSocket,
    required String cacheFile,
    String? secret,
    String exitCountry = '',
    bool allowDirect = false,
    bool spoofDns = false,
    bool blockAds = false,
    bool blockAdult = false,
  }) async {
    return <String, dynamic>{
      'socks5_listen': '127.0.0.1:$socksPort',
      'http_proxy_listen': null,
      'pac_listen': null,
      'control_listen': null,
      'control_listen_unix': controlSocket,
      'exit_constraint': exitCountry.trim().isEmpty
          ? 'auto'
          : <String, dynamic>{'country': exitCountry.trim().toUpperCase()},
      'allow_direct': allowDirect,
      'cache': cacheFile,
      'broker': <String, dynamic>{
        'priority_race': <String, dynamic>{
          '2500': <String, dynamic>{
            'aws_lambda': <String, dynamic>{
              'function_name': 'geph-lambda-bouncer',
              'region': 'us-east-1',
              'obfs_key':
                  '855MJGAMB58MCPJBB97NADJ36D64WM2T:C4TN2M1H68VNMRVCCH57GDV2C5VN6V3RB8QMWP235D0P4RT2ACV7GVTRCHX3EC37',
            },
          },
          '1500': <String, dynamic>{
            'fronted': <String, dynamic>{
              'front': 'https://kubernetes.io/',
              'host': 'svitania-naidallszei-2.netlify.app',
              'override_dns': <String>['75.2.60.5:443'],
            },
          },
          '500': <String, dynamic>{
            'fronted': <String, dynamic>{
              'front': 'https://kubernetes.io/',
              'host': 'svitania-naidallszei-2.netlify.app',
            },
          },
          '0': <String, dynamic>{
            'fronted': <String, dynamic>{
              'front': 'https://www.cdn77.com/',
              'host': '1826209743.rsc.cdn77.org',
            },
          },
        },
      },
      'tunneled_broker': <String, dynamic>{
        'direct': 'https://broker.geph.io',
      },
      'broker_keys': <String, dynamic>{
        'master':
            '88c1d2d4197bed815b01a22cadfc6c35aa246dddb553682037a118aebfaa3954',
        'mizaru_free':
            '0558216cbab7a9c46f298f4c26e171add9af87d0694988b8a8fe52ee932aa754',
        'mizaru_plus':
            'cf6f58868c6d9459b3a63bc2bd86165631b3e916bad7f62b578cd9614e0bcb3b',
        'mizaru_bw':
            '3082010a0282010100d0ae53a794ea37bf2e100cb3a872177ec6c11e8375fdcbf92960ce0293465674eb1426a1841b7622a58979a5ff3f8aa2301a621545e9b90bb39d1a6bfda19d6ca1aae74a3192ddfd2b9558eb652c3c2c22f42bdde272852fb67d93cae5846213512c474bf799844aee019bf718f6fa64223be06364459fc8dec66796b141d450d730c4fffe1cac7df8f05591560afa44bcf274f6c0e2303b39c21ab09d19b459ee594512b8341f3d407c026e2509f42c6d89f82f6a3a36fd5c05ad423cd99ad39089403eb9122ea60ef6648afff65438e8e26ce41fa55b9b18741965c77a627bae947bd38fc345e9adab42d6c458f6e194e4232cfd3f04924d5a5e932fe769610203010001',
      },
      'port_forward': <dynamic>[],
      'spoof_dns': spoofDns,
      'passthrough_china': false,
      'allow_lan': true,
      'dry_run': false,
      'credentials': <String, dynamic>{
        'secret': (secret == null || secret.trim().isEmpty)
            ? ''
            : secret.trim(),
      },
      'sess_metadata': <String, dynamic>{
        'filter': <String, dynamic>{
          'nsfw': blockAdult,
          'ads': blockAds,
        },
      },
      'task_limit': null,
    };
  }

  /// اتصال کامل: استارت هسته → آماده شدن SOCKS → بستن مسیر با Xray.
  static Future<bool> connect({
    void Function(String msg)? onProgress,
    bool Function()? isCancelled,
  }) async {
    lastError = null;
    _connected = false;
    bool cancelled() => isCancelled?.call() ?? false;

    try {
      final installed = await StoreService.gephInstalled();
      if (!installed) {
        lastError = 'engine-missing';
        return false;
      }

      final allowed = await V2RayEngine.requestPermission();
      if (!allowed) {
        lastError = 'VPN permission denied';
        return false;
      }

      onProgress?.call('Geph · آماده‌سازی config');
      final dir = await _dataDir();
      await dir.create(recursive: true);
      final port = await _freePort();
      final prefs = await SharedPreferences.getInstance();
      final secret = prefs.getString('geph_secret');
      final exitCountry = prefs.getString('geph_exit_country') ?? '';
      final cfg = await buildConfig(
        socksPort: port,
        controlSocket: '${dir.path}/ctl.sock',
        cacheFile: '${dir.path}/cache.db',
        secret: secret,
        exitCountry: exitCountry,
      );
      final cfgFile = File('${dir.path}/config.json');
      // JSON = YAML معتبر؛ همان کاری که MLM می‌کند.
      await cfgFile.writeAsString(jsonEncode(cfg));

      final binary = await StoreService.gephBinaryPath();
      await _storeCh.invokeMethod('makeExecutable', {'path': binary});

      onProgress?.call('Geph · راه‌اندازی هسته (v'
          '${StoreService.gephInstalledVersion ?? "?"})');
      final started = await _ch.invokeMethod<bool>('start', {
        'binary': binary,
        'config': cfgFile.path,
        'port': port,
        'remark': 'Geph',
      });
      if (started != true) {
        lastError = 'Geph service could not be started';
        return false;
      }
      _socksPort = port;

      // صبر تا آماده شدن واقعی — پروب SOCKS (مثل همهٔ موتورها).
      final deadline = DateTime.now().add(const Duration(seconds: 120));
      var lastShown = '';
      while (DateTime.now().isBefore(deadline)) {
        if (cancelled()) {
          await stop();
          return false;
        }
        await Future<void>.delayed(const Duration(milliseconds: 600));
        final st = await status();
        final line = st['lastLine']?.toString() ?? '';
        final alive = st['running'] == true;
        if (!alive) {
          lastError = st['error']?.toString() ??
              'Geph exited: ${st['lastLine'] ?? ''}';
          return false;
        }
        if (line.isNotEmpty && line != lastShown) {
          lastShown = line;
          onProgress?.call('Geph · ${_shorten(line)}');
        }
        final probe = await SocksProbe.measure(
          port: port,
          samples: 1,
          timeout: const Duration(seconds: 5),
        );
        if (probe.ok) break;
      }
      if (cancelled()) return false;

      final ready = await SocksProbe.isPortOpen(port);
      if (!ready) {
        lastError =
            'Timed out${lastShown.isNotEmpty ? ': $lastShown' : ''}';
        await stop();
        return false;
      }

      onProgress?.call('Geph · بستن مسیر با Xray');
      final cfgXray = SocksXrayBuilder.buildXrayConfig(socksPort: port);
      final fake = VpnServer(
        id: 'geph_fake_${DateTime.now().millisecondsSinceEpoch}',
        name: 'Geph',
        flag: '🌀',
        shareLink: 'xrayjson://geph',
        protocol: VpnProtocol.xrayJson,
        host: '127.0.0.1',
        port: port,
        isDeletable: false,
      );
      final ok = await V2RayEngine.startConfig(
        remark: 'Geph',
        config: cfgXray,
        server: fake,
      );
      if (!ok) {
        lastError = V2RayEngine.lastError ?? 'VPN routing failed';
        await stop();
        return false;
      }
      _connected = true;
      ConnectionLogService.logConnect('Geph');
      return true;
    } catch (e) {
      lastError = e.toString();
      return false;
    }
  }

  static Future<void> stop() async {
    try {
      await V2RayEngine.disconnect();
    } catch (_) {}
    try {
      await _ch.invokeMethod('stop');
    } catch (_) {}
    _connected = false;
    _socksPort = 0;
  }

  static Future<Map<String, dynamic>> status() async {
    try {
      final r = await _ch.invokeMapMethod<String, dynamic>('status');
      return r ?? {'running': false};
    } catch (_) {
      return {'running': false};
    }
  }

  static String _shorten(String v) =>
      v.length <= 72 ? v : '${v.substring(0, 72)}…';
}
