import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_vless/flutter_vless.dart';

import '../models/server.dart';
import 'socks_probe.dart';

class V2RayEngine {
  V2RayEngine._();

  /// آدرس تست «پینگ واقعی». HTTP ساده (بدون TLS) تا عدد نهایی فقط شامل
  /// مسیر پروکسی + یک رفت‌وبرگشت باشد و با دست‌دادن TLS بادکنکی نشود.
  static const String delayUrl = 'http://cp.cloudflare.com/generate_204';

  static bool _initialized = false;
  static bool _connected = false;
  static DateTime? _startedAt;
  static VpnServer? _current;
  static String _lastState = '';

  static String? lastError;

  /// پورت SOCKS محلیِ هسته‌ی در حال اجرا (برای اندازه‌گیری پینگ زنده).
  static int localSocksPort = 10808;

  /// false اگر نسخه‌ی افزونه پارامتر blockedApps را پشتیبانی نکند.
  static bool blockedAppsSupported = true;

  static String _stateOf(dynamic status) {
    try {
      final value = status.state;
      if (value != null) return value.toString();
    } catch (_) {}
    try {
      final value = status.connectionState;
      if (value != null) return value.toString();
    } catch (_) {}
    return status.toString();
  }

  static final FlutterVless _engine = FlutterVless(
    onStatusChanged: (dynamic status) {
      try {
        final state = _stateOf(status).toLowerCase();
        _lastState = state;
        debugPrint('V2Ray status: $state');

        if (state.contains('disconnect') ||
            state.contains('stop') ||
            state.contains('closed') ||
            state.contains('idle')) {
          // ابتدای شروع ممکن است یک «قطع» قدیمی برسد؛ نادیده‌اش می‌گیریم.
          final started = _startedAt;
          final inGrace = started != null &&
              DateTime.now().difference(started) < const Duration(seconds: 4);
          if (!inGrace) _connected = false;
        } else if (state.contains('connected')) {
          _connected = true;
        }
      } catch (_) {}
    },
  );

  static bool get isConnected => _connected;
  static VpnServer? get current => _current;

  static Future<void> init() async {
    if (_initialized) return;
    try {
      await _engine.initializeVless(
        notificationIconResourceType: 'mipmap',
        notificationIconResourceName: 'ic_launcher',
      );
    } catch (e) {
      debugPrint('V2Ray init error: $e');
    }
    _initialized = true;
  }

  static Future<bool> requestPermission() async {
    try {
      await init();
      final allowed = await _engine.requestPermission();
      if (!allowed) lastError = 'VPN permission denied';
      return allowed;
    } catch (e) {
      lastError = e.toString();
      return false;
    }
  }

  // ---------------------------------------------------------------- connect

  static Future<bool> connect(VpnServer server) async {
    lastError = null;
    try {
      await init();

      final FlutterVlessURL parser = FlutterVless.parse(server.shareLink);
      final String config = parser.getFullConfiguration();
      if (config.trim().isEmpty) {
        lastError = 'empty config';
        return false;
      }

      return await startConfig(
        remark: parser.remark.isNotEmpty ? parser.remark : server.name,
        config: config,
        server: server,
      );
    } catch (e) {
      lastError = e.toString();
      debugPrint('V2Ray connect error: $e');
      _connected = false;
      _current = null;
      return false;
    }
  }

