package com.hasan.hasan_vpn

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.content.Intent
import android.widget.RemoteViews

/**
 * E7: Tor-only 2x1 widget — toggles Tor via broadcast action.
 * Wire in AndroidManifest + res/xml like QuickConnectWidget.
 */
class TorQuickWidget : AppWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
    ) {
        for (id in appWidgetIds) {
            val views = RemoteViews(context.packageName, android.R.layout.simple_list_item_1)
            views.setTextViewText(android.R.id.text1, "Tor")
            val intent = Intent(context, TorQuickWidget::class.java).setAction(ACTION_TOGGLE)
            val pi = PendingIntent.getBroadcast(
                context, id, intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
            views.setOnClickPendingIntent(android.R.id.text1, pi)
            appWidgetManager.updateAppWidget(id, views)
        }
    }

    override fun onReceive(context: Context, intent: Intent) {
        super.onReceive(context, intent)
        if (intent.action == ACTION_TOGGLE) {
            // Headless: start Tor vanilla via TorService
            try {
                TorService.start(context, "vanilla", null, null)
            } catch (_: Exception) {
            }
        }
    }

    companion object {
        const val ACTION_TOGGLE = "com.hasan.hasan_vpn.TOR_WIDGET_TOGGLE"
    }
}
