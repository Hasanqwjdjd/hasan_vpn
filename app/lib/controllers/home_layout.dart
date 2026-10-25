import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../app/registry.dart';

/// چیدمان صفحه‌خانه — پورت `ui/home/HomeLayoutStore.kt` + `BoardLayoutRules.kt`.
/// کلیدها عیناً مثل MLM: home_icon_order / home_folders / home_folders_v1.
sealed class BoardItem {
  const BoardItem();
}

class AppItem extends BoardItem {
  final String id; // id مقصد یا '@key' پوشه
  const AppItem(this.id);
}

class FolderItem extends BoardItem {
  final String key;
  String title;
  final List<String> apps;
  FolderItem(this.key, this.title, this.apps);

  static const String prefix = '@';
  bool has(String id) => apps.contains(id);
}

class HomeLayoutStore extends ChangeNotifier {
  HomeLayoutStore._();
  static final HomeLayoutStore instance = HomeLayoutStore._();

  static const String _kOrder = 'home_icon_order';
  static const String _kFolders = 'home_folders';
  static const String _kMigrated = 'home_folders_v1';
  static const int capacity = 24; // 4×6

  /// آیتم‌های سطح برد به ترتیب فعلی.
  final List<BoardItem> board = [];

  final Map<String, FolderItem> folders = {};

  Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    folders.clear();
    final rawFolders = p.getString(_kFolders);
    if (rawFolders != null) {
      try {
        final dec = jsonDecode(rawFolders) as Map;
        dec.forEach((k, v) {
          if (v is Map) {
            folders[k.toString()] = FolderItem(
              k.toString(),
              (v['title'] ?? '').toString(),
              ((v['apps'] ?? []) as List).map((e) => e.toString()).toList(),
            );
          }
        });
      } catch (_) {}
    }

