# MERGE REPORT — Grok ZIP (A) + Claude ZIP (B)

Base: GitHub main (Hasanqwjdjd/hasan_vpn) at merge time.
- ZIP A (Grok / artifacts): aether WIW env, valid Psiphon protocols, subs, name clean, ping budget
- ZIP B (Claude / attachments): v2ray_engine, psiphon_service, tor_screen only (older)

## Classifications

| File | Decision | Reason |
|------|----------|--------|
| app/lib/models/aether_profile.dart | KEEP_A | WIW outer/inner env, scan verified, noize gfw/firewall, ACCESS_CLIENT_* |
| app/lib/services/psiphon_auto.dart | KEEP_A | No FRONTED-MEEK-HTTPS-OSSH; FRONTED-MEEK-OSSH first |
| app/lib/services/link_parser.dart | KEEP_A | this,'حسن' cleaning |
| app/lib/services/subscription_service.dart | KEEP_A | Sync defaults + 40s timeout; Aetris filtered |
| app/lib/screens/add_config_screen.dart | KEEP_A | Oblivion info block removed |
| app/lib/services/server_tester.dart | KEEP_A | Faster TCP/real budgets |
| app/lib/services/test_budget.dart | KEEP_A | concurrency default 32 |
| B: app/lib/services/v2ray_engine.dart | SKIP (HEAD) | Chain-grace 15s already on main |
| B: app/lib/services/psiphon_service.dart | SKIP (HEAD) | HEAD has generation tokens; B lacks them |
| B: app/lib/screens/tor_screen.dart | SKIP (HEAD) | HEAD mobile-first bridges already present |

## Conflicts

None. File sets barely overlap; B's unique files are already superseded on HEAD.

## Critical checklist

- [x] No LimitTunnelProtocols value FRONTED-MEEK-HTTPS-OSSH
- [x] AETHER_WIW_OUTER_PEER / AETHER_WIW_INNER_PEER for gool link outer=/inner=
- [x] scan stealth → verified
- [x] noize includes light, firewall, gfw
