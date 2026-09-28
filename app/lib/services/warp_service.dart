import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/server.dart';

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
  static Future<({VpnServer? server, String? error})> generate({
    bool plus = false,
    String? proxySocksPort,
    String? endpointOverride,
    int? scanTimeoutMs,
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

      // 3) اسکن edge — سریع‌ترین IP
      String chosenEndpoint = endpointOverride ?? '';
      if (chosenEndpoint.isEmpty) {
        onProgress?.call('Scanning edge IPs...');
        final fastest = await _scanFastest(
          timeoutMs: scanTimeoutMs ?? 1500,
          onProgress: onProgress,
        );
        chosenEndpoint = fastest ?? '$peerEndpoint:$_warpPort';
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
        'port': '\$port',
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
    return 'vpn://\$rawB64';
  }

  /// ساخت WARP Plus 2-hop — Outer (بدون license) + Inner (با license).
  /// خروجی یک chain:// است که توی _buildChainConfig تبدیل به دو outbound
  /// wireguard می‌شود (outer اول، inner دوم).
  static Future<({VpnServer? server, String? error})> generatePlusChain({
    required String license,
    String? proxySocksPort,
    void Function(String msg)? onProgress,
  }) async {
    try {
      final lic = license.trim();
      if (lic.isEmpty) {
        return (server: null, error: 'license is required');
      }

      // 1) endpoint — یک بار برای هر دو hop
      onProgress?.call('Scanning edge IPs...');
      var endpoint = '162.159.192.1:\$_warpPort';
      try {
        final fastest = await _scanFastest(
          timeoutMs: 1500,
          onProgress: onProgress,
        );
        if (fastest != null && fastest.isNotEmpty) endpoint = fastest;
      } catch (_) {}

      // 2) OUTER — keypair تازه، بدون license
      onProgress?.call('Registering outer WARP...');
      final outerKp = await _generateX25519();
      final outerReg = await _register(
        outerKp.publicKeyB64,
        proxySocksPort: proxySocksPort,
      );
      if (outerReg.error != null || outerReg.account == null) {
        return (
          server: null,
          error: 'outer: \${outerReg.error ?? "no account"}',
        );
      }
      final outerLink = _buildVpnLinkFromAccount(
        privateKeyB64: outerKp.privateKeyB64,
        account: outerReg.account!,
        endpoint: endpoint,
        description: 'WARP outer',
      );

      // 3) INNER — keypair تازه + license
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
          error: 'inner: \${innerReg.error ?? "no account"}',
        );
      }
      final innerLink = _buildVpnLinkFromAccount(
        privateKeyB64: innerKp.privateKeyB64,
        account: innerReg.account!,
        endpoint: endpoint,
        description: 'WARP inner (Plus)',
      );

      // 4) chain:// — outer اول (dialer)، inner دوم (exit)
      onProgress?.call('Building chain config...');
      final chainLink = Uri(
        scheme: 'chain',
        host: 'config',
        queryParameters: <String, String>{
          'first': outerLink,
          'second': innerLink,
          'name': 'WARP+ 2-hop',
        },
      ).toString();

      final host = endpoint.split(':').first;
      final port = int.tryParse(endpoint.split(':').last) ?? _warpPort;

      final server = VpnServer(
        id: 'warp_plus_chain_\${DateTime.now().millisecondsSinceEpoch}',
        name: 'WARP+ · 2-hop · \$host',
        flag: '\u{1F310}',
        shareLink: chainLink,
        protocol: VpnProtocol.chain,
        host: host,
        port: port,
        isDeletable: true,
      );
      return (server: server, error: null);
    } catch (e) {
      return (server: null, error: e.toString());
    }
  }
}
