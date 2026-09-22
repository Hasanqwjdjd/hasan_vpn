/// پل‌های پیشنهادی/رایگان برای هر نوع مخفی‌سازی.
/// این پل‌ها از Tor Project و منابع عمومی هستند.
/// ممکن است به‌مرور مسدود شوند؛ کاربر می‌تواند پل شخصی اضافه کند.
class TorBridges {
  TorBridges._();

  /// پل‌های obfs4 پیش‌فرض Tor Project (رایگان).
  /// نکته: ممکن است در ایران مسدود شده باشند.
  /// برای بهترین نتیجه از bridges.torproject.org یا @GetBridgesBot بگیرید.
  static const List<String> obfs4 = <String>[
    'obfs4 85.31.186.98:443 011F2599C0E9B27EE74B353155E244813763C3E5 cert=ayq0XzCwhpdysn5o0EyDUbmSOx3X/oTEbzDMvczHOdBJKlvIdHHLJGkZARtT4dcBFArPPg iat-mode=0',
    'obfs4 85.31.186.26:443 91A6354697E6B02A386312F68D82CF86824D3606 cert=PBwr+S8JTVoY5s2ZoU4crfN3+7iRHvBkthvS7X6nJDMqLmRU+aGWDsBqsjt8tgALri8DA iat-mode=0',
    'obfs4 193.11.166.194:27015 2D82C2E354D531A68469ADF7F878FA6060C6BEB4 cert=4TLQPJrTSaDffMK7Nbao6LC7G9OW/NHkUwIdjLSS3KYf0Nv4/nQiiI8dY2TcsQx01NniOg iat-mode=0',
    'obfs4 193.11.166.194:27020 86AC7B8D43B3F0A5B7EC1B0D3D22AC2ABDC1BF76 cert=hn+QhFuKUvNJKZQZoqk0pWXBjNq9NbqmxTBna0e+7OxsSJqhvz0j7BF9+YyRzTXj9wW4Ig iat-mode=0',
    'obfs4 193.11.166.194:27025 1AE2AC633B43DFE098342A6951ADFA3B523137D2 cert=H7dp/KfIY8kJsKtv1hnPYFxnDM1hF2t4A2UgAp/1KzXQjVo1Z+zkd4CJxZ3N3jq5LZCFIA iat-mode=0',
    'obfs4 209.148.46.65:443 74FAD13168806246602538555B9351E037946476 cert=ssH+9rP8dG2NLDN2XuFw63hWP/zAYy2N6MzYqTgxfDQ iat-mode=0',
    'obfs4 146.57.248.225:22 10A6CD36A537FCE513A322361547444B393989F0 cert=K1gDtDAIcUfeLqbstggjIw2rtgI3xdX2xmnFTIqqpAH8mLuVKhM1WT3S40/b9aU2vz75XQ iat-mode=0',
    'obfs4 45.145.95.6:27015 C5B7CD6946FF10C5B3E89691A7D3F2C122D2117C cert=TD7PbUO0/0k6xYHMvW7T2wEbmTm6x2D5aQh5v4mQzqE iat-mode=0',
  ];

  /// پل meek_lite بر اساس دامنه SNI (جعل نشانگر).
  static List<String> meekLiteFor(String host) => <String>[
        'meek_lite 192.0.2.2:443 url=https://$host/ front=$host',
      ];

  /// جبهه‌های meek (سبک InviZible).
  static const List<String> meekFronts = <String>[
    'play.googleapis.com',
    'drive.google.com',
    'cdn.ampproject.org',
    'api.github.com',
    'ajax.aspnetcdn.com',
    'verizon.com',
    'eset.com',
    'certum.pl',
    'ajax.microsoft.com',
    'www.google.com',
  ];

  /// پل‌های conjure پیش‌فرض.
  static const List<String> conjure = <String>[
    'conjure 192.0.2.3:80 url=https://registration.refraction.network/api',
    'conjure 192.0.2.4:80 url=https://registration.refraction.network/api',
  ];

  /// Snowflake — چند خط استاندارد.
  static const List<String> snowflake = <String>[
    'snowflake 192.0.2.3:1 2B280B23E1107BB62ABFC40DDCC8824814F80A72',
    'snowflake 192.0.2.4:1 8838024498816A039FCBBAB14E6F40A0843051FA',
    'snowflake 192.0.2.5:1 2B280B23E1107BB62ABFC40DDCC8824814F80A72 url=https://snowflake-broker.torproject.net.global.prod.fastly.net/ fronts=cdn.sstatic.net ice=stun:stun.l.google.com:19302,stun:stun.antisip.com:3478',
  ];

  /// DNSTT سبک Slipnet: دامنه + resolver (+ pubkey واقعی از اپراتور).
  static const List<String> dnstt = <String>[
    'dnstt dns.google resolver=8.8.8.8:53',
    'dnstt cloudflare-dns.com resolver=1.1.1.1:53',
    'dnstt dns.quad9.net resolver=9.9.9.9:53',
  ];

