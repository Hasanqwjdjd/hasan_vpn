import 'dart:convert';

import '../models/server.dart';

/// فرمت فشرده برای اشتراک‌گذاری WARP / WARP Plus / WARP MASQUE بین دستگاه‌ها.
///
/// سرورهای معمولی (vless/vmess/...) همون shareLink استاندارد رو دارن که
/// کوتاهه. ولی chain:// دو-hop که برای WARP Plus ساخته می‌شه دو تا vpn://
/// طولانی رو تودرتو embed می‌کنه (~1100 کاراکتر) که برای QR بزرگ می‌شه.
///
/// این codec برای این سه نوع یه URI فشرده می‌سازه:
///   hasan-warp://m?d=<b64>             ← MASQUE
///   hasan-warp://w?d=<b64>             ← WireGuard تک‌هاپ
///   hasan-warp://p?o=<b64>&i=<b64>     ← Plus 2-hop (outer + inner)
///
/// دیتای b64 شده = فیلدهای ضروری به‌شکل pipe-separated، بدون overhead JSON.
class WarpShareCodec {
  WarpShareCodec._();

  static const String prefix = 'hasan-warp://';
  static const String version = '1';

  /// آیا این سرور باید با codec فشرده به اشتراک گذاشته بشه؟
  static bool shouldEncode(VpnServer server) {
    if (server.protocol == VpnProtocol.warpMasque) return true;
    if (server.protocol == VpnProtocol.amneziaWg) return true;
    if (server.protocol == VpnProtocol.chain) {
      final link = server.shareLink;
      // فقط اگه chain شامل vpn:// باشه (WARP Plus 2-hop)
      return link.contains('vpn%3A%2F%2F') || link.contains('vpn://');
    }
    return false;
  }

  /// کدگذاری سرور به URI فشرده. اگه پشتیبانی نشه `null`.
  static String? encode(VpnServer server) {
    if (server.protocol == VpnProtocol.warpMasque) {
      return _encodeMasque(server);
    }
    if (server.protocol == VpnProtocol.amneziaWg) {
      return _encodeWireGuard(server);
    }
    if (server.protocol == VpnProtocol.chain) {
      return _encodePlus(server);
    }
    return null;
  }

  /// دیکد از URI فشرده. اگر فرمت ناشناخته باشه `null`.
  static VpnServer? decode(String link, {required String id}) {
    final text = link.trim();
    if (!text.startsWith(prefix)) return null;
    try {
      final uri = Uri.parse(text);
      final kind = uri.host;
      final q = uri.queryParameters;
      switch (kind) {
        case 'm':
          return _decodeMasque(q, id);
        case 'w':
          return _decodeWireGuard(q, id);
        case 'p':
          return _decodePlus(q, id);
        default:
          return null;
      }
    } catch (_) {
      return null;
    }
  }

  // ── MASQUE ─────────────────────────────────────────────────

  static String _encodeMasque(VpnServer server) {
    final params = _parseMasqueParams(server.shareLink);
    if (params == null) return server.shareLink;
    final payload = [
      params.endpoint,
      params.sni,
      params.dns,
      params.http2 ? '1' : '0',
      server.displayName,
      params.candidates ?? '',
    ].join('|');
    return Uri(
      scheme: 'hasan-warp',
      host: 'm',
      queryParameters: <String, String>{'d': _b64(payload)},
    ).toString();
  }

