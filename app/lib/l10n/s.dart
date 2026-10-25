import 'mlm_strings.dart';

/// دسترسی به رشته‌های ۱:۱ پورت‌شده از MLM VPN (GPL-3.0).
/// زبان فعلی یک static سراسری است که AppState در بوت و پس از تغییر
/// زبان تنظیمش می‌کند؛ سازوکار سبک است و به Inherited وابسته نیست.
class S {
  S._();

  /// 'fa' | 'en' — پیش‌فرض فارسی.
  static String lang = 'fa';

  static bool get isFa => lang == 'fa';

  /// ترجمه با fallback: fa → en → خود کلید.
  static String t(String key) {
    if (isFa) {
      return kMlmStringsFa[key] ?? kMlmStringsEn[key] ?? key;
    }
    return kMlmStringsEn[key] ?? kMlmStringsFa[key] ?? key;
  }

  /// مثل [t] ولی با قالب‌بندی ساده: {0}، {1} ...
  static String tf(String key, List<Object> args) {
    var out = t(key);
    for (var i = 0; i < args.length; i++) {
      out = out.replaceAll('{$i}', args[i].toString()).replaceAll(
          'ellan{$i}', args[i].toString());
    }
    // الگوی رایج Android: %1$s را هم پشتیبانی می‌کنیم
    for (var i = 0; i < args.length; i++) {
      out = out.replaceAll('%${i + 1}\$s', args[i].toString());
    }
    return out;
  }
}
