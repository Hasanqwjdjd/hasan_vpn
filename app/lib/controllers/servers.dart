import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/server.dart';
import '../models/subscription.dart';
import '../services/connection_log_service.dart';
import '../services/link_parser.dart';
import '../services/server_overrides.dart';
import '../services/server_tester.dart';
import '../services/settings_service.dart';
import '../services/subscription_service.dart';

/// مخزن سرورها و اشتراک‌ها — استخراج‌شدهٔ ۱:۱ از منطق صفحه‌خانه و main قدیمی
/// (همان کلیدهای SharedPreferences تا داده‌های کاربران حفظ شود).
class ServerRepository extends ChangeNotifier {
  ServerRepository._();
  static final ServerRepository instance = ServerRepository._();

  // ── کلیدها — عیناً از home_screen.dart قدیمی ──
  static const String _customKey = 'custom_servers_v1';
  static const String _deletedKey = 'deleted_server_ids_v1';
  static const String _pinnedKey = 'pinned_server_ids_v1';
  static const String _pingsKey = 'server_pings_v1';
  static const String _orderKey = 'server_order_v1';
  static const String _customSubTagsKey = 'custom_server_sub_tags_v1';
  static const String _sortKey = 'settings_sort_ascending_v1';
  static const String _userGroupsKey = 'server_groups_v1';
  static const String _userGroupsOrderKey = 'server_groups_order_v1';

  List<Subscription> subs = [];
  List<VpnServer> customServers = [];
  Set<String> deletedIds = {};
  Map<String, String> customSubTags = {};
  Set<String> pinnedIds = {};
  List<String> manualOrder = [];
  Map<String, List<String>> userGroups = {};
  List<String> userGroupsOrder = [];
  Map<String, Map<String, dynamic>> fullOverrides = {};
  bool sortAscending = true;

  List<VpnServer> servers = [];

  /// سرور انتخاب‌شده برای دکمهٔ اتصال.
  VpnServer? selected;

  /// آخرین لیست‌های گرفته‌شده از اشتراک‌ها (برای merge حفظِ شیء و پینگ).
  List<List<VpnServer>> _fetchedLists = const [];

  Future<void>? _refreshing;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();

    await SettingsService.loadVersion();

    subs = await SubscriptionService.load();

    // سرورهای custom
    try {
      final raw = prefs.getString(_customKey);
      final decoded = raw == null ? null : jsonDecode(raw);
      final loaded = <VpnServer>[];
      if (decoded is List) {
        for (final e in decoded) {
          if (e is! Map) continue;
          try {
            final s = VpnServer(
              id: e['id']?.toString() ?? '',
              name: e['name']?.toString() ?? '',
              flag: e['flag']?.toString() ?? '⚡',
              shareLink: e['shareLink']?.toString() ?? '',
              protocol: VpnProtocol.values.firstWhere(
                (p) => p.name == (e['protocol']?.toString() ?? ''),
                orElse: () => VpnProtocol.custom,
              ),
              host: e['host']?.toString() ?? '',
              port: (e['port'] as num?)?.toInt() ?? 0,
            );
            if (s.id.isNotEmpty) loaded.add(s);
          } catch (_) {}
        }
      }
      customServers = loaded;
    } catch (_) {
      customServers = <VpnServer>[];
    }

    deletedIds = _loadStrSet(prefs, _deletedKey);
    pinnedIds = _loadStrSet(prefs, _pinnedKey);
    manualOrder = prefs.getStringList(_orderKey) ?? <String>[];
    sortAscending = prefs.getBool(_sortKey) ?? true;

    try {
      final raw = prefs.getString(_customSubTagsKey);
      if (raw != null) {
        final m = jsonDecode(raw) as Map;
        customSubTags =
            m.map((k, v) => MapEntry(k.toString(), v.toString()));
      }
    } catch (_) {}

    try {
      final raw = prefs.getString(_userGroupsKey) ?? '{}';
      final dec = jsonDecode(raw);
      final m = <String, List<String>>{};
      if (dec is Map) {
        dec.forEach((k, v) {
          if (v is List) {
            m[k.toString()] = v.map((e) => e.toString()).toList();
          }
        });
      }
      userGroups = m;
      final ord = prefs.getStringList(_userGroupsOrderKey) ?? <String>[];
      for (final k in m.keys) {
        if (!ord.contains(k)) ord.add(k);
      }
      userGroupsOrder = ord;
    } catch (_) {}

