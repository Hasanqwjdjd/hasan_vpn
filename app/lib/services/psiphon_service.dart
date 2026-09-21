import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../models/server.dart';
import 'aether_service.dart';
import 'v2ray_engine.dart';

typedef PsiphonProgress = void Function(String message);

/// سرویس Dart برای هستهٔ واقعی Psiphon.
///
/// معماری:
///   برنامه → VPN سیستم (flutter_vless) → Xray outbound SOCKS →
///   پراکسی محلی Psiphon → شبکهٔ Psiphon
///
/// نیاز به AAR رسمی `ca.psiphon:psiphontunnel` در بیلد اندروید دارد.
/// بدون SponsorId/PropagationChannelId معتبر، هسته وصل نمی‌شود.
class PsiphonService {
  PsiphonService._();

  static const MethodChannel _channel =
      MethodChannel('com.hasan.hasan_vpn/psiphon');

  static const String _appPackage = 'com.hasan.hasan_vpn';

  static bool _connected = false;
  static VpnServer? _current;
  static int _socksPort = 0;
  static String? lastError;
  static String? lastRegion;

  static bool get isConnected => _connected;
  static VpnServer? get current => _current;

  /// کانفیگ پیش‌فرض — همان الگوی bepass-org/warp-plus (Cfon/Psiphon در Oblivion).
  /// SponsorId و PropagationChannelId در warp-plus برابر FFFFFFFFFFFFFFFF است؛
  /// اتصال با RemoteServerListUrl + کلید امضا کار می‌کند.
  static const String _oblivionRemoteServerListUrl =
      'https://s3.amazonaws.com//psiphon/web/mjr4-p23r-puwl/server_list_compressed';

  static const String _oblivionRemoteServerListSigKey =
      'MIICIDANBgkqhkiG9w0BAQEFAAOCAg0AMIICCAKCAgEAt7Ls+/39r+T6zNW7GiVpJfzq/'
      'xvL9SBH5rIFnk0RXYEYavax3WS6HOD35eTAqn8AniOwiH+DOkvgSKF2caqk/y1dfq47P'
      'dymtwzp9ikpB1C5OfAysXzBiwVJlCdajBKvBZDerV1cMvRzCKvKwRmvDmHgphQQ7WfXI'
      'GbRbmmk6opMBh3roE42KcotLFtqp0RRwLtcBRNtCdsrVsjiI1Lqz/lH+T61sGjSjQ3CH'
      'MuZYSQJZo/KrvzgQXpkaCTdbObxHqb6/+i1qaVOfEsvjoiyzTxJADvSytVtcTjijhPEV'
      '6XskJVHE1Zgl+7rATr/pDQkw6DPCNBS1+Y6fy7GstZALQXwEDN/qhQI9kWkHijT8ns+i'
      '1vGg00Mk/6J75arLhqcodWsdeG/M/moWgqQAnlZAGVtJI1OgeF5fsPpXu4kctOfuZlGj'
      'VZXQNW34aOzm8r8S0eVZitPlbhcPiR4gT/aSMz/wd8lZlzZYsje/Jr8u/YtlwjjreZrG'
      'RmG8KMOzukV3lLmMppXFMvl4bxv6YFEmIuTsOhbLTwFgh7KYNjodLj/LsqRVfwz31PgW'
      'QFTEPICV7GCvgVlPRxnofqKSjgTWI4mxDhBpVcATvaoBl1L/6WLbFvBsoAUBItWwctO2'
      'xalKxF5szhGm8lccoc5MZr8kfE0uxMgsxz4er68iCID+rsCAQM=';

  static String defaultConfigJson({
    String sponsorId = '',
    String propagationChannelId = '',
    String egressRegion = '',
  }) {
    final map = <String, dynamic>{
      // همان مقادیر bepass-org/warp-plus/psiphon/p.go
      'SponsorId':
          sponsorId.isEmpty ? 'FFFFFFFFFFFFFFFF' : sponsorId,
      'PropagationChannelId': propagationChannelId.isEmpty
          ? 'FFFFFFFFFFFFFFFF'
          : propagationChannelId,
      'RemoteServerListUrl': _oblivionRemoteServerListUrl,
      'RemoteServerListSignaturePublicKey': _oblivionRemoteServerListSigKey,
      'RemoteServerListDownloadFilename': 'remote_server_list',
      'ClientPlatform': 'Android_4.0.4_com.hasan.hasan_vpn',
      'ClientVersion': '1',
      'LocalSocksProxyPort': 0,
      'LocalHttpProxyPort': 0,
      'DisableLocalHTTPProxy': true,
      'EgressRegion': egressRegion,
      'ConnectionWorkerPoolSize': 8,
      'EstablishTunnelTimeoutSeconds': 60,
      'NetworkID': 'hasan_vpn',
      'AllowDefaultDNSResolverWithBindToDevice': true,
    };
    return jsonEncode(map);
  }

