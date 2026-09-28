import 'dart:convert';

import '../models/server.dart';
import 'xray_json.dart';
import 'warp_share_codec.dart';

/// تجزیه‌ی لینک‌های اشتراک‌گذاری (vless / vmess / trojan / ss / hysteria2 / custom / aether / xrayjson)
/// و همچنین کانفیگ خام JSON هسته Xray به [VpnServer].
class LinkParser {
  LinkParser._();

  static const List<String> supportedSchemes = <String>[
    'vless',
    'vmess',
    'trojan',
    'ss',
    'hysteria2',
    'hy2',
    'aether',
    'custom',
    'xrayjson',
    'ssd',
    'vpn',
    'ssh',
    'masterdns',
    'mdns',
    'warpmasque',
    'wmq',
  ];

  static final RegExp linkRegex = RegExp(
    r'(?:vless|vmess|trojan|ss|ssd|vpn|ssh|masterdns|mdns|warpmasque|wmq|hasan-warp|hysteria2|hy2|aether|custom|xrayjson)://[^\s"<>\\]+',
    caseSensitive: false,
  );

  static bool isSupportedLink(String link) {
    final value = link.trim();
    final lower = value.toLowerCase();
    if (supportedSchemes.any((scheme) => lower.startsWith('$scheme://'))) {
      return true;
    }
    // کانفیگ خام JSON (Patterniha و مشابه)
    return XrayJson.looksLike(value);
  }

  /// همه‌ی لینک‌های پشتیبانی‌شده‌ی داخل یک متن (بدون تکرار، با حفظ ترتیب).
  static List<String> extractLinks(String text) {
    final seen = <String>{};
    final result = <String>[];
    for (final match in linkRegex.allMatches(text)) {
      final link = match.group(0)?.trim();
      if (link == null || link.isEmpty) continue;
      if (seen.add(link)) result.add(link);
    }
    return result;
  }

  /// شناسه‌ی پایدار بر اساس خود لینک.
  static String stableId(String prefix, String link) {
    var hash = 0x811c9dc5;
    for (final unit in link.trim().codeUnits) {
      hash ^= unit;
      hash = (hash * 0x01000193) & 0xFFFFFFFF;
    }
    return '${prefix}_${hash.toRadixString(16)}';
  }

  /// پارس چند-سروری: برای ssd:// چند سرور برمی‌گردونه، برای بقیه تک سرور.
  static List<VpnServer> parseMany(String rawLink, {required String id}) {
    final link = rawLink.trim();
    final lower = link.toLowerCase();
    if (lower.startsWith('ssd://')) {
      return parseSsd(link, id);
    }
    final one = parse(link, id: id);
    return one == null ? <VpnServer>[] : <VpnServer>[one];
  }

  static VpnServer? parse(String rawLink, {required String id}) {
    try {
      final link = rawLink.trim();

      // کانفیگ خام JSON یا لینک xrayjson://
      if (XrayJson.looksLike(link) ||
          link.toLowerCase().startsWith('xrayjson://')) {
        return XrayJson.parse(link, id: id);
      }

      final sep = link.indexOf('://');
      if (sep <= 0) return null;

      final scheme = link.substring(0, sep).toLowerCase();

      // hasan-warp:// — کدگذاری فشرده WARP/MASQUE/Plus
      if (scheme == 'hasan-warp') {
        final decoded = WarpShareCodec.decode(link, id: id);
        if (decoded != null) return decoded;
        return null;
      }

      switch (scheme) {
        case 'vmess':
          return _parseVmess(link, id);
        case 'ss':
          return _parseShadowsocks(link, id);
        case 'aether':
          return _parseAether(link, id);
        case 'custom':
          return _parseCustom(link, id);
        case 'xrayjson':
          return XrayJson.parse(link, id: id);
        case 'vless':
          return _parseUri(link, id, VpnProtocol.vless);
        case 'trojan':
          return _parseUri(link, id, VpnProtocol.trojan);
        case 'hysteria2':
        case 'hy2':
          return _parseUri(link, id, VpnProtocol.hysteria2);
        case 'vpn':
          return _parseVpnLink(link, id);
        case 'ssh':
          return _parseSsh(link, id);
        case 'masterdns':
        case 'mdns':
          return _parseMasterDns(link, id);
        case 'warpmasque':
        case 'wmq':
          return _parseWarpMasque(link, id);
        default:
          return null;
      }
    } catch (_) {
      return null;
    }
  }

