import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/server.dart';
import 'warp_endpoint_tester.dart';
import 'connection_log_service.dart';
import 'warp_real_tunnel_tester.dart';
import 'v2ray_engine.dart';
import 'warp_endpoint_scanner.dart';

/// WARP / WARP Plus key generator + endpoint scanner.
///
/// این سرویس:
///   1. یه جفت کلید X25519 می‌سازه (private/public)
///   2. با Cloudflare API ثبت می‌کنه → آدرس + کلیدهای سرور رو می‌گیره
///   3. لیست IP های edge Cloudflare رو اسکن می‌کنه و سریع‌ترین رو انتخاب می‌کنه
///   4. یه VpnServer از نوع amneziaWg می‌سازه که با WireGuard outbound
///      در Xray وصل می‌شه.
class WarpService {
  WarpService._();

  static const String _prefsKeyDeviceId = 'warp_device_id_v1';
  static const String _prefsKeyPrivateKey = 'warp_private_key_v1';
  static const String _prefsKeyPublicKey = 'warp_public_key_v1';
  static const String _prefsKeyReserved = 'warp_reserved_v1';
  static const String _prefsKeyLicense = 'warp_license_v1';
  static const String _prefsKeyAccount = 'warp_account_v1';

  static const String _apiBase = 'https://api.cloudflareclient.com/v0a2158';
  static const String _apiUserAgent = 'okhttp/3.12.1';

  /// لیست edge IP های Cloudflare برای اسکن.
  /// اینا رو از منابع عمومی گرفتم؛ کاربر می‌تونه خودش اضافه کنه.
  static const List<String> _edgeCandidates = [
    '162.159.192.1',
    '162.159.192.7',
    '162.159.192.28',
    '162.159.192.31',
    '162.159.192.42',
    '162.159.192.56',
    '162.159.192.74',
    '162.159.192.86',
    '162.159.192.107',
    '162.159.192.118',
    '162.159.192.146',
    '162.159.192.153',
    '162.159.192.166',
    '162.159.192.174',
    '162.159.192.189',
    '162.159.192.201',
    '162.159.192.220',
    '162.159.192.236',
    '162.159.192.246',
    '162.159.192.255',
    '188.114.96.1',
    '188.114.97.1',
    '188.114.98.1',
    '188.114.99.1',
    '188.114.96.2',
    '188.114.97.2',
    '188.114.98.2',
    '188.114.99.2',
  ];

  static const int _warpPort = 2408;

  /// ساخت VpnServer آماده WARP (بدون WARP Plus).
  /// [plus] اگه true باشه، نیاز به license داره (که کاربر paste می‌کنه).
  /// وضعیت زنده اسکن endpoint که UI می‌تونه listen کنه.
  /// این notifier global است — از home_screen هم قابل دسترسیه.
  static final ValueNotifier<WarpScanState> scanProgress =
      ValueNotifier(const WarpScanState());

  /// ریست کردن progress (قبل از شروع scan جدید).
  static void _resetProgress() {
    scanProgress.value = const WarpScanState();
  }

  /// به‌روزرسانی progress (داخلی).
  static void _updateProgress({
    required String phase,
    int tested = 0,
    int total = 0,
    String? lastEndpoint,
    int? lastMs,
    bool done = false,
    String? error,
  }) {
    final current = scanProgress.value;
    scanProgress.value = current.copyWith(
      phase: phase,
      tested: tested,
      total: total,
      lastEndpoint: lastEndpoint,
      lastMs: lastMs,
      done: done,
      error: error,
      clearError: error == null && done,
    );
  }

