import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/server.dart';

/// بخش ۱.۳ — ذخیره‌سازی «ویرایش‌های کامل» سرورها بر اساس id.
///
/// سرورهای سابسکریپشن در هر refresh دوباره از کش لینک‌ها ساخته می‌شوند و
/// `_saveCustomServers` هم فقط فیلدهای پایه را نگه می‌دارد (name/flag/link/
/// host/port) — بنابراین ویرایش TLS/SNI/DNS/نام هر دو دسته سرور بین
/// ری‌استارت‌ها از دست می‌رفت. این سرویس ویرایش کامل را بر اساس id نگه
/// می‌دارد و در بازسازی لیست دوباره اعمال می‌شود.
class ServerOverrides {
  ServerOverrides._();

  static const String storageKey = 'server_full_overrides_v1';

  static Future<Map<String, Map<String, dynamic>>> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(storageKey);
      if (raw == null || raw.isEmpty) return <String, Map<String, dynamic>>{};
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return <String, Map<String, dynamic>>{};
      final out = <String, Map<String, dynamic>>{};
      decoded.forEach((key, value) {
        if (value is Map) {
          out[key.toString()] = Map<String, dynamic>.from(value);
        }
      });
      return out;
    } catch (e) {
      debugPrint('[ServerOverrides] load failed: $e');
      return <String, Map<String, dynamic>>{};
    }
  }

  static Future<void> save(String id, Map<String, dynamic> override) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final map = await load();
      map[id] = override;
      await prefs.setString(storageKey, jsonEncode(map));
      debugPrint('[ServerOverrides] saved override for $id');
    } catch (e) {
      debugPrint('[ServerOverrides] save failed: $e');
    }
  }

  static Future<void> remove(String id) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final map = await load();
      if (map.remove(id) != null) {
        await prefs.setString(storageKey, jsonEncode(map));
        debugPrint('[ServerOverrides] removed override for $id');
      }
    } catch (_) {}
  }

  /// اعمال یک override روی سرور. فیلدهای mutable درجا ست می‌شوند؛
  /// backupAddresses (final) با copyWith بازسازی می‌شود — نتیجه‌ی برگشتی
  /// باید توسط صدا زننده استفاده شود.
  static VpnServer apply(VpnServer server, Map<String, dynamic>? ov) {
    if (ov == null || ov.isEmpty) return server;
    var out = server;
    try {
      final nameOv = ov['nameOverride']?.toString() ?? '';
      if (nameOv.isNotEmpty) {
        out.nameOverride = VpnServer.sanitizeServerName(nameOv);
      }
      if (ov.containsKey('sni')) {
        final sni = ov['sni']?.toString() ?? '';
        out.sniOrHost = sni.isEmpty ? null : sni;
      }
      final tlsJson = ov['tls'];
      if (tlsJson is Map) {
        out.tls = TlsOptions.fromJson(Map<String, dynamic>.from(tlsJson));
      }
      if (ov.containsKey('dns')) {
        final dns = ov['dns']?.toString() ?? '';
        out.dns = dns.isEmpty ? null : dns;
      }
      if (ov.containsKey('backupAddresses')) {
        final raw = ov['backupAddresses'];
        if (raw is List) {
          out = out.copyWith(
            backupAddresses: raw
                .map((e) => e.toString())
                .where((e) => e.isNotEmpty)
                .toList(),
          );
        }
      }
    } catch (e) {
      debugPrint('[ServerOverrides] apply failed for ${server.id}: $e');
    }
    return out;
  }

  /// ساخت map ذخیره‌شدنی از یک سرور ویرایش‌شده.
  static Map<String, dynamic> of(VpnServer s) {
    return <String, dynamic>{
      'nameOverride': s.nameOverride ?? '',
      'sni': s.sniOrHost ?? '',
      'tls': s.tls.toJson(),
      'dns': s.dns ?? '',
      'backupAddresses': s.backupAddresses,
    };
  }
}
