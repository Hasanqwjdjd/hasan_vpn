package com.hasan.hasan_vpn

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.widget.RemoteViews
import org.json.JSONArray

/**
 * ویجت صفحهٔ اصلی — اتصال سریع به سرور / DNS / پل Tor.
 * حداکثر ۴ اسلات از SharedPreferences کلید quick_home_widgets_v1
 * (همگام با Flutter SharedPreferences).
 *
 * در AndroidManifest ثبت شود:
 * <receiver android:name=".QuickConnectWidget" android:exported="true">
 *   <intent-filter>
 *     <action android:name="android.appwidget.action.APPWIDGET_UPDATE" />
 *   </intent-filter>
 *   <meta-data android:name="android.appwidget.provider"
 *       android:resource="@xml/quick_connect_widget_info" />
 * </receiver>
 */
class QuickConnectWidget : AppWidgetProvider() {

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
            val slotIndex = intent.getIntExtra(EXTRA_SLOT, 0)
            val type = intent.getStringExtra(EXTRA_TYPE) ?: "server"
            val payload = intent.getStringExtra(EXTRA_PAYLOAD) ?: ""
            val title = intent.getStringExtra(EXTRA_TITLE) ?: ""
            // باز کردن اپ با deep-link برای اتصال
            val launch = context.packageManager
                .getLaunchIntentForPackage(context.packageName)
            if (launch != null) {
                launch.action = Intent.ACTION_VIEW
                launch.putExtra("widget_action", "connect")
                launch.putExtra("widget_type", type)
                launch.putExtra("widget_payload", payload)
                launch.putExtra("widget_title", title)
                launch.putExtra("widget_slot", slotIndex)
                launch.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
                context.startActivity(launch)
            }
        }
    }

    companion object {
        const val ACTION_TAP = "com.hasan.hasan_vpn.WIDGET_TAP"
        const val EXTRA_SLOT = "slot"
        const val EXTRA_TYPE = "type"
        const val EXTRA_PAYLOAD = "payload"
        const val EXTRA_TITLE = "title"

        fun updateAppWidget(
            context: Context,
            appWidgetManager: AppWidgetManager,
            appWidgetId: Int,
        ) {
            val prefs = flutterPrefs(context)
            val slots = readSlots(prefs)
            // هر ویجت به یک اسلات map می‌شود (appWidgetId % 4 یا از option)
            val options = appWidgetManager.getAppWidgetOptions(appWidgetId)
            var slotIndex = options.getInt("slot_index", -1)
            if (slotIndex < 0) slotIndex = appWidgetId % 4
            val slot = slots.firstOrNull { it.index == slotIndex } ?: slots.getOrNull(0)

            val views = RemoteViews(context.packageName, R.layout.widget_quick_connect)
            val title = slot?.title?.ifBlank { "Hasan VPN" } ?: "Hasan VPN"
            val subtitle = slot?.subtitle?.ifBlank { "افزودن از داخل برنامه" }
                ?: "افزودن از داخل برنامه"
            views.setTextViewText(R.id.widget_title, title)
            views.setTextViewText(R.id.widget_subtitle, subtitle)

            val tap = Intent(context, QuickConnectWidget::class.java).apply {
                action = ACTION_TAP
                putExtra(EXTRA_SLOT, slot?.index ?: 0)
                putExtra(EXTRA_TYPE, slot?.type ?: "server")
                putExtra(EXTRA_PAYLOAD, slot?.payload ?: "")
                putExtra(EXTRA_TITLE, title)
            }
            val pi = PendingIntent.getBroadcast(
                context,
                appWidgetId,
                tap,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
            views.setOnClickPendingIntent(R.id.widget_root, pi)

            appWidgetManager.updateAppWidget(appWidgetId, views)
        }

        /** SharedPreferences مربوط به Flutter (shared_preferences plugin). */
        private fun flutterPrefs(context: Context): SharedPreferences {
            return context.getSharedPreferences(
                "FlutterSharedPreferences",
                Context.MODE_PRIVATE,
            )
        }

        data class Slot(
            val index: Int,
            val type: String,
            val title: String,
            val subtitle: String,
            val payload: String,
        )

        private fun readSlots(prefs: SharedPreferences): List<Slot> {
            // Flutter shared_preferences کلیدها را با پیشوند flutter. ذخیره می‌کند
            val raw = prefs.getString("flutter.quick_home_widgets_v1", null)
                ?: return emptyList()
            return try {
                val arr = JSONArray(raw)
                val out = mutableListOf<Slot>()
                for (i in 0 until arr.length()) {
                    val o = arr.getJSONObject(i)
                    out.add(
                        Slot(
                            index = o.optInt("index", i),
                            type = o.optString("type", "server"),
                            title = o.optString("title", ""),
                            subtitle = o.optString("subtitle", ""),
                            payload = o.optString("payload", ""),
                        ),
                    )
                }
                out
            } catch (_: Exception) {
                emptyList()
            }
        }
    }
}
