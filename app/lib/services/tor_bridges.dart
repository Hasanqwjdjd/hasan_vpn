/// پل‌های پیشنهادی برای هر نوع مخفی‌سازی.
/// این پل‌ها از Tor Project به‌عنوان پیش‌فرض قابل استفاده هستند،
/// اما ممکن است به‌مرور مسدود شوند. کاربر می‌تواند پل شخصی اضافه کند.
class TorBridges {
  TorBridges._();

  /// پل‌های obfs4 پیش‌فرض Tor Project.
  /// نکته: این پل‌ها ممکن است در ایران مسدود شده باشند.
  /// برای بهترین نتیجه، از @TorBridges در تلگرام پل بگیرید.
  static const List<String> obfs4 = <String>[
    'obfs4 85.31.186.98:443 011F2599C0E9B27EE74B353155E244813763C3E5 cert=ayq0XzCwhpdysn5o0EyDUbmSOx3X/oTEbzDMvczHOdBJKlvIdHHLJGkZARtT4dcBFArPPg iat-mode=0',
    'obfs4 85.31.186.26:443 91A6354697E6B02A386312F68D82CF86824D3606 cert=PBwr+S8JTVoY5s2ZoU4crfN3+7iRHvBkthvS7X6nJDMqLmRU+aGWDsBqsjt8tgALri8DA iat-mode=0',
    'obfs4 193.11.166.194:27015 2D82C2E354D531A68469ADF7F878FA6060C6BEB4 cert=4TLQPJrTSaDffMK7Nbao6LC7G9OW/NHkUwIdjLSS3KYf0Nv4/nQiiI8dY2TcsQx01NniOg iat-mode=0',
    'obfs4 193.11.166.194:27020 86AC7B8D43B3F0A5B7EC1B0D3D22AC2ABDC1BF76 cert=hn+QhFuKUvNJKZQZoqk0pWXBjNq9NbqmxTBna0e+7OxsSJqhvz0j7BF9+YyRzTXj9wW4Ig iat-mode=0',
    'obfs4 193.11.166.194:27025 1AE2AC633B43DFE098342A6951ADFA3B523137D2 cert=H7dp/KfIY8kJsKtv1hnPYFxnDM1hF2t4A2UgAp/1KzXQjVo1Z+zkd4CJxZ3N3jq5LZCFIA iat-mode=0',
  ];

  /// پل‌های meek_lite پیش‌فرض (بر اساس دامنه SNI).
  static List<String> meekLiteFor(String host) => <String>[
        'meek_lite 192.0.2.2:443 url=https://$host/ front=$host',
      ];

  /// پل‌های conjure پیش‌فرض.
  static const List<String> conjure = <String>[
    'conjure 192.0.2.3:80',
  ];

  /// Snowflake پیش‌فرض (بدون پل شخصی، خودش broker می‌گیرد).
  static const List<String> snowflake = <String>[];

  /// DNSTT پیش‌فرض.
  static const List<String> dnstt = <String>[
    'dnstt t.example.com',
  ];

  /// برای هر نوع، لیست پل‌های پیشنهادی را برمی‌گرداند.
  static List<String> forType(String bridgeType, {String? sni}) {
    switch (bridgeType) {
      case 'obfs4':
        return obfs4;
      case 'meek_lite':
        return sni != null ? meekLiteFor(sni) : <String>[];
      case 'conjure':
        return conjure;
      case 'snowflake':
        return snowflake;
      case 'dnstt':
        return dnstt;
      default:
        return <String>[];
    }
  }
}
