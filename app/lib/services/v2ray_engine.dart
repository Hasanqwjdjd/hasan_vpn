import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_vless/flutter_vless.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/server.dart';
import 'settings_service.dart';
import 'socks_probe.dart';
import 'xray_json.dart';
import 'xray_settings.dart';

class V2RayEngine {
  V2RayEngine._();

  static const String _defaultDelayUrl = 'http://cp.cloudflare.com/generate_204';
  static String delayUrl = _defaultDelayUrl;

  static bool _initialized = false;
  static bool _connected = false;
  static DateTime? _startedAt;
  static VpnServer? _current;
  static String _lastState = '';

  static String? lastError;

  static int localSocksPort = 10808;
  static bool blockedAppsSupported = true;

  /// آدرس تست تأخیر رو از تنظیمات می‌خونه.
  static Future<void> loadDelayUrl() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('test_settings_v1');
      if (raw == null) return;
      final m = jsonDecode(raw) as Map;
      final u = m['delayUrl']?.toString();
      if (u != null && u.isNotEmpty) delayUrl = u;
    } catch (_) {}
  }

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

  // ------------------------------------------------------- DNS injection

  static Future<String> _applyGameDns(String config) async {
    try {
      final mode = await SettingsService.getVpnMode();
      if (mode != 'proxy') return config;

      final dns = await SettingsService.getGameDns();
      if (dns == null || dns.length < 2) return config;

      final pref = await SettingsService.getDnsIpPreference();

      final dynamic json = jsonDecode(config);
      if (json is! Map) return config;

      final map = Map<String, dynamic>.from(json);

      final servers = <String>[];
      if (pref == 'ipv4') {
        servers.addAll(<String>[dns[0], dns[1]]);
      } else if (pref == 'ipv6') {
        servers.addAll(<String>[
          'https://dns.google/dns-query',
          'https://cloudflare-dns.com/dns-query',
        ]);
      } else {
        servers.addAll(<String>[dns[0], dns[1]]);
      }

      final queryStrategy = pref == 'ipv6'
          ? 'UseIPv6'
          : (pref == 'both' ? 'UseIP' : 'UseIPv4');

      map['dns'] = <String, dynamic>{
        'servers': servers,
        'queryStrategy': queryStrategy,
      };

      return jsonEncode(map);
    } catch (e) {
      debugPrint('applyGameDns error: $e');
      return config;
    }
  }

  // ---------------------------------------------------------------- connect

  static Future<bool> connect(VpnServer server) async {
    lastError = null;
    try {
      await init();

      String config;
      String remark = server.name;

      if (server.protocol == VpnProtocol.xrayJson) {
        final raw = XrayJson.extractJson(server.shareLink);
        if (raw == null || raw.trim().isEmpty) {
          lastError = 'invalid xray json config';
          return false;
        }
        config = raw;
        config = _ensureLocalInbound(config);
      } else {
        final FlutterVlessURL parser = FlutterVless.parse(server.shareLink);
        config = parser.getFullConfiguration();
        if (parser.remark.isNotEmpty) remark = parser.remark;
      }

      if (config.trim().isEmpty) {
        lastError = 'empty config';
        return false;
      }

      // برای xrayJson نباید XraySettings رو اعمال کنیم چون inbound خودش رو خراب می‌کنه.
      if (server.protocol != VpnProtocol.xrayJson) {
        config = await XraySettings.applyToConfig(config);
      }

      config = await _applyGameDns(config);

      return await startConfig(
        remark: remark,
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

  static String _ensureLocalInbound(String config) {
    try {
      final dynamic decoded = jsonDecode(config);
      if (decoded is! Map) return config;
      final map = Map<String, dynamic>.from(decoded);

      final inbounds = map['inbounds'];
      if (inbounds is List && inbounds.isNotEmpty) {
        return config;
      }

      map['inbounds'] = <Map<String, dynamic>>[
        <String, dynamic>{
          'tag': 'socks-in',
          'port': 10808,
          'listen': '127.0.0.1',
          'protocol': 'socks',
          'settings': <String, dynamic>{
            'auth': 'noauth',
            'udp': true,
          },
          'sniffing': <String, dynamic>{
            'enabled': true,
            'destOverride': <String>['http', 'tls', 'quic'],
          },
        },
      ];
      return jsonEncode(map);
    } catch (_) {
      return config;
    }
  }

  static Future<bool> startConfig({
    required String remark,
    required String config,
    VpnServer? server,
    List<String>? blockedApps,
    bool requireBlockedApps = false,
    bool? forceProxyOnly,
  }) async {
    lastError = null;
    try {
      await init();

      bool proxyOnly = forceProxyOnly ?? false;
      if (forceProxyOnly == null) {
        try {
          final vpnMode = await SettingsService.getVpnMode();
          proxyOnly = vpnMode == 'proxy';
        } catch (_) {}
      }

      if (!proxyOnly) {
        final allowed = await _engine.requestPermission();
        if (!allowed) {
          lastError = 'VPN permission denied';
          return false;
        }
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
            proxyOnly: proxyOnly,
            blockedApps: blockedApps,
          );
        } on NoSuchMethodError {
          debugPrint('flutter_vless: blockedApps is not supported');
          blockedAppsSupported = false;
          if (requireBlockedApps) {
            lastError = 'This flutter_vless version does not support '
                'blockedApps, which Aether needs to avoid a routing loop.';
            _connected = false;
            _current = null;
            return false;
          }
          await _engine.startVless(
            remark: remark,
            config: config,
            proxyOnly: proxyOnly,
          );
        }
      } else {
        await _engine.startVless(
          remark: remark,
          config: config,
          proxyOnly: proxyOnly,
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

  static Future<int> realDelay(
    VpnServer server, {
    Duration timeout = const Duration(seconds: 12),
  }) async {
    String? config = _fullConfigOf(server);
    if (config == null || config.trim().isEmpty) return -2;

    try {
      if (server.protocol != VpnProtocol.xrayJson) {
        config = await XraySettings.applyToConfig(config!);
      }
      config = await _applyGameDns(config);
    } catch (_) {}

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
      if (server.protocol == VpnProtocol.xrayJson) {
        final raw = XrayJson.extractJson(server.shareLink);
        if (raw == null || raw.trim().isEmpty) return null;
        return _ensureLocalInbound(raw);
      }
      final FlutterVlessURL parser = FlutterVless.parse(server.shareLink);
      return parser.getFullConfiguration();
    } catch (_) {
      return null;
    }
  }

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
          if (inbound is Map) {
            final proto = inbound['protocol']?.toString().toLowerCase() ?? '';
            if (proto == 'socks' || proto == 'mixed' || proto == 'http') {
              final raw = inbound['port'];
              final port = raw is int ? raw : int.tryParse(raw.toString());
              if (port != null && port > 0 && port <= 65535) return port;
            }
          }
        }
      }
    } catch (_) {}
    return 10808;
  }
}