  // ---------------------------------------------------------------- generic

  static final RegExp _authorityRegex = RegExp(
    r'^[a-zA-Z0-9+.-]+://(?:[^@/?#]*@)?(\[[^\]]+\]|[^:/?#\[\]]+)(?::(\d+))?',
  );

  /// SSH — فرمت `ssh://user:pass@host:port?params#name` (V2Box) یا
  /// `ssh://user@host:port` با key از query.
  /// پارامترهای query:
  ///   password=xxx یا pwd=xxx
  ///   key=base64(private key PEM)
  ///   socks=1080 (پورت SOCKS روی سرور)
  /// MasterDNS — masterdns://config?domain=...&key=...&method=N&resolvers=...
  /// WARP MASQUE — warpmasque://config?endpoint=host:port&sni=...&dns=...&h2=1
  static VpnServer? _parseWarpMasque(String link, String id) {
    try {
      final uri = Uri.parse(link);
      final q = uri.queryParameters;
      final endpoint =
          (q['endpoint'] ?? q['ep'] ?? '162.159.198.238:443').trim();
      final sni = (q['sni'] ?? 'soft98.ir').trim();
      final dns = (q['dns'] ?? '1.1.1.1,1.0.0.1').trim();
      final h2 = (q['h2'] ?? '1') == '1';

      final name = _cleanName(
        _decode(uri.fragment),
        fallback: 'WARP MASQUE · $endpoint',
      );

      final candidates = (q['candidates'] ?? q['cn'] ?? '').trim();
      final device = (q['device'] ?? q['dn'] ?? '').trim();

      final internal = <String, String>{
        'endpoint': endpoint,
        'sni': sni,
        'dns': dns,
        'h2': h2 ? '1' : '0',
        if (candidates.isNotEmpty) 'candidates': candidates,
        if (device.isNotEmpty) 'device': device,
        if (name.isNotEmpty) 'name': name,
      };
      final rebuilt = Uri(
        scheme: 'warpmasque',
        host: 'config',
        queryParameters: internal,
      );

      final hostPort = endpoint.split(':');
      final host = hostPort.first;
      final port =
          int.tryParse(hostPort.length > 1 ? hostPort[1] : '443') ?? 443;

      return VpnServer(
        id: id,
        name: name,
        flag: '\u{1F310}',
        shareLink: rebuilt.toString(),
        protocol: VpnProtocol.warpMasque,
        host: host,
        port: port,
        sniOrHost: sni,
        warpMasqueEndpointCandidates: candidates.isEmpty ? null : candidates,
      );
    } catch (_) {
      return null;
    }
  }

  static VpnServer? _parseMasterDns(String link, String id) {
    try {
      final uri = Uri.parse(link);
      final q = uri.queryParameters;
      final domain = (q['domain'] ?? '').trim();
      final key = (q['key'] ?? '').trim();
      if (domain.isEmpty || key.isEmpty) return null;
      final method = int.tryParse(q['method'] ?? '1')?.clamp(0, 5) ?? 1;
      final resolvers = (q['resolvers'] ?? '').trim();
      final advanced = (q['advanced'] ?? '').trim();

      final name = _cleanName(
        _decode(uri.fragment),
        fallback: 'MasterDNS · $domain',
      );

      final internal = <String, String>{
        'domain': domain,
        'key': key,
        'method': '$method',
        if (resolvers.isNotEmpty) 'resolvers': resolvers,
        if (advanced.isNotEmpty) 'advanced': advanced,
        if (name.isNotEmpty) 'name': name,
      };
      final rebuilt = Uri(
        scheme: 'masterdns',
        host: 'config',
        queryParameters: internal,
      );

      return VpnServer(
        id: id,
        name: name,
        flag: '\u{1F5FA}',
        shareLink: rebuilt.toString(),
        protocol: VpnProtocol.masterdns,
        host: domain,
        port: 0,
        sniOrHost: domain,
      );
    } catch (_) {
      return null;
    }
  }

