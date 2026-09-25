// app/lib/services/dns_registry_service.dart
//
// Phase (c): per-user state for the DNS Game directory — pin/hide,
// ping stats, notes, custom entries — stored under the new
// `game_dns_registry_v2` key family, migrated once from the old v1
// keys in settings_service.dart. The old keys are left untouched (not
// deleted) so a failed/partial migration can be retried safely.

import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/dns_entry.dart';
import 'settings_service.dart';

class DnsRegistryService {
  DnsRegistryService._();
  static final DnsRegistryService instance = DnsRegistryService._();

  static const String _statsKey = 'game_dns_registry_v2_stats';
  static const String _customKey = 'game_dns_registry_v2_custom';
  static const String _migratedFlagKey = 'game_dns_registry_v2_migrated_from_v1';
  static const String _activeIdKey = 'game_dns_registry_v2_active_id';

  // ---------------------------------------------------------- Stats (pin/hide/ping/notes)

  Future<Map<String, DnsStats>> loadStats() async {
    await _migrateIfNeeded();
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_statsKey);
    if (raw == null) return {};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return {};
      return decoded.map(
        (k, v) => MapEntry(k.toString(), DnsStats.fromJson(Map<String, dynamic>.from(v as Map))),
      );
    } catch (_) {
      return {};
    }
  }

  Future<void> _saveStats(Map<String, DnsStats> stats) async {
    final prefs = await SharedPreferences.getInstance();
    final encoded = stats.map((k, v) => MapEntry(k, v.toJson()));
    await prefs.setString(_statsKey, jsonEncode(encoded));
  }

  Future<DnsStats> statFor(String entryId) async {
    final all = await loadStats();
    return all[entryId] ?? DnsStats();
  }

  /// Generic read-modify-write helper so callers (ping engine, UI
  /// actions) don't each re-implement the load/mutate/save dance.
  Future<DnsStats> updateStat(String entryId, void Function(DnsStats s) mutate) async {
    final all = await loadStats();
    final s = all[entryId] ?? DnsStats();
    mutate(s);
    all[entryId] = s;
    await _saveStats(all);
    return s;
  }

  Future<void> setPinned(String entryId, bool pinned) =>
      updateStat(entryId, (s) => s.pinned = pinned);

  Future<void> setHidden(String entryId, bool hidden) =>
      updateStat(entryId, (s) => s.hidden = hidden);

  Future<void> setDeleted(String entryId, bool deleted) =>
      updateStat(entryId, (s) => s.deleted = deleted);

  Future<void> setNotes(String entryId, String? notes) =>
      updateStat(entryId, (s) => s.notes = notes);

  /// Records a fresh ping outcome (see dns_ping_service.dart's
  /// PingResult) into persisted stats, bumping success/failure
  /// counters so the UI's small "42 ok / 1 fail" subtitle stays
  /// accurate over time, not just for the last sample.
  Future<void> recordPing(String entryId, {int? medianMs, int? jitterMs, required bool succeeded}) {
    return updateStat(entryId, (s) {
      s.lastCheckedAt = DateTime.now();
      if (succeeded) {
        s.lastPingMs = medianMs;
        s.lastJitterMs = jitterMs;
        s.successCount += 1;
      } else {
        s.failureCount += 1;
      }
    });
  }

  Future<List<String>> pinnedIds() async {
    final all = await loadStats();
    return all.entries.where((e) => e.value.pinned).map((e) => e.key).toList();
  }

  Future<List<String>> hiddenIds() async {
    final all = await loadStats();
    return all.entries.where((e) => e.value.hidden).map((e) => e.key).toList();
  }

  // ---------------------------------------------------------- Custom entries

  Future<List<CustomDnsEntry>> loadCustom() async {
    await _migrateIfNeeded();
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_customKey);
    if (raw == null) return [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return [];
      return decoded
          .whereType<Map>()
          .map((m) => CustomDnsEntry.fromJson(Map<String, dynamic>.from(m)))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> _saveCustom(List<CustomDnsEntry> list) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_customKey, jsonEncode(list.map((e) => e.toJson()).toList()));
  }

  Future<void> addCustom(CustomDnsEntry entry) async {
    final list = await loadCustom();
    list.add(entry);
    await _saveCustom(list);
  }

  Future<void> updateCustom(String id, CustomDnsEntry entry) async {
    final list = await loadCustom();
    final idx = list.indexWhere((e) => e.id == id);
    if (idx != -1) {
      list[idx] = entry;
      await _saveCustom(list);
    }
  }

  Future<void> removeCustom(String id) async {
    final list = await loadCustom();
    list.removeWhere((e) => e.id == id);
    await _saveCustom(list);
    await updateStat(id, (_) {}); // no-op, keeps id if stats exist; harmless
  }

  // ---------------------------------------------------------- Active DNS

  Future<String?> getActiveId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_activeIdKey);
  }

  Future<void> setActiveId(String id) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_activeIdKey, id);
  }

  Future<void> clearActiveId() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_activeIdKey);
  }

  // ---------------------------------------------------------- Import / export

  Future<String> exportJson() async {
    final stats = await loadStats();
    final custom = await loadCustom();
    final payload = {
      'version': 2,
      'exportedAt': DateTime.now().toIso8601String(),
      'stats': stats.map((k, v) => MapEntry(k, v.toJson())),
      'custom': custom.map((e) => e.toJson()).toList(),
    };
    return jsonEncode(payload);
  }

  /// Imports a previously-exported registry. When [merge] is true
  /// (default), existing stats/custom entries are kept and only
  /// missing/older ones are added; when false, the import replaces
  /// the current registry entirely.
  Future<void> importJson(String raw, {bool merge = true}) async {
    final decoded = jsonDecode(raw);
    if (decoded is! Map) {
      throw const FormatException('Registry export must be a JSON object');
    }

    final importedStats = <String, DnsStats>{};
    final statsRaw = decoded['stats'];
    if (statsRaw is Map) {
      statsRaw.forEach((k, v) {
        if (v is Map) {
          importedStats[k.toString()] = DnsStats.fromJson(Map<String, dynamic>.from(v));
        }
      });
    }

    final importedCustom = <CustomDnsEntry>[];
    final customRaw = decoded['custom'];
    if (customRaw is List) {
      for (final c in customRaw) {
        if (c is Map) {
          importedCustom.add(CustomDnsEntry.fromJson(Map<String, dynamic>.from(c)));
        }
      }
    }

    if (!merge) {
      await _saveStats(importedStats);
      await _saveCustom(importedCustom);
      return;
    }

    final currentStats = await loadStats();
    currentStats.addAll(importedStats); // imported wins on id collision
    await _saveStats(currentStats);

    final currentCustom = await loadCustom();
    final existingIds = currentCustom.map((e) => e.id).toSet();
    for (final c in importedCustom) {
      if (!existingIds.contains(c.id)) currentCustom.add(c);
    }
    await _saveCustom(currentCustom);
  }

  // ---------------------------------------------------------- Migration (v1 -> v2)

  /// One-shot migration from the old flat SharedPreferences keys in
  /// settings_service.dart into the new stats/custom shape. Guarded
  /// by [_migratedFlagKey] so it only runs once; if it throws partway
  /// through, the flag is NOT set, so it will simply retry next load
  /// (old keys are read-only here, never deleted).
  Future<void> _migrateIfNeeded() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_migratedFlagKey) == true) return;

    final stats = <String, DnsStats>{};

    // Old pin list was keyed by "primary|secondary" style strings, not
    // ids. We keep that exact string as the migrated id too, since the
    // v1 game_dns.dart list has no stable id of its own — the UI layer
    // matches on primary/secondary when resolving to a DnsEntry.
    final pinned = await SettingsService.getPinnedDns();
    for (final key in pinned) {
      stats.putIfAbsent(key, () => DnsStats()).pinned = true;
    }

    final hidden = await SettingsService.getHiddenDns();
    for (final key in hidden) {
      stats.putIfAbsent(key, () => DnsStats()).hidden = true;
    }

    final pings = await SettingsService.getDnsPingResults();
    pings.forEach((key, ms) {
      final s = stats.putIfAbsent(key, () => DnsStats());
      if (ms >= 0) {
        s.lastPingMs = ms;
        s.lastCheckedAt = DateTime.now();
        s.successCount = 1;
      } else {
        s.failureCount = 1;
      }
    });

    if (stats.isNotEmpty) {
      final existing = await _loadStatsRaw(prefs);
      existing.addAll(stats); // don't clobber anything v2 already has
      await _saveStats(existing);
    }

    // Old free-form custom DNS list -> CustomDnsEntry, generating a
    // fresh uuid-ish id (timestamp + index; good enough — these are
    // only referenced from within this device's own storage).
    final oldCustom = await SettingsService.getCustomDnsList();
    if (oldCustom.isNotEmpty) {
      final migrated = <CustomDnsEntry>[];
      final now = DateTime.now().millisecondsSinceEpoch;
      for (var i = 0; i < oldCustom.length; i++) {
        final c = oldCustom[i];
        migrated.add(CustomDnsEntry(
          id: 'migrated-$now-$i',
          name: c['name'] ?? 'Custom DNS',
          primary: c['primary'],
          secondary: c['secondary'],
        ));
      }
      final existingCustom = await loadCustom();
      existingCustom.addAll(migrated);
      await _saveCustom(existingCustom);
    }

    await prefs.setBool(_migratedFlagKey, true);
  }

  Future<Map<String, DnsStats>> _loadStatsRaw(SharedPreferences prefs) async {
    final raw = prefs.getString(_statsKey);
    if (raw == null) return {};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return {};
      return decoded.map(
        (k, v) => MapEntry(k.toString(), DnsStats.fromJson(Map<String, dynamic>.from(v as Map))),
      );
    } catch (_) {
      return {};
    }
  }
}