  /// برای هر نوع، لیست پل‌های رایگان/پیشنهادی را برمی‌گرداند.
  static List<String> forType(String bridgeType, {String? sni}) {
    switch (bridgeType) {
      case 'obfs4':
        return List<String>.from(obfs4);
      case 'meek_lite':
        if (sni != null && sni.isNotEmpty) {
          return meekLiteFor(sni);
        }
        // چند جبهه رایگان مثل InviZible
        return meekFronts
            .map((h) =>
                'meek_lite 192.0.2.2:443 url=https://$h/ front=$h')
            .toList();
      case 'conjure':
        return List<String>.from(conjure);
      case 'snowflake':
        return List<String>.from(snowflake);
      case 'dnstt':
        return List<String>.from(dnstt);
      default:
        return <String>[];
    }
  }

  /// آیا این نوع پل رایگان/پیش‌فرض دارد؟
  static bool hasFree(String bridgeType) {
    switch (bridgeType) {
      case 'obfs4':
      case 'meek_lite':
      case 'conjure':
      case 'snowflake':
      case 'dnstt':
        return true;
      default:
        return false;
    }
  }

  /// برچسب کوتاه برای نمایش در UI (نوع · IP:port).
  static String shortLabel(String bridgeLine) {
    final parts = bridgeLine.trim().split(RegExp(r'\s+'));
    if (parts.length >= 2) {
      return '${parts[0]} · ${parts[1]}';
    }
    if (parts.isNotEmpty) return parts[0];
    return bridgeLine;
  }

  /// استخراج host و port قابل‌پینگ از خط پل.
  /// meek/snowflake با 192.0.2.x از front= یا url= دامنه را می‌گیرند.
  static ({String host, int port})? parseEndpoint(String bridgeLine) {
    final line = bridgeLine.trim();
    if (line.isEmpty) return null;

    final frontMatch =
        RegExp(r'fronts?=([^\s]+)', caseSensitive: false).firstMatch(line);
    if (frontMatch != null) {
      final host = frontMatch.group(1)!.split(',').first.trim();
      if (host.isNotEmpty && !host.startsWith('192.0.2.')) {
        return (host: host, port: 443);
      }
    }

    final urlMatch = RegExp(r'url=https?://([^/\s]+)', caseSensitive: false)
        .firstMatch(line);
    if (urlMatch != null) {
      final host = urlMatch.group(1)!.split(':').first;
      if (host.isNotEmpty && !host.startsWith('192.0.2.')) {
        return (host: host, port: 443);
      }
    }

    final parts = line.split(RegExp(r'\s+'));
    if (parts.length < 2) return null;
    final type = parts[0].toLowerCase();
    final ep = parts[1];

    if (type == 'dnstt' && !ep.contains(':') && ep.contains('.')) {
      return (host: ep, port: 53);
    }

    if (ep.startsWith('192.0.2.')) {
      if (type == 'snowflake') {
        return (host: 'stun.l.google.com', port: 19302);
      }
      if (type == 'meek_lite' || type == 'meek') {
        return (host: 'ajax.aspnetcdn.com', port: 443);
      }
      if (type == 'conjure') {
        return (host: 'registration.refraction.network', port: 443);
      }
      return null;
    }

    final colon = ep.lastIndexOf(':');
    if (colon <= 0 || colon >= ep.length - 1) {
      if (ep.contains('.')) return (host: ep, port: 443);
      return null;
    }
    final host = ep.substring(0, colon);
    final port = int.tryParse(ep.substring(colon + 1));
    if (host.isEmpty || port == null || port <= 0) return null;
    return (host: host, port: port);
  }

  /// استخر اضافی برای دکمه «پل‌های رایگان جدید».
  static List<String> extraPool(String bridgeType) {
    switch (bridgeType) {
      case 'obfs4':
        return const [
          'obfs4 38.229.33.83:80 0CAD576E561AEE617D2137E67723A123A23A123B cert=iCsa3l3BbZv+2u9bvcpTNUVG4Esge/XabRocHl86p23Z/aMsM0Vuom9g4bbz2PlY9/oNzQ iat-mode=0',
          'obfs4 37.218.245.14:38224 D9A82D2F9C2F65A18407B1D2B764F130847F8B5D cert=bjRaMvr/wWjJwG+SN5pRaqFHycJksMui9n7hMKqNpX0ZQfRyb9a5EwQ5N2N4YdX6bY0+1Q iat-mode=0',
        ];
      case 'meek_lite':
        return meekFronts
            .skip(3)
            .map((h) =>
                'meek_lite 192.0.2.2:443 url=https://$h/ front=$h')
            .toList();
      case 'snowflake':
        return const [
          'snowflake 192.0.2.6:1 2B280B23E1107BB62ABFC40DDCC8824814F80A72 url=https://snowflake-broker.torproject.net.global.prod.fastly.net/ fronts=ajax.aspnetcdn.com ice=stun:stun.l.google.com:19302',
          'snowflake 192.0.2.7:1 2B280B23E1107BB62ABFC40DDCC8824814F80A72 url=https://snowflake-broker.torproject.net.global.prod.fastly.net/ fronts=www.google.com ice=stun:stun.voipgate.com:3478',
        ];
      case 'conjure':
        return const [
          'conjure 192.0.2.5:80 url=https://registration.refraction.network/api',
        ];
      default:
        return const [];
    }
  }
}