  static VpnServer? _parseSsh(String link, String id) {
    try {
      final uri = Uri.parse(link);
      final host = uri.host;
      if (host.isEmpty) return null;
      final port = uri.hasPort ? uri.port : 22;
      final q = uri.queryParameters;

      final user = uri.userInfo.isNotEmpty
          ? Uri.decodeComponent(uri.userInfo.split(':').first)
          : (q['user'] ?? '');
      final passFromUri = uri.userInfo.contains(':')
          ? Uri.decodeComponent(uri.userInfo.split(':').sublist(1).join(':'))
          : '';
      final password = passFromUri.isNotEmpty
          ? passFromUri
          : (q['password'] ?? q['pwd'] ?? '');
      final keyB64 = q['key'] ?? '';
      final socksPort =
          int.tryParse(q['socks'] ?? q['socksPort'] ?? '1080') ?? 1080;

      final name = _cleanName(
        _decode(uri.fragment),
        fallback: 'SSH · $host',
      );

      // FIX: خروجی با فرمت داخلی SshProfile.toLink() هماهنگ بشه:
      // ssh://config?host=...&port=...&user=...&pass=...&key=...&socks=...&name=...
      final internal = <String, String>{
        'host': host,
        'port': '$port',
        'user': user,
        if (password.isNotEmpty) 'pass': password,
        if (keyB64.isNotEmpty) 'key': keyB64,
        if (socksPort != 1080) 'socks': '$socksPort',
        if (name.isNotEmpty) 'name': name,
      };
      final rebuiltUri = Uri(
        scheme: 'ssh',
        host: 'config',
        queryParameters: internal,
      );

      return VpnServer(
        id: id,
        name: name,
        flag: guessFlag(name),
        shareLink: rebuiltUri.toString(),
        protocol: VpnProtocol.ssh,
        host: host,
        port: port,
      );
    } catch (_) {
      return null;
    }
  }

  /// Amnezia `vpn://` — base64 از یه JSON با containers[].awg.last_config.
  /// last_config خودش یه JSON string از interface/peer WireGuard هست.
  static VpnServer? _parseVpnLink(String link, String id) {
    try {
      final body = link.substring(link.indexOf('://') + 3);
      // حذف fragment/query احتمالی
      final clean = body.split('#').first.split('?').first.trim();
      final decoded = utf8.decode(_b64(clean), allowMalformed: true);
      final json = jsonDecode(decoded);
      if (json is! Map) return null;

      final host = (json['hostName'] ?? '').toString().trim();
      if (host.isEmpty) return null;

      // اولین container از نوع awg رو پیدا کن
      Map? awg;
      final containers = json['containers'];
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

      // last_config خودش یه JSON string هست
      dynamic inner;
      try {
        inner = jsonDecode(lastCfg);
      } catch (_) {
        return null;
      }
      if (inner is! Map) return null;

      final iface = inner['interface'];
      final peer = inner['peer'];
      if (peer is! Map) return null;
      final port = int.tryParse((awg['port'] ?? '51820').toString()) ?? 51820;

      final name = _cleanName(
        (json['description'] ?? '').toString(),
        fallback: 'AmneziaWG · $host',
      );

      // کل JSON رو دوباره base64 می‌کنیم که موقع اتصال بتونیم بازیابی کنیم
      final rawB64 = base64.encode(utf8.encode(decoded));

      return VpnServer(
        id: id,
        name: name,
        flag: guessFlag(name),
        shareLink: 'vpn://$rawB64',
        protocol: VpnProtocol.amneziaWg,
        host: host,
        port: port,
        sniOrHost: (peer['endpoint'] ?? '').toString(),
      );
    } catch (_) {
      return null;
    }
  }