  static VpnServer? _decodeMasque(Map<String, String> q, String id) {
    final payload = _unb64(q['d'] ?? '');
    if (payload == null) return null;
    final parts = payload.split('|');
    if (parts.length < 4) return null;
    final endpoint = parts[0];
    final sni = parts[1];
    final dns = parts[2];
    final http2 = parts[3] == '1';
    final name = parts.length > 4 && parts[4].isNotEmpty
        ? parts[4]
        : 'WARP MASQUE · $endpoint';
    // v2: candidates اختیاری (سازگار با v1 که نداره)
    final candidates = parts.length > 5 ? parts[5] : '';

    final internal = <String, String>{
      'endpoint': endpoint,
      'sni': sni,
      'dns': dns,
      'h2': http2 ? '1' : '0',
      if (candidates.isNotEmpty) 'candidates': candidates,
      'name': name,
    };
    final rebuilt = Uri(
      scheme: 'warpmasque',
      host: 'config',
      queryParameters: internal,
    ).toString();

    final hostPort = endpoint.split(':');
    final host = hostPort.first;
    final port = int.tryParse(hostPort.length > 1 ? hostPort[1] : '443') ?? 443;

    return VpnServer(
      id: id,
      name: name,
      flag: '\u{1F310}',
      shareLink: rebuilt,
      protocol: VpnProtocol.warpMasque,
      host: host,
      port: port,
      sniOrHost: sni,
      warpMasqueEndpointCandidates:
          candidates.isEmpty ? null : candidates,
      isDeletable: true,
    );
  }

  static _MasqueParams? _parseMasqueParams(String link) {
    try {
      final uri = Uri.parse(link);
      if (uri.scheme != 'warpmasque' && uri.scheme != 'wmq') return null;
      final q = uri.queryParameters;
      final candidates = (q['candidates'] ?? q['cn'] ?? '').trim();
      return _MasqueParams(
        endpoint: (q['endpoint'] ?? q['ep'] ?? '162.159.198.238:443').trim(),
        sni: (q['sni'] ?? 'soft98.ir').trim(),
        dns: (q['dns'] ?? '1.1.1.1,1.0.0.1').trim(),
        http2: (q['h2'] ?? '1') == '1',
        candidates: candidates.isEmpty ? null : candidates,
      );
    } catch (_) {
      return null;
    }
  }

  // ── WireGuard تک‌هاپ ───────────────────────────────────────

  static String _encodeWireGuard(VpnServer server) {
    final inner = _extractWireGuardFields(server.shareLink);
    if (inner == null) return server.shareLink;
    final payload = [
      inner.privateKey,
      inner.publicKey,
      inner.endpoint,
      inner.address,
      inner.reserved ?? '',
      inner.mtu?.toString() ?? '',
      server.displayName,
    ].join('|');
    return Uri(
      scheme: 'hasan-warp',
      host: 'w',
      queryParameters: <String, String>{'d': _b64(payload)},
    ).toString();
  }

  static VpnServer? _decodeWireGuard(Map<String, String> q, String id) {
    final payload = _unb64(q['d'] ?? '');
    if (payload == null) return null;
    final parts = payload.split('|');
    if (parts.length < 5) return null;

    final privateKey = parts[0];
    final publicKey = parts[1];
    final endpoint = parts[2];
    final address = parts[3];
    final reserved = parts[4];
    final mtu = parts.length > 5 ? int.tryParse(parts[5]) : null;
    final name = parts.length > 6 && parts[6].isNotEmpty
        ? parts[6]
        : 'WARP';

    final hostPort = endpoint.split(':');
    final host = hostPort.first;
    final port = int.tryParse(hostPort.length > 1 ? hostPort[1] : '2408') ?? 2408;

    // rebuild vpn:// link
    final lastCfg = jsonEncode(<String, dynamic>{
      'interface': <String, dynamic>{
        'private_key': privateKey,
        'address': address,
        'dns': '1.1.1.1',
        'mtu': mtu ?? 1280,
      },
      'peer': <String, dynamic>{
        'public_key': publicKey,
        'endpoint': endpoint,
        'allowed_ips': <String>['0.0.0.0/0', '::/0'],
        if (reserved.isNotEmpty)
          'reserved':
              reserved.split(',').map((e) => int.tryParse(e) ?? 0).toList(),
      },
    });
    final outer = <String, dynamic>{
      'hostName': host,
      'description': name,
      'containers': <dynamic>[
        <String, dynamic>{
          'awg': <String, dynamic>{
            'port': '$port',
            'last_config': lastCfg,
            'mtu': '1280',
          },
        },
      ],
    };
    final rawB64 = base64.encode(utf8.encode(jsonEncode(outer)));

    return VpnServer(
      id: id,
      name: name,
      flag: '\u{1F310}',
      shareLink: 'vpn://$rawB64',
      protocol: VpnProtocol.amneziaWg,
      host: host,
      port: port,
      isDeletable: true,
    );
  }

