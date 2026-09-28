/// نگاشت کشور → پرچم ایموجی.
///
/// از کد ISO یا نام کامل کشور یه ایموجی پرچم می‌سازه.
/// fallback به 🌐 اگه نشناسه.
class GeoFlag {
  GeoFlag._();

  /// نام کشور (انگلیسی) → کد ISO 2 حرفی.
  static const Map<String, String> _nameToIso = {
    'iran': 'IR',
    'islamic republic of iran': 'IR',
    'united states': 'US',
    'united states of america': 'US',
    'usa': 'US',
    'canada': 'CA',
    'united kingdom': 'GB',
    'uk': 'GB',
    'great britain': 'GB',
    'germany': 'DE',
    'france': 'FR',
    'netherlands': 'NL',
    'holland': 'NL',
    'sweden': 'SE',
    'norway': 'NO',
    'denmark': 'DK',
    'finland': 'FI',
    'switzerland': 'CH',
    'austria': 'AT',
    'belgium': 'BE',
    'italy': 'IT',
    'spain': 'ES',
    'portugal': 'PT',
    'poland': 'PL',
    'czech republic': 'CZ',
    'czechia': 'CZ',
    'hungary': 'HU',
    'romania': 'RO',
    'bulgaria': 'BG',
    'greece': 'GR',
    'turkey': 'TR',
    'russia': 'RU',
    'russian federation': 'RU',
    'ukraine': 'UA',
    'belarus': 'BY',
    'kazakhstan': 'KZ',
    'india': 'IN',
    'china': 'CN',
    'japan': 'JP',
    'south korea': 'KR',
    'korea': 'KR',
    'singapore': 'SG',
    'malaysia': 'MY',
    'indonesia': 'ID',
    'thailand': 'TH',
    'vietnam': 'VN',
    'philippines': 'PH',
    'australia': 'AU',
    'new zealand': 'NZ',
    'brazil': 'BR',
    'argentina': 'AR',
    'mexico': 'MX',
    'chile': 'CL',
    'colombia': 'CO',
    'south africa': 'ZA',
    'egypt': 'EG',
    'saudi arabia': 'SA',
    'united arab emirates': 'AE',
    'uae': 'AE',
    'qatar': 'QA',
    'kuwait': 'KW',
    'bahrain': 'BH',
    'oman': 'OM',
    'israel': 'IL',
    'iraq': 'IQ',
    'afghanistan': 'AF',
    'pakistan': 'PK',
    'armenia': 'AM',
    'azerbaijan': 'AZ',
    'georgia': 'GE',
    'cyprus': 'CY',
    'ireland': 'IE',
    'iceland': 'IS',
    'luxembourg': 'LU',
    'lithuania': 'LT',
    'latvia': 'LV',
    'estonia': 'EE',
    'moldova': 'MD',
    'serbia': 'RS',
    'croatia': 'HR',
    'slovenia': 'SI',
    'slovakia': 'SK',
    'albania': 'AL',
    'macedonia': 'MK',
    'north macedonia': 'MK',
    'malta': 'MT',
    'hong kong': 'HK',
    'taiwan': 'TW',
    'macau': 'MO',
    'bangladesh': 'BD',
    'sri lanka': 'LK',
    'nepal': 'NP',
    'myanmar': 'MM',
    'cambodia': 'KH',
    'laos': 'LA',
    'mongolia': 'MN',
  };

  /// کد ISO 2 حرفی → پرچم.
  static String fromIso(String? iso) {
    if (iso == null || iso.length != 2) return '🌐';
    final upper = iso.toUpperCase();
    const offset = 0x1F1E6; // 'A'
    const base = 0x41; // 'A'.codeUnitAt(0)
    try {
      final a = upper.codeUnitAt(0) - base + offset;
      final b = upper.codeUnitAt(1) - base + offset;
      return String.fromCharCode(a) + String.fromCharCode(b);
    } catch (_) {
      return '🌐';
    }
  }

  /// نام کشور → پرچم.
  static String fromName(String? name) {
    if (name == null || name.isEmpty) return '🌐';
    final key = name.trim().toLowerCase();
    final iso = _nameToIso[key];
    if (iso != null) return fromIso(iso);
    // اگه خودش ISO 2 حرفی بود
    if (key.length == 2) return fromIso(key);
    return '🌐';
  }

  /// نام انگلیسی → نام فارسی (اختیاری برای نمایش).
  static const Map<String, String> nameToFarsi = {
    'iran': 'ایران',
    'united states': 'آمریکا',
    'usa': 'آمریکا',
    'canada': 'کانادا',
    'united kingdom': 'بریتانیا',
    'germany': 'آلمان',
    'france': 'فرانسه',
    'netherlands': 'هلند',
    'sweden': 'سوئد',
    'norway': 'نروژ',
    'denmark': 'دانمارک',
    'finland': 'فینلاند',
    'switzerland': 'سوئیس',
    'austria': 'اتریش',
    'belgium': 'بلژیک',
    'italy': 'ایتالیا',
    'spain': 'اسپانیا',
    'portugal': 'پرتغال',
    'poland': 'لهستان',
    'czech republic': 'چک',
    'hungary': 'مجارستان',
    'romania': 'رومانی',
    'bulgaria': 'بلغارستان',
    'greece': 'یونان',
    'turkey': 'ترکیه',
    'russia': 'روسیه',
    'ukraine': 'اوکراین',
    'india': 'هند',
    'china': 'چین',
    'japan': 'ژاپن',
    'south korea': 'کره جنوبی',
    'singapore': 'سنگاپور',
    'malaysia': 'مالزی',
    'indonesia': 'اندونزی',
    'thailand': 'تایلند',
    'vietnam': 'ویتنام',
    'philippines': 'فیلیپین',
    'australia': 'استرالیا',
    'new zealand': 'نیوزلند',
    'brazil': 'برزیل',
    'argentina': 'آرژانتین',
    'mexico': 'مکزیک',
    'chile': 'شیلی',
    'colombia': 'کلمبیا',
    'south africa': 'آفریقای جنوبی',
    'egypt': 'مصر',
    'saudi arabia': 'عربستان',
    'united arab emirates': 'امارات',
    'qatar': 'قطر',
    'kuwait': 'کویت',
    'bahrain': 'بحرین',
    'oman': 'عمان',
    'israel': 'اسرائیل',
    'iraq': 'عراق',
    'afghanistan': 'افغانستان',
    'pakistan': 'پاکستان',
    'armenia': 'ارمنستان',
    'azerbaijan': 'آذربایجان',
    'georgia': 'گرجستان',
    'cyprus': 'قبرس',
    'ireland': 'ایرلند',
    'hong kong': 'هنگ‌کنگ',
    'taiwan': 'تایوان',
    'bangladesh': 'بنگلادش',
  };

  static String farsiName(String? name) {
    if (name == null || name.isEmpty) return '';
    return nameToFarsi[name.trim().toLowerCase()] ?? name;
  }
}
