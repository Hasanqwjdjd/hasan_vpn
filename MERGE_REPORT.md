# MERGE REPORT — Grok ZIP + Claude ZIP + HEAD

Base: GitHub main (Hasanqwjdjd/hasan_vpn) at merge time.
Inputs:
- Grok: artifacts/hasan_vpn_final_fix.zip (full earlier pass)
- Claude: attachments/hasan_vpn_final_fix.zip (3 files only)
- HEAD: raw.githubusercontent.com main

## Classifications

| File | Decision | Reason |
|------|----------|--------|
| app/lib/services/v2ray_engine.dart | MERGE_MANUAL | HEAD base + Claude chain-grace 6s→15s + HTTP delay URL preference |
| app/lib/services/psiphon_service.dart | KEEP_HEAD / KEEP_YOURS | Generation tokens already on HEAD; Claude ZIP lacked them |
| app/lib/services/psiphon_auto.dart | KEEP_HEAD | Mobile-first already on HEAD |
| app/lib/screens/tor_screen.dart | KEEP_HEAD | Mobile-first + extraPool callers; Claude older |
| app/lib/services/tor_bridges.dart | KEEP_HEAD | extraPool restored on HEAD; do not drop |
| android-extra/kotlin/PsiphonService.kt | KEEP_HEAD | Kotlin generation guard on HEAD |
| android-extra/kotlin/AetherService.kt | KEEP_HEAD | testBinary + ELF already on HEAD |
| .github/workflows/build-apk.yml | KEEP_HEAD | tag + FALLBACK_BASE=369 |
| HEV screens/settings | KEEP_HEAD | Already on HEAD if present |
| android-extra/kotlin/TelemetryNotifier.kt | NEW FIX | Single notif ID 4240; actions; cancel legacy 4243 |
| android-extra/kotlin/TorForegroundService.kt | NEW FIX | FG ID 4243→4241 so it does not collide with status |
| app/lib/services/telemetry_service.dart | NEW FIX | Same-ID update when toggling speed |

## Conflicts

None requiring human decision. Claude's psiphon_service was strictly weaker (no gen tokens).

## Notification strategy

- User-facing status+speed: ID **4240**, channel `hasan_status`
- Tor core FG (required by Android): ID **4241**
- Aether core FG: ID **4242** (unchanged)
- Legacy ID **4243** cancelled on each status update
