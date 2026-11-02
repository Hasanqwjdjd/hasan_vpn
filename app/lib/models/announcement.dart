/// دسته‌بندی اعلان‌ها (الگوی MarbleNG، بازنویسی‌شده)
enum AnnouncementCategory {
  connection,   // وضعیت اتصال
  recovery,     // بازیابی خودکار
  privacy,      // حریم خصوصی / kill-switch
  network,      // تغییر شبکه
  subscription, // به‌روزرسانی اشتراک
  core,         // هسته / نسخه
  telemetry,    // آمار / پینگ
}

class Announcement {
  final String id;
  final AnnouncementCategory category;
  final String titleFa;
  final String titleEn;
  final String bodyFa;
  final String bodyEn;
  final DateTime createdAt;
  final bool read;
  final String? actionLabelFa;
  final String? actionLabelEn;
  final String? actionRoute; // مثلاً 'settings' / 'subscriptions'

  const Announcement({
    required this.id,
    required this.category,
    required this.titleFa,
    required this.titleEn,
    required this.bodyFa,
    required this.bodyEn,
    required this.createdAt,
    this.read = false,
    this.actionLabelFa,
    this.actionLabelEn,
    this.actionRoute,
  });

  Announcement copyWith({bool? read}) => Announcement(
        id: id,
        category: category,
        titleFa: titleFa,
        titleEn: titleEn,
        bodyFa: bodyFa,
        bodyEn: bodyEn,
        createdAt: createdAt,
        read: read ?? this.read,
        actionLabelFa: actionLabelFa,
        actionLabelEn: actionLabelEn,
        actionRoute: actionRoute,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'category': category.name,
        'titleFa': titleFa,
        'titleEn': titleEn,
        'bodyFa': bodyFa,
        'bodyEn': bodyEn,
        'createdAt': createdAt.toIso8601String(),
        'read': read,
        'actionLabelFa': actionLabelFa,
        'actionLabelEn': actionLabelEn,
        'actionRoute': actionRoute,
      };

  factory Announcement.fromJson(Map<String, dynamic> j) {
    final catName = j['category']?.toString() ?? 'telemetry';
    final cat = AnnouncementCategory.values.firstWhere(
      (e) => e.name == catName,
      orElse: () => AnnouncementCategory.telemetry,
    );
    return Announcement(
      id: j['id']?.toString() ?? '',
      category: cat,
      titleFa: j['titleFa']?.toString() ?? '',
      titleEn: j['titleEn']?.toString() ?? '',
      bodyFa: j['bodyFa']?.toString() ?? '',
      bodyEn: j['bodyEn']?.toString() ?? '',
      createdAt: DateTime.tryParse(j['createdAt']?.toString() ?? '') ??
          DateTime.now(),
      read: j['read'] == true,
      actionLabelFa: j['actionLabelFa']?.toString(),
      actionLabelEn: j['actionLabelEn']?.toString(),
      actionRoute: j['actionRoute']?.toString(),
    );
  }

  String title(String lang) => lang == 'fa' ? titleFa : titleEn;
  String body(String lang) => lang == 'fa' ? bodyFa : bodyEn;
  String? actionLabel(String lang) =>
      lang == 'fa' ? actionLabelFa : actionLabelEn;
}
