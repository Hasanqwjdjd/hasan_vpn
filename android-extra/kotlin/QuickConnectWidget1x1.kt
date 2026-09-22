package com.hasan.hasan_vpn

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.content.Intent
import android.widget.RemoteViews

/**
 * ویجت ۱×۱ — اتصال مستقیم بدون باز کردن UI (مثل v2rayNG).
 * با کلیک: Intent با widget_bg_connect=true به MainActivity می‌رود
 * و Flutter باید بدون نمایش صفحه، اتصال را شروع کند.
 *
 * ثبت Manifest:
 * <receiver android:name=".QuickConnectWidget1x1" android:exported="true">
 *   <intent-filter>
 *     <action android:name="android.appwidget.action.APPWIDGET_UPDATE" />
 *   </intent-filter>
 *   <meta-data android:name="android.appwidget.provider"
 *       android:resource="@xml/quick_connect_widget_1x1_info" />
 * </receiver>
 */
class QuickConnectWidget1x1 : AppWidgetProvider() {

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
    ) {
        for (id in appWidgetIds) {
            updateAppWidget(context, appWidgetManager, id)
        }
    }

    override fun onReceive(context: Context, intent: Intent) {
        super.onReceive(context, intent)
        if (intent.action == ACTION_TAP) {
            val type = intent.getStringExtra(EXTRA_TYPE) ?: "server"
            val payload = intent.getStringExtra(EXTRA_PAYLOAD) ?: ""
            val title = intent.getStringExtra(EXTRA_TITLE) ?: ""
            val launch = context.packageManager
                .getLaunchIntentForPackage(context.packageName)
            if (launch != null) {
                launch.action = Intent.ACTION_VIEW
                // اتصال پس‌زمینه: اپ فقط برای سرویس باز می‌شود
                launch.putExtra("widget_action", "bg_connect")
                launch.putExtra("widget_type", type)
                launch.putExtra("widget_payload", payload)
                launch.putExtra("widget_title", title)
                launch.putExtra("widget_bg_connect", true)
                launch.putExtra("widget_auto_connect", true)
                launch.addFlags(
                    Intent.FLAG_ACTIVITY_NEW_TASK or
                        Intent.FLAG_ACTIVITY_CLEAR_TOP or
                        Intent.FLAG_ACTIVITY_SINGLE_TOP,
                )
                context.startActivity(launch)
            }
        }
    }

    companion object {
        const val ACTION_TAP = "com.hasan.hasan_vpn.WIDGET_1X1_TAP"
        const val EXTRA_TYPE = "type"
        const val EXTRA_PAYLOAD = "payload"
        const val EXTRA_TITLE = "title"

        fun updateAppWidget(
            context: Context,
            appWidgetManager: AppWidgetManager,
            appWidgetId: Int,
        ) {
            val prefs = context.getSharedPreferences(
                "FlutterSharedPreferences",
                Context.MODE_PRIVATE,
            )
            val raw = prefs.getString("flutter.quick_home_widgets_v1", null)
            var title = "Hasan"
            var type = "server"
            var payload = ""
            if (raw != null) {
                try {
                    val arr = org.json.JSONArray(raw)
                    if (arr.length() > 0) {
                        val o = arr.getJSONObject(0)
                        title = o.optString("title", "Hasan")
                        type = o.optString("type", "server")
                        payload = o.optString("payload", "")
                    }
                } catch (_: Exception) {
                }
            }
            val views = RemoteViews(context.packageName, R.layout.widget_quick_connect_1x1)
            views.setTextViewText(R.id.widget_title, title)

            val tap = Intent(context, QuickConnectWidget1x1::class.java).apply {
                action = ACTION_TAP
                putExtra(EXTRA_TYPE, type)
                putExtra(EXTRA_PAYLOAD, payload)
                putExtra(EXTRA_TITLE, title)
            }
            val pi = PendingIntent.getBroadcast(
                context,
                appWidgetId + 10000,
                tap,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
            views.setOnClickPendingIntent(R.id.widget_root, pi)
            appWidgetManager.updateAppWidget(appWidgetId, views)
        }
    }
}
