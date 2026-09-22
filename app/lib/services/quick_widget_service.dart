import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// اسلات ویجت صفحهٔ اصلی برای اتصال سریع به سرور / DNS / پل Tor.
/// حداکثر ۴ اسلات (مطابق درخواست کاربر).
class QuickWidgetSlot {
  final int index; // 0..3
  final String type; // server | dns | tor_bridge
  final String id;
  final String title;
  final String subtitle;
  final String payload; // shareLink / primary|secondary / bridge line

  const QuickWidgetSlot({
    required this.index,
    required this.type,
    required this.id,
    required this.title,
    required this.subtitle,
    required this.payload,
  });

  Map<String, dynamic> toJson() => {
        'index': index,
        'type': type,
        'id': id,
        'title': title,
        'subtitle': subtitle,
        'payload': payload,
      };

  factory QuickWidgetSlot.fromJson(Map<String, dynamic> j) => QuickWidgetSlot(
        index: (j['index'] as num?)?.toInt() ?? 0,
        type: j['type']?.toString() ?? 'server',
        id: j['id']?.toString() ?? '',
        title: j['title']?.toString() ?? '',
        subtitle: j['subtitle']?.toString() ?? '',
        payload: j['payload']?.toString() ?? '',
      );
}

class QuickWidgetService {
  QuickWidgetService._();

  static const String _key = 'quick_home_widgets_v1';
  static const MethodChannel _channel =
      MethodChannel('com.hasan.hasan_vpn/widgets');

  static Future<List<QuickWidgetSlot>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = jsonDecode(raw);
      if (list is! List) return [];
      return list
          .whereType<Map>()
          .map((e) => QuickWidgetSlot.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> _save(List<QuickWidgetSlot> slots) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _key,
      jsonEncode(slots.map((e) => e.toJson()).toList()),
    );
    // همگام‌سازی با ویجت‌های Android
    try {
      await _channel.invokeMethod('updateWidgets', {
        'slots': slots.map((e) => e.toJson()).toList(),
      });
    } catch (_) {
      // در محیط بدون native هنوز OK است
    }
  }

  /// افزودن یا جایگزینی اسلات (حداکثر ۴)
  static Future<bool> addOrReplace(QuickWidgetSlot slot) async {
    final list = await load();
    final idx = list.indexWhere((s) => s.index == slot.index);
    if (idx >= 0) {
      list[idx] = slot;
    } else if (list.length >= 4) {
      // پر کردن اولین اسلات خالی ۰..۳
      final used = list.map((s) => s.index).toSet();
      int? free;
      for (var i = 0; i < 4; i++) {
        if (!used.contains(i)) {
          free = i;
          break;
        }
      }
      if (free == null) return false;
      list.add(QuickWidgetSlot(
        index: free,
        type: slot.type,
        id: slot.id,
        title: slot.title,
        subtitle: slot.subtitle,
        payload: slot.payload,
      ));
    } else {
      final used = list.map((s) => s.index).toSet();
      var index = slot.index;
      if (used.contains(index)) {
        for (var i = 0; i < 4; i++) {
          if (!used.contains(i)) {
            index = i;
            break;
          }
        }
      }
      list.add(QuickWidgetSlot(
        index: index,
        type: slot.type,
        id: slot.id,
        title: slot.title,
        subtitle: slot.subtitle,
        payload: slot.payload,
      ));
    }
    await _save(list);
    return true;
  }

  static Future<void> remove(int index) async {
    final list = await load();
    list.removeWhere((s) => s.index == index);
    await _save(list);
  }

  static Future<bool> pinServer({
    required String id,
    required String name,
    required String shareLink,
    String host = '',
  }) async {
    // index رو خودکار پیدا کن (اولین اسلات خالی از 0..3)
    final slots = await load();
    final used = slots.map((s) => s.index).toSet();
    int freeIndex = -1;
    for (var i = 0; i < 4; i++) {
      if (!used.contains(i)) {
        freeIndex = i;
        break;
      }
    }
    // اگه پر بود، اسلات ۰ رو overwrite کن
    if (freeIndex < 0) freeIndex = 0;

    return addOrReplace(QuickWidgetSlot(
      index: freeIndex,
      type: 'server',
      id: id,
      title: name,
      subtitle: host,
      payload: shareLink,
    ));
  }

  static Future<bool> pinDns({
    required String name,
    required String primary,
    required String secondary,
  }) async {
    final slots = await load();
    final used = slots.map((s) => s.index).toSet();
    int freeIndex = -1;
    for (var i = 0; i < 4; i++) {
      if (!used.contains(i)) {
        freeIndex = i;
        break;
      }
    }
    if (freeIndex < 0) freeIndex = 0;
    return addOrReplace(QuickWidgetSlot(
      index: freeIndex,
      type: 'dns',
      id: '$primary|$secondary',
      title: name,
      subtitle: primary,
      payload: '$primary|$secondary',
    ));
  }

  static Future<bool> pinTorBridge({
    required String label,
    required String bridgeLine,
  }) async {
    final slots = await load();
    final used = slots.map((s) => s.index).toSet();
    int freeIndex = -1;
    for (var i = 0; i < 4; i++) {
      if (!used.contains(i)) {
        freeIndex = i;
        break;
      }
    }
    if (freeIndex < 0) freeIndex = 0;
    return addOrReplace(QuickWidgetSlot(
      index: freeIndex,
      type: 'tor_bridge',
      id: bridgeLine.hashCode.toString(),
      title: label,
      subtitle: 'Tor',
      payload: bridgeLine,
    ));
  }
}
