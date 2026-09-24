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
 * ویجت ۲×۱ — اولویت با binding اختصاصی Tor:
 *   flutter.widget_tor_$appWidgetId = "tor|bridgeLine|label"
 * اگر unbound باشد، اولین tap اپ را با SnackBar «پل را انتخاب کنید» باز می‌کند.
 * در غیر این صورت مثل قبل از اسلات‌های quick_home_widgets_v1 استفاده می‌کند.
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
        if (intent.action != ACTION_TAP) return

        val widgetId = intent.getIntExtra(EXTRA_WIDGET_ID, -1)
        val type = intent.getStringExtra(EXTRA_TYPE) ?: "server"
        val payload = intent.getStringExtra(EXTRA_PAYLOAD) ?: ""
        val title = intent.getStringExtra(EXTRA_TITLE) ?: ""
        val unbound = intent.getBooleanExtra(EXTRA_UNBOUND, false)

        if (unbound || (type == "tor" && payload.isEmpty())) {
            // اول tap بدون binding → باز کردن اپ برای انتخاب پل
            val launch = context.packageManager
                .getLaunchIntentForPackage(context.packageName)
            if (launch != null) {
                launch.action = Intent.ACTION_VIEW
                launch.putExtra("widget_action", "choose_tor_bridge")
                launch.putExtra("widget_id", widgetId)
                launch.putExtra("widget_snack", "Choose bridge")
                launch.addFlags(
                    Intent.FLAG_ACTIVITY_NEW_TASK or
                        Intent.FLAG_ACTIVITY_CLEAR_TOP or
                        Intent.FLAG_ACTIVITY_SINGLE_TOP,
                )
                context.startActivity(launch)
            }
            return
        }

        if (type == "tor") {
            // اتصال headless شبیه ۱×۱
            try {
                WidgetConnectService.start(context, type, payload, title, widgetId)
            } catch (_: Exception) {
                val launch = Intent(context, WidgetBgConnectActivity::class.java).apply {
                    putExtra("widget_type", type)
                    putExtra("widget_payload", payload)
                    putExtra("widget_title", title)
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_NO_ANIMATION)
                }
                context.startActivity(launch)
            }
            return
        }

        // سرور / DNS: باز کردن اپ + auto-connect
        val launch = context.packageManager
            .getLaunchIntentForPackage(context.packageName)
        if (launch != null) {
            launch.action = Intent.ACTION_VIEW
            launch.putExtra("widget_action", "connect")
            launch.putExtra("widget_type", type)
            launch.putExtra("widget_payload", payload)
            launch.putExtra("widget_title", title)
            launch.putExtra("widget_auto_connect", true)
            launch.putExtra("widget_id", widgetId)
            launch.addFlags(
                Intent.FLAG_ACTIVITY_NEW_TASK or
                    Intent.FLAG_ACTIVITY_CLEAR_TOP or
                    Intent.FLAG_ACTIVITY_SINGLE_TOP,
            )
            context.startActivity(launch)
        }
    }

    companion object {
        const val ACTION_TAP = "com.hasan.hasan_vpn.WIDGET_TAP"
        const val EXTRA_SLOT = "slot"
        const val EXTRA_TYPE = "type"
        const val EXTRA_PAYLOAD = "payload"
        const val EXTRA_TITLE = "title"
        const val EXTRA_WIDGET_ID = "widget_id"
        const val EXTRA_UNBOUND = "unbound"

        fun updateAppWidget(
            context: Context,
            appWidgetManager: AppWidgetManager,
            appWidgetId: Int,
        ) {
            val prefs = flutterPrefs(context)
            val views = RemoteViews(context.packageName, R.layout.widget_quick_connect)

            // ─── binding اختصاصی Tor برای این widget id ───
            val torBinding = prefs.getString("flutter.widget_tor_$appWidgetId", null)
            val progress = prefs.getString("flutter.widget_tor_progress_$appWidgetId", null)

            val title: String
            val subtitle: String
            val type: String
            val payload: String
            val unbound: Boolean

            if (torBinding != null && torBinding.isNotBlank()) {
                // format: tor|bridgeLine|label
                val parts = torBinding.split("|", limit = 3)
                type = parts.getOrNull(0) ?: "tor"
                payload = parts.getOrNull(1) ?: ""
                title = parts.getOrNull(2)?.ifBlank { "Tor" } ?: "Tor"
                subtitle = progress?.ifBlank { "Tor bridge" } ?: "Tor bridge"
                unbound = payload.isEmpty()
            } else {
                val slots = readSlots(prefs)
                val options = appWidgetManager.getAppWidgetOptions(appWidgetId)
                var slotIndex = options.getInt("slot_index", -1)
                if (slotIndex < 0) slotIndex = appWidgetId % 4
                val slot = slots.firstOrNull { it.index == slotIndex } ?: slots.getOrNull(0)
                if (slot != null && slot.type == "tor") {
                    type = "tor"
                    payload = slot.payload
                    title = slot.title.ifBlank { "Tor" }
                    subtitle = progress ?: slot.subtitle.ifBlank { "Tor bridge" }
                    unbound = payload.isEmpty()
                } else if (slot != null) {
                    type = slot.type
                    payload = slot.payload
                    title = slot.title.ifBlank { "Hasan VPN" }
                    subtitle = slot.subtitle.ifBlank { "افزودن از داخل برنامه" }
                    unbound = false
                } else {
                    type = "tor"
                    payload = ""
                    title = "Tor"
                    subtitle = "انتخاب پل / Choose bridge"
                    unbound = true
                }
            }

            views.setTextViewText(R.id.widget_title, title)
            views.setTextViewText(R.id.widget_subtitle, subtitle)

            val tap = Intent(context, QuickConnectWidget::class.java).apply {
                action = ACTION_TAP
                putExtra(EXTRA_WIDGET_ID, appWidgetId)
                putExtra(EXTRA_TYPE, type)
                putExtra(EXTRA_PAYLOAD, payload)
                putExtra(EXTRA_TITLE, title)
                putExtra(EXTRA_UNBOUND, unbound)
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
