import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_vless/flutter_vless.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/server.dart';
import 'game_booster_settings.dart';
import 'settings_service.dart';
import 'socks_probe.dart';
import 'telemetry_service.dart';
import 'xray_json.dart';
import 'xray_settings.dart';

class V2RayEngine {
  V2RayEngine._();

  static const String _defaultDelayUrl = 'https://www.gstatic.com/generate_204';
  static String delayUrl = _defaultDelayUrl;

  static bool _initialized = false;
  static bool _connected = false;
  static bool _sawState = false;
  static DateTime? _startedAt;
  static VpnServer? _current;
  static String _lastState = '';

  static String? lastError;

  static int localSocksPort = 10808;
  static bool blockedAppsSupported = true;

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

  static void _pushTelemetry(dynamic status) {
    try {
      final down = (status.downloadSpeed as num?)?.toInt() ?? 0;
      final up = (status.uploadSpeed as num?)?.toInt() ?? 0;
      TelemetryService.onSpeed(
          down: down, up: up, server: _current?.displayName);
    } catch (_) {}
  }

  static final FlutterVless _engine = FlutterVless(
    onStatusChanged: (dynamic status) {
      try {
        final state = _stateOf(status).toLowerCase();
        _lastState = state;
        _sawState = true;
        debugPrint('V2Ray status: $state');

        final down = state.contains('disconnect') ||
            state.contains('stop') ||
            state.contains('closed') ||
            state.contains('idle');
        if (down) {
          final started = _startedAt;
          final inGrace = started != null &&
              DateTime.now().difference(started) < const Duration(seconds: 4);
          if (!inGrace) {
            _connected = false;
            unawaited(TelemetryService.hide());
          }
        } else if (state.contains('connected')) {
          _connected = true;
          _pushTelemetry(status);
        }
      } catch (_) {}
    },
  );

  static bool get isConnected => _connected;
  static VpnServer? get current => _current;

  static Future<void> init() async {
    if (_initialized) return;
    try {
      await TelemetryService.load();
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
      // قبلاً فقط در حالت proxy اعمال می‌شد → در VPN واقعی DNS بازی نادیده گرفته می‌شد
      final dns = await SettingsService.getGameDns();
      if (dns == null || dns.length < 2) return config;

      final pref = await SettingsService.getDnsIpPreference();

      final dynamic json = jsonDecode(config);
      if (json is! Map) return config;

      final map = Map<String, dynamic>.from(json);

      // فقط همان DNS انتخاب‌شده کاربر (نه DoH جایگزین که مسیر را عوض کند)
      final servers = <dynamic>[
        dns[0],
        if (dns[1].isNotEmpty && dns[1] != dns[0]) dns[1],
      ];

      // برای بازی (COD و مشابه) IPv4 معمولاً پینگ پایدارتری دارد
      final queryStrategy = pref == 'ipv6'
          ? 'UseIPv6'
          : (pref == 'both' ? 'UseIP' : 'UseIPv4');

      map['dns'] = <String, dynamic>{
        'servers': servers,
        'queryStrategy': queryStrategy,
        // کش کوچک‌تر = رزولوشن تازه‌تر برای سرورهای بازی
        'cacheSize': 64,
        'disableCache': false,
      };

      // اگر routing وجود دارد، domainStrategy را برای سرعت بهتر تنظیم کن
      final routing = map['routing'];
      if (routing is Map) {
        final r = Map<String, dynamic>.from(routing);
        r['domainStrategy'] = r['domainStrategy'] ?? 'AsIs';
        map['routing'] = r;
      }

      return jsonEncode(map);
    } catch (e) {
      debugPrint('applyGameDns error: $e');
      return config;
    }
  }

