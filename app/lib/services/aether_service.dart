import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/aether_profile.dart';
import '../models/server.dart';
import 'socks_probe.dart';
import 'v2ray_engine.dart';
import 'warp_registration_proxy.dart';
import 'connection_log_service.dart';

typedef AetherProgress = void Function(String message);

/// معماری اتصال Aether:
///
///   برنامه ⇢ VPN سیستم (tun2socks داخل افزونه‌ی Xray)
///          ⇢ Xray (outbound از نوع SOCKS)
///          ⇢ پردازه‌ی بومی Aether (SOCKS5 روی 127.0.0.1)
///          ⇢ WARP (MASQUE / WireGuard / Gool ...)
///
/// پردازه‌ی Aether در یک Foreground Service بومی (AetherService.kt) اجرا می‌شود
/// و خود برنامه از VPN مستثنا می‌شود تا ترافیک خود Aether به تونل برنگردد.
class AetherService {
  AetherService._();

  static const MethodChannel _channel =
      MethodChannel('com.hasan.hasan_vpn/aether');

  static const String _appPackage = 'com.hasan.hasan_vpn';
  static const String _lastGoodKey = 'aether_last_good_v1';
  static const String _lastPeersKey = 'aether_last_peers_v1';

  static bool _connected = false;
  static VpnServer? _current;
  static int _corePort = 0;

  static String? lastError;

  static bool get isConnected => _connected;
  static VpnServer? get current => _current;

  // ---------------------------------------------------------------- native

  static Future<Map<String, dynamic>> _invoke(String method,
      [Map<String, dynamic>? args]) async {
    try {
      final result =
          await _channel.invokeMapMethod<String, dynamic>(method, args);
      return result ?? <String, dynamic>{};
    } on PlatformException catch (error) {
      debugPrint('Aether $method failed: ${error.code} ${error.message}');
      return <String, dynamic>{'error': error.message ?? error.code};
    } on MissingPluginException {
      return <String, dynamic>{'error': 'native bridge is missing'};
    } catch (error) {
      return <String, dynamic>{'error': error.toString()};
    }
  }

  static Future<Map<String, dynamic>> nativeInfo() => _invoke('info');

  static Future<Map<String, dynamic>> nativeStatus() => _invoke('status');

  /// آخرین لاگ پردازه Aether (۲۰ خط آخر) برای parse کردن outer/inner.
  static Future<String> nativeLog() async {
    final s = await nativeStatus();
    return s['log']?.toString() ?? '';
  }

  static Future<void> _stopNative() async {
    try {
      await _channel.invokeMethod<bool>('stop');
    } catch (error) {
      debugPrint('Aether stop error: $error');
    }
  }

  /// هویت WARP فعلی (فایل‌های aether*.toml) را حذف می‌کند تا دفعه‌ی بعد که
  /// Aether اجرا شود یک حساب رایگان تازه بسازد. فقط وقتی Aether در حال
  /// اجرا/متصل نیست کار می‌کند — قبلش باید قطع بشه.
  static Future<bool> resetIdentity() async {
    if (_connected) return false;
    try {
      return await _channel.invokeMethod<bool>('resetIdentity') ?? false;
    } catch (error) {
      debugPrint('Aether resetIdentity error: $error');
      return false;
    }
  }

  static Future<int> _freePort() async {
    final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final port = socket.port;
    await socket.close();
    return port;
  }

  // ------------------------------------------------------- last good profile

