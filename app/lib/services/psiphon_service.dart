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

  /// نسل اتصال Dart-side. هر فراخوانی connect() این را افزایش می‌دهد تا
  /// callback/timeout دیرهنگام از attempt قبلی نتواند stop بزند وقتی
  /// attempt بعدی قبلاً برنده‌شده است.
  static int _connectGen = 0;

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

  /// توقف صریح کاربر/لایهٔ بالاتر. نسل را باطل می‌کند تا هیچ attempt
  /// در حال اجرا بعداً state را به connected برنگرداند.
  static Future<void> stop({String reason = 'explicit'}) async {
    final gen = _connectGen;
    debugPrint('PSIPHON: stop reason=$reason gen=$gen connected=$_connected');
    try {
      await _channel.invokeMethod('stop');
    } catch (_) {}
    _connected = false;
    _current = null;
    _socksPort = 0;
  }

  /// stop فقط وقتی مجاز است که هنوز نسل فعلی باشیم و به connected
  /// نرسیده باشیم — مگر reason صریح کاربر باشد.
  static Future<void> _stopIfStillCurrent(int gen, String reason) async {
    if (gen != _connectGen) {
      debugPrint('PSIPHON: skip stop ($reason) stale gen=$gen current=$_connectGen');
      return;
    }
    if (_connected) {
      debugPrint('PSIPHON: skip stop ($reason) already connected gen=$gen');
      return;
    }
    await stop(reason: reason);
  }

  static Future<bool> connect(
    VpnServer server, {
    PsiphonProgress? onProgress,
    bool Function()? isCancelled,
  }) async {
    // نسل جدید: هر attempt/timeout قدیمی دیگر نمی‌تواند stop بزند.
    final gen = ++_connectGen;
    lastError = null;
    lastRegion = null;
    _connected = false;
    _current = null;

    debugPrint('PSIPHON: connect BEGIN gen=$gen server=${server.name}');

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

      if (cancelled() || gen != _connectGen) {
        lastError = 'cancelled';
        await _stopIfStillCurrent(gen, 'cancelled-before-permission');
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
        if (cancelled() || gen != _connectGen) {
          await _stopIfStillCurrent(gen, 'cancelled-in-loop');
          lastError = 'cancelled';
          return false;
        }

        final a = attempts[i];
        final counter =
            attempts.length > 1 ? ' ${i + 1}/${attempts.length}' : '';
        onProgress?.call('Psiphon · connecting (${a.label})$counter');
        debugPrint(
            'PSIPHON: attempt START gen=$gen i=${i + 1}/${attempts.length} '
            'label=${a.label} timeout=${a.timeoutSec}');

        final result = await _channel.invokeMapMethod<String, dynamic>('start', {
          'config': a.configJson,
          'timeoutSec': a.timeoutSec,
        });

        // اگر نسل عوض شده (کاربر قطع کرده یا connect جدید شروع شده) برنده نیستیم.
        if (gen != _connectGen) {
          debugPrint('PSIPHON: attempt LOSE gen=$gen (superseded by $_connectGen)');
          lastError = 'cancelled';
          return false;
        }

        if (cancelled()) {
          await _stopIfStillCurrent(gen, 'cancelled-after-start');
          lastError = 'cancelled';
          return false;
        }

        final p = (result?['socksPort'] as num?)?.toInt() ?? 0;
        final ok = result != null && result['ok'] == true && p > 0;
        debugPrint(
            'PSIPHON: attempt RESULT gen=$gen label=${a.label} ok=$ok '
            'port=$p err=${result?['error']}');

        if (ok) {
          port = p;
          lastRegion = result!['region']?.toString();
          if (a.mode != 'manual') {
            // ignore: unawaited_futures
            PsiphonAuto.rememberSuccess(a);
          }
          // ignore: unawaited_futures
          _cacheRegionsLater();
          debugPrint('PSIPHON: attempt WIN gen=$gen label=${a.label} port=$port region=$lastRegion');
          // مهم: بعد از برد، stop() صدا نزن و از حلقه خارج شو.
          break;
        }

        failure = result?['error']?.toString() ??
            'Psiphon failed — SponsorId نامعتبر یا شبکه در دسترس نیست';
        // فقط اگر هنوز نسل فعلی هستیم و هنوز connected نیستیم stop کن.
        await _stopIfStillCurrent(gen, 'attempt-fail-${a.label}');
      }

      if (gen != _connectGen) {
        lastError = 'cancelled';
        return false;
      }

      if (port <= 0) {
        lastError = failure ?? 'Psiphon SOCKS port is 0';
        debugPrint('PSIPHON: all attempts LOSE gen=$gen err=$lastError');
        return false;
      }
      _socksPort = port;

      onProgress?.call('Psiphon · VPN ($port)');
      final xrayConfig = AetherService.buildXrayConfig(socksPort: port, blockQuic: true);
      debugPrint('PSIPHON_DIAG: socksPort=$port region=$lastRegion');
      debugPrint('PSIPHON_DIAG: proxy_outbound=socks://127.0.0.1:$port');
      debugPrint('PSIPHON_DIAG: config_head=${xrayConfig.substring(0, xrayConfig.length.clamp(0, 600))}');
      // Sanity: encoded JSON must embed the live port.
      if (!xrayConfig.contains('"port":$port') &&
          !xrayConfig.contains('"port": $port')) {
        debugPrint('PSIPHON_DIAG: WARNING config missing port $port');
      }
      final started = await V2RayEngine.startConfig(
        remark: server.name,
        config: xrayConfig,
        server: server,
        blockedApps: await V2RayEngine.resolveBlockedApps(),
        requireBlockedApps: true,
      );

      if (gen != _connectGen) {
        debugPrint('PSIPHON: VPN started but gen superseded — stopping');
        await stop(reason: 'superseded-after-vpn');
        lastError = 'cancelled';
        return false;
      }

      if (!started) {
        lastError = V2RayEngine.lastError ?? 'VPN start failed';
        await _stopIfStillCurrent(gen, 'vpn-start-failed');
        return false;
      }

      _connected = true;
      _current = server;
      debugPrint('PSIPHON: CONNECTED gen=$gen port=$port region=$lastRegion');
      return true;
    } catch (e) {
      lastError = e.toString();
      debugPrint('Psiphon connect: $e');
      await _stopIfStillCurrent(gen, 'exception');
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