  /// حالت بازی: فایروال سبک + DNS روی کانفیگ Xray
  static Future<String> _applyGameBooster(String config) async {
    try {
      final s = await GameBoosterSettings.load();
      if (s['enabled'] != true) return config;

      final dynamic json = jsonDecode(config);
      if (json is! Map) return config;
      final map = Map<String, dynamic>.from(json);

      // --- DNS: اجبار IPv4 + کش کوچک ---
      final dns = Map<String, dynamic>.from(
        (map['dns'] is Map)
            ? Map<String, dynamic>.from(map['dns'] as Map)
            : <String, dynamic>{},
      );
      if (s['forceIpv4'] == true) {
        dns['queryStrategy'] = 'UseIPv4';
      }
      if (s['smallDnsCache'] == true) {
        dns['cacheSize'] = 32;
      }
      map['dns'] = dns;

      // --- blackhole outbound ---
      final outbounds = <dynamic>[];
      if (map['outbounds'] is List) {
        outbounds.addAll(map['outbounds'] as List);
      }
      final hasBlock = outbounds.any(
        (o) => o is Map && (o['tag'] == 'block' || o['tag'] == 'blackhole'),
      );
      if (!hasBlock) {
        outbounds.add({
          'tag': 'block',
          'protocol': 'blackhole',
          'settings': {
            'response': {'type': 'none'},
          },
        });
      }
      map['outbounds'] = outbounds;

      // --- routing rules ---
      final routing = Map<String, dynamic>.from(
        (map['routing'] is Map)
            ? Map<String, dynamic>.from(map['routing'] as Map)
            : <String, dynamic>{'domainStrategy': 'AsIs', 'rules': <dynamic>[]},
      );
      if (s['forceIpv4'] == true) {
        routing['domainStrategy'] = 'AsIs';
      }
      final rules = <dynamic>[];
      if (routing['rules'] is List) {
        rules.addAll(routing['rules'] as List);
      }

      // مسدودسازی QUIC (UDP/443) — ترافیک رقابتی کمتر
      if (s['blockQuic'] == true) {
        rules.insert(0, {
          'type': 'field',
          'network': 'udp',
          'port': '443',
          'outboundTag': 'block',
        });
      }

      // بلاک IPv6 در سطح مسیر (تقریبی)
      if (s['forceIpv4'] == true) {
        rules.insert(0, {
          'type': 'field',
          'ip': ['::/0'],
          'outboundTag': 'block',
        });
      }

      final blockDomains = <String>[];
      if (s['blockTelemetry'] == true) {
        blockDomains.addAll(GameBoosterSettings.telemetryDomains);
      }
      if (s['blockAds'] == true) {
        blockDomains.addAll(GameBoosterSettings.adDomains);
      }
      if (blockDomains.isNotEmpty) {
        rules.insert(0, {
          'type': 'field',
          'domain': blockDomains.map((d) => 'domain:$d').toList(),
          'outboundTag': 'block',
        });
      }

      routing['rules'] = rules;
      map['routing'] = routing;

      return jsonEncode(map);
    } catch (e) {
      debugPrint('applyGameBooster error: $e');
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
        config = _ensureLocalInbound(raw);
      } else {
        final FlutterVlessURL parser = FlutterVless.parse(server.shareLink);
        config = parser.getFullConfiguration();
        if (parser.remark.isNotEmpty) remark = parser.remark;
      }

      if (config.trim().isEmpty) {
        lastError = 'empty config';
        return false;
      }

      if (server.protocol != VpnProtocol.xrayJson) {
        config = await XraySettings.applyToConfig(config);
      }

      config = await _applyGameDns(config);
      config = await _applyGameBooster(config);

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

  /// نسخه‌های جدید پلاگین در حالت VPN خودشان SOCKS را مدیریت می‌کنند و
  /// listener اضافه را رد می‌کنند؛ این تابع آن‌ها را برمی‌دارد.
  static String _stripProxyInbounds(String config) {
    try {
      final dynamic decoded = jsonDecode(config);
      if (decoded is! Map) return config;
      final map = Map<String, dynamic>.from(decoded);
      final inbounds = map['inbounds'];
      if (inbounds is List) {
        map['inbounds'] = inbounds.where((e) {
          if (e is! Map) return true;
          final p = e['protocol']?.toString().toLowerCase() ?? '';
          return p != 'socks' && p != 'http' && p != 'mixed';
        }).toList();
      }
      return jsonEncode(map);
    } catch (_) {
      return config;
    }
  }

  static bool _looksLikeInboundError(String? e) {
    if (e == null) return false;
    final t = e.toLowerCase();
    return t.contains('inbound') || t.contains('listener');
  }

  static Future<bool> _startOnce({
    required String remark,
    required String config,
    required bool proxyOnly,
    List<String>? blockedApps,
    required bool requireBlockedApps,
  }) async {
    try {
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
      return true;
    } catch (e) {
      lastError = e.toString();
      debugPrint('V2Ray start error: $e');
      return false;
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

      // تونل قبلی (اگر مانده) یک‌بار بسته می‌شود.
      try {
        await _engine.stopVless();
      } catch (_) {}
      await Future<void>.delayed(const Duration(milliseconds: 700));

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
      _sawState = false;
      _connected = false;
      _startedAt = DateTime.now();
      _current = server;

      var started = await _startOnce(
        remark: remark,
        config: config,
        proxyOnly: proxyOnly,
        blockedApps: blockedApps,
        requireBlockedApps: requireBlockedApps,
      );

      if (!started && _looksLikeInboundError(lastError)) {
        debugPrint('retrying without extra proxy inbounds');
        lastError = null;
        started = await _startOnce(
          remark: remark,
          config: _stripProxyInbounds(config),
          proxyOnly: proxyOnly,
          blockedApps: blockedApps,
          requireBlockedApps: requireBlockedApps,
        );
      }

      if (!started) {
        _connected = false;
        _current = null;
        return false;
      }

      final ok = await _waitConnected(const Duration(seconds: 30));
      if (!ok) {
        try {
          await _engine.stopVless();
        } catch (_) {}
        _connected = false;
        _current = null;
        return false;
      }

      _connected = true;
      _current = server;
      return true;
    } catch (e) {
      lastError = e.toString();
      debugPrint('V2Ray start error: $e');
      _connected = false;
      _current = null;
      return false;
    }
  }

  static Future<bool> _waitConnected(Duration timeout) async {
    final started = DateTime.now();
    final deadline = started.add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      final s = _lastState;
      if (s.contains('connected') && !s.contains('disconnect')) return true;

      final elapsed = DateTime.now().difference(started);
      if (_sawState &&
          s.contains('disconnect') &&
          elapsed > const Duration(seconds: 6)) {
        final ms = await connectedDelay(timeout: const Duration(seconds: 5));
        if (ms > 0) return true;
        lastError ??= 'VPN service stopped before it connected (state: $s)';
        return false;
      }
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }

    // پلاگین وضعیت نداد یا روی CONNECTING ماند: با یک درخواست واقعی بررسی کن.
    final ms = await connectedDelay();
    if (ms > 0) return true;
    lastError ??= _sawState
        ? 'connect timeout (state: $_lastState)'
        : 'no status from VPN service';
    return false;
  }

