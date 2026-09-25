# PROOF.md (v4)

## DEFECT 5 — build-apk.yml included

Path in ZIP: `.github/workflows/build-apk.yml`

## DEFECT 6 — path override resolves in CI

### dependency_overrides (app/pubspec.yaml → copied to build_src/pubspec.yaml)
```
dependency_overrides:
  flutter_vless_android:
    path: plugins/flutter_vless_android
```

### CI step (immediately before `flutter pub get`)
```
      - name: Copy forked flutter_vless_android into build tree
        run: |
          set -e
          rm -rf build_src/plugins
          mkdir -p build_src/plugins
          cp -a android-extra/plugins/flutter_vless_android \
            build_src/plugins/flutter_vless_android
          # Safety: verify the fork really contains VpnTuner hook
          grep -q "VpnTuner" \
            build_src/plugins/flutter_vless_android/android/src/main/kotlin/com/github/tfox/flutter_vless/xray/service/XrayVPNService.kt \
            || (echo "FATAL: VpnTuner hook missing from fork" && exit 1)
          echo "Forked plugin copied and verified"

      - name: Flutter pub get
```

Resolved path at pub get time: `build_src/plugins/flutter_vless_android`.

## DEFECT 7 — invariants

### FALLBACK_BASE (unchanged)
```
FALLBACK_BASE=369
```

### build-counter jobs present
`jobs:` → `check:` → `build:` → `reset_counter:` (unchanged names).

### Kotlin cp lines (new + existing)
```
          cp -f android-extra/kotlin/MainActivity.kt "$KT_DIR/MainActivity.kt"
          cp -f android-extra/kotlin/VpnTuner.kt "$KT_DIR/VpnTuner.kt"
          cp -f android-extra/kotlin/HevLauncher.kt "$KT_DIR/HevLauncher.kt"
          cp -f android-extra/kotlin/BootReceiver.kt "$KT_DIR/BootReceiver.kt"
          cp -f android-extra/kotlin/AetherService.kt "$KT_DIR/AetherService.kt"
          cp -f android-extra/kotlin/TelemetryNotifier.kt "$KT_DIR/TelemetryNotifier.kt"
          cp -f android-extra/kotlin/SafeLog.kt "$KT_DIR/SafeLog.kt"
          cp -f android-extra/kotlin/TorService.kt "$KT_DIR/TorService.kt"
          cp -f android-extra/kotlin/TorForegroundService.kt "$KT_DIR/TorForegroundService.kt"
          cp -f android-extra/kotlin/LiveMonitorService.kt "$KT_DIR/LiveMonitorService.kt"
          cp -f android-extra/kotlin/QuickConnectWidget1x1.kt "$KT_DIR/QuickConnectWidget1x1.kt"
          cp -f android-extra/kotlin/WidgetBgConnectActivity.kt "$KT_DIR/WidgetBgConnectActivity.kt"
          cp -f android-extra/kotlin/WidgetConnectService.kt "$KT_DIR/WidgetConnectService.kt"
          cp -f android-extra/kotlin/WidgetHeadlessActivity.kt "$KT_DIR/WidgetHeadlessActivity.kt"
```

### Manifest (Task C + A8)
```
              <uses-permission android:name="android.permission.QUERY_ALL_PACKAGES"/>
              <uses-permission android:name="android.permission.RECEIVE_BOOT_COMPLETED"/>
```
```
                  android:name="com.hasan.hasan_vpn.BootReceiver"
```
with BOOT_COMPLETED / QUICKBOOT_POWERON intent-filter.

## DEFECT 1 consumer (unchanged from v3)
Forked XrayVPNService before establish():
```
                val apply = tunerClz.getMethod("applyToBuilder", Builder::class.java)
                apply.invoke(tunerClz, builder)
...
            mInterface = builder.establish()
```

## DEFECT 2 / 3 (unchanged from v3)
HevLauncher writes real YAML + ProcessBuilder(binary, yamlPath); startHev call site in v2ray_engine.
No `_hasan*` keys in Xray JSON; assets → filesDir = XRAY_LOCATION_ASSET.