  /// rescan کردن endpoint برای یک سرور موجود (WARP یا WARP Plus).
  ///
  /// از کلیدهای ذخیره‌شده استفاده می‌کنه و فقط endpoint رو دوباره اسکن + verify.
  static Future<({String? endpoint, int? ms, String? error})>
      rescanEndpoints(VpnServer server) async {
    if (!server.isDeletable) {
      return (endpoint: null, ms: null, error: 'built-in server');
    }
    try {
      _resetProgress();

      // استخراج privateKey از shareLink
      String? privateKeyB64;
      String? peerPublicKeyB64;
      if (server.protocol == VpnProtocol.amneziaWg) {
        final fields = _extractWgFieldsFromVpnLink(server.shareLink);
        privateKeyB64 = fields?.privateKey;
        peerPublicKeyB64 = fields?.publicKey;
      } else if (server.protocol == VpnProtocol.chain) {
        // inner = exit hop (دومی)
        final uri = Uri.parse(server.shareLink);
        final inner = uri.queryParameters['second'] ?? '';
        if (inner.isNotEmpty) {
          final fields = _extractWgFieldsFromVpnLink(inner);
          privateKeyB64 = fields?.privateKey;
          peerPublicKeyB64 = fields?.publicKey;
        }
      }
      if (privateKeyB64 == null || peerPublicKeyB64 == null) {
        return (endpoint: null, ms: null, error: 'no keys');
      }

      final modeLabel = server.warpEndpointMode ?? 'Fast';
      final mode = WarpEndpointMode.values.firstWhere(
        (m) => m.label == modeLabel,
        orElse: () => WarpEndpointMode.fast,
      );

      _updateProgress(phase: 'Scanning', tested: 0, total: 0);
      final hits = await WarpEndpointTester.selectMany(
        mode: mode,
        privateKeyB64: privateKeyB64,
        peerPublicKeyB64: peerPublicKeyB64,
        maxHits: 12,
        onProgress: (label, tested, total) {
          _updateProgress(
            phase: 'Scanning (${modeLabel})',
            tested: tested,
            total: total,
          );
        },
      );

      if (hits.isEmpty) {
        _updateProgress(phase: 'No hits', done: true,
            error: 'no endpoint found');
        return (endpoint: null, ms: null, error: 'no endpoint');
      }

      _updateProgress(phase: 'Verifying', tested: 0, total: hits.length);
      final verified = await WarpRealTunnelTester.findFirstWorking(
        hits: hits,
        makeServerFromEndpoint: (ep) {
          return server.copyWith(
            host: ep.host,
            port: ep.port,
          );
        },
        maxCandidates: 12,
        onProgress: (tested, total, ep, ms) {
          _updateProgress(
            phase: 'Verifying',
            tested: tested,
            total: total,
            lastEndpoint: ep.toString(),
            lastMs: ms > 0 ? ms : null,
          );
        },
      );

      if (verified == null) {
        _updateProgress(
          phase: 'Done',
          done: true,
          error: 'no verified endpoint',
        );
        return (endpoint: null, ms: null, error: 'no verified endpoint');
      }

      _updateProgress(
        phase: 'Done',
        done: true,
        lastEndpoint: verified.endpoint.toString(),
        lastMs: verified.latencyMs,
      );
      // log نتیجه
      // ignore: unawaited_futures
      ConnectionLogService.logWarpRescanResult(
        server: server.name,
        endpoint: verified.endpoint.toString(),
        ms: verified.latencyMs,
      );
      return (
        endpoint: verified.endpoint.toString(),
        ms: verified.latencyMs,
        error: null,
      );
    } catch (e) {
      _updateProgress(phase: 'Error', done: true, error: e.toString());
      return (endpoint: null, ms: null, error: e.toString());
    }
  }

  /// استخراج privateKey/publicKey از یک vpn:// link (بدون JSON کامل).
  static _WgKeys? _extractWgFieldsFromVpnLink(String link) {
    try {
      if (!link.startsWith('vpn://')) return null;
      final b64 = link.substring('vpn://'.length).trim();
      final raw = utf8.decode(
        base64.decode(base64.normalize(b64)),
        allowMalformed: true,
      );
      final outer = jsonDecode(raw);
      if (outer is! Map) return null;
      Map? awg;
      final containers = outer['containers'];
      if (containers is List) {
        for (final c in containers) {
          if (c is Map && c['awg'] is Map) {
            awg = Map<String, dynamic>.from(c['awg'] as Map);
            break;
          }
        }
      }
      if (awg == null) return null;
      final lastCfg = (awg['last_config'] ?? '').toString();
      if (lastCfg.isEmpty) return null;
      final inner = jsonDecode(lastCfg);
      if (inner is! Map) return null;
      final iface = inner['interface'];
      final peer = inner['peer'];
      if (iface is! Map || peer is! Map) return null;
      final priv = (iface['private_key'] ?? iface['privateKey'] ?? '').toString();
      final pub = (peer['public_key'] ?? peer['publicKey'] ?? '').toString();
      if (priv.isEmpty || pub.isEmpty) return null;
      return _WgKeys(privateKey: priv, publicKey: pub);
    } catch (_) {
      return null;
    }
  }

