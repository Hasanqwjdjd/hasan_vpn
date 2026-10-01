/// Central FA/EN strings. Use S.of(lang, key).
class S {
  S._();

  static const Map<String, Map<String, String>> _m = {
    'app_name': {'fa': 'حسن VPN', 'en': 'Hasan VPN'},
    'connect': {'fa': 'اتصال', 'en': 'Connect'},
    'disconnect': {'fa': 'قطع', 'en': 'Disconnect'},
    'settings': {'fa': 'تنظیمات', 'en': 'Settings'},
    'servers': {'fa': 'سرورها', 'en': 'Servers'},
    'quick_connect': {'fa': 'اتصال سریع', 'en': 'Quick Connect'},
    'game_booster': {'fa': 'گیم بوستر / DNS', 'en': 'Game Booster / DNS'},
    'sanction_gemini': {'fa': 'رفع تحریم / جمینای', 'en': 'Sanction / Gemini'},
    'dns_race': {'fa': 'رقابت DNS', 'en': 'DNS Race'},
    'games': {'fa': 'بازی‌ها', 'en': 'Games'},
    'custom_dns': {'fa': 'DNS سفارشی', 'en': 'Custom DNS'},
    'tor_bridges': {'fa': 'مدیریت پل‌های Tor', 'en': 'Tor Bridges'},
    'apply': {'fa': 'اعمال', 'en': 'Apply'},
    'stop': {'fa': 'توقف', 'en': 'Stop'},
    'loading': {'fa': 'در حال بارگذاری…', 'en': 'Loading…'},
    'error': {'fa': 'خطا', 'en': 'Error'},
    'success': {'fa': 'موفق', 'en': 'Success'},
    'no_servers': {'fa': 'سروری نیست', 'en': 'No servers'},
    'ping': {'fa': 'پینگ', 'en': 'Ping'},
    'installed': {'fa': 'نصب‌شده', 'en': 'Installed'},
  };

  static String of(String lang, String key) {
    final row = _m[key];
    if (row == null) return key;
    return row[lang] ?? row['en'] ?? key;
  }

  static String t(String lang, String fa, String en) =>
      lang == 'fa' ? fa : en;
}
