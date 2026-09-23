class Subscription {
  final String id;
  final String name;
  final String url;
  final bool isDefault;
  bool autoUpdate;
  int intervalHours;
  DateTime? lastUpdated;
  int serverCount;
  List<String> cachedLinks;

  /// آخرین خطای دریافت (اگر آخرین تلاش شکست خورد). روی دیسک ذخیره نمی‌شود؛
  /// فقط برای نمایش نوار خطا در همین اجرای برنامه است.
  String? lastError;
  int? lastErrorCode;

  Subscription({
    required this.id,
    required this.name,
    required this.url,
    this.isDefault = false,
    this.autoUpdate = true,
    this.intervalHours = 12,
    this.lastUpdated,
    this.serverCount = 0,
    List<String>? cachedLinks,
    this.lastError,
    this.lastErrorCode,
  }) : cachedLinks = cachedLinks ?? [];

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'url': url,
        'isDefault': isDefault,
        'autoUpdate': autoUpdate,
        'intervalHours': intervalHours,
        'lastUpdated': lastUpdated?.toIso8601String(),
        'serverCount': serverCount,
        'cachedLinks': cachedLinks,
      };

  factory Subscription.fromJson(Map<String, dynamic> json) => Subscription(
        id: json['id'] as String,
        name: json['name'] as String,
        url: json['url'] as String,
        isDefault: json['isDefault'] as bool? ?? false,
        autoUpdate: json['autoUpdate'] as bool? ?? true,
        intervalHours: json['intervalHours'] as int? ?? 12,
        lastUpdated: json['lastUpdated'] != null
            ? DateTime.tryParse(json['lastUpdated'] as String)
            : null,
        serverCount: json['serverCount'] as int? ?? 0,
        cachedLinks: (json['cachedLinks'] as List?)
            ?.map((e) => e.toString())
            .toList(),
      );

  bool needsUpdate() {
    if (!autoUpdate) return false;
    if (lastUpdated == null) return true;
    return DateTime.now().difference(lastUpdated!).inHours >= intervalHours;
  }
}