    final rawOrder = p.getString(_kOrder);
    board.clear();
    if (rawOrder != null && rawOrder.isNotEmpty) {
      for (final token in rawOrder.split(',')) {
        final t = token.trim();
        if (t.isEmpty) continue;
        if (t.startsWith(FolderItem.prefix)) {
          final f = folders[t.substring(1)];
          if (f != null && f.apps.isNotEmpty) board.add(f);
        } else if (destinationById(t) != null) {
          board.add(AppItem(t));
        }
      }
    }
    reconcile();
    notifyListeners();
  }

  /// هرگز ترتیب کاربر را دور نمی‌ریزد؛ idهای مرده را بدون شکاف حذف و
  /// مقصدهای جدید را به انتها اضافه می‌کند؛ پوشه‌های خالی حذف می‌شوند.
  void reconcile() {
    final seen = <String>{};
    final out = <BoardItem>[];
    for (final item in board) {
      if (item is AppItem) {
        if (destinationById(item.id) == null) continue;
        if (!seen.add(item.id)) continue;
        out.add(item);
      } else if (item is FolderItem) {
        item.apps.removeWhere((a) => destinationById(a) == null);
        if (item.apps.isEmpty) {
          folders.remove(item.key);
          continue;
        }
        out.add(item);
      }
    }
    // مقصدهای جدید (در پیش‌فرض اما نه روی برد) به انتها
    for (final id in kBoardDefault) {
      if (seen.contains(id)) continue;
      if (!out.any((i) => i is AppItem && i.id == id) &&
          !out.any((i) => i is FolderItem && i.has(id))) {
        out.add(AppItem(id));
        seen.add(id);
      }
    }
    // مقصدهای ثبت‌شده که نه در پیش‌فرض‌اند نه روی برد (فازهای بعدی)
    for (final d in kDestinations) {
      if (kBoardDefault.contains(d.id)) continue;
      final onBoard = out.any((i) =>
          (i is AppItem && i.id == d.id) ||
          (i is FolderItem && i.has(d.id)));
      if (!onBoard) out.add(AppItem(d.id));
    }
    board
      ..clear()
      ..addAll(out);
  }

  Future<void> persist() async {
    final p = await SharedPreferences.getInstance();
    final order = <String>[];
    for (final item in board) {
      if (item is AppItem) {
        order.add(item.id);
      } else if (item is FolderItem) {
        order.add('${FolderItem.prefix}${item.key}');
      }
    }
    await p.setString(_kOrder, order.join(','));
    final fmap = <String, dynamic>{};
    folders.forEach((k, v) {
      fmap[k] = {'title': v.title, 'apps': v.apps};
    });
    await p.setString(_kFolders, jsonEncode(fmap));
    await p.setBool(_kMigrated, true);
  }

  Future<void> save() async {
    reconcile();
    notifyListeners();
    await persist();
  }

  Future<void> reset() async {
    final p = await SharedPreferences.getInstance();
    await p.remove(_kOrder);
    await p.remove(_kFolders);
    board.clear();
    folders.clear();
    reconcile();
    notifyListeners();
    await persist();
  }

  // ── عملیات درگ (پورت BoardLayoutRules) ──

  int _indexOf(String id) =>
      board.indexWhere((i) => i is AppItem && i.id == id);

  /// جابه‌جایی ساده روی برد.
  Future<void> moveOnBoard(String id, int toIndex) async {
    final from = _indexOf(id);
    if (from < 0) return;
    var to = toIndex.clamp(0, board.length - 1);
    if (to == from) return;
    final item = board.removeAt(from);
    if (to > board.length) to = board.length;
    board.insert(to, item);
    await save();
  }

  /// انداختن یک اپ روی اپ دیگر → پوشه با نام دسته‌ی مشترک.
  Future<void> mergeIntoFolder(String draggedId, String targetId) async {
    if (draggedId == targetId) return;
    final a = destinationById(draggedId);
    final b = destinationById(targetId);
    if (a == null || b == null) return;
    final from = _indexOf(draggedId);
    final to = _indexOf(targetId);
    if (from < 0 || to < 0) return;

    final key = 'c_${DateTime.now().millisecondsSinceEpoch.toRadixString(36)}';
    final title = _categoryTitle(a.id, b.id);
    final folder = FolderItem(key, title, [targetId, draggedId]);
    final target = board[to];
    board.removeAt(from);
    final insertAt = board.indexOf(target);
    board[insertAt] = folder;
    folders[key] = folder;
    await save();
  }

  /// انداختن اپ روی پوشه → عضویت.
  Future<void> dropIntoFolder(String draggedId, String folderKey) async {
    final f = folders[folderKey];
    if (f == null) return;
    if (!f.apps.contains(draggedId)) f.apps.add(draggedId);
    final from = _indexOf(draggedId);
    if (from >= 0) board.removeAt(from);
    await save();
  }

  /// خروج یک اپ از پوشه (درگ به بیرون یا دکمه حذف عضو).
  Future<void> moveOut(String appId, String folderKey) async {
    final f = folders[folderKey];
    if (f == null) return;
    f.apps.remove(appId);
    board.add(AppItem(appId));
    if (f.apps.isEmpty) folders.remove(folderKey);
    await save();
  }

  /// انحلال پوشه — اعضا به ترتیب سر جای آن.
  Future<void> ungroup(String folderKey) async {
    final idx =
        board.indexWhere((i) => i is FolderItem && i.key == folderKey);
    final f = folders[folderKey];
    if (f == null || idx < 0) return;
    board.removeAt(idx);
    for (var i = 0; i < f.apps.length; i++) {
      board.insert(idx + i, AppItem(f.apps[i]));
    }
    folders.remove(folderKey);
    await save();
  }

  Future<void> renameFolder(String folderKey, String title) async {
    final f = folders[folderKey];
    if (f == null) return;
    f.title = title.trim().substring(
        0, title.trim().length.clamp(0, 40));
    await save();
  }

  /// حذف اپ از برد (فقط از چیدمان — مقصد از رجیستری حذف نمی‌شود).
  Future<void> removeFromBoard(String id) async {
    final from = _indexOf(id);
    if (from >= 0) board.removeAt(from);
    await save();
  }

  String _categoryTitle(String a, String b) {
    String catOf(String id) {
      if (const ['masque', 'wireguard', 'warp_on_warp', 'warp', 'psiphon',
                'tor', 'geph'].contains(id)) return 'connect';
      if (const ['nodes', 'freeconfig', 'sublink', 'iran'].contains(id)) {
        return 'configs';
      }
      if (const ['game'].contains(id)) return 'games';
      if (const ['emergency_2', 'emergency_3', 'fronting'].contains(id)) {
        return 'emergency';
      }
      return 'tools';
    }

    final cat = catOf(a) == catOf(b) ? catOf(a) : 'tools';
    switch (cat) {
      case 'connect':
        return 'اتصال‌ها';
      case 'configs':
        return 'کانفیگ‌ها';
      case 'games':
        return 'بازی‌ها';
      case 'emergency':
        return 'اضطراری';
      default:
        return 'ابزارها';
    }
  }
}
