import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../models/server.dart';
import 'aether_service.dart';
import 'psiphon_auto.dart';
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

  /// کانفیگ پیش‌فرض (پروفایل اول حالت خودکار). SponsorId / Channel /
  /// Region اگر داده شوند جایگزین می‌شوند.
  static String defaultConfigJson({
    String sponsorId = '',
    String propagationChannelId = '',
    String egressRegion = '',
  }) {
    final base = PsiphonAuto.profiles.first;
    final profile = PsiphonProfile(
      id: 'custom',
      sponsorId: sponsorId.isEmpty ? base.sponsorId : sponsorId,
      channelId: propagationChannelId.isEmpty
          ? base.channelId
          : propagationChannelId,
    );
    return jsonEncode(
      PsiphonAuto.buildConfig(
        profile,
        region: egressRegion,
        establishTimeoutSec: 60,
      ),
    );
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

      // حالت خودکار: چند تلاش با پروفایل/پروتکل‌های مختلف.
      // حالت دستی: فقط یک تلاش با همان کانفیگی که کاربر داده.
      final List<PsiphonAttempt> attempts;
      if (isAutoLink(server.shareLink)) {
        attempts = await PsiphonAuto.attempts(
          region: regionOfLink(server.shareLink),
        );
      } else {
        attempts = <PsiphonAttempt>[
          PsiphonAttempt(
            label: 'manual',
            profileId: 'manual',
            mode: 'manual',
            configJson: _configFromServer(server),
            timeoutSec: 90,
          ),
        ];
      }

      int port = 0;
      String? failure;
      for (var i = 0; i < attempts.length; i++) {
        if (cancelled()) {
          await stop();
          lastError = 'cancelled';
          return false;
        }

        final a = attempts[i];
        final counter =
            attempts.length > 1 ? ' ${i + 1}/${attempts.length}' : '';
        onProgress?.call('Psiphon · connecting (${a.label})$counter');

        final result = await _channel.invokeMapMethod<String, dynamic>('start', {
          'config': a.configJson,
          'timeoutSec': a.timeoutSec,
        });

        if (cancelled()) {
          await stop();
          lastError = 'cancelled';
          return false;
        }

        final p = (result?['socksPort'] as num?)?.toInt() ?? 0;
        if (result != null && result['ok'] == true && p > 0) {
          port = p;
          lastRegion = result['region']?.toString();
          if (a.mode != 'manual') {
            // ignore: unawaited_futures
            PsiphonAuto.rememberSuccess(a);
          }
          // فهرست کشورهایی که هسته گزارش می‌دهد کمی دیرتر می‌رسد.
          // ignore: unawaited_futures
          _cacheRegionsLater();
          break;
        }

        failure = result?['error']?.toString() ??
            'Psiphon failed — SponsorId نامعتبر یا شبکه در دسترس نیست';
        await stop();
      }

      if (port <= 0) {
        lastError = failure ?? 'Psiphon SOCKS port is 0';
        return false;
      }
      _socksPort = port;

      onProgress?.call('Psiphon · VPN ($port)');
      final xrayConfig = AetherService.buildXrayConfig(socksPort: port, blockQuic: true);
      // Diagnostic: dump first 400 chars of config so we can verify
      // routing rules actually point to the SOCKS outbound.
      debugPrint('PSIPHON_DIAG: socksPort=$port region=$lastRegion');
      debugPrint('PSIPHON_DIAG: config_head=${xrayConfig.substring(0, xrayConfig.length.clamp(0, 400))}');
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

  static Future<void> _cacheRegionsLater() async {
    try {
      await Future<void>.delayed(const Duration(seconds: 4));
      final s = await status();
      await PsiphonAuto.cacheRegions(s['regions']);
    } catch (_) {}
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

  /// لینک «خودکار»: psiphon://auto?region=DE (region اختیاری).
  static String toAutoLink({String region = ''}) {
    final r = PsiphonAuto.normalizeRegion(region);
    return Uri(
      scheme: 'psiphon',
      host: 'auto',
      queryParameters: r.isEmpty ? null : <String, String>{'region': r},
    ).toString();
  }

  /// true اگر این سرور باید با حالت خودکار وصل شود.
  /// لینک‌های قدیمی بدون SponsorId/Channel/JSON هم خودکار حساب می‌شوند.
  static bool isAutoLink(String link) {
    final l = link.trim();
    if (l.startsWith('{')) return false;
    if (!l.toLowerCase().startsWith('psiphon://')) return true;
    try {
      final uri = Uri.parse(l);
      if (uri.host.toLowerCase() == 'auto') return true;
      final q = uri.queryParameters;
      final hasManual = (q['config'] ?? '').isNotEmpty ||
          (q['json'] ?? '').isNotEmpty ||
          (q['sponsor'] ?? '').isNotEmpty ||
          (q['channel'] ?? '').isNotEmpty;
      return !hasManual;
    } catch (_) {
      return true;
    }
  }

  static String regionOfLink(String link) {
    try {
      final uri = Uri.parse(link.trim());
      return PsiphonAuto.normalizeRegion(uri.queryParameters['region'] ?? '');
    } catch (_) {
      return '';
    }
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