  static Future<void> disconnect() async {
    try {
      await _engine.stopVless();
    } catch (_) {}
    _connected = false;
    _current = null;
    unawaited(TelemetryService.hide());
  }

  // ------------------------------------------------------------------- ping

  /// تأخیر واقعی از داخل تونل فعلی (از خود پلاگین).
  static Future<int> connectedDelay(
      {Duration timeout = const Duration(seconds: 8)}) async {
    try {
      final dynamic engine = _engine;
      final dynamic raw = await Future<dynamic>.value(
        engine.getConnectedServerDelay(url: delayUrl),
      ).timeout(timeout);
      final int? v = raw is int ? raw : int.tryParse(raw.toString());
      if (v == null || v <= 0) return -1;
      return v;
    } catch (_) {
      return -1;
    }
  }

  static Future<int> realDelay(
    VpnServer server, {
    Duration timeout = const Duration(seconds: 12),
  }) async {
    String? config = _fullConfigOf(server);
    if (config == null || config.trim().isEmpty) return -2;

    try {
      if (server.protocol != VpnProtocol.xrayJson) {
        config = await XraySettings.applyToConfig(config);
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

  static Future<ProbeResult> probeConnected() async {
    final viaSocks = await SocksProbe.measure(
      port: localSocksPort,
      samples: 2,
      timeout: const Duration(seconds: 6),
    );
    if (viaSocks.ok) {
      TelemetryService.livePing = viaSocks.ms;
      return viaSocks;
    }
    // نسخه‌های جدید پلاگین SOCKS را رمزدار می‌کنند؛ از خود پلاگین بپرس.
    final ms = await connectedDelay();
    if (ms > 0) {
      TelemetryService.livePing = ms;
      return ProbeResult(ms: ms);
    }
    return viaSocks;
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
