import 'dart:convert';

/// پروفایل زنجیره‌ی دو سرور (multi-hop).
///
/// معماری: Xray config ساخته می‌شه با دو outbound:
///   - primary (سرور اول) → به دومی به‌عنوان dialerProxy وصل می‌شه.
/// این ساده‌ترین شکل multi-hop هست و بدون نیاز به سرور واسط کار می‌کنه.
class ChainProfile {
  /// لینک سرور اول (ورودی)
  final String firstLink;

  /// لینک سرور دوم (خروجی — به اینترنت وصل می‌شه)
  final String secondLink;

  /// نام نمایشی
  final String name;

  const ChainProfile({
    this.firstLink = '',
    this.secondLink = '',
    this.name = '',
  });

  bool get isComplete => firstLink.isNotEmpty && secondLink.isNotEmpty;

  String get summary {
    if (name.isNotEmpty) return name;
    if (firstLink.isEmpty || secondLink.isEmpty) return 'Chain';
    return 'Chain';
  }

  String toLink() {
    final q = <String, String>{
      'first': firstLink,
      'second': secondLink,
      if (name.isNotEmpty) 'name': name,
    };
    return Uri(scheme: 'chain', host: 'config', queryParameters: q).toString();
  }

  factory ChainProfile.fromLink(String link) {
    try {
      final uri = Uri.parse(link);
      if (uri.scheme.toLowerCase() != 'chain') return const ChainProfile();
      final q = uri.queryParameters;
      return ChainProfile(
        firstLink: q['first'] ?? '',
        secondLink: q['second'] ?? '',
        name: q['name'] ?? '',
      );
    } catch (_) {
      return const ChainProfile();
    }
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'first': firstLink,
        'second': secondLink,
        'name': name,
      };

  factory ChainProfile.fromJson(Map<String, dynamic> j) => ChainProfile(
        firstLink: j['first']?.toString() ?? '',
        secondLink: j['second']?.toString() ?? '',
        name: j['name']?.toString() ?? '',
      );
}
