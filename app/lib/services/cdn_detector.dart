/// تشخیص اینکه سرور پشت CDN معروف (مثل Cloudflare) هست یا نه.
/// صرفاً برای نمایش badge کوچک در لیست سرورها — روی config اثری ندارد.
class CdnDetector {
  CdnDetector._();

  static const Set<String> _cfPrefixes4 = <String>{
    '104.16.',
    '104.17.',
    '104.18.',
    '104.19.',
    '104.20.',
    '104.21.',
    '104.22.',
    '104.23.',
    '104.24.',
    '104.25.',
    '104.26.',
    '104.27.',
    '162.159.',
    '172.64.',
    '172.65.',
    '172.66.',
    '172.67.',
    '172.68.',
    '172.69.',
    '172.70.',
    '172.71.',
    '188.114.',
    '190.93.',
    '197.234.',
    '198.41.',
  };

  /// IPv4 رو با prefix چک می‌کنه. IPv6 رو فعلاً چک نمی‌کنه.
  static bool isCloudflare(String host) {
    final h = host.trim();
    if (h.isEmpty) return false;
    if (h.contains(':')) return false; // IPv6
    for (final p in _cfPrefixes4) {
      if (h.startsWith(p)) return true;
    }
    return false;
  }

  /// Fastly (CDN معروف دیگه که خیلی کانفیگ‌ها روی اون هستن).
  static bool isFastly(String host) {
    final h = host.trim();
    return h.startsWith('151.101.') ||
        h.startsWith('199.232.') ||
        h.startsWith('23.235.');
  }

  /// متن نمایشی کوتاه برای badge، یا null اگر CDN ناشناس.
  static String? label(String host) {
    if (isCloudflare(host)) return 'CF';
    if (isFastly(host)) return 'Fastly';
    return null;
  }
}
