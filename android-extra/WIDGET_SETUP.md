# ویجت اتصال سریع — راهنمای ادغام کامل

## رفتار

| ویجت | کلاس | رفتار کاربر |
|------|------|-------------|
| **۲×۱** | `QuickConnectWidget` | اپ را با `CLEAR_TOP` باز می‌کند → HomeScreen سرور/DNS/Tor را انتخاب و **خودکار وصل** می‌کند (بدون زدن دایره). |
| **۱×۱** | `QuickConnectWidget1x1` → `WidgetBgConnectActivity` | Activity شفاف extras را در SharedPreferences می‌نویسد و Main را بیدار می‌کند؛ UI کامل دیده نمی‌شود (شبیه v2rayNG). |

## فایل‌ها

- `kotlin/QuickConnectWidget.kt`
- `kotlin/QuickConnectWidget1x1.kt`
- `kotlin/WidgetBgConnectActivity.kt`
- `res/layout/widget_quick_connect.xml`
- `res/layout/widget_quick_connect_1x1.xml`
- `res/xml/quick_connect_widget_info.xml`
- `res/xml/quick_connect_widget_1x1_info.xml`
- `res/drawable/widget_bg.xml`

## AndroidManifest

```xml
<receiver android:name=".QuickConnectWidget" android:exported="true"
    android:label="Hasan VPN 2x1">
  <intent-filter>
    <action android:name="android.appwidget.action.APPWIDGET_UPDATE" />
  </intent-filter>
  <meta-data android:name="android.appwidget.provider"
      android:resource="@xml/quick_connect_widget_info" />
</receiver>

<receiver android:name=".QuickConnectWidget1x1" android:exported="true"
    android:label="Hasan VPN 1x1">
  <intent-filter>
    <action android:name="android.appwidget.action.APPWIDGET_UPDATE" />
  </intent-filter>
  <meta-data android:name="android.appwidget.provider"
      android:resource="@xml/quick_connect_widget_1x1_info" />
</receiver>

<activity
    android:name=".WidgetBgConnectActivity"
    android:theme="@android:style/Theme.Translucent.NoTitleBar"
    android:excludeFromRecents="true"
    android:taskAffinity=""
    android:exported="true"
    android:noHistory="true" />
```

```xml
<string name="widget_description">اتصال سریع ۲×۱</string>
<string name="widget_description_1x1">اتصال سریع ۱×۱</string>
```

## MainActivity (Kotlin) — انتقال extras به Flutter

```kotlin
private val widgetChannel = "com.hasan.hasan_vpn/widget"

override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
  super.configureFlutterEngine(flutterEngine)
  MethodChannel(flutterEngine.dartExecutor.binaryMessenger, widgetChannel)
    .setMethodCallHandler { call, result ->
      when (call.method) {
        "updateWidgets" -> {
          val mgr = AppWidgetManager.getInstance(this)
          val c2 = ComponentName(this, QuickConnectWidget::class.java)
          for (id in mgr.getAppWidgetIds(c2)) {
            QuickConnectWidget.updateAppWidget(this, mgr, id)
          }
          val c1 = ComponentName(this, QuickConnectWidget1x1::class.java)
          for (id in mgr.getAppWidgetIds(c1)) {
            QuickConnectWidget1x1.updateAppWidget(this, mgr, id)
          }
          result.success(true)
        }
        "getLaunchExtras" -> {
          result.success(extractWidgetExtras(intent))
        }
        else -> result.notImplemented()
      }
    }
  // اگر اپ از قبل باز بود و ویجت زد
  intent?.let { pushWidgetIntent(it, flutterEngine) }
}

override fun onNewIntent(intent: Intent) {
  super.onNewIntent(intent)
  setIntent(intent)
  flutterEngine?.let { pushWidgetIntent(intent, it) }
}

private fun extractWidgetExtras(i: Intent?): Map<String, Any?> {
  if (i == null) return emptyMap()
  return mapOf(
    "widget_action" to i.getStringExtra("widget_action"),
    "widget_type" to i.getStringExtra("widget_type"),
    "widget_payload" to i.getStringExtra("widget_payload"),
    "widget_title" to i.getStringExtra("widget_title"),
    "widget_auto_connect" to i.getBooleanExtra("widget_auto_connect", false),
    "widget_bg_connect" to i.getBooleanExtra("widget_bg_connect", false),
  )
}

private fun pushWidgetIntent(i: Intent, engine: FlutterEngine) {
  val action = i.getStringExtra("widget_action") ?: return
  val payload = i.getStringExtra("widget_payload") ?: return
  MethodChannel(engine.dartExecutor.binaryMessenger, widgetChannel)
    .invokeMethod("onWidgetIntent", extractWidgetExtras(i))
}
```

## مسیر Flutter (از قبل در سورس)

1. `HomeWidgetService.pin(...)` → SharedPreferences `quick_home_widgets_v1`
2. `WidgetConnectHandler.consumePending()` / `listen` → `_handleWidgetRequest` در `HomeScreen`
3. سرور: انتخاب + `_toggleConnection()`
4. DNS: `SettingsService.setGameDns`
5. Tor: `TorScreen(initialBridgeLine:, autoConnect: true)`

## نکته واقعی دربارهٔ «بدون باز شدن برنامه»

Android برای شروع VPN معمولاً به یک Context اپ نیاز دارد. v2rayNG هم Activity کوتاه/شفاف دارد. `WidgetBgConnectActivity` همان نقش را دارد و بلافاصله `finish` می‌شود؛ کاربر عملاً UI کامل نمی‌بیند. اتصال کامل بدون هیچ Activity فقط با `VpnService` از قبل مجوزگرفته ممکن است و به کد بومی هستهٔ VPN وابسته است.
