# ویجت صفحهٔ اصلی — راهنمای کامل ادغام

## رفتار مورد انتظار

| ویجت | رفتار |
|------|--------|
| **۱×۱** | `WidgetConnectService` → Activity شفاف → اتصال خودکار → `moveTaskToBack` (مثل v2rayNG، بدون ماندن روی UI) |
| **۲×۱** | باز شدن اپ با `CLEAR_TOP` + انتخاب همان سرور/DNS/Tor + **اتصال خودکار** بدون زدن دکمه |

## فایل‌های Kotlin

- `QuickConnectWidget.kt` — ۲×۱
- `QuickConnectWidget1x1.kt` — ۱×۱
- `WidgetConnectService.kt` — سرویس پس‌زمینهٔ ۱×۱
- `WidgetBgConnectActivity.kt` — Activity شفاف
- layouts/xml در `res/`

## AndroidManifest

```xml
<receiver android:name=".QuickConnectWidget" android:exported="true" android:label="Hasan 2x1">
  <intent-filter>
    <action android:name="android.appwidget.action.APPWIDGET_UPDATE" />
  </intent-filter>
  <meta-data android:name="android.appwidget.provider"
      android:resource="@xml/quick_connect_widget_info" />
</receiver>

<receiver android:name=".QuickConnectWidget1x1" android:exported="true" android:label="Hasan 1x1">
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
    android:noHistory="true"
    android:finishOnTaskLaunch="true" />

<service
    android:name=".WidgetConnectService"
    android:exported="false"
    android:foregroundServiceType="specialUse" />
```

## MainActivity — الزامی برای ویجت

```kotlin
private val widgetChannel = "com.hasan.hasan_vpn/widget"

override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
  super.configureFlutterEngine(flutterEngine)
  MethodChannel(flutterEngine.dartExecutor.binaryMessenger, widgetChannel)
    .setMethodCallHandler { call, result ->
      when (call.method) {
        "updateWidgets" -> {
          val mgr = AppWidgetManager.getInstance(this)
          mgr.getAppWidgetIds(ComponentName(this, QuickConnectWidget::class.java))
            .forEach { QuickConnectWidget.updateAppWidget(this, mgr, it) }
          mgr.getAppWidgetIds(ComponentName(this, QuickConnectWidget1x1::class.java))
            .forEach { QuickConnectWidget1x1.updateAppWidget(this, mgr, it) }
          result.success(true)
        }
        "getLaunchExtras" -> result.success(extractWidgetExtras(intent))
        "moveTaskToBack" -> {
          moveTaskToBack(true)
          result.success(true)
        }
        else -> result.notImplemented()
      }
    }
  intent?.let { pushWidgetIntent(it, flutterEngine) }
}

override fun onNewIntent(intent: Intent) {
  super.onNewIntent(intent)
  setIntent(intent)
  flutterEngine?.let { pushWidgetIntent(intent, it) }
  // اگر bg_connect بود فوراً به پس‌زمینه
  if (intent.getBooleanExtra("widget_bg_connect", false)) {
    moveTaskToBack(true)
  }
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
  MethodChannel(engine.dartExecutor.binaryMessenger, widgetChannel)
    .invokeMethod("onWidgetIntent", extractWidgetExtras(i))
}
```

## نکته واقعی Android

شروع VpnService معمولاً به Context اپ نیاز دارد؛ v2rayNG هم Activity/سرویس کوتاه دارد.
هدف ۱×۱: **بدون ماندن روی UI** — نه «بدون هیچ پردازه‌ای».
با `WidgetConnectService` + Activity شفاف + `moveTaskToBack` تجربه نزدیک به v2rayNG است.
