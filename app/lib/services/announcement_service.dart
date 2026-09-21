import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/announcement.dart';

/// سرویس اعلان‌های درون‌برنامه‌ای.
/// حداکثر ۵۰ اعلان نگه می‌دارد؛ قدیمی‌تر از ۳۰ روز حذف می‌شود.
class AnnouncementService {
  AnnouncementService._();

  static const String _key = 'announcements_v1';
  static const int _maxItems = 50;
  static const Duration _ttl = Duration(days: 30);

  /// فاصله‌ی حداقل بین دو اعلان هم‌دسته (جلوگیری از اسپم)
  static const Duration _categoryCooldown = Duration(minutes: 3);

  static final Map<AnnouncementCategory, DateTime> _lastByCategory = {};

  static Future<List<Announcement>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) return [];
    try {
      final list = jsonDecode(raw);
      if (list is! List) return [];
      final now = DateTime.now();
      final items = list
          .whereType<Map>()
          .map((m) => Announcement.fromJson(Map<String, dynamic>.from(m)))
          .where((a) => now.difference(a.createdAt) < _ttl)
          .toList();
      items.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return items;
    } catch (_) {
      return [];
    }
  }

  static Future<void> _save(List<Announcement> items) async {
    final prefs = await SharedPreferences.getInstance();
    final trimmed = items.take(_maxItems).toList();
    await prefs.setString(
      _key,
      jsonEncode(trimmed.map((a) => a.toJson()).toList()),
    );
  }

  static Future<int> unreadCount() async {
    final items = await load();
    return items.where((a) => !a.read).length;
  }

  static Future<void> markRead(String id) async {
    final items = await load();
    final updated = items
        .map((a) => a.id == id ? a.copyWith(read: true) : a)
        .toList();
    await _save(updated);
  }

  static Future<void> markAllRead() async {
    final items = await load();
    await _save(items.map((a) => a.copyWith(read: true)).toList());
  }

  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }

  /// افزودن اعلان با کنترل cooldown دسته‌ای
  static Future<void> push({
    required AnnouncementCategory category,
    required String titleFa,
    required String titleEn,
    required String bodyFa,
    required String bodyEn,
    String? actionLabelFa,
    String? actionLabelEn,
    String? actionRoute,
    bool force = false,
  }) async {
    final now = DateTime.now();
    if (!force) {
      final last = _lastByCategory[category];
      if (last != null && now.difference(last) < _categoryCooldown) return;
    }
    _lastByCategory[category] = now;

    final item = Announcement(
      id: '${category.name}_${now.millisecondsSinceEpoch}',
      category: category,
      titleFa: titleFa,
      titleEn: titleEn,
      bodyFa: bodyFa,
      bodyEn: bodyEn,
      createdAt: now,
      actionLabelFa: actionLabelFa,
      actionLabelEn: actionLabelEn,
      actionRoute: actionRoute,
    );

    final items = await load();
    items.insert(0, item);
    await _save(items);
  }

  // ---------------- helpers برای رویدادهای رایج ----------------

  static Future<void> onConnected(String serverName) => push(
        category: AnnouncementCategory.connection,
        titleFa: 'متصل شد',
        titleEn: 'Connected',
        bodyFa: 'اتصال به «$serverName» برقرار شد.',
        bodyEn: 'Connected to "$serverName".',
      );

  static Future<void> onDisconnected() => push(
        category: AnnouncementCategory.connection,
        titleFa: 'قطع شد',
        titleEn: 'Disconnected',
        bodyFa: 'اتصال VPN قطع شد.',
        bodyEn: 'VPN connection closed.',
      );

  static Future<void> onNetworkChanged(String type) => push(
        category: AnnouncementCategory.network,
        titleFa: 'تغییر شبکه',
        titleEn: 'Network changed',
        bodyFa: 'نوع شبکه به $type تغییر کرد.',
        bodyEn: 'Network type changed to $type.',
      );

  static Future<void> onSubscriptionUpdated(String name, int count) => push(
        category: AnnouncementCategory.subscription,
        titleFa: 'اشتراک به‌روز شد',
        titleEn: 'Subscription updated',
        bodyFa: '«$name» — $count سرور.',
        bodyEn: '"$name" — $count servers.',
        actionRoute: 'subscriptions',
      );

  static Future<void> onTestFinished({
    required int online,
    required int total,
  }) =>
      push(
        category: AnnouncementCategory.telemetry,
        titleFa: 'تست تمام شد',
        titleEn: 'Test finished',
        bodyFa: '$online از $total سرور آنلاین.',
        bodyEn: '$online of $total servers online.',
      );

  static Future<void> onCoreIssue(String detail) => push(
        category: AnnouncementCategory.core,
        titleFa: 'هسته',
        titleEn: 'Core',
        bodyFa: detail,
        bodyEn: detail,
        actionRoute: 'settings',
      );
}
