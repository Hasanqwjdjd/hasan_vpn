package com.hasan.hasan_vpn

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.widget.RemoteViews

/**
 * Tor-only 2×1 widget.
 *
 * Binding: flutter.widget_tor_$appWidgetId = "tor|bridgeLine|label"
 * Progress: flutter.widget_tor_progress_$appWidgetId = "Bootstrapped 45%"
 *
 * First tap when unbound → opens app with "Choose bridge" hint.
 * Bound tap → toggles Tor headless via WidgetConnectService.
 * While Tor bootstraps, subtitle shows live Bootstrap % from TorService.
 */
class TorQuickWidget : AppWidgetProvider() {

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
    ) {
        for (id in appWidgetIds) updateAppWidget(context, appWidgetManager, id)
    }

    override fun onReceive(context: Context, intent: Intent) {
        super.onReceive(context, intent)
        val widgetId = intent.getIntExtra(EXTRA_WIDGET_ID, -1)
        when (intent.action) {
            ACTION_TAP -> handleTap(context, widgetId)
            ACTION_REFRESH -> {
                if (widgetId > 0) {
                    val mgr = AppWidgetManager.getInstance(context)
                    updateAppWidget(context, mgr, widgetId)
                }
            }
        }
    }

    private fun handleTap(context: Context, widgetId: Int) {
        if (widgetId <= 0) return
        val prefs = flutterPrefs(context)
        val binding = prefs.getString(KEY_BINDING_PREFIX + widgetId, null)
        val bound = !binding.isNullOrBlank()
        val payload = binding?.split("|", limit = 3)?.getOrNull(1) ?: ""

        if (!bound || payload.isEmpty()) {
            val launch = context.packageManager
                .getLaunchIntentForPackage(context.packageName) ?: return
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
            return
        }

        try {
            WidgetConnectService.start(context, "tor", payload, "Tor", widgetId)
        } catch (_: Exception) {
            val launch = Intent(context, WidgetBgConnectActivity::class.java).apply {
                putExtra("widget_type", "tor")
                putExtra("widget_payload", payload)
                putExtra("widget_title", "Tor")
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_NO_ANIMATION)
            }
            context.startActivity(launch)
        }
    }

    companion object {
        const val ACTION_TAP = "com.hasan.hasan_vpn.TOR_WIDGET_TAP"
        const val ACTION_REFRESH = "com.hasan.hasan_vpn.TOR_WIDGET_REFRESH"
        const val EXTRA_WIDGET_ID = "widget_id"
        const val KEY_BINDING_PREFIX = "flutter.widget_tor_"
        const val KEY_PROGRESS_PREFIX = "flutter.widget_tor_progress_"

        fun updateAppWidget(
            context: Context,
            appWidgetManager: AppWidgetManager,
            appWidgetId: Int,
        ) {
            val prefs = flutterPrefs(context)
            val views = RemoteViews(context.packageName, R.layout.widget_quick_connect)

            val binding = prefs.getString(KEY_BINDING_PREFIX + appWidgetId, null)
            val storedProgress =
                prefs.getString(KEY_PROGRESS_PREFIX + appWidgetId, null)

            val livePct = try { TorService.getBootstrapPercent() } catch (_: Exception) { 0 }
            val liveMsg = try { TorService.getBootstrapMessage() } catch (_: Exception) { "" }

            val title: String
            val subtitle: String

            if (!binding.isNullOrBlank()) {
                val parts = binding.split("|", limit = 3)
                title = parts.getOrNull(2)?.ifBlank { "Tor" } ?: "Tor"
                subtitle = when {
                    livePct in 1..99 -> "Bootstrapped $livePct%"
                    !storedProgress.isNullOrBlank() -> storedProgress
                    liveMsg.isNotBlank() -> liveMsg
                    else -> "Tor ready"
                }
            } else {
                title = "Tor"
                subtitle = "انتخاب پل / Choose bridge"
            }

            views.setTextViewText(R.id.widget_title, title)
            views.setTextViewText(R.id.widget_subtitle, subtitle)

            val tap = Intent(context, TorQuickWidget::class.java).apply {
                action = ACTION_TAP
                putExtra(EXTRA_WIDGET_ID, appWidgetId)
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

        private fun flutterPrefs(context: Context): SharedPreferences =
            context.getSharedPreferences(
                "FlutterSharedPreferences",
                Context.MODE_PRIVATE,
            )
    }
}
