import 'dart:convert';

import '../models/server.dart';
import 'link_parser.dart';

/// تبدیل و شناسایی کانفیگ کامل JSON هسته Xray.
///
/// بعضی اشتراک‌ها (مثل Patterniha) به‌جای لینک vless:// یک JSON کامل
/// با outboundهای direct + fragment می‌فرستند. این ماژول آن را به یک
/// لینک داخلی `xrayjson://...` تبدیل می‌کند تا بقیه برنامه بتواند مثل
/// بقیه سرورها با آن کار کند.
class XrayJson {
  XrayJson._();

  static const String scheme = 'xrayjson';

  /// آیا متن یک JSON معتبر Xray است؟
  static bool looksLike(String raw) {
    final t = raw.trim();
    if (!t.startsWith('{')) return false;
    try {
      final decoded = jsonDecode(t);
      if (decoded is! Map) return false;
      // حداقل یک outbound یا routing داشته باشد
      return decoded.containsKey('outbounds') ||
          decoded.containsKey('outbound') ||
          decoded.containsKey('routing');
    } catch (_) {
      return false;
    }
  }

  /// استخراج نام نمایشی از remarks / ps / نام اولین outbound
  static String extractName(Map<String, dynamic> json) {
    final remarks = json['remarks'] ?? json['ps'] ?? json['name'];
    if (remarks is String && remarks.trim().isNotEmpty) {
      return remarks.trim();
    }

    final outbounds = json['outbounds'];
    if (outbounds is List && outbounds.isNotEmpty) {
      for (final o in outbounds) {
        if (o is Map) {
          final tag = o['tag']?.toString();
          final protocol = o['protocol']?.toString() ?? '';
          if (tag != null &&
              tag.isNotEmpty &&
              protocol != 'freedom' &&
              protocol != 'blackhole' &&
              protocol != 'dns') {
            return tag;
          }
        }
      }
    }
    return 'Xray Config';
  }

  /// تلاش برای پیدا کردن host/port از outboundهای پروکسی (نه freedom)
  static (String host, int port) extractEndpoint(Map<String, dynamic> json) {
    final outbounds = json['outbounds'];
    if (outbounds is! List) return ('local', 0);

    for (final o in outbounds) {
      if (o is! Map) continue;
      final protocol = (o['protocol']?.toString() ?? '').toLowerCase();
      if (protocol == 'freedom' ||
          protocol == 'blackhole' ||
          protocol == 'dns' ||
          protocol == 'loopback') {
        continue;
      }

      final settings = o['settings'];
      if (settings is! Map) continue;

      // vless / vmess / trojan
      final vnext = settings['vnext'];
      if (vnext is List && vnext.isNotEmpty && vnext.first is Map) {
        final first = vnext.first as Map;
        final address = first['address']?.toString() ?? '';
        final port = int.tryParse(first['port']?.toString() ?? '') ?? 443;
        if (address.isNotEmpty) return (address, port);
      }

      // shadowsocks / socks
      final servers = settings['servers'];
      if (servers is List && servers.isNotEmpty && servers.first is Map) {
        final first = servers.first as Map;
        final address = first['address']?.toString() ?? '';
        final port = int.tryParse(first['port']?.toString() ?? '') ?? 443;
        if (address.isNotEmpty) return (address, port);
      }
    }

    // کانفیگ فقط-direct (مثل بعضی پروفایل‌های fragment)
    return ('direct', 0);
  }

  /// تبدیل JSON خام به لینک داخلی xrayjson://base64#name
  static String toShareLink(String rawJson, {String? name}) {
    final cleaned = rawJson.trim();
    final b64 = base64Url.encode(utf8.encode(cleaned)).replaceAll('=', '');
    final label = Uri.encodeComponent(name ?? 'Xray');
    return '$scheme://$b64#$label';
  }

  /// پارس لینک xrayjson:// یا JSON خام → VpnServer
  static VpnServer? parse(String raw, {required String id}) {
    try {
      String jsonText;
      String? fragmentName;

      final trimmed = raw.trim();
      if (trimmed.toLowerCase().startsWith('$scheme://')) {
        final body = trimmed.substring(scheme.length + 3);
        final hash = body.indexOf('#');
        String b64Part;
        if (hash >= 0) {
          b64Part = body.substring(0, hash);
          fragmentName = Uri.decodeComponent(body.substring(hash + 1));
        } else {
          b64Part = body;
        }
        final normalized = base64Url.normalize(
          b64Part.replaceAll('-', '+').replaceAll('_', '/'),
        );
        jsonText = utf8.decode(base64.decode(normalized), allowMalformed: true);
      } else if (looksLike(trimmed)) {
        jsonText = trimmed;
      } else {
        return null;
      }

      final decoded = jsonDecode(jsonText);
      if (decoded is! Map) return null;
      final map = Map<String, dynamic>.from(decoded);

      final name = fragmentName?.isNotEmpty == true
          ? fragmentName!
          : extractName(map);
      final endpoint = extractEndpoint(map);
      final shareLink = trimmed.toLowerCase().startsWith('$scheme://')
          ? trimmed
          : toShareLink(jsonText, name: name);

      return VpnServer(
        id: id,
        name: name,
        flag: LinkParser.guessFlag(name),
        shareLink: shareLink,
        protocol: VpnProtocol.xrayJson,
        host: endpoint.$1,
        port: endpoint.$2,
        sniOrHost: endpoint.$1,
      );
    } catch (_) {
      return null;
    }
  }

  /// برگرداندن JSON اصلی از لینک xrayjson://
  static String? extractJson(String shareLink) {
    try {
      final trimmed = shareLink.trim();
      if (!trimmed.toLowerCase().startsWith('$scheme://')) {
        if (looksLike(trimmed)) return trimmed;
        return null;
      }
      final body = trimmed.substring(scheme.length + 3);
      final hash = body.indexOf('#');
      final b64Part = hash >= 0 ? body.substring(0, hash) : body;
      final normalized = base64Url.normalize(
        b64Part.replaceAll('-', '+').replaceAll('_', '/'),
      );
      return utf8.decode(base64.decode(normalized), allowMalformed: true);
    } catch (_) {
      return null;
    }
  }
}
