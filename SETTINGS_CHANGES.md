# CHANGES v4

## DEFECT 5 FIXED
`.github/workflows/build-apk.yml` is included in the ZIP (explicitly added;
previous zip tooling omitted the hidden `.github` directory).

## DEFECT 6 FIXED
- `path: plugins/flutter_vless_android` (relative to build_src/pubspec.yaml)
- CI step copies `android-extra/plugins/flutter_vless_android` →
  `build_src/plugins/flutter_vless_android` **before** `flutter pub get`
- `grep -q "VpnTuner"` verification on the copied fork

## DEFECT 7 FIXED
- `FALLBACK_BASE=369` present
- jobs `check` / `build` / `reset_counter` present
- cp lines for MainActivity, VpnTuner, HevLauncher, BootReceiver, Tor*, Widget*

All prior DEFECT 1–4 fixes retained.