  /// ssd:// (ShadowsocksDroid) — base64 JSON با servers[]. چند سرور برمی‌گردونه.
  static List<VpnServer> parseSsd(String link, String idPrefix) {
    final out = <VpnServer>[];
    try {
      final body = link.substring(link.indexOf('://') + 3);
      final clean = body.split('#').first.split('?').first.trim();
      final decoded = utf8.decode(_b64(clean), allowMalformed: true);
      final json = jsonDecode(decoded);
      if (json is! Map) return out;

      final servers = json['servers'];
      if (servers is! List) return out;

      final defaultPort =
          int.tryParse((json['port'] ?? '443').toString()) ?? 443;
      final defaultEnc = (json['encryption'] ?? 'aes-256-gcm').toString();
      final defaultPwd = (json['password'] ?? '').toString();
      final groupName = (json['airport'] ?? 'SSD').toString();

      for (var i = 0; i < servers.length; i++) {
        final s = servers[i];
        if (s is! Map) continue;
        final host = (s['server'] ?? '').toString().trim();
        if (host.isEmpty) continue;
        final port =
            int.tryParse((s['port'] ?? defaultPort).toString()) ?? defaultPort;
        final enc = (s['encryption'] ?? defaultEnc).toString();
        final pwd = (s['password'] ?? defaultPwd).toString();
        final remarks = (s['remarks'] ?? '').toString().trim();

        // لینک استاندارد ss://userinfo@host:port#name
        // userinfo = base64(method:password)
        final userInfo =
            base64.encode(utf8.encode('$enc:$pwd')).replaceAll('=', '');
        final tag = remarks.isEmpty ? '$groupName #$i' : '$groupName · $remarks';
        final ssLink = 'ss://$userInfo@$host:$port#${Uri.encodeComponent(tag)}';

        final srv = _parseShadowsocks(ssLink, '${idPrefix}_$i');
        if (srv != null) out.add(srv);
      }
    } catch (_) {}
    return out;
  }

  static VpnServer? _parseUri(String link, String id, VpnProtocol protocol) {
    final scheme = link.substring(0, link.indexOf('://')).toLowerCase();

    String host = '';
    int port = 443;
    String fragment = '';
    Map<String, String> query = const <String, String>{};

    final uri = Uri.tryParse(link);
    if (uri != null && uri.host.isNotEmpty) {
      host = uri.host;
      if (uri.hasPort && _validPort(uri.port)) port = uri.port;
      fragment = uri.fragment;
      try {
        query = uri.queryParameters;
      } catch (_) {}
    } else {
      final match = _authorityRegex.firstMatch(link);
      if (match == null) return null;
      host = (match.group(1) ?? '').replaceAll(RegExp(r'^\[|\]$'), '');
      final parsedPort = int.tryParse(match.group(2) ?? '');
      if (_validPort(parsedPort)) port = parsedPort!;
      final hash = link.indexOf('#');
      if (hash >= 0) fragment = link.substring(hash + 1);
    }

    if (host.isEmpty) return null;

    final name = _cleanName(
      _decode(fragment),
      fallback: '$scheme://$host',
    );

    final sni = query['sni'] ?? query['host'] ?? host;
    final correctSni = _railwaySni(host, sni);

    // اگه SNI محاسبه‌شده با query فرق داره، shareLink رو بازنویسی کن تا
    // FlutterVless.parse() دوباره SNI درست رو بخونه. (رفع مشکل Railway)
    var finalLink = link;
    final qSni = query['sni'];
    if (correctSni != null && correctSni != qSni) {
      try {
        final rewritten = applySniOverride(link, correctSni);
        if (rewritten.isNotEmpty) finalLink = rewritten;
      } catch (_) {}
    }

    // FIX: خواندن فیلدهای TLS از query و پر کردن TlsOptions
    final tls = _tlsFromQuery(query);
    final dns = (query['dns'] ?? '').trim();

    // Multi-address failover pool (BackPack-derived).
    // "bk=host1:port1,host2:port2" — additional addresses for the same server.
    final bkRaw = (query['bk'] ?? query['backup'] ?? '').trim();
    final backups = bkRaw
        .split(',')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();

    return VpnServer(
      id: id,
      name: name,
      flag: guessFlag(name),
      shareLink: finalLink,
      protocol: protocol,
      host: host,
      port: port,
      sniOrHost: correctSni,
      tls: tls,
      dns: dns.isEmpty ? null : dns,
      backupAddresses: backups,
    );
  }

