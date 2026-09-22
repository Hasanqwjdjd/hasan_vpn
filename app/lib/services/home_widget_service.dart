import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// اسلات‌های ویجت صفحهٔ اصلی (حداکثر ۴).
/// کلید SharedPreferences با QuickConnectWidget.kt همگام است.
class HomeWidgetSlot {
  final int index;
  final String type; // server | dns | tor
  final String title;
  final String subtitle;
  final String payload;

  const HomeWidgetSlot({
    required this.index,
    required this.type,
    required this.title,
    required this.subtitle,
    required this.payload,
  });

  Map<String, dynamic> toJson() => {
        'index': index,
        'type': type,
        'title': title,
        'subtitle': subtitle,
        'payload': payload,
      };

  factory HomeWidgetSlot.fromJson(Map<String, dynamic> j) => HomeWidgetSlot(
        index: (j['index'] as num?)?.toInt() ?? 0,
        type: j['type']?.toString() ?? 'server',
        title: j['title']?.toString() ?? '',
        subtitle: j['subtitle']?.toString() ?? '',
        payload: j['payload']?.toString() ?? '',
      );
}

class HomeWidgetService {
  HomeWidgetService._();

  static const String _key = 'quick_home_widgets_v1';
  static const int maxSlots = 4;
  static const MethodChannel _channel =
      MethodChannel('com.hasan.hasan_vpn/widget');

  static Future<List<HomeWidgetSlot>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = jsonDecode(raw) as List;
      return list
          .whereType<Map>()
          .map((e) => HomeWidgetSlot.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> _save(List<HomeWidgetSlot> slots) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _key,
      jsonEncode(slots.map((e) => e.toJson()).toList()),
    );
    // به‌روزرسانی ویجت‌های نصب‌شده
    try {
      await _channel.invokeMethod('updateWidgets');
    } catch (_) {
      // اگر کانال native نباشد، با بازشدن بعدی اپ ویجت refresh می‌شود
    }
  }

  /// افزودن یا جایگزینی اسلات. اگر ۴ تا پر باشد، قدیمی‌ترین حذف می‌شود.
  static Future<bool> pin({
    required String type,
    required String title,
    required String subtitle,
    required String payload,
  }) async {
    final slots = await load();
    // اگر همان payload هست، فقط عنوان را به‌روز کن
    final existing = slots.indexWhere((s) => s.payload == payload && s.type == type);
    if (existing >= 0) {
      slots[existing] = HomeWidgetSlot(
        index: slots[existing].index,
        type: type,
        title: title,
        subtitle: subtitle,
        payload: payload,
      );
      await _save(slots);
      return true;
    }
    if (slots.length >= maxSlots) {
      slots.removeAt(0);
      for (var i = 0; i < slots.length; i++) {
        slots[i] = HomeWidgetSlot(
          index: i,
          type: slots[i].type,
          title: slots[i].title,
          subtitle: slots[i].subtitle,
          payload: slots[i].payload,
        );
      }
    }
    slots.add(HomeWidgetSlot(
      index: slots.length,
      type: type,
      title: title,
      subtitle: subtitle,
      payload: payload,
    ));
    await _save(slots);
    return true;
  }

  static Future<void> removeByPayload(String type, String payload) async {
    final slots = await load();
    slots.removeWhere((s) => s.type == type && s.payload == payload);
    for (var i = 0; i < slots.length; i++) {
      slots[i] = HomeWidgetSlot(
        index: i,
        type: slots[i].type,
        title: slots[i].title,
        subtitle: slots[i].subtitle,
        payload: slots[i].payload,
      );
    }
    await _save(slots);
  }

  static Future<bool> isPinned(String type, String payload) async {
    final slots = await load();
    return slots.any((s) => s.type == type && s.payload == payload);
  }
}