    fullOverrides = await ServerOverrides.load();

    // نمایش فوری از کش (الگوی قدیمی main.dart)
    _fetchedLists = subs.map(SubscriptionService.fromCache).toList();
    _applyPingsTo(_fetchedLists.expand((l) => l).toList());
    rebuild();
    selected = await _loadSelected();
    notifyListeners();

    unawaited(refreshSubscriptions());
  }

  Set<String> _loadStrSet(SharedPreferences p, String key) {
    try {
      final raw = p.getString(key);
      if (raw == null) return {};
      final dec = jsonDecode(raw);
      if (dec is List) return dec.map((e) => e.toString()).toSet();
    } catch (_) {}
    return {};
  }

  Future<VpnServer?> _loadSelected() async {
    final prefs = await SharedPreferences.getInstance();
    final id = prefs.getString('settings_last_server_v1');
    if (id == null || id.isEmpty) return null;
    for (final s in servers) {
      if (s.id == id) return s;
    }
    return null;
  }

  Future<void> select(VpnServer? server) async {
    selected = server;
    final prefs = await SharedPreferences.getInstance();
    if (server == null) {
      await prefs.remove('settings_last_server_v1');
    } else {
      await prefs.setString('settings_last_server_v1', server.id);
    }
    notifyListeners();
  }

  // ── به‌روزرسانی اشتراک‌ها (پورت _refreshSubscriptions/_doRefresh/_merge) ──

  Future<void> refreshSubscriptions({bool force = false}) {
    final running = _refreshing;
    if (running != null && !force) {
      return running.then((_) => refreshSubscriptions());
    }
    final future = _doRefresh(force);
    _refreshing = future;
    future.whenComplete(() {
      if (identical(_refreshing, future)) _refreshing = null;
    });
    return future;
  }

  Future<void> _doRefresh(bool force) async {
    final list = List<Subscription>.from(subs);
    final results = await Future.wait(
      list.map((s) async {
        if (force || s.needsUpdate()) {
          try {
            final servers = await SubscriptionService.fetch(s);
            s.lastUpdated = DateTime.now();
            s.serverCount = servers.length;
            s.lastError = null;
            s.lastErrorCode = null;
            return servers;
          } catch (e) {
            s.lastError =
                e is SubscriptionFetchException ? e.message : e.toString();
            s.lastErrorCode =
                e is SubscriptionFetchException ? e.statusCode : null;
            return SubscriptionService.fromCache(s);
          }
        }
        return SubscriptionService.fromCache(s);
      }),
    );
    await SubscriptionService.save(subs);
    // حفظ دقیق اشیاء گرفته‌شده — مثل _merge قدیمی که نتیجهٔ تست را
    // با هر refresh پاک نمی‌کرد.
    _fetchedLists = results;
    rebuild();
    _applyPingsTo(servers);
    notifyListeners();
  }

  /// ادغام: تکراری‌ها حذف؛ شیء قبلی برای حفظ نتیجهٔ پینگ نگه داشته می‌شود.
  List<VpnServer> _merge(List<List<VpnServer>> lists) {
    final previous = <String, VpnServer>{
      for (final server in servers) server.id: server,
    };
    final seen = <String>{};
    final merged = <VpnServer>[];
    for (final list in lists) {
      for (final server in list) {
        if (!seen.add(server.id)) continue;
        merged.add(previous[server.id] ?? server);
      }
    }
    return merged;
  }

  // ── بازسازی لیست (پورت _rebuildServerList) ──

  void rebuild() {
    final allServers = <VpnServer>[
      ...customServers,
      ..._merge(_fetchedLists),
    ].where((s) => !deletedIds.contains(s.id)).toList();

    if (fullOverrides.isNotEmpty) {
      for (var i = 0; i < allServers.length; i++) {
        final ov = fullOverrides[allServers[i].id];
        if (ov != null) {
          allServers[i] = ServerOverrides.apply(allServers[i], ov);
        }
      }
    }

    for (final server in allServers) {
      server.isPinned = pinnedIds.contains(server.id);
    }

    servers = allServers;
    if (manualOrder.isNotEmpty) {
      final pos = <String, int>{};
      for (var i = 0; i < manualOrder.length; i++) {
        pos[manualOrder[i]] = i;
      }
      servers.sort((a, b) {
        if (a.isPinned != b.isPinned) return a.isPinned ? -1 : 1;
        final ai = pos[a.id] ?? 9999999;
        final bi = pos[b.id] ?? 9999999;
        return ai.compareTo(bi);
      });
    } else {
      ServerTester.sortServers(servers, descending: !sortAscending);
      final pinned = servers.where((s) => s.isPinned).toList();
      final unpinned = servers.where((s) => !s.isPinned).toList();
      servers = <VpnServer>[...pinned, ...unpinned];
    }
  }

  void _applyPingsTo(List<VpnServer> list) {
    // از کشِ server_pings_v1 فقط نتایج real معتبرند (مثل نسخهٔ قدیمی).
    SharedPreferences.getInstance().then((prefs) {
      final raw = prefs.getString(_pingsKey);
      if (raw == null) return;
      try {
        final decoded = jsonDecode(raw);
        if (decoded is! Map) return;
        final pings = Map<String, dynamic>.from(decoded);
        for (final server in list) {
          final entry = pings[server.id];
          if (entry is Map) {
            final ping = entry['ping'];
            final kind = entry['kind']?.toString();
            if (ping is int && ping > 0 && kind == 'real') {
              server.ping = ping;
              server.pingKind = PingKind.real;
              server.status = ServerStatus.online;
            }
          }
        }
        notifyListeners();
      } catch (_) {}
    });
  }

  // ── ذخیره‌سازی‌ها ──

  Future<void> _saveCustomServers() async {
    final prefs = await SharedPreferences.getInstance();
    final data = customServers
        .map((server) => <String, dynamic>{
              'id': server.id,
              'name': server.name,
              'flag': server.flag,
              'shareLink': server.shareLink,
              'protocol': server.protocol.name,
              'host': server.host,
              'port': server.port,
            })
        .toList();
    await prefs.setString(_customKey, jsonEncode(data));
  }

  Future<void> _saveDeleted() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_deletedKey, jsonEncode(deletedIds.toList()));
  }

  Future<void> _saveCustomSubTags() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_customSubTagsKey, jsonEncode(customSubTags));
  }

  Future<void> _savePinned() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_pinnedKey, jsonEncode(pinnedIds.toList()));
  }

  Future<void> _savePings() async {
    final prefs = await SharedPreferences.getInstance();
    final map = <String, dynamic>{};
    for (final server in servers) {
      if (server.ping != null &&
          server.ping! > 0 &&
          server.pingKind == PingKind.real) {
        map[server.id] = {'ping': server.ping, 'kind': 'real'};
      }
    }
    await prefs.setString(_pingsKey, jsonEncode(map));
  }

  Future<void> _saveOrder() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_orderKey, manualOrder);
  }

  Future<void> _cleanupOrphanGroupIds() async {
    if (userGroups.isEmpty) return;
    var changed = false;
    final cleaned = <String, List<String>>{};
    userGroups.forEach((k, v) {
      final filtered =
          v.where((id) => !deletedIds.contains(id)).toList();
      if (filtered.length != v.length) changed = true;
      cleaned[k] = filtered;
    });
    if (!changed) return;
    userGroups = cleaned;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_userGroupsKey, jsonEncode(userGroups));
  }

  // ── افزودن / ویرایش / حذف ──

  /// افزودن از share-link. خروجی: تعداد سرور افزوده‌شده.
  Future<int> addFromLink(String rawLink, {String? subTag}) async {
    final links = LinkParser.extractLinks(rawLink);
    var added = 0;
    final existingIds = <String>{
      ...customServers.map((s) => s.id),
      ...servers.map((s) => s.id),
    };
    for (final link in links) {
      final id = LinkParser.stableId('c', link);
      if (existingIds.contains(id)) continue;
      final server = LinkParser.parse(link, id: id);
      if (server == null) continue;
      server.isDeletable = true;
      customServers.add(server);
      if (subTag != null && subTag.isNotEmpty) {
        customSubTags[server.id] = subTag;
      }
      existingIds.add(id);
      added++;
      debugPrint('[Repo] added ${server.protocol.name}: ${server.displayName}');
    }
    if (added > 0) {
      await _saveCustomServers();
      await _saveCustomSubTags();
      rebuild();
      notifyListeners();
    }
    return added;
  }

  /// افزودن مستقیم (فرم دستی).
  Future<bool> addServer(VpnServer server, {String? subTag}) async {
    if (customServers.any((s) => s.id == server.id)) return false;
    server.isDeletable = true;
    customServers.add(server);
    if (subTag != null && subTag.isNotEmpty) {
      customSubTags[server.id] = subTag;
    }
    await _saveCustomServers();
    await _saveCustomSubTags();
    rebuild();
    notifyListeners();
    return true;
  }

  /// حذف دائمی (تکی یا گروهی) — مسیر v3: از لیست custom حذف یا
  /// در deletedIds ثبت؛ اوررایدها/تگ‌ها/پین/گروه‌ها هم پاک می‌شوند.
  Future<void> deleteServers(Set<String> ids) async {
    if (ids.isEmpty) return;
    customServers.removeWhere((s) => ids.contains(s.id));
    deletedIds.addAll(ids);
    for (final id in ids) {
      customSubTags.remove(id);
      fullOverrides.remove(id);
      pinnedIds.remove(id);
    }
    final prefs = await SharedPreferences.getInstance();
    for (final id in ids) {
      await ServerOverrides.remove(id);
      await prefs.remove('server_override_$id');
    }
    await _cleanupOrphanGroupIds();
    await _saveCustomServers();
    await _saveDeleted();
    await _saveCustomSubTags();
    await _savePinned();
    if (selected != null && ids.contains(selected!.id)) {
      await select(null);
    }
    rebuild();
    notifyListeners();
  }

  Future<void> updateOverride(String id, Map<String, dynamic> ov) async {
    if (ov.isEmpty) {
      fullOverrides.remove(id);
      await ServerOverrides.remove(id);
    } else {
      fullOverrides[id] = ov;
      await ServerOverrides.save(id, ov);
    }
    rebuild();
    notifyListeners();
  }

  Future<void> togglePin(VpnServer server) async {
    if (pinnedIds.contains(server.id)) {
      pinnedIds.remove(server.id);
    } else {
      pinnedIds.add(server.id);
    }
    server.isPinned = pinnedIds.contains(server.id);
    await _savePinned();
    rebuild();
    notifyListeners();
  }

  Future<void> reorderServer(int from, int to) async {
    if (from < 0 || from >= servers.length) return;
    var toIdx = to.clamp(0, servers.length - 1);
    final s = servers.removeAt(from);
    servers.insert(toIdx, s);
    manualOrder = servers.map((e) => e.id).toList();
    await _saveOrder();
    notifyListeners();
  }

  Future<void> toggleSort() async {
    sortAscending = !sortAscending;
    manualOrder = [];
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_sortKey, sortAscending);
    await _saveOrder();
    rebuild();
    notifyListeners();
  }

  // ── تست‌ها ──

  TestSession? _session;

  bool get testing => _session != null;

  void cancelTesting() {
    _session?.cancel();
  }

  Future<void> testAll() async {
    if (_session != null) return;
    final session = TestSession();
    _session = session;
    notifyListeners();
    debugPrint('[Repo] testAll begin (${servers.length} servers)');
    try {
      await ServerTester.testAll(
        servers,
        session: session,
        onChanged: notifyListeners,
      );
      await _savePings();
      await ConnectionLogService.logError('TEST',
          'testAll finished: ${servers.length} servers');
    } finally {
      _session = null;
      notifyListeners();
    }
  }

  Future<void> testOne(VpnServer server) async {
    final session = TestSession();
    try {
      await ServerTester.testOne(server, session: session);
      await _savePings();
      notifyListeners();
    } catch (e) {
      debugPrint('[Repo] testOne error: $e');
    }
  }

  /// سریع‌ترین سرور آنلاین (برای «اتصال سریع»).
  VpnServer? fastest() => ServerTester.fastest(servers);

  Future<void> saveSubs() async {
    await SubscriptionService.save(subs);
    notifyListeners();
  }

  Future<void> setSubs(List<Subscription> next) async {
    subs = next;
    await SubscriptionService.save(subs);
    rebuild();
    notifyListeners();
    unawaited(refreshSubscriptions());
  }
}
