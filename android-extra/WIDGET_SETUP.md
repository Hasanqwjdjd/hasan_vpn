# ویجت اتصال سریع (Quick Connect Widget)

## دو اندازه

| ویجت | فایل‌ها | رفتار |
|------|---------|--------|
| **۲×۱** | QuickConnectWidget.kt + widget_quick_connect.xml | اپ را با CLEAR_TOP باز می‌کند، همان سرور/DNS/Tor را انتخاب و **خودکار وصل** می‌کند. به صفحهٔ قبلی ناوبری نمی‌رود. |
| **۱×۱** | QuickConnectWidget1x1.kt + widget_quick_connect_1x1.xml | مثل v2rayNG: Intent با widget_bg_connect=true برای اتصال سریع |

## ثبت در AndroidManifest.xml

```xml
<receiver android:name=".QuickConnectWidget" android:exported="true" android:label="Hasan VPN 2x1">
  <intent-filter>
    <action android:name="android.appwidget.action.APPWIDGET_UPDATE" />
  </intent-filter>
  <meta-data android:name="android.appwidget.provider"
      android:resource="@xml/quick_connect_widget_info" />
</receiver>

<receiver android:name=".QuickConnectWidget1x1" android:exported="true" android:label="Hasan VPN 1x1">
  <intent-filter>
    <action android:name="android.appwidget.action.APPWIDGET_UPDATE" />
  </intent-filter>
  <meta-data android:name="android.appwidget.provider"
      android:resource="@xml/quick_connect_widget_1x1_info" />
</receiver>
```

```xml
<string name="widget_description">اتصال سریع ۲×۱</string>
<string name="widget_description_1x1">اتصال سریع ۱×۱</string>
```

## Intent extras (Flutter)

- widget_action: connect | bg_connect
- widget_type: server | dns | tor
- widget_payload: id یا خط پل یا primary|secondary
- widget_auto_connect: true
- widget_bg_connect: true (فقط ۱×۱)

در MainActivity extras را بخوانید و به Flutter (MethodChannel) بفرستید تا HomeScreen همان آیتم را انتخاب و connect کند.

## MethodChannel به‌روزرسانی ویجت

channel: com.hasan.hasan_vpn/widget
method: updateWidgets