  static Future<({String outer, String inner})?> _loadLastPeers() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_lastPeersKey);
      if (raw == null || raw.isEmpty) return null;
      final parts = raw.split('|');
      if (parts.length != 2) return null;
      if (parts[0].isEmpty || parts[1].isEmpty) return null;
      return (outer: parts[0], inner: parts[1]);
    } catch (_) { return null; }
  }

  static Future<void> _saveLastPeers(String outer, String inner) async {
    if (outer.isEmpty || inner.isEmpty) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_lastPeersKey, '$outer|$inner');
    } catch (_) {}
  }

  static Future<AetherAttempt?> _loadLastGood() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_lastGoodKey);
      if (raw == null) return null;
      return AetherAttempt.fromJson(jsonDecode(raw));
    } catch (_) {
      return null;
    }
  }

  static Future<void> _saveLastGood(AetherAttempt attempt) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_lastGoodKey, jsonEncode(attempt.toJson()));
    } catch (_) {}
  }

  // ---------------------------------------------------------------- connect

  static Future<bool> connect(
    VpnServer server, {
    AetherProgress? onProgress,
    bool Function()? isCancelled,
  }) async {
    lastError = null;
    _connected = false;
    _current = null;

    bool cancelled() => isCancelled?.call() ?? false;

    if (!server.isAether) {
      lastError = 'Selected server is not an Aether configuration';
      return false;
    }

    try {
      // اگر پردازه‌ی نیمه‌کاره‌ای از تلاش قبلی مانده باشد، پورت را اشغال می‌کند.
      await _stopNative();

      final info = await nativeInfo();
      if (info['binary'] != true) {
        final abi = info['abi']?.toString() ?? 'unknown';
        lastError = info['error']?.toString() ??
            'Aether core (libaether.so) is not available for this device '
                '(CPU: $abi). Use the arm64 build.';
        return false;
      }

      // مجوز VPN را همین اول بگیر تا کاربر بعد از ۳۰ ثانیه اسکن با دیالوگ غافلگیر نشود.
      final allowed = await V2RayEngine.requestPermission();
      if (!allowed) {
        lastError = 'VPN permission denied';
        return false;
      }

      var profile = AetherProfile.fromLink(server.shareLink);
      final cachedPeers = await _loadLastPeers();
      if (cachedPeers != null &&
          (profile.protocol == 'gool' ||
              profile.protocol == 'mim' ||
              profile.protocol == 'auto') &&
          profile.outer.isEmpty &&
          profile.inner.isEmpty) {
        profile = AetherProfile.fromQuery(
          Uri.parse(profile.toLink()).queryParameters
            ..addAll({'outer': cachedPeers.outer, 'inner': cachedPeers.inner}),
        );
      }
      final plan = profile.plan(lastGood: await _loadLastGood());
      final firstRun = info['hasIdentity'] != true;

      for (var i = 0; i < plan.length; i++) {
        if (cancelled()) break;

        var attempt = plan[i];
        if (firstRun && i == 0) {
          // بار اول Aether باید حساب WARP بسازد؛ زمان بیشتری بده.
          attempt = AetherAttempt(
            protocol: attempt.protocol,
            h2: attempt.h2,
            scan: attempt.scan,
            noize: attempt.noize,
            timeout: attempt.timeout + const Duration(seconds: 25),
          );
        }

        final prefix = plan.length > 1 ? '${i + 1}/${plan.length} · ' : '';
        onProgress?.call('Aether $prefix${attempt.label}');

        final port = await _freePort();
        final ready = await _runAttempt(
          server: server,
          profile: profile,
          attempt: attempt,
          port: port,
          prefix: 'Aether $prefix',
          onProgress: onProgress,
          cancelled: cancelled,
        );

        if (!ready) {
          await _stopNative();
          continue;
        }

        await _saveLastGood(plan[i]);

        onProgress?.call('Aether · VPN');
        final xrayConfig = buildXrayConfig(
          socksPort: port,
          blockQuic: profile.blockQuic,
        );

        // FIX: requireBlockedApps=false — اگه plugin از blockedApps
        // پشتیبانی نکنه، نباید Aether تازه وصل شده رو بکشه.
        final started = await V2RayEngine.startConfig(
          remark: server.name,
          config: xrayConfig,
          server: server,
          blockedApps: await V2RayEngine.resolveBlockedApps(),
          requireBlockedApps: false,
        );

        if (!started) {
          lastError = V2RayEngine.lastError ?? 'VPN service could not be started';
          await _stopNative();
          return false;
        }

        _corePort = port;
        _connected = true;
        _current = server;
        return true;
      }

      await _stopNative();
      if (cancelled()) {
        lastError = 'cancelled';
      } else {
        lastError ??= 'Aether could not find a working route';
      }
      return false;
    } catch (error) {
      lastError = error.toString();
      debugPrint('Aether connection error: $lastError');
      await _stopNative();
      _connected = false;
      _current = null;
      return false;
    }
  }

  /// یک تلاش: پردازه را با env مربوطه بالا می‌آورد و منتظر می‌ماند تا SOCKS
  /// واقعاً ترافیک عبور دهد (نه فقط پورت باز باشد).
  static Future<bool> _runAttempt({
    required VpnServer server,
    required AetherProfile profile,
    required AetherAttempt attempt,
    required int port,
    required String prefix,
    required AetherProgress? onProgress,
    required bool Function() cancelled,
  }) async {
    final env = profile.buildEnv(attempt, port);

    // Aether's own env var for its upstream relay is AETHER_UPSTREAM.
    // ALL_PROXY / HTTPS_PROXY are ignored by its reqwest/hyper stack —
    // that is why every register attempt printed "error sending request
    // for url api.cloudflareclient.com" even though we passed a SOCKS
    // proxy. The value format the binary expects is a URL.
    //
    // Two sources for the proxy, in order of reliability:
    //
    //   1. The active Xray session, if one is connected. Whatever the user
    //      already trusts is what Aether should dial through. This is the
    //      only path that actually reaches Cloudflare from Iran.
    //
    //   2. The bundled WarpRegistrationProxy VLESS — a fallback used
    //      before any server is connected. It runs on 127.0.0.1 and, when
    //      its own upstream is itself filtered, cannot finish the
    //      registration handshake. That is why the fallback keeps failing
    //      even though the binary correctly reports "dialling out through
    //      the socks5 proxy at 127.0.0.1".
    try {
      final activePort =
          V2RayEngine.isConnected ? V2RayEngine.localSocksPort : 0;
      int? proxyPort = activePort > 0 ? activePort : null;
      if (proxyPort == null) {
        // No active Xray session. Try the bundled WARP-registration
        // proxy — but it depends on a Cloudflare Workers endpoint that
        // may be dead. If it does not come up, fail fast with a message
        // the UI can show, instead of starting Aether with a dead
        // AETHER_UPSTREAM and letting it retry for 90 s.
        proxyPort = await WarpRegistrationProxy.ensureStarted();
      }
      if (proxyPort == null || proxyPort <= 0) {
        lastError = 'برای اتصال Aether، اول یک سرور VLESS/VMess/Trojan وصل کنید'
            ' (Aether برای ساخت حساب WARP به یک پروکسی فعال نیاز دارد)';
        return false;
      }
      env['AETHER_UPSTREAM'] = 'socks5://127.0.0.1:$proxyPort';
      env['ALL_PROXY'] = 'socks5h://127.0.0.1:$proxyPort';
      env['HTTPS_PROXY'] = 'socks5h://127.0.0.1:$proxyPort';
      env['http_proxy'] = 'socks5h://127.0.0.1:$proxyPort';
      env['https_proxy'] = 'socks5h://127.0.0.1:$proxyPort';
    } catch (e) {
      lastError = 'Aether upstream setup failed: $e';
      return false;
    }

    // Find-server: ensure gool/mim scan uses auto peers when endpoints missing
    if ((env['AETHER_PROTOCOL'] == 'gool') &&
        (env['AETHER_WIW_OUTER_PEER'] == null || env['AETHER_WIW_OUTER_PEER']!.isEmpty)) {
      env['AETHER_WIW_PEERS'] = 'auto';
    }
    if ((env['AETHER_PROTOCOL'] == 'mim') &&
        (env['AETHER_MIM_OUTER_PEER'] == null || env['AETHER_MIM_OUTER_PEER']!.isEmpty)) {
      env['AETHER_MIM_PEERS'] = 'auto';
    }


    // The native service can refuse to start; give the call a bound so
    // one hung start cannot block the whole attempt.
    bool started = false;
    try {
      final r = await _channel
          .invokeMethod<bool>(
            'start',
            <String, dynamic>{
              'env': jsonEncode(env),
              'remark': server.name,
            },
          )
          .timeout(const Duration(seconds: 12));
      started = r ?? false;
    } catch (e) {
      debugPrint('Aether start invoke failed: $e');
      started = false;
    }

    if (!started) {
      final status = await nativeStatus();
      lastError = status['error']?.toString() ??
          'Aether service could not be started';
      // Ensure the process is stopped before the next attempt spawns a
      // new one, otherwise a failed attempt leaves its binary running.
      try {
        await _stopNative();
      } catch (_) {}
      return false;
    }

    final deadline = DateTime.now().add(attempt.timeout);
    var lastShown = '';

    while (DateTime.now().isBefore(deadline)) {
      if (cancelled()) return false;

      // The status poll is a MethodChannel round trip; without a sleep it
      // fires hundreds of times a second and heats the phone all on its
      // own. 400 ms is fast enough to feel live and slow enough to be free.
      await Future<void>.delayed(const Duration(milliseconds: 400));
      final status = await nativeStatus();

      final line = _shorten(status['lastLine']?.toString() ?? '');
      if (line.isNotEmpty && line != lastShown) {
        lastShown = line;
        onProgress?.call('$prefix${attempt.label}\n$line');
      }

      if (status['exited'] == true) {
        final code = status['exitCode'];
        lastError = 'Aether exited (code $code)'
            '${line.isNotEmpty ? ': $line' : ''}';
        return false;
      }

      final error = status['error']?.toString();
      if (error != null && error.isNotEmpty) {
        lastError = error;
        return false;
      }

      if (await SocksProbe.isPortOpen(port)) {
        final probe = await SocksProbe.measure(
          port: port,
          samples: 1,
          timeout: const Duration(seconds: 5),
        );
        if (probe.ok) return true;
      }

      await Future<void>.delayed(const Duration(milliseconds: 300));
    }

    lastError = 'Timed out (${attempt.label})'
        '${lastShown.isNotEmpty ? ': $lastShown' : ''}';
    return false;
  }

  static String _shorten(String value) {
    final text = value.trim();
    return text.length <= 72 ? text : '${text.substring(0, 72)}…';
  }

  /// فقط تست: با تنظیمات داده‌شده مسیر سالم Aether را پیدا می‌کند بدون اینکه
  /// VPN واقعی سیستم را بالا بیاورد (بر خلاف [connect]). برای دکمه‌ی «اسکن
  /// برای یافتن سرور» در فرم افزودن کانفیگ.
  static Future<bool> scanOnly(
    AetherProfile profile, {
    AetherProgress? onProgress,
    bool Function()? isCancelled,
  }) async {
    lastError = null;
    bool cancelled() => isCancelled?.call() ?? false;

    final dummyServer = VpnServer(
      id: 'aether_scan',
      name: 'Aether scan',
      flag: '🛰️',
      shareLink: profile.toLink(),
      protocol: VpnProtocol.aether,
      host: 'scan',
      port: 0,
    );

    try {
      await _stopNative();

      final info = await nativeInfo();
      if (info['binary'] != true) {
        final abi = info['abi']?.toString() ?? 'unknown';
        lastError = info['error']?.toString() ??
            'Aether core (libaether.so) is not available for this device '
                '(CPU: $abi). Use the arm64 build.';
        return false;
      }

      final plan = profile.plan(lastGood: await _loadLastGood());
      final firstRun = info['hasIdentity'] != true;

      for (var i = 0; i < plan.length; i++) {
        if (cancelled()) break;

        var attempt = plan[i];
        if (firstRun && i == 0) {
          attempt = AetherAttempt(
            protocol: attempt.protocol,
            h2: attempt.h2,
            scan: attempt.scan,
            noize: attempt.noize,
            timeout: attempt.timeout + const Duration(seconds: 25),
          );
        }

        final prefix = plan.length > 1 ? '${i + 1}/${plan.length} · ' : '';
        onProgress?.call('Scan $prefix${attempt.label}');

        final port = await _freePort();
        final ready = await _runAttempt(
          server: dummyServer,
          profile: profile,
          attempt: attempt,
          port: port,
          prefix: 'Scan $prefix',
          onProgress: onProgress,
          cancelled: cancelled,
        );

        await _stopNative();

        if (ready) {
          await _saveLastGood(plan[i]);
          return true;
        }
      }

      if (!cancelled()) lastError ??= 'Aether could not find a working route';
      return false;
    } catch (error) {
      lastError = error.toString();
      debugPrint('Aether scanOnly error: $lastError');
      await _stopNative();
      return false;
    }
  }

  // ------------------------------------------------------------- disconnect

  static Future<void> disconnect() async {
    try {
      await V2RayEngine.disconnect();
    } catch (_) {}
    await _stopNative();
    _connected = false;
    _current = null;
    _corePort = 0;
  }

  // ----------------------------------------------------------------- status

  /// آیا پردازه‌ی Aether هنوز زنده است؟
  static Future<bool> isAlive() async {
    final status = await nativeStatus();
    return status['running'] == true && status['exited'] != true;
  }

  static Future<bool> syncStatus() async {
    final alive = _connected && await isAlive();
    if (!alive) {
      _connected = false;
      _current = null;
    }
    return alive;
  }

  /// پینگ واقعی Aether: مستقیم از خود پراکسی SOCKS پردازه‌ی Aether.
  static Future<ProbeResult> probeCore() {
    if (_corePort == 0) {
      return Future<ProbeResult>.value(
        const ProbeResult(error: 'aether is not running'),
      );
    }
    return SocksProbe.measure(
      port: _corePort,
      samples: 3,
      timeout: const Duration(seconds: 8),
    );
  }

  // ------------------------------------------------------------ xray config

  static const List<String> _privateRanges = <String>[
    '10.0.0.0/8',
    '100.64.0.0/10',
    '127.0.0.0/8',
    '169.254.0.0/16',
    '172.16.0.0/12',
    '192.168.0.0/16',
    '224.0.0.0/4',
  ];

  /// کانفیگ Xray که همه‌ی ترافیک VPN را به SOCKS5 پردازه‌ی Aether می‌دهد.
  ///
  ///  - DNS سیستم (UDP/53) توسط خود Xray پاسخ داده می‌شود و پرس‌وجوها با DoH
  ///    از داخل تونل می‌روند، پس به UDP در Aether نیازی نیست و نشتی هم ندارد.
  ///  - sniffing باعث می‌شود «نام دامنه» (نه IP) به Aether برسد.
  ///  - QUIC (UDP/443) در صورت فعال‌بودن مسدود می‌شود تا مرورگر بلافاصله به
  ///    TCP برگردد (به‌جای چند ثانیه انتظار).
  static String buildXrayConfig({
    required int socksPort,
    bool blockQuic = true,
  }) {
    // End-to-end chain for Psiphon/Aether SOCKS:
    //   app → VPN/TUN → Xray → socks://127.0.0.1:<port> → Psiphon/Aether → net
    //
    // Critical constraints of Psiphon LocalSocksProxyPort:
    //   • TCP CONNECT only — no UDP ASSOCIATE
    //   • so UDP:53 must NOT go to the 'proxy' outbound
    //
    // Catch-all MUST send TCP to 'proxy'. Without it Xray defaults to direct
    // and the user sees "connected but nothing loads".
    final rules = <Map<String, dynamic>>[
      <String, dynamic>{
        'type': 'field',
        'port': '53',
        'network': 'udp',
        'outboundTag': 'dns-out',
      },
      if (blockQuic)
        <String, dynamic>{
          'type': 'field',
          'port': '443',
          'network': 'udp',
          'outboundTag': 'block',
        },
      <String, dynamic>{
        'type': 'field',
        'ip': _privateRanges,
        'outboundTag': 'direct',
      },
      // TCP only through SOCKS (UDP would fail on Psiphon socks).
      <String, dynamic>{
        'type': 'field',
        'network': 'tcp',
        'outboundTag': 'proxy',
      },
    ];

    final config = <String, dynamic>{
      'log': <String, dynamic>{'loglevel': 'warning'},
      'stats': <String, dynamic>{},
      'policy': <String, dynamic>{
        'levels': <String, dynamic>{
          '8': <String, dynamic>{
            'connIdle': 300,
            'downlinkOnly': 1,
            'handshake': 4,
            'uplinkOnly': 1,
          },
        },
        'system': <String, dynamic>{
          'statsOutboundUplink': true,
          'statsOutboundDownlink': true,
        },
      },
      'inbounds': <Map<String, dynamic>>[
        <String, dynamic>{
          'tag': 'socks',
          'port': 10808,
          'listen': '127.0.0.1',
          'protocol': 'socks',
          'settings': <String, dynamic>{
            'auth': 'noauth',
            'udp': true,
            'userLevel': 8,
          },
          'sniffing': <String, dynamic>{
            'enabled': true,
            'destOverride': <String>['http', 'tls'],
            'routeOnly': false,
          },
        },
        <String, dynamic>{
          'tag': 'http',
          'port': 10809,
          'listen': '127.0.0.1',
          'protocol': 'http',
          'settings': <String, dynamic>{'userLevel': 8},
        },
      ],
      'outbounds': <Map<String, dynamic>>[
        <String, dynamic>{
          'tag': 'proxy',
          'protocol': 'socks',
          'settings': <String, dynamic>{
            'servers': <Map<String, dynamic>>[
              <String, dynamic>{
                'address': '127.0.0.1',
                'port': socksPort,
                // Psiphon socks has no UDP ASSOCIATE
                'udp': false,
              },
            ],
          },
          'streamSettings': <String, dynamic>{
            'sockopt': <String, dynamic>{
              'dialerProxy': '',
            },
          },
        },
        <String, dynamic>{
          'tag': 'direct',
          'protocol': 'freedom',
          'settings': <String, dynamic>{
            'domainStrategy': 'UseIPv4',
          },
        },
        <String, dynamic>{
          'tag': 'block',
          'protocol': 'blackhole',
          'settings': <String, dynamic>{
            'response': <String, dynamic>{'type': 'http'},
          },
        },
        // Built-in DNS client — answers UDP:53, then fetches via DoH (TCP)
        // which the catch-all routes through 'proxy'.
        <String, dynamic>{'tag': 'dns-out', 'protocol': 'dns'},
      ],
      'dns': <String, dynamic>{
        'servers': <dynamic>[
          <String, dynamic>{
            'address': 'https://1.1.1.1/dns-query',
            'skipFallback': false,
          },
          <String, dynamic>{
            'address': 'https://8.8.8.8/dns-query',
            'skipFallback': false,
          },
          '1.1.1.1',
          '8.8.8.8',
        ],
        'queryStrategy': 'UseIPv4',
        'disableCache': false,
      },
      'routing': <String, dynamic>{
        // Resolve names so IP rules apply; DoH still goes via proxy.
        'domainStrategy': 'IPIfNonMatch',
        'domainMatcher': 'hybrid',
        'rules': rules,
      },
    };

    final encoded = jsonEncode(config);
    // Log the SOCKS target so device logs prove port matches Psiphon WIN.
    // ignore: avoid_print
    assert(() {
      // debugPrint available via foundation in callers; keep pure here
      return true;
    }());
    return encoded;
  }

  /// اندازه‌گیری تأخیر واقعی Aether برای تست پینگ.
  /// [server] برای سازگاری با ServerTester نگه داشته شده؛ فعلاً استفاده نمی‌شود
  /// چون پروب روی هسته‌ی محلی (SOCKS) انجام می‌شود نه روی خود سرور.

  /// Env map that would be sent for [profile] (for UI Dump env button).
  static Map<String, String> dumpEnvPreview(AetherProfile profile, {int socksPort = 1819}) {
    final attempts = profile.plan();
    final attempt = attempts.isNotEmpty
        ? attempts.first
        : AetherAttempt(protocol: 'masque', h2: false, scan: 'balanced', timeout: const Duration(seconds: 30));
    return profile.buildEnv(attempt, socksPort);
  }

  static Future<int> measureDelay(
    VpnServer server, {
    Duration? budget,
  }) async {
    final p = await probeCore();
    if (!p.ok) return 0;
    return p.ms ?? 0;
  }

  /// اجرای `libaether.so --version` روی دستگاه برای تشخیص مشکل dlopen/ELF.
  /// خروجی stdout+stderr و کد خروج را برمی‌گرداند.

  /// Cloudflare WARP identity registration (same API surface as common WARP clients).
  /// POST https://api.cloudflareclient.com/v0a2158/reg
  static Future<Map<String, dynamic>> registerWarpKey() async {
    try {
      final client = HttpClient();
      final uri = Uri.parse('https://api.cloudflareclient.com/v0a2158/reg');
      final req = await client.postUrl(uri);
      req.headers.set('Content-Type', 'application/json; charset=UTF-8');
      req.headers.set('User-Agent', 'okhttp/3.12.1');
      req.headers.set('CF-Client-Version', 'a-6.11-2223');
      // Placeholder public key — real clients generate a WireGuard keypair.
      // Binary will re-provision if identity is incomplete (AETHER_REPROVISION).
      final body = jsonEncode(<String, dynamic>{
        'key': base64Encode(List<int>.generate(32, (i) => (i * 17 + 3) & 0xff)),
        'install_id': '',
        'fcm_token': '',
        'referrer': '',
        'warp_enabled': false,
        'tos': DateTime.now().toUtc().toIso8601String(),
        'type': 'Android',
        'locale': 'en_US',
      });
      req.add(utf8.encode(body));
      final res = await req.close().timeout(const Duration(seconds: 20));
      final text = await res.transform(utf8.decoder).join();
      client.close(force: true);
      if (res.statusCode >= 200 && res.statusCode < 300) {
        try {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('warp_reg_json_v1', text);
        } catch (_) {}
        return <String, dynamic>{'ok': true, 'status': res.statusCode, 'body': text};
      }
      return <String, dynamic>{
        'ok': false,
        'status': res.statusCode,
        'body': text,
      };
    } catch (e) {
      return <String, dynamic>{'ok': false, 'error': e.toString()};
    }
  }

  static Future<Map<String, dynamic>> testBinary() async {
    try {
      final result =
          await _channel.invokeMapMethod<String, dynamic>('testBinary');
      return result ?? <String, dynamic>{'error': 'empty result'};
    } on PlatformException catch (error) {
      return <String, dynamic>{
        'error': error.message ?? error.code,
        'ok': false,
      };
    } catch (error) {
      return <String, dynamic>{'error': error.toString(), 'ok': false};
    }
  }
}