  static _WgFields? _extractWireGuardFields(String link) {
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

      String s(dynamic v) => v?.toString().trim() ?? '';
      final reservedRaw = s(peer['reserved']);
      return _WgFields(
        privateKey: s(iface['private_key'] ?? iface['privateKey']),
        publicKey: s(peer['public_key'] ?? peer['publicKey']),
        endpoint: s(peer['endpoint']),
        address: s(iface['address']),
        reserved: reservedRaw.isEmpty ? null : reservedRaw,
        mtu: int.tryParse(s(iface['mtu'] ?? '1280')),
      );
    } catch (_) {
      return null;
    }
  }

  // ── Plus 2-hop ─────────────────────────────────────────────

  static String _encodePlus(VpnServer server) {
    try {
      final uri = Uri.parse(server.shareLink);
      if (uri.scheme != 'chain') return server.shareLink;
      // پشتیبانی N-hop (`hops`) و 2-hop (`first`+`second`)
      final rawHops = uri.queryParameters['hops'] ?? '';
      final List<String> hopLinks;
      if (rawHops.isNotEmpty) {
        hopLinks = rawHops
            .split(',')
            .map((s) => s.trim())
            .where((s) => s.isNotEmpty)
            .toList();
      } else {
        final first = uri.queryParameters['first'] ?? '';
        final second = uri.queryParameters['second'] ?? '';
        if (first.isEmpty || second.isEmpty) return server.shareLink;
        hopLinks = [first, second];
      }
      if (hopLinks.length < 2) return server.shareLink;

      // استخراج payload برای هر hop
      final payloads = <String>[];
      for (final link in hopLinks) {
        final fields = _extractWireGuardFields(link);
        if (fields == null) return server.shareLink;
        payloads.add([
          fields.privateKey,
          fields.publicKey,
          fields.endpoint,
          fields.address,
          fields.reserved ?? '',
        ].join('|'));
      }

      // encode همه hop ها با کلید h0, h1, h2, ...
      final q = <String, String>{
        'n': server.displayName,
        'c': payloads.length.toString(),
      };
      for (var i = 0; i < payloads.length; i++) {
        q['h${i}'] = _b64(payloads[i]);
      }
      return Uri(
        scheme: 'hasan-warp',
        host: 'p',
        queryParameters: q,
      ).toString();
    } catch (_) {
      return server.shareLink;
    }
  }

  static VpnServer? _decodePlus(Map<String, String> q, String id) {
    // فرمت v2: `h0`, `h1`, ... + `c` (count)
    // فرمت v1: `o` (outer) + `i` (inner)
    final List<String> hopLinks = [];

    final countStr = q['c'];
    if (countStr != null) {
      final count = int.tryParse(countStr) ?? 0;
      if (count < 2 || count > 8) return null;
      for (var i = 0; i < count; i++) {
        final payload = _unb64(q['h${i}'] ?? '');
        if (payload == null) return null;
        final link = _wgPayloadToVpnLink(payload);
        if (link == null) return null;
        hopLinks.add(link);
      }
    } else {
      // v1
      final oPayload = _unb64(q['o'] ?? '');
      final iPayload = _unb64(q['i'] ?? '');
      if (oPayload == null || iPayload == null) return null;
      final outerLink = _wgPayloadToVpnLink(oPayload);
      final innerLink = _wgPayloadToVpnLink(iPayload);
      if (outerLink == null || innerLink == null) return null;
      hopLinks.add(outerLink);
      hopLinks.add(innerLink);
    }

    if (hopLinks.length < 2) return null;

    final name = (q['n'] ?? '').trim();
    final display = name.isEmpty
        ? 'WARP+ ${hopLinks.length}-hop'
        : name;

    // برای 2-hop از first/second استفاده کن (سازگاری)
    // برای N-hop از hops استفاده کن
    final Map<String, String> chainParams;
    if (hopLinks.length == 2) {
      chainParams = <String, String>{
        'first': hopLinks[0],
        'second': hopLinks[1],
        'name': display,
      };
    } else {
      chainParams = <String, String>{
        'hops': hopLinks.join(','),
        'name': display,
      };
    }

    final chainLink = Uri(
      scheme: 'chain',
      host: 'config',
      queryParameters: chainParams,
    ).toString();

    // host/port از outer وام می‌گیریم.
    final outerFields = _extractWireGuardFields(hopLinks.first);
    final hostPort =
        (outerFields?.endpoint ?? '162.159.192.1:2408').split(':');
    final host = hostPort.first;
    final port =
        int.tryParse(hostPort.length > 1 ? hostPort[1] : '2408') ?? 2408;

    return VpnServer(
      id: id,
      name: display,
      flag: '\u{1F310}',
      shareLink: chainLink,
      protocol: VpnProtocol.chain,
      host: host,
      port: port,
      isDeletable: true,
    );
  }

  static String? _wgPayloadToVpnLink(String payload) {
    final parts = payload.split('|');
    if (parts.length < 4) return null;
    final privateKey = parts[0];
    final publicKey = parts[1];
    final endpoint = parts[2];
    final address = parts[3];
    final reserved = parts.length > 4 ? parts[4] : '';
    if (privateKey.isEmpty || publicKey.isEmpty || endpoint.isEmpty) {
      return null;
    }
    final lastCfg = jsonEncode(<String, dynamic>{
      'interface': <String, dynamic>{
        'private_key': privateKey,
        'address': address.isEmpty ? '172.16.0.2/32' : address,
        'dns': '1.1.1.1',
        'mtu': 1280,
      },
      'peer': <String, dynamic>{
        'public_key': publicKey,
        'endpoint': endpoint,
        'allowed_ips': <String>['0.0.0.0/0', '::/0'],
        if (reserved.isNotEmpty)
          'reserved':
              reserved.split(',').map((e) => int.tryParse(e) ?? 0).toList(),
      },
    });
    final host = endpoint.split(':').first;
    final port = int.tryParse(endpoint.split(':').last) ?? 2408;
    final outer = <String, dynamic>{
      'hostName': host,
      'description': 'WARP',
      'containers': <dynamic>[
        <String, dynamic>{
          'awg': <String, dynamic>{
            'port': '$port',
            'last_config': lastCfg,
            'mtu': '1280',
          },
        },
      ],
    };
    final rawB64 = base64.encode(utf8.encode(jsonEncode(outer)));
    return 'vpn://$rawB64';
  }

  // ── Base64 URL-safe helpers ────────────────────────────────

  static String _b64(String value) => base64
      .encode(utf8.encode(value))
      .replaceAll('+', '-')
      .replaceAll('/', '_')
      .replaceAll('=', '');

  static String? _unb64(String encoded) {
    try {
      var normalized = encoded.replaceAll('-', '+').replaceAll('_', '/');
      final pad = (4 - normalized.length % 4) % 4;
      normalized = normalized.padRight(normalized.length + pad, '=');
      return utf8.decode(base64.decode(normalized), allowMalformed: true);
    } catch (_) {
      return null;
    }
  }
}

class _MasqueParams {
  final String endpoint;
  final String sni;
  final String dns;
  final bool http2;
  final String? candidates;
  const _MasqueParams({
    required this.endpoint,
    required this.sni,
    required this.dns,
    required this.http2,
    this.candidates,
  });
}

class _WgFields {
  final String privateKey;
  final String publicKey;
  final String endpoint;
  final String address;
  final String? reserved;
  final int? mtu;
  const _WgFields({
    required this.privateKey,
    required this.publicKey,
    required this.endpoint,
    required this.address,
    this.reserved,
    this.mtu,
  });
}