  /// خواندن فیلدهای TLS از query string لینک اشتراک.
  /// کلیدهای استاندارد: fp/fingerprint, allowInsecure/insecure, alpn,
  /// cipherSuites, echConfigList, verifyPeerCertByName,
  /// pinnedPeerCertSha256, finalMask, dialMode, browserDialer, targetStrategy.
  static TlsOptions _tlsFromQuery(Map<String, String> q) {
    String? s(String key) {
      final v = q[key];
      if (v == null || v.isEmpty) return null;
      return _decode(v);
    }

    bool b(String key) {
      final v = (q[key] ?? '').toLowerCase();
      return v == '1' || v == 'true' || v == 'yes';
    }

    final fp = s('fp') ?? s('fingerprint');
    final insecure = b('allowInsecure') || b('insecure') || b('skip-cert-verify');

    // FIX (PingNG-style): sni-pool یا sniPool — چند دامنه با کاما جدا
    final sniPoolRaw = s('sni-pool') ?? s('sniPool') ?? '';
    final sniPool = sniPoolRaw
        .split(',')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();

    return TlsOptions(
      fingerprint: fp,
      allowInsecure: insecure,
      alpn: s('alpn'),
      cipherSuites: s('cipherSuites') ?? s('cipher-suites'),
      echConfigList: s('echConfigList') ?? s('ech'),
      verifyPeerCertByName: s('verifyPeerCertByName'),
      pinnedPeerCertSha256: s('pinnedPeerCertSha256') ?? s('pinSHA256'),
      finalMask: s('finalMask') ?? s('final-mask'),
      dialMode: s('dialMode'),
      browserDialer: b('browserDialer'),
      targetStrategy: s('targetStrategy'),
      sniPool: sniPool,
    );
  }

  // ------------------------------------------------------------------ vmess

  static VpnServer? _parseVmess(String link, String id) {
    final body = link.substring(link.indexOf('://') + 3);
    final main = body.split('#').first.trim();

    if (main.contains('@')) {
      return _parseUri(link, id, VpnProtocol.vmess);
    }

    final decoded = utf8.decode(_b64(main), allowMalformed: true);
    final json = jsonDecode(decoded);
    if (json is! Map) return null;

    String s(dynamic v) => v?.toString().trim() ?? '';

    final host = s(json['add']);
    if (host.isEmpty) return null;

    final port = int.tryParse(s(json['port'])) ?? 443;
    final name = _cleanName(s(json['ps']), fallback: 'vmess://$host');
    final sni = s(json['sni']).isNotEmpty
        ? s(json['sni'])
        : (s(json['host']).isNotEmpty ? s(json['host']) : host);

    return VpnServer(
      id: id,
      name: name,
      flag: guessFlag(name),
      shareLink: link,
      protocol: VpnProtocol.vmess,
      host: host,
      port: (port > 0 && port <= 65535) ? port : 443,
      sniOrHost: _railwaySni(host, sni),
    );
  }

  // ------------------------------------------------------------ shadowsocks