  static Future<({VpnServer? server, String? error})> generate({
    bool plus = false,
    String? proxySocksPort,
    String? endpointOverride,
    int? scanTimeoutMs,
    WarpEndpointMode mode = WarpEndpointMode.fast,
    String? customEndpoint,
    void Function(String msg)? onProgress,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // 1) کلیدها — یا از prefs موجود یا ساخت جدید
      var privateKeyB64 = prefs.getString(_prefsKeyPrivateKey);
      var publicKeyB64 = prefs.getString(_prefsKeyPublicKey);

      if (privateKeyB64 == null || publicKeyB64 == null) {
        onProgress?.call('Generating X25519 keypair...');
        final kp = await _generateX25519();
        privateKeyB64 = kp.privateKeyB64;
        publicKeyB64 = kp.publicKeyB64;
        await prefs.setString(_prefsKeyPrivateKey, privateKeyB64);
        await prefs.setString(_prefsKeyPublicKey, publicKeyB64);
      }

      // 2) ثبت در Cloudflare (یا بازیابی ثبت قبلی)
      var deviceId = prefs.getString(_prefsKeyDeviceId);
      var accountRaw = prefs.getString(_prefsKeyAccount);
      Map<String, dynamic>? account;

      if (accountRaw != null) {
        try {
          final dec = jsonDecode(accountRaw);
          if (dec is Map) account = Map<String, dynamic>.from(dec);
        } catch (_) {}
      }

      if (deviceId == null || account == null) {
        onProgress?.call('Registering device with Cloudflare...');
        final reg = await _register(
          publicKeyB64,
          proxySocksPort: proxySocksPort,
          license: plus ? prefs.getString(_prefsKeyLicense) : null,
        );
        if (reg.error != null) {
          return (server: null, error: reg.error);
        }
        deviceId = reg.deviceId;
        account = reg.account;
        await prefs.setString(_prefsKeyDeviceId, deviceId!);
        await prefs.setString(_prefsKeyAccount, jsonEncode(account));
      }

      if (account == null) {
        return (server: null, error: 'registration failed');
      }

      // استخراج IP + peer public key از account
      final cfg = account['config'] as Map?;
      final peers = cfg?['peers'] as List?;
      if (peers == null || peers.isEmpty) {
        return (server: null, error: 'no peers in account');
      }
      final peer = Map<String, dynamic>.from(peers.first as Map);
      final peerPublicKey = (peer['public_key'] ?? '').toString();
      final peerEndpoint =
          ((peer['endpoint'] as Map?)?['host'] ?? '').toString();
      if (peerPublicKey.isEmpty) {
        return (server: null, error: 'no peer public key');
      }

      final iface = cfg?['interface'] as Map?;
      final address = (iface?['addresses'] as Map?) ??
          (cfg?['interface'] as Map?)?['addresses'];
      final v4 = ((address as Map?)?['v4'] ?? '').toString();

      final clientId = (cfg?['client_id'] ?? '').toString();
      final reserved = _decodeReserved(clientId);

      // 3) اسکن edge — WARPSCOUT-style + real-tunnel verify
      String chosenEndpoint = endpointOverride ?? '';
      if (chosenEndpoint.isEmpty) {
        onProgress?.call('Scanning WARP endpoints (${mode.label})...');
        final hits = await WarpEndpointTester.selectMany(
          mode: mode,
          privateKeyB64: privateKeyB64,
          peerPublicKeyB64: peerPublicKey,
          customEndpoint: customEndpoint,
          maxHits: 12,
          onProgress: (label, tested, total) {
            onProgress?.call('$label $tested/$total');
          },
        );
        if (hits.isNotEmpty) {
          onProgress?.call(
              'Verifying ${hits.length} candidates via real tunnel...');
          final verifyServerFor = (WarpEndpoint ep) => VpnServer(
                id: 'warp_verify',
                name: 'WARP verify',
                flag: '\u{1F310}',
                shareLink: 'vpn://verify',
                protocol: VpnProtocol.amneziaWg,
                host: ep.host,
                port: ep.port,
                isDeletable: false,
              );
          final verified = await WarpRealTunnelTester.findFirstWorking(
            hits: hits,
            makeServerFromEndpoint: (ep) {
              // ساخت vpn:// link برای این endpoint خاص + keys واقعی
              final container = <String, dynamic>{
                'awg': <String, dynamic>{
                  'port': '${ep.port}',
                  'last_config': jsonEncode(<String, dynamic>{
                    'interface': <String, dynamic>{
                      'private_key': privateKeyB64,
                      'address':
                          v4.isNotEmpty ? v4 : '172.16.0.2/32',
                      'dns': '1.1.1.1',
                      'mtu': 1280,
                    },
                    'peer': <String, dynamic>{
                      'public_key': peerPublicKey,
                      'endpoint': ep.toString(),
                      'allowed_ips': <String>['0.0.0.0/0', '::/0'],
                      if (reserved != null) 'reserved': reserved,
                    },
                  }),
                  'mtu': '1280',
                },
              };
              final outer = <String, dynamic>{
                'hostName': ep.host,
                'description': plus ? 'WARP+ verify' : 'WARP verify',
                'containers': <dynamic>[container],
              };
              final link = 'vpn://${base64.encode(utf8.encode(jsonEncode(outer)))}';
              return VpnServer(
                id: 'warp_verify_${ep.host}_${ep.port}',
                name: 'WARP verify',
                flag: '\u{1F310}',
                shareLink: link,
                protocol: VpnProtocol.amneziaWg,
                host: ep.host,
                port: ep.port,
                isDeletable: false,
              );
            },
            maxCandidates: 12,
            onProgress: (tested, total, ep, ms) {
              onProgress?.call(
                  'Verify $tested/$total: $ep ${ms > 0 ? "$ms ms" : "\u2715"}');
            },
          );
          if (verified != null) {
            chosenEndpoint = verified.endpoint.toString();
            onProgress?.call(
                'Verified ${verified.endpoint} (${verified.latencyMs}ms)');
          } else {
            onProgress?.call(
                'Verify found nothing — using first UDP hit');
            chosenEndpoint = hits.first.endpoint.toString();
          }
        } else {
          onProgress?.call(
              'Scanner found nothing — falling back to default');
          chosenEndpoint = '$peerEndpoint:$_warpPort';
        }
      }

      // 4) ساخت VpnServer
      final host = chosenEndpoint.split(':').first;
      final port = int.tryParse(chosenEndpoint.split(':').last) ?? _warpPort;

      final container = {
        'awg': {
          'port': '$port',
          'last_config': jsonEncode({
            'interface': {
              'private_key': privateKeyB64,
              'address': v4.isNotEmpty ? v4 : '172.16.0.2/32',
              'dns': '1.1.1.1',
              'mtu': 1280,
            },
            'peer': {
              'public_key': peerPublicKey,
              'endpoint': chosenEndpoint,
              'allowed_ips': ['0.0.0.0/0', '::/0'],
              if (reserved != null)
                'reserved': reserved,
            },
          }),
          'mtu': '1280',
        },
      };

      final outer = {
        'hostName': host,
        'description': plus
            ? 'WARP+ · ${plus ? _shortId(deviceId) : ""}'
            : 'WARP · ${_shortId(deviceId)}',
        'containers': [container],
      };

      final rawB64 = base64.encode(utf8.encode(jsonEncode(outer)));
      final name = plus ? 'WARP+' : 'WARP';

      final server = VpnServer(
        id: 'warp_${DateTime.now().millisecondsSinceEpoch}',
        name: '$name · $host',
        flag: '\u{1F310}', // 🌐
        shareLink: 'vpn://$rawB64',
        protocol: VpnProtocol.amneziaWg,
        host: host,
        port: port,
        isDeletable: true,
        warpEndpointMode: mode.label,
      );

      return (server: server, error: null);
    } catch (e) {
      return (server: null, error: e.toString());
    }
  }

