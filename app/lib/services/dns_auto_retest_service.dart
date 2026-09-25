// app/lib/services/dns_auto_retest_service.dart
//
// Goal 2.6: periodic re-test of the active DNS while the VPN is
// running, auto-swap if a better candidate shows up. Off by default
// (autoRetestIntervalMinutes == 0), opt-in via DnsAdvancedSettings.
//
// Hooked from V2RayEngine.connect() / disconnect() (phase f) so it
// naturally starts/stops with the tunnel — it does nothing on its own
// otherwise.

import 'dart:async';

import 'dns_advanced_settings.dart';
import 'dns_directory.dart';
import 'dns_ping_service.dart';
import 'dns_registry_service.dart';
import 'settings_service.dart';

class DnsAutoRetestService {
  DnsAutoRetestService._();
  static final DnsAutoRetestService instance = DnsAutoRetestService._();

  Timer? _timer;

  Future<void> start() async {
    await stop(); // no duplicate timers if called twice
    final minutes = await DnsAdvancedSettings.getAutoRetestIntervalMinutes();
    if (minutes <= 0) return; // opt-in, off by default

    _timer = Timer.periodic(Duration(minutes: minutes), (_) => _tick());
  }

  Future<void> stop() async {
    _timer?.cancel();
    _timer = null;
  }

  Future<void> _tick() async {
    try {
      final activeId = await DnsRegistryService.instance.getActiveId();
      if (activeId == null) return;

      final index = DnsDirectoryIndex.build();
      final active = index.byId[activeId];
      if (active == null) return; // custom entries aren't in the static index; skip

      final regionPref = await DnsAdvancedSettings.getRegionPreference();
      List<DnsEntry> candidates;
      switch (regionPref) {
        case RegionPreference.myCountry:
          candidates = index.forCountry(active.country);
          break;
        case RegionPreference.nearest:
        case RegionPreference.any:
          candidates = index.all.where((e) => e.tags.contains(DnsTag.anycast) || e.country == active.country).toList();
          break;
      }
      if (candidates.isEmpty) return;
      candidates = candidates.take(20).toList(); // keep the periodic check cheap

      final currentResult = await DnsPingService.instance.pingEntry(active, samples: 3);
      final best = await DnsPingService.instance.autoSelectBest(candidates, samples: 3);
      if (best == null) return;

      final bestResult = await DnsPingService.instance.pingEntry(best, samples: 3);

      // Only swap for a clear win, so we don't flap between two
      // similar servers every interval.
      final currentScore = (currentResult.medianMs ?? 999999) + (currentResult.jitterMs ?? 0) * 2;
      final bestScore = (bestResult.medianMs ?? 999999) + (bestResult.jitterMs ?? 0) * 2;
      if (best.id != active.id && bestScore < currentScore * 0.8) {
        await SettingsService.setGameDns(best.xrayPrimary, best.xraySecondary ?? best.xrayPrimary);
        await DnsRegistryService.instance.setActiveId(best.id);
      }
    } catch (_) {
      // Best-effort background task — never crash the VPN over a
      // failed re-test.
    }
  }
}