  static Future<Map<String, dynamic>> status() async {
    try {
      final r = await _channel.invokeMapMethod<String, dynamic>('status');
      return r ?? <String, dynamic>{};
    } catch (e) {
      return <String, dynamic>{'error': e.toString(), 'libraryPresent': false};
    }
  }

  static Future<bool> libraryPresent() async {
    final s = await status();
    return s['libraryPresent'] == true;
  }

  static Future<void> stop() async {
    try {
      await _channel.invokeMethod('stop');
    } catch (_) {}
    _connected = false;
    _current = null;
    _socksPort = 0;
  }

  static Future<bool> connect(
    VpnServer server, {
    PsiphonProgress? onProgress,
    bool Function()? isCancelled,
  }) async {
    lastError = null;
    lastRegion = null;
    _connected = false;
    _current = null;

    if (!server.isPsiphon) {
      lastError = 'Not a Psiphon server';
      return false;
    }

    bool cancelled() => isCancelled?.call() ?? false;

    try {
      onProgress?.call('Psiphon · checking library');
      final present = await libraryPresent();
      if (!present) {
        lastError =
            'کتابخانهٔ Psiphon در این بیلد نیست. workflow باید AAR را اضافه کند.';
        return false;
      }

      if (cancelled()) {
        lastError = 'cancelled';
        return false;
      }

      // مجوز VPN
      final allowed = await V2RayEngine.requestPermission();
      if (!allowed) {
        lastError = 'VPN permission denied';
        return false;
      }

      // کانفیگ از shareLink: psiphon://config?json=base64 یا JSON خام
      final config = _configFromServer(server);
      onProgress?.call('Psiphon · connecting');

      final result = await _channel.invokeMapMethod<String, dynamic>('start', {
        'config': config,
        'timeoutSec': 90,
      });

      if (cancelled()) {
        await stop();
        lastError = 'cancelled';
        return false;
      }

      if (result == null || result['ok'] != true) {
        lastError = result?['error']?.toString() ??
            'Psiphon failed — SponsorId نامعتبر یا شبکه در دسترس نیست';
        return false;
      }

      final port = (result['socksPort'] as num?)?.toInt() ?? 0;
      if (port <= 0) {
        lastError = 'Psiphon SOCKS port is 0';
        await stop();
        return false;
      }
      _socksPort = port;
      lastRegion = result['region']?.toString();

      onProgress?.call('Psiphon · VPN ($port)');
      final xrayConfig = AetherService.buildXrayConfig(socksPort: port, blockQuic: true);
      final started = await V2RayEngine.startConfig(
        remark: server.name,
        config: xrayConfig,
        server: server,
        blockedApps: const <String>[_appPackage],
        requireBlockedApps: true,
      );

      if (!started) {
        lastError = V2RayEngine.lastError ?? 'VPN start failed';
        await stop();
        return false;
      }

      _connected = true;
      _current = server;
      return true;
    } catch (e) {
      lastError = e.toString();
      debugPrint('Psiphon connect: $e');
      await stop();
      return false;
    }
  }

  static String _configFromServer(VpnServer server) {
    final link = server.shareLink.trim();
    if (link.startsWith('{')) return link;
    if (link.toLowerCase().startsWith('psiphon://')) {
      try {
        final uri = Uri.parse(link);
        final raw = uri.queryParameters['config'] ??
            uri.queryParameters['json'] ??
            '';
        if (raw.isNotEmpty) {
          // maybe base64
          try {
            return utf8.decode(base64.decode(base64.normalize(
              raw.replaceAll('-', '+').replaceAll('_', '/'),
            )));
          } catch (_) {
            return Uri.decodeComponent(raw);
          }
        }
        final sponsor = uri.queryParameters['sponsor'] ?? '';
        final channel = uri.queryParameters['channel'] ?? '';
        final region = uri.queryParameters['region'] ?? '';
        return defaultConfigJson(
          sponsorId: sponsor,
          propagationChannelId: channel,
          egressRegion: region,
        );
      } catch (_) {}
    }
    return defaultConfigJson();
  }

  static String toShareLink({
    String sponsorId = '',
    String channelId = '',
    String region = '',
    String? rawJson,
  }) {
    if (rawJson != null && rawJson.trim().startsWith('{')) {
      final b64 = base64Url.encode(utf8.encode(rawJson.trim()));
      return 'psiphon://config?json=$b64';
    }
    final q = <String, String>{};
    if (sponsorId.isNotEmpty) q['sponsor'] = sponsorId;
    if (channelId.isNotEmpty) q['channel'] = channelId;
    if (region.isNotEmpty) q['region'] = region;
    return Uri(scheme: 'psiphon', host: 'config', queryParameters: q).toString();
  }
}