  static VpnServer? _parseShadowsocks(String link, String id) {
    var main = link.substring(link.indexOf('://') + 3);
    var name = 'Shadowsocks';

    final hash = main.indexOf('#');
    if (hash >= 0) {
      name = _decode(main.substring(hash + 1));
      main = main.substring(0, hash);
    }

    final query = main.indexOf('?');
    if (query >= 0) main = main.substring(0, query);
    while (main.endsWith('/')) {
      main = main.substring(0, main.length - 1);
    }

    String hostPort;
    final at = main.lastIndexOf('@');
    if (at >= 0) {
      hostPort = main.substring(at + 1);
    } else {
      final decoded = utf8.decode(_b64(main), allowMalformed: true);
      final innerAt = decoded.lastIndexOf('@');
      if (innerAt < 0) return null;
      hostPort = decoded.substring(innerAt + 1);
    }

    final parsed = _parseHostPort(hostPort);
    if (parsed == null) return null;

    final cleanName = _cleanName(name, fallback: 'ss://${parsed.$1}');

    return VpnServer(
      id: id,
      name: cleanName,
      flag: guessFlag(cleanName),
      shareLink: link,
      protocol: VpnProtocol.shadowsocks,
      host: parsed.$1,
      port: parsed.$2,
    );
  }

  // ----------------------------------------------------------------- aether

  static VpnServer? _parseAether(String link, String id) {
    final uri = Uri.tryParse(link);
    final name = _cleanName(
      uri == null ? '' : _decode(uri.fragment),
      fallback: 'Aether',
    );

    return VpnServer(
      id: id,
      name: name,
      flag: '🟣',
      shareLink: link,
      protocol: VpnProtocol.aether,
      host: 'auto-discover',
      port: 0,
    );
  }

  // ------------------------------------------------------------------ custom

  static VpnServer? _parseCustom(String link, String id) {
    try {
      final uri = Uri.tryParse(link);
      if (uri == null) return null;

      final params = uri.queryParameters;
      final host = uri.host.isNotEmpty
          ? uri.host
          : (params['address'] ?? params['host'] ?? '');
      final port = uri.hasPort
          ? uri.port
          : (int.tryParse(params['port'] ?? '') ?? 443);

      if (host.isEmpty) return null;

      final rawName = uri.fragment.isNotEmpty
          ? _decode(uri.fragment)
          : (params['remarks'] ?? params['name'] ?? 'Custom');

      final name = _cleanName(rawName, fallback: 'custom://$host');
      final protocol =
          (params['type'] ?? params['protocol'] ?? '').toLowerCase();

      VpnProtocol vp = VpnProtocol.custom;
      if (protocol.contains('vless')) {
        vp = VpnProtocol.vless;
      } else if (protocol.contains('vmess')) {
        vp = VpnProtocol.vmess;
      } else if (protocol.contains('trojan')) {
        vp = VpnProtocol.trojan;
      } else if (protocol.contains('ss') ||
          protocol.contains('shadowsocks')) {
        vp = VpnProtocol.shadowsocks;
      } else if (protocol.contains('hysteria') ||
          protocol.contains('hy2')) {
        vp = VpnProtocol.hysteria2;
      }

      return VpnServer(
        id: id,
        name: name,
        flag: guessFlag(name),
        shareLink: link,
        protocol: vp,
        host: host,
        port: (port > 0 && port <= 65535) ? port : 443,
        sniOrHost: params['sni'] ?? params['host'] ?? host,
      );
    } catch (_) {
      return null;
    }
  }

  // ---------------------------------------------------------------- helpers

  static (String, int)? _parseHostPort(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return null;

    if (trimmed.startsWith('[')) {
      final close = trimmed.indexOf(']');
      if (close <= 1) return null;
      final host = trimmed.substring(1, close);
      final rest = trimmed.substring(close + 1);
      if (!rest.startsWith(':')) return (host, 443);
      final port = int.tryParse(rest.substring(1));
      return (host, _validPort(port) ? port! : 443);
    }

    final colon = trimmed.lastIndexOf(':');
    if (colon <= 0 || colon == trimmed.length - 1) return (trimmed, 443);

    final host = trimmed.substring(0, colon);
    final port = int.tryParse(trimmed.substring(colon + 1));
    if (!_validPort(port)) return (host, 443);
    return (host, port!);
  }

