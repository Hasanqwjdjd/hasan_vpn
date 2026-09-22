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
            val widgetId = intent.getIntExtra(EXTRA_WIDGET_ID, -1)
            // ─── اتصال کاملاً بدون UI از طریق WidgetConnectService ───
            try {
                WidgetConnectService.start(context, type, payload, title, widgetId)
            } catch (_: Exception) {
                // fallback: اگر سرویس کار نکرد، از Activity شفاف استفاده کن
                val launch = Intent(context, WidgetBgConnectActivity::class.java).apply {
                    putExtra("widget_type", type)
                    putExtra("widget_payload", payload)
                    putExtra("widget_title", title)
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_NO_ANIMATION)
                }
                context.startActivity(launch)
            }
        }
    }

    companion object {
        const val ACTION_TAP = "com.hasan.hasan_vpn.WIDGET_1X1_TAP"
        const val EXTRA_TYPE = "type"
        const val EXTRA_PAYLOAD = "payload"
        const val EXTRA_TITLE = "title"
        const val EXTRA_WIDGET_ID = "widget_id"

        fun updateAppWidget(
            context: Context,
            appWidgetManager: AppWidgetManager,
            appWidgetId: Int,
        ) {
            val prefs = context.getSharedPreferences(
                "FlutterSharedPreferences",
                Context.MODE_PRIVATE,
            )

            // ─── هر ویجت ۱×۱ سرور مخصوص خودش را دارد ───
            // binding format: "type|payload|title"
            val binding = prefs.getString("flutter.widget_server_$appWidgetId", null)
            var title = "Tap to set"
            var type = "server"
            var payload = ""
            if (binding != null) {
                val parts = binding.split("|", limit = 3)
                if (parts.size == 3) {
                    type = parts[0]
                    payload = parts[1]
                    title = parts[2].ifBlank { "Hasan" }
                }
            }

            val views = RemoteViews(context.packageName, R.layout.widget_quick_connect_1x1)
            views.setTextViewText(R.id.widget_title, title)

            val tap = Intent(context, QuickConnectWidget1x1::class.java).apply {
                action = ACTION_TAP
                putExtra(EXTRA_TYPE, type)
                putExtra(EXTRA_PAYLOAD, payload)
                putExtra(EXTRA_TITLE, title)
                putExtra(EXTRA_WIDGET_ID, appWidgetId)
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
