#!/usr/bin/env python3
results = []

def apply(path, name, old, new):
    with open(path, "r", encoding="utf-8") as f:
        src = f.read()
    occurrences = src.count(old)
    if occurrences == 0:
        results.append((name, "MISS", f"anchor not found in {path}"))
        return
    if occurrences > 1:
        results.append((name, "MISS", f"anchor ambiguous ({occurrences}) in {path}"))
        return
    src = src.replace(old, new, 1)
    with open(path, "w", encoding="utf-8") as f:
        f.write(src)
    results.append((name, "OK", ""))

# Fix 1
st_path = "app/lib/services/server_tester.dart"
old_st = """  static VpnServer? fastest(List<VpnServer> servers) {
    VpnServer? best;
    double bestScore = -1;
    for (final server in servers) {
      final s = scoreOf(server);
      if (s < 0) continue;
      if (best == null || s > bestScore) {
        best = server;
        bestScore = s;
      }
    }
    return best;
  }"""
new_st = """  static VpnServer? fastest(List<VpnServer> servers) {
    VpnServer? best;
    double bestScore = -1;
    for (final server in servers) {
      // FIX(R3): ssh/tunnel از دکمه‌ی اصلی Connect وصل نمی‌شن.
      if (server.protocol == VpnProtocol.ssh ||
          server.protocol == VpnProtocol.tunnel) {
        continue;
      }
      final s = scoreOf(server);
      if (s < 0) continue;
      if (best == null || s > bestScore) {
        best = server;
        bestScore = s;
      }
    }
    return best;
  }"""
apply(st_path, "fix1_fastest_exclude_ssh_tunnel", old_st, new_st)

# Fix 2 - MainActivity widgets channel
ma_path = "android-extra/kotlin/MainActivity.kt"
old_ma1 = """    private val widgetChannel = "com.hasan.hasan_vpn/widget"
    private val widgetsChannel = "com.hasan.hasan_vpn/widgets"
    private val logsChannel = "com.hasan.hasan_vpn/logs"

    private var widgetChannelRef: MethodChannel? = null
    private var widgetsChannelRef: MethodChannel? = null"""
new_ma1 = """    private val widgetChannel = "com.hasan.hasan_vpn/widget"
    private val logsChannel = "com.hasan.hasan_vpn/logs"

    private var widgetChannelRef: MethodChannel? = null"""
apply(ma_path, "fix2a_remove_widgets_channel_decls", old_ma1, new_ma1)

old_ma2 = """
        widgetsChannelRef = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, widgetsChannel)
        widgetsChannelRef!!.setMethodCallHandler { call, result ->
            when (call.method) {
                "updateWidgets" -> { refreshAllWidgets(); result.success(true) }
                "getInitialIntent" -> result.success(intentToMap(intent))
                "getLaunchExtras" -> result.success(intentToMap(intent))
                "moveTaskToBack" -> { moveTaskToBack(true); result.success(true) }
                else -> result.notImplemented()
            }
        }"""
apply(ma_path, "fix2b_remove_widgets_channel_handler", old_ma2, "")

old_ma3 = """                widgetChannelRef?.invokeMethod("onWidgetIntent", map)
                widgetsChannelRef?.invokeMethod("onWidgetIntent", map)"""
new_ma3 = """                widgetChannelRef?.invokeMethod("onWidgetIntent", map)"""
apply(ma_path, "fix2c_remove_widgets_invokemethod", old_ma3, new_ma3)

# Fix 3 - home_screen controllers
hs_path = "app/lib/screens/home_screen.dart"
old_h1 = """    if (ok != true) return;

    final newName = ctrl.text.trim();
    if (newName.isEmpty) return;"""
new_h1 = """    if (ok != true) {
      ctrl.dispose();
      return;
    }

    final newName = ctrl.text.trim();
    ctrl.dispose();
    if (newName.isEmpty) return;"""
apply(hs_path, "fix3a_dispose_editServerName_ctrl", old_h1, new_h1)

old_h2 = """                                    );
                                    if (nn == null ||
                                        nn.isEmpty ||
                                        nn == name) {
                                      return;
                                    }"""
new_h2 = """                                    );
                                    ctrl.dispose();
                                    if (nn == null ||
                                        nn.isEmpty ||
                                        nn == name) {
                                      return;
                                    }"""
apply(hs_path, "fix3b_dispose_groupRename_ctrl", old_h2, new_h2)

old_h3 = """    );
    if (groupName == null || groupName.isEmpty) return;"""
new_h3 = """    );
    ctrl.dispose();
    if (groupName == null || groupName.isEmpty) return;"""
apply(hs_path, "fix3c_dispose_addSelectedToGroup_ctrl", old_h3, new_h3)

# Fix 4 - subscriptions controllers
subs_path = "app/lib/screens/subscriptions_screen.dart"
old_s1 = """    if (ok != true) return;
    final name = nameCtrl.text.trim();
    if (name.isEmpty) {"""
new_s1 = """    if (ok != true) {
      nameCtrl.dispose();
      return;
    }
    final name = nameCtrl.text.trim();
    nameCtrl.dispose();
    if (name.isEmpty) {"""
apply(subs_path, "fix4a_dispose_addEmptyGroup_ctrl", old_s1, new_s1)

old_s2 = """    if (ok != true) return;
    final raw = ctrl.text;
    if (raw.trim().isEmpty) return;"""
new_s2 = """    if (ok != true) {
      ctrl.dispose();
      return;
    }
    final raw = ctrl.text;
    ctrl.dispose();
    if (raw.trim().isEmpty) return;"""
apply(subs_path, "fix4b_dispose_pasteConfigDialog_ctrl", old_s2, new_s2)

old_s3 = """    final typedName = nameCtrl.text.trim();
    final typedUrl = urlCtrl.text.trim();

    if (ok != true) return;"""
new_s3 = """    final typedName = nameCtrl.text.trim();
    final typedUrl = urlCtrl.text.trim();
    nameCtrl.dispose();
    urlCtrl.dispose();

    if (ok != true) return;"""
apply(subs_path, "fix4c_dispose_addSubWithUrl_ctrls", old_s3, new_s3)

print("")
for name, status, note in results:
    tag = f"[{status}]"
    print(f"{tag:7s} {name} {('- ' + note) if note else ''}")

missed = [r for r in results if r[1] == "MISS"]
print("")
print(f"{len(missed)} MISS, {len(results)-len(missed)} OK")
