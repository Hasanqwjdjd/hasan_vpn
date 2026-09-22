# ویجت اتصال سریع (Quick Connect Widget)

فایل‌های لازم در همین پوشه:

- `kotlin/QuickConnectWidget.kt`
- `res/layout/widget_quick_connect.xml`
- `res/xml/quick_connect_widget_info.xml`
- `res/drawable/widget_bg.xml`

## ثبت در AndroidManifest.xml

داخل `<application>`:

```xml
<receiver
    android:name=".QuickConnectWidget"
    android:exported="true"
    android:label="Hasan VPN">
    <intent-filter>
        <action android:name="android.appwidget.action.APPWIDGET_UPDATE" />
    </intent-filter>
    <meta-data
        android:name="android.appwidget.provider"
        android:resource="@xml/quick_connect_widget_info" />
</receiver>
```

در صورت نیاز، string برای description:

```xml
<string name="widget_description">اتصال سریع سرور / DNS / Tor</string>
```

## MethodChannel (اختیاری)

در `MainActivity` برای refresh ویجت بعد از pin:

```kotlin
MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.hasan.hasan_vpn/widget")
  .setMethodCallHandler { call, result ->
    if (call.method == "updateWidgets") {
      val mgr = AppWidgetManager.getInstance(this)
      val ids = mgr.getAppWidgetIds(ComponentName(this, QuickConnectWidget::class.java))
      for (id in ids) {
        QuickConnectWidget.updateAppWidget(this, mgr, id)
      }
      result.success(true)
    } else {
      result.notImplemented()
    }
  }
```

## استفاده کاربر

1. داخل اپ روی آیکون ویجت (شبکه/widgets) کنار سرور، DNS یا پل Tor بزنید.
2. در صفحهٔ اصلی گوشی: ویجت‌ها → Hasan VPN را اضافه کنید (تا ۴ اسلات).
3. با زدن ویجت، اپ باز می‌شود و intent اتصال ارسال می‌شود.

## جلوگیری از زنده شدن ناخواسته در پس‌زمینه

- `TorForegroundService` با `START_NOT_STICKY` و `onTaskRemoved` متوقف می‌شود.
- سرویس VPN سیستم (flutter_vless) تا وقتی اتصال VPN فعال است نوتیفیکیشن دارد — این رفتار استاندارد Android است.
- برای قطع کامل: در اپ Disconnect بزنید، یا در تنظیمات سیستم Always-on VPN را برای این اپ خاموش کنید.