  /// شروع هسته با یک کانفیگ کامل Xray (JSON). Aether هم از همین مسیر استفاده
  /// می‌کند: کانفیگ یک outbound از نوع SOCKS به Aether دارد و VPN سیستم‌عامل
  /// (tun2socks داخل افزونه) همه‌ی ترافیک را به آن می‌رساند.
  ///
  /// [requireBlockedApps]: برای Aether لازم است (اگر خود برنامه از VPN مستثنا
  /// نشود، ترافیک خود Aether دوباره داخل تونل می‌افتد و حلقه می‌شود). در این
  /// حالت اگر افزونه blockedApps را پشتیبانی نکند، به‌جای اتصال معیوب، خطای
  /// روشن برگردانده می‌شود.
  static Future<bool> startConfig({
    required String remark,
    required String config,
    VpnServer? server,
    List<String>? blockedApps,
    bool requireBlockedApps = false,
  }) async {
    lastError = null;
    try {
      await init();

      final allowed = await _engine.requestPermission();
      if (!allowed) {
        lastError = 'VPN permission denied';
        return false;
      }

      localSocksPort = _socksPortOf(config);
      _lastState = '';
      _startedAt = DateTime.now();

      if (blockedApps != null && blockedApps.isNotEmpty) {
        try {
          final dynamic engine = _engine;
          await engine.startVless(
            remark: remark,
            config: config,
            proxyOnly: false,
            blockedApps: blockedApps,
          );
        } on NoSuchMethodError {
          debugPrint('flutter_vless: blockedApps is not supported');
          blockedAppsSupported = false;
          if (requireBlockedApps) {
            lastError = 'This flutter_vless version does not support '
                'blockedApps, which Aether needs to avoid a routing loop. '
                'Update the flutter_vless dependency.';
            _connected = false;
            _current = null;
            return false;
          }
          await _engine.startVless(
            remark: remark,
            config: config,
            proxyOnly: false,
          );
        }
      } else {
        await _engine.startVless(
          remark: remark,
          config: config,
          proxyOnly: false,
        );
      }

      _connected = true;
      _current = server;
      await _waitForConnectedState(const Duration(seconds: 3));
      return true;
    } catch (e) {
      lastError = e.toString();
      debugPrint('V2Ray start error: $e');
      _connected = false;
      _current = null;
      return false;
    }
  }

  static Future<void> _waitForConnectedState(Duration timeout) async {
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      if (_lastState.contains('connected') &&
          !_lastState.contains('disconnect')) {
        return;
      }
      await Future<void>.delayed(const Duration(milliseconds: 150));
    }
  }

  static Future<void> disconnect() async {
    try {
      await _engine.stopVless();
    } catch (_) {}
    _connected = false;
    _current = null;
  }

  // ------------------------------------------------------------------- ping

  /// پینگ واقعی یک سرور بدون اتصال: هسته یک نمونه‌ی موقت با همان outbound
  /// می‌سازد و یک درخواست HTTP از داخلش می‌فرستد.
  ///
  /// مقدار برگشتی: میلی‌ثانیه (>0) | -1 ناموفق | -2 پشتیبانی نمی‌شود.
  static Future<int> realDelay(
    VpnServer server, {
    Duration timeout = const Duration(seconds: 6),
  }) async {
    final config = _fullConfigOf(server);
    if (config == null || config.trim().isEmpty) return -2;

    try {
      await init();
      final dynamic engine = _engine;
      final dynamic raw = await Future<dynamic>.value(
        engine.getServerDelay(config: config, url: delayUrl),
      ).timeout(timeout);

      final int? value = raw is int ? raw : int.tryParse(raw.toString());
      if (value == null || value <= 0) return -1;
      return value;
    } on TimeoutException {
      return -1;
    } on NoSuchMethodError {
      return -2;
    } catch (e) {
      final text = e.toString();
      if (text.contains('MissingPluginException') ||
          text.contains('not implemented')) {
        return -2;
      }
      return -1;
    }
  }

  static String? _fullConfigOf(VpnServer server) {
    try {
      final FlutterVlessURL parser = FlutterVless.parse(server.shareLink);
      return parser.getFullConfiguration();
    } catch (_) {
      return null;
    }
  }

  /// پینگ زنده‌ی اتصال فعلی (کل مسیر: اپ ← تونل ← اینترنت).
  static Future<ProbeResult> probeConnected() {
    return SocksProbe.measure(
      port: localSocksPort,
      samples: 2,
      timeout: const Duration(seconds: 6),
    );
  }

  static int _socksPortOf(String config) {
    try {
      final json = jsonDecode(config);
      final inbounds = json is Map ? json['inbounds'] : null;
      if (inbounds is List) {
        for (final inbound in inbounds) {
          if (inbound is Map && inbound['protocol'] == 'socks') {
            final raw = inbound['port'];
            final port = raw is int ? raw : int.tryParse(raw.toString());
            if (port != null && port > 0 && port <= 65535) return port;
          }
        }
      }
    } catch (_) {}
    return 10808;
  }
}
