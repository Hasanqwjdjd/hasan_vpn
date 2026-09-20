import 'dart:convert';

import '../models/server.dart';

/// تجزیه‌ی لینک‌های اشتراک‌گذاری (vless / vmess / trojan / ss / hysteria2 / custom / aether)
/// به [VpnServer].
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
  ];

  static final RegExp linkRegex = RegExp(
    r'(?:vless|vmess|trojan|ss|hysteria2|hy2|aether|custom)://[^\s"<>\\]+',
    caseSensitive: false,
  );

  static bool isSupportedLink(String link) {
    final value = link.trim().toLowerCase();
    return supportedSchemes.any((scheme) => value.startsWith('$scheme://'));
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

  static VpnServer? parse(String rawLink, {required String id}) {
    try {
      final link = rawLink.trim();
      final sep = link.indexOf('://');
      if (sep <= 0) return null;

      final scheme = link.substring(0, sep).toLowerCase();

      switch (scheme) {
        case 'vmess':
          return _parseVmess(link, id);
        case 'ss':
          return _parseShadowsocks(link, id);
        case 'aether':
          return _parseAether(link, id);
        case 'custom':
          return _parseCustom(link, id);
        case 'vless':
          return _parseUri(link, id, VpnProtocol.vless);
        case 'trojan':
          return _parseUri(link, id, VpnProtocol.trojan);
        case 'hysteria2':
        case 'hy2':
          return _parseUri(link, id, VpnProtocol.hysteria2);
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

    return VpnServer(
      id: id,
      name: name,
      flag: guessFlag(name),
      shareLink: link,
      protocol: protocol,
      host: host,
      port: port,
      sniOrHost: sni,
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
      sniOrHost: sni,
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
    final collapsed = value.replaceAll(RegExp(r'\s+'), ' ').trim();
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
}