  static bool _validPort(int? port) =>
      port != null && port > 0 && port <= 65535;

  /// Base64 استاندارد و URL-safe، با یا بدون padding.
  static List<int> _b64(String input) {
    final cleaned = input
        .replaceAll(RegExp(r'\s+'), '')
        .replaceAll('-', '+')
        .replaceAll('_', '/');
    return base64.decode(base64.normalize(cleaned));
  }

  static String _decode(String value) {
    if (value.isEmpty) return value;
    try {
      return Uri.decodeComponent(value);
    } catch (_) {
      return value;
    }
  }

  static String _cleanName(String value, {required String fallback}) {
    var v = value.trim();

    // Patterns from broken subscription remarks / tuple .toString():
    //   (this, 'حسن')   this,'حسن'   this, "حسن"
    final quoted = RegExp(
      r"""(?:^|\b)this\s*,\s*['"]([^'"]+)['"]""",
      caseSensitive: false,
    ).firstMatch(v);
    if (quoted != null && (quoted.group(1) ?? '').isNotEmpty) {
      v = quoted.group(1)!;
    } else {
      final tupleMatch = RegExp(
        r"""^\(\s*(?:this\s*,\s*)?['"]([^'"]*)['"]\s*\)$""",
        caseSensitive: false,
      ).firstMatch(v);
      if (tupleMatch != null && (tupleMatch.group(1) ?? '').isNotEmpty) {
        v = tupleMatch.group(1)!;
      } else {
        v = v.replaceFirst(
            RegExp(r"""^\(\s*[A-Za-z_][A-Za-z0-9_.]*\s*,\s*['"]?"""), '');
        v = v.replaceFirst(RegExp(r"""['"]?\s*\)\s*$"""), '');
        v = v.replaceFirst(
            RegExp(r"""^this\s*,\s*['"]?""", caseSensitive: false), '');
        v = v.replaceFirst(RegExp(r"""['"]\s*$"""), '');
      }
    }

    // Also strip leading "this," without quotes around name
    v = v.replaceFirst(RegExp(r'^this\s*,\s*', caseSensitive: false), '');

    final collapsed = v.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (collapsed.isEmpty) return fallback;
    return collapsed.length > 80 ? collapsed.substring(0, 80) : collapsed;
  }

  // ------------------------------------------------------------------ flags

  static final List<MapEntry<String, RegExp>> _flagRules =
      <MapEntry<String, RegExp>>[
    MapEntry('🇺🇸',
        RegExp(r'united states|\busa\b|\bus\b|america|آمریکا', caseSensitive: false)),
    MapEntry('🇩🇪', RegExp(r'germany|\bde\b|deutsch|آلمان', caseSensitive: false)),
    MapEntry('🇫🇷', RegExp(r'france|\bfr\b|فرانسه', caseSensitive: false)),
    MapEntry('🇬🇧',
        RegExp(r'england|britain|\buk\b|\bgb\b|انگلیس', caseSensitive: false)),
    MapEntry('🇮🇷', RegExp(r'iran|\bir\b|ایران', caseSensitive: false)),
    MapEntry('🇹🇷', RegExp(r'turkey|türk|\btr\b|ترکیه', caseSensitive: false)),
    MapEntry('🇳🇱', RegExp(r'netherland|\bnl\b|هلند', caseSensitive: false)),
    MapEntry('🇯🇵', RegExp(r'japan|\bjp\b|ژاپن', caseSensitive: false)),
    MapEntry('🇭🇰', RegExp(r'hong ?kong|\bhk\b|هنگ ?کنگ', caseSensitive: false)),
    MapEntry('🇸🇬', RegExp(r'singapore|\bsg\b|سنگاپور', caseSensitive: false)),
    MapEntry('🇦🇪',
        RegExp(r'emirates|dubai|\buae\b|امارات', caseSensitive: false)),
    MapEntry('🇷🇺', RegExp(r'russia|\bru\b|روسیه', caseSensitive: false)),
    MapEntry('🇨🇦', RegExp(r'canada|\bca\b|کانادا', caseSensitive: false)),
    MapEntry('🇮🇳', RegExp(r'india|هندوستان', caseSensitive: false)),
    MapEntry('🇰🇷', RegExp(r'korea|\bkr\b|کره', caseSensitive: false)),
    MapEntry('🇦🇺', RegExp(r'australia|\bau\b|استرالیا', caseSensitive: false)),
  ];