  /// اعمال license (برای WARP Plus).
  static Future<({bool ok, String? error})> applyLicense(
      String license, {
      String? proxySocksPort,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final deviceId = prefs.getString(_prefsKeyDeviceId);
      if (deviceId == null) {
        return (ok: false, error: 'first generate a WARP key');
      }
      final r = await _apiPut(
        '/reg/$deviceId/account',
        {'license': license.trim()},
        proxySocksPort: proxySocksPort,
      );
      if (r.statusCode == 200) {
        await prefs.setString(_prefsKeyLicense, license.trim());
        return (ok: true, error: null);
      }
      return (ok: false, error: 'HTTP ${r.statusCode}: ${r.body}');
    } catch (e) {
      return (ok: false, error: e.toString());
    }
  }

  /// پاک کردن state (شروع از صفر).
  static Future<void> reset() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefsKeyDeviceId);
    await prefs.remove(_prefsKeyPrivateKey);
    await prefs.remove(_prefsKeyPublicKey);
    await prefs.remove(_prefsKeyReserved);
    await prefs.remove(_prefsKeyAccount);
    // license حفظ می‌شه
  }

  // ------------------------------------------------------------------ private

  static String _shortId(String? id) {
    if (id == null || id.isEmpty) return '?';
    return id.length > 8 ? id.substring(0, 8) : id;
  }

  /// X25519 keypair از cryptography package.
  /// کلید private به‌شکل standard WireGuard باید 32 بایت be و
  /// clamping روش اعمال شه. public از private derive می‌شه.
  static Future<({String privateKeyB64, String publicKeyB64})>
      _generateX25519() async {
    final algo = X25519();
    final keyPair = await algo.newKeyPair();

    // private key — 32 bytes, باید clamp بشه
    final privBytes = await keyPair.extractPrivateKeyBytes();
    final clampedPriv = _clampWireGuard(privBytes);

    // public — derive از clamped private
    final deriveSeed = await algo.newKeyPairFromSeed(clampedPriv);
    final pubBytes = (await deriveSeed.extractPublicKey()).bytes;

    return (
      privateKeyB64: base64.encode(clampedPriv),
      publicKeyB64: base64.encode(pubBytes),
    );
  }

  /// WireGuard clamping روی کلید private:
  ///   byte[0]  &= 248
  ///   byte[31] &= 127
  ///   byte[31] |= 64
  static List<int> _clampWireGuard(List<int> raw) {
    final b = List<int>.from(raw);
    b[0] &= 248;
    b[31] &= 127;
    b[31] |= 64;
    return b;
  }

  /// استخراج reserved از client_id. این یه 3-byte برعکس‌شده‌ست که
  /// WireGuard برای WARP نیاز داره.
  static List<int>? _decodeReserved(String clientId) {
    if (clientId.isEmpty) return null;
    try {
      final b = base64.decode(base64.normalize(clientId));
      if (b.length < 3) return null;
      return [b[0], b[1], b[2]];
    } catch (_) {
      return null;
    }
  }

  /// ثبت دستگاه جدید در Cloudflare API.
  static Future<
      ({String? deviceId, Map<String, dynamic>? account, String? error})>
      _register(
    String publicKeyB64, {
    String? proxySocksPort,
    String? license,
  }) async {
    try {
      final body = {
        'key': publicKeyB64,
        'install_id': '',
        'fcm_token': '',
        'tos': DateTime.now().toUtc().toIso8601String(),
        'model': 'PC',
        'serial_number': '',
        'locale': 'en_US',
        'referrer': 'warp',
      };
      final r = await _apiPost('/reg', body, proxySocksPort: proxySocksPort);

      if (r.statusCode != 200) {
        return (
          deviceId: null,
          account: null,
          error: 'HTTP ${r.statusCode}: ${r.body.substring(0, r.body.length > 200 ? 200 : r.body.length)}'
        );
      }

      final decoded = jsonDecode(r.body);
      if (decoded is! Map) {
        return (deviceId: null, account: null, error: 'invalid response');
      }
      final data = Map<String, dynamic>.from(decoded);
      final deviceId =
          ((data['id'] ?? '') as String).trim();
      final account = Map<String, dynamic>.from(data);

      if (license != null && license.isNotEmpty) {
        try {
          await _apiPut(
            '/reg/$deviceId/account',
            {'license': license},
            proxySocksPort: proxySocksPort,
          );
        } catch (_) {}
      }

      return (deviceId: deviceId, account: account, error: null);
    } catch (e) {
      return (deviceId: null, account: null, error: e.toString());
    }
  }

  static Future<http.Response> _apiPost(
    String path,
    Map<String, dynamic> body, {
    String? proxySocksPort,
  }) async {
    final url = Uri.parse('$_apiBase$path');
    final headers = {
      'Content-Type': 'application/json; charset=UTF-8',
      'User-Agent': _apiUserAgent,
      'CF-Client-Version': 'a-6.30.1',
      'Accept': 'application/json',
    };

    if (proxySocksPort != null && proxySocksPort.isNotEmpty) {
      final client = HttpClient();
      client.findProxy = (u) => 'SOCKS 127.0.0.1:$proxySocksPort';
      client.badCertificateCallback = (_, __, ___) => true;
      try {
        final req = await client.postUrl(url);
        headers.forEach((k, v) => req.headers.set(k, v));
        req.write(jsonEncode(body));
        final res = await req.close();
        final text = await res.transform(utf8.decoder).join();
        client.close(force: true);
        return http.Response(text, res.statusCode);
      } catch (e) {
        client.close(force: true);
        rethrow;
      }
    }

    return await http
        .post(url, headers: headers, body: jsonEncode(body))
        .timeout(const Duration(seconds: 20));
  }

  static Future<http.Response> _apiPut(
    String path,
    Map<String, dynamic> body, {
    String? proxySocksPort,
  }) async {
    final url = Uri.parse('$_apiBase$path');
    final headers = {
      'Content-Type': 'application/json; charset=UTF-8',
      'User-Agent': _apiUserAgent,
      'CF-Client-Version': 'a-6.30.1',
      'Accept': 'application/json',
    };

    if (proxySocksPort != null && proxySocksPort.isNotEmpty) {
      final client = HttpClient();
      client.findProxy = (u) => 'SOCKS 127.0.0.1:$proxySocksPort';
      client.badCertificateCallback = (_, __, ___) => true;
      try {
        final req = await client.putUrl(url);
        headers.forEach((k, v) => req.headers.set(k, v));
        req.write(jsonEncode(body));
        final res = await req.close();
        final text = await res.transform(utf8.decoder).join();
        client.close(force: true);
        return http.Response(text, res.statusCode);
      } catch (e) {
        client.close(force: true);
        rethrow;
      }
    }

    return await http
        .put(url, headers: headers, body: jsonEncode(body))
        .timeout(const Duration(seconds: 20));
  }

  /// اسکن موازی edge IP ها برای سریع‌ترین.
  static Future<String?> _scanFastest({
    int timeoutMs = 1500,
    void Function(String msg)? onProgress,
  }) async {
    final results = <String, int>{};

    final futures = _edgeCandidates.map((ip) async {
      final sw = Stopwatch()..start();
      try {
        final s = await Socket.connect(
          ip,
          _warpPort,
          timeout: Duration(milliseconds: timeoutMs),
        );
        sw.stop();
        s.destroy();
        results['$ip:$_warpPort'] = sw.elapsedMilliseconds;
        onProgress?.call('$ip ✓ ${sw.elapsedMilliseconds}ms');
      } catch (_) {}
    }).toList();

    await Future.wait(futures, eagerError: false);
    if (results.isEmpty) return null;

    final sorted = results.entries.toList()
      ..sort((a, b) => a.value.compareTo(b.value));
    return sorted.first.key;
  }

  /// چک کردن اینکه WARP قبلاً ساخته شده یا نه.
  static Future<bool> hasExisting() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_prefsKeyPrivateKey) != null &&
        prefs.getString(_prefsKeyAccount) != null;
  }

  /// آدرس edge پیشنهادی از پروب‌ها.
  static Future<String?> bestEndpoint() => _scanFastest();

  /// فعال‌سازی WARP Plus با license + endpoint scanner.
  static Future<({VpnServer? server, String? error})> generatePlus({
    required String license,
    String? proxySocksPort,
    void Function(String msg)? onProgress,
  }) async {
    final lic = await applyLicense(
      license,
      proxySocksPort: proxySocksPort,
    );
    if (!lic.ok) {
      return (server: null, error: lic.error ?? 'license failed');
    }
    return generate(
      plus: true,
      proxySocksPort: proxySocksPort,
      onProgress: onProgress,
    );
  }

  // ------------------------------------------------- WARP Plus 2-hop (chain)

  /// ساخت لینک vpn:// از account ثبت‌شده — قابل استفاده در chain.
  /// برخلاف generate()، این نسخه reserved را داخل settings می‌ذاره چون
  /// chain به آن نیاز دارد.
  static String _buildVpnLinkFromAccount({
    required String privateKeyB64,
    required Map<String, dynamic> account,
    required String endpoint,
    required String description,
  }) {
    final cfg = account['config'] as Map?;
    final peers = cfg?['peers'] as List?;
    if (peers == null || peers.isEmpty) {
      throw StateError('no peers in account');
    }
    final peer = Map<String, dynamic>.from(peers.first as Map);
    final peerPublicKey = (peer['public_key'] ?? '').toString();
    if (peerPublicKey.isEmpty) {
      throw StateError('no peer public key');
    }
    final iface = cfg?['interface'] as Map?;
    final addrMap = (iface?['addresses'] as Map?) ??
        ((cfg?['interface'] as Map?)?['addresses'] as Map?);
    final v4 = ((addrMap)?['v4'] ?? '').toString();
    final clientId = (cfg?['client_id'] ?? '').toString();
    final reserved = _decodeReserved(clientId);
    final host = endpoint.split(':').first;
    final port = int.tryParse(endpoint.split(':').last) ?? _warpPort;

    final container = <String, dynamic>{
      'awg': <String, dynamic>{
        'port': '$port',
        'last_config': jsonEncode(<String, dynamic>{
          'interface': <String, dynamic>{
            'private_key': privateKeyB64,
            'address': v4.isNotEmpty ? v4 : '172.16.0.2/32',
            'dns': '1.1.1.1',
            'mtu': 1280,
          },
          'peer': <String, dynamic>{
            'public_key': peerPublicKey,
            'endpoint': endpoint,
            'allowed_ips': <String>['0.0.0.0/0', '::/0'],
            if (reserved != null) 'reserved': reserved,
          },
        }),
        'mtu': '1280',
      },
    };
    final outer = <String, dynamic>{
      'hostName': host,
      'description': description,
      'containers': <dynamic>[container],
    };
    final rawB64 = base64.encode(utf8.encode(jsonEncode(outer)));
    return 'vpn://$rawB64';
  }

  /// ساخت WARP Plus 2-hop از دو لینک آماده vpn:// — بدون register.
  ///
  /// برای کاربران پیشرفته که کلید outer/inner رو جدا ساختن.
  /// هر دو link باید فرمت `vpn://<base64>` داشته باشن (AmneziaWG format).
  static ({VpnServer? server, String? error}) buildPlusChainFromLinks({
    required String outerVpnLink,
    required String innerVpnLink,
    String name = 'WARP+ manual 2-hop',
  }) {
    try {
      final outer = outerVpnLink.trim();
      final inner = innerVpnLink.trim();
      if (!outer.startsWith('vpn://')) {
        return (server: null, error: 'outer link must be vpn://...');
      }
      if (!inner.startsWith('vpn://')) {
        return (server: null, error: 'inner link must be vpn://...');
      }

      // اطمینان از اینکه هر دو valid هستن
      final outerFields = _extractWgFieldsFromVpnLink(outer);
      final innerFields = _extractWgFieldsFromVpnLink(inner);
      if (outerFields == null) {
        return (server: null, error: 'outer link is invalid');
      }
      if (innerFields == null) {
        return (server: null, error: 'inner link is invalid');
      }

      final chainLink = Uri(
        scheme: 'chain',
        host: 'config',
        queryParameters: <String, String>{
          'first': outer,
          'second': inner,
          'name': name,
        },
      ).toString();

      // endpoint از outer می‌گیریم برای نمایش
      final outerEndpoint = _extractWgEndpointFromLink(outer) ?? '';
      final host = outerEndpoint.split(':').first;
      final port = int.tryParse(
              outerEndpoint.split(':').length > 1
                  ? outerEndpoint.split(':').last
                  : '') ??
          _warpPort;

      final server = VpnServer(
        id: 'warp_plus_manual_${DateTime.now().millisecondsSinceEpoch}',
        name: host.isEmpty ? name : '$name · $host',
        flag: '\u{1F310}',
        shareLink: chainLink,
        protocol: VpnProtocol.chain,
        host: host,
        port: port,
        isDeletable: true,
        warpEndpointMode: 'Custom',
      );
      return (server: server, error: null);
    } catch (e) {
      return (server: null, error: e.toString());
    }
  }

  /// استخراج endpoint از یک vpn:// link (برای نمایش).
  static String? _extractWgEndpointFromLink(String link) {
    try {
      final b64 = link.substring('vpn://'.length).trim();
      final raw = utf8.decode(
        base64.decode(base64.normalize(b64)),
        allowMalformed: true,
      );
      final outer = jsonDecode(raw);
      if (outer is! Map) return null;
      Map? awg;
      final containers = outer['containers'];
      if (containers is List) {
        for (final c in containers) {
          if (c is Map && c['awg'] is Map) {
            awg = Map<String, dynamic>.from(c['awg'] as Map);
            break;
          }
        }
      }
      if (awg == null) return null;
      final lastCfg = (awg['last_config'] ?? '').toString();
      if (lastCfg.isEmpty) return null;
      final innerCfg = jsonDecode(lastCfg);
      if (innerCfg is! Map) return null;
      final peer = innerCfg['peer'];
      if (peer is! Map) return null;
      return (peer['endpoint'] ?? '').toString();
    } catch (_) {
      return null;
    }
  }

  /// ساخت WARP Plus 2-hop — Outer (بدون license) + Inner (با license).
  /// خروجی یک chain:// است که توی _buildChainConfig تبدیل به دو outbound
  /// wireguard می‌شود (outer اول، inner دوم).
  static Future<({VpnServer? server, String? error})> generatePlusChain({
    required String license,
    String? proxySocksPort,
    WarpEndpointMode mode = WarpEndpointMode.fast,
    String? customEndpoint,
    void Function(String msg)? onProgress,
  }) async {
    try {
      final lic = license.trim();
      if (lic.isEmpty) {
        return (server: null, error: 'license is required');
      }

      // 1) اسکن اولیه — WARPSCOUT-style
      onProgress?.call('Scanning endpoints for outer hop (${mode.label})...');
      // outer keypair هنوز ساخته نشده — با keypair موقت اسکن می‌کنیم.
      final scanKp = await _generateX25519();
      final hits = await WarpEndpointTester.selectMany(
        mode: mode,
        privateKeyB64: scanKp.privateKeyB64,
        peerPublicKeyB64: scanKp.publicKeyB64,
        customEndpoint: customEndpoint,
        maxHits: 12,
        onProgress: (label, tested, total) {
          onProgress?.call('$label $tested/$total');
        },
      );
      if (hits.isEmpty) {
        return (server: null, error: 'no endpoint found');
      }
      final candidateEndpoints = hits.take(4).map((h) => h.endpoint.toString()).toList();
      onProgress?.call(
          'Got ${hits.length} UDP hits; will verify top ${candidateEndpoints.length} via chain');

      // 2) OUTER + 3) INNER — یک‌بار register، بعد verify روی endpoint های مختلف
      onProgress?.call('Registering outer WARP...');
      final outerKp = await _generateX25519();
      final outerReg = await _register(
        outerKp.publicKeyB64,
        proxySocksPort: proxySocksPort,
      );
      if (outerReg.error != null || outerReg.account == null) {
        return (
          server: null,
          error: 'outer: ${outerReg.error ?? "no account"}',
        );
      }

      onProgress?.call('Registering inner WARP with license...');
      final innerKp = await _generateX25519();
      final innerReg = await _register(
        innerKp.publicKeyB64,
        proxySocksPort: proxySocksPort,
        license: lic,
      );
      if (innerReg.error != null || innerReg.account == null) {
        return (
          server: null,
          error: 'inner: ${innerReg.error ?? "no account"}',
        );
      }

      // 4) Verify هر endpoint با chain واقعی
      String? chosenEndpoint;
      int? chosenMs;
      for (var i = 0; i < candidateEndpoints.length; i++) {
        final ep = candidateEndpoints[i];
        onProgress?.call(
            'Verify chain $ep (${i + 1}/${candidateEndpoints.length})');

        final outerLink = _buildVpnLinkFromAccount(
          privateKeyB64: outerKp.privateKeyB64,
          account: outerReg.account!,
          endpoint: ep,
          description: 'WARP outer',
        );
        final innerLink = _buildVpnLinkFromAccount(
          privateKeyB64: innerKp.privateKeyB64,
          account: innerReg.account!,
          endpoint: ep,
          description: 'WARP inner (Plus)',
        );

        final chainLink = Uri(
          scheme: 'chain',
          host: 'config',
          queryParameters: <String, String>{
            'first': outerLink,
            'second': innerLink,
            'name': 'WARP+ 2-hop verify',
          },
        ).toString();

        final hostPort = ep.split(':');
        final testServer = VpnServer(
          id: 'warp_plus_verify_$i',
          name: 'WARP+ verify',
          flag: '\u{1F310}',
          shareLink: chainLink,
          protocol: VpnProtocol.chain,
          host: hostPort.first,
          port: int.tryParse(hostPort.length > 1 ? hostPort[1] : '2408') ?? 2408,
          isDeletable: false,
        );

        try {
          await V2RayEngine.disconnect();
          await Future<void>.delayed(const Duration(milliseconds: 250));

          final ok = await V2RayEngine
              .connect(testServer)
              .timeout(const Duration(seconds: 12), onTimeout: () => false);
          if (ok) {
            final ms = await V2RayEngine
                .connectedDelay(timeout: const Duration(seconds: 6))
                .timeout(const Duration(seconds: 8), onTimeout: () => -1);
            if (ms > 0) {
              chosenEndpoint = ep;
              chosenMs = ms;
              onProgress?.call('Chain works on $ep ($ms ms)');
              break;
            }
          }
          onProgress?.call('Chain rejected $ep');
        } catch (e) {
          debugPrint('chain verify $ep error: $e');
        } finally {
          try {
            await V2RayEngine.disconnect();
          } catch (_) {}
          await Future<void>.delayed(const Duration(milliseconds: 200));
        }
      }

      // اگه هیچ کدوم verify نشد، اولین UDP hit رو استفاده کن
      final endpoint = chosenEndpoint ?? candidateEndpoints.first;
      if (chosenMs != null) {
        onProgress?.call('Selected verified endpoint $endpoint ($chosenMs ms)');
      } else {
        onProgress?.call('No endpoint verified; using first UDP hit $endpoint');
      }

      // ساخت لینک‌های نهایی با endpoint انتخاب‌شده
      final finalOuterLink = _buildVpnLinkFromAccount(
        privateKeyB64: outerKp.privateKeyB64,
        account: outerReg.account!,
        endpoint: endpoint,
        description: 'WARP outer',
      );
      final finalInnerLink = _buildVpnLinkFromAccount(
        privateKeyB64: innerKp.privateKeyB64,
        account: innerReg.account!,
        endpoint: endpoint,
        description: 'WARP inner (Plus)',
      );

      // 5) chain:// نهایی — outer اول (dialer)، inner دوم (exit)
      onProgress?.call('Building chain config...');
      final chainLink = Uri(
        scheme: 'chain',
        host: 'config',
        queryParameters: <String, String>{
          'first': finalOuterLink,
          'second': finalInnerLink,
          'name': 'WARP+ 2-hop',
        },
      ).toString();

      final host = endpoint.split(':').first;
      final port = int.tryParse(endpoint.split(':').last) ?? _warpPort;

      final server = VpnServer(
        id: 'warp_plus_chain_${DateTime.now().millisecondsSinceEpoch}',
        name: 'WARP+ · 2-hop · $host',
        flag: '\u{1F310}',
        shareLink: chainLink,
        protocol: VpnProtocol.chain,
        host: host,
        port: port,
        isDeletable: true,
        warpEndpointMode: mode.label,
      );
      return (server: server, error: null);
    } catch (e) {
      return (server: null, error: e.toString());
    }
  }
}

/// وضعیت زنده اسکن endpoint — قابل listen در UI.
class WarpScanState {
  final String phase;
  final int tested;
  final int total;
  final String? lastEndpoint;
  final int? lastMs;
  final bool done;
  final String? error;

  const WarpScanState({
    this.phase = '',
    this.tested = 0,
    this.total = 0,
    this.lastEndpoint,
    this.lastMs,
    this.done = false,
    this.error,
  });

  WarpScanState copyWith({
    String? phase,
    int? tested,
    int? total,
    String? lastEndpoint,
    int? lastMs,
    bool? done,
    String? error,
    bool clearError = false,
  }) =>
      WarpScanState(
        phase: phase ?? this.phase,
        tested: tested ?? this.tested,
        total: total ?? this.total,
        lastEndpoint: lastEndpoint ?? this.lastEndpoint,
        lastMs: lastMs ?? this.lastMs,
        done: done ?? this.done,
        error: clearError ? null : (error ?? this.error),
      );

  double get progress => total > 0 ? tested / total : 0.0;
  bool get active => !done && phase.isNotEmpty;
}

class _WgKeys {
  final String privateKey;
  final String publicKey;
  const _WgKeys({required this.privateKey, required this.publicKey});
}