  static String? _railwaySni(String host, String? sni) {
    final h = host.toLowerCase();
    if (h.contains('railway.app') || h.contains('up.railway.app')) {
      return host; // SNI + Host must be the railway hostname
    }
    return sni;
  }

  static String guessFlag(String name) {
    final runes = name.runes.toList();
    for (var i = 0; i + 1 < runes.length; i++) {
      final a = runes[i];
      final b = runes[i + 1];
      if (a >= 0x1F1E6 && a <= 0x1F1FF && b >= 0x1F1E6 && b <= 0x1F1FF) {
        return String.fromCharCodes(<int>[a, b]);
      }
    }

    for (final rule in _flagRules) {
      if (rule.value.hasMatch(name)) return rule.key;
    }
    return '🌐';
  }



  /// جایگزینی SNI و Host در لینک‌های اشتراک‌گذاری برای جعل نام سرور.
  static String applySniOverride(String rawLink, String newSni) {
    final link = rawLink.trim();
    final sni = newSni.trim();
    if (sni.isEmpty || link.isEmpty) return link;
    try {
      if (XrayJson.looksLike(link)) {
        final decoded = jsonDecode(link);
        if (decoded is Map) {
          final m = Map<String, dynamic>.from(decoded);
          final outbounds = m['outbounds'];
          if (outbounds is List) {
            for (final ob in outbounds) {
              if (ob is! Map) continue;
              final stream = ob['streamSettings'];
              if (stream is Map) {
                final tls = stream['tlsSettings'];
                if (tls is Map) tls['serverName'] = sni;
                final reality = stream['realitySettings'];
                if (reality is Map) reality['serverName'] = sni;
              }
            }
          }
          return jsonEncode(m);
        }
        return link;
      }
      final sep = link.indexOf('://');
      if (sep <= 0) return link;
      final scheme = link.substring(0, sep).toLowerCase();
      if (scheme == 'vmess') {
        return _applySniToVmess(link, sni);
      }
      final uri = Uri.tryParse(link);
      if (uri == null) return link;
      final q = Map<String, String>.from(uri.queryParameters);
      q['sni'] = sni;
      q['host'] = sni;
      q['peer'] = sni;
      final newUri = uri.replace(queryParameters: q);
      return newUri.toString();
    } catch (_) {
      return link;
    }
  }

  static String _applySniToVmess(String link, String sni) {
    try {
      final body = link.substring('vmess://'.length);
      final hashIdx = body.indexOf('#');
      String b64;
      String fragment = '';
      if (hashIdx >= 0) {
        b64 = body.substring(0, hashIdx);
        fragment = body.substring(hashIdx);
      } else {
        b64 = body;
      }
      final normalized = base64.normalize(
        b64.replaceAll('-', '+').replaceAll('_', '/'),
      );
      final decoded = utf8.decode(base64.decode(normalized));
      final json = jsonDecode(decoded);
      if (json is! Map) return link;
      final m = Map<String, dynamic>.from(json);
      m['sni'] = sni;
      m['host'] = sni;
      final re = base64.encode(utf8.encode(jsonEncode(m))).replaceAll('=', '');
      return 'vmess://$re$fragment';
    } catch (_) {
      return link;
    }
  }

}
