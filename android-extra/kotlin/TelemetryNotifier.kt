package com.hasan.hasan_vpn

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build

/**
 * SINGLE user-facing status notification for Hasan VPN.
 *
 * Strategy:
 *  - One fixed NOTIFICATION_ID (4240). Never stack a second "speed" notif.
 *  - When speed is enabled: title + ↓/↑ + ping in the same notification.
 *  - When speed is disabled: same ID, title + short status only (still one notif).
 *  - setOnlyAlertOnce(true) so updates do not re-alert.
 *  - TorForegroundService / AetherService keep their OWN foreground IDs
 *    (4241 / 4242) required by Android for those services — they must not
 *    reuse 4240 or 4243.
 */
object TelemetryNotifier {
    // FIX: از channel مشترک NotificationHelper استفاده می‌کنیم.
    const val NOTIFICATION_ID = 4240

    fun show(context: Context, title: String, text: String) {
        val manager =
            context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

        NotificationHelper.ensureChannel(context)

        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(context, CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(context)
        }

        val icon = if (context.applicationInfo.icon != 0) {
            context.applicationInfo.icon
        } else {
            android.R.drawable.ic_dialog_info
        }

        // Read current VPN state so the action button reflects reality.
        val vpnActive = try {
            context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
                .getBoolean("flutter.vpn_active", false)
        } catch (_: Exception) { false }

        val launch = context.packageManager.getLaunchIntentForPackage(context.packageName)
        if (launch != null) {
            launch.putExtra("widget_action", "toggle")
            launch.putExtra("widget_type", "current")
            launch.putExtra("widget_title", "Notification")
        }
        val contentPi = launch?.let {
            PendingIntent.getActivity(
                context,
                1,
                it,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
        }

        // Action button: real toggle via WidgetHeadlessActivity (no UI flash).
        // This works even when the app was killed — Flutter engine spins up
        // in background, runs `widgetHeadlessMain`, performs connect/disconnect.
        val toggleIntent = Intent(context, WidgetHeadlessActivity::class.java).apply {
            putExtra(WidgetHeadlessActivity.EXTRA_TYPE, "current")
            putExtra(WidgetHeadlessActivity.EXTRA_PAYLOAD, "")
            putExtra(WidgetHeadlessActivity.EXTRA_TITLE, "Notification")
            putExtra(
                WidgetHeadlessActivity.EXTRA_ACTION,
                if (vpnActive) "disconnect" else "connect",
            )
            addFlags(
                Intent.FLAG_ACTIVITY_NEW_TASK or
                    Intent.FLAG_ACTIVITY_NO_ANIMATION or
                    Intent.FLAG_ACTIVITY_EXCLUDE_FROM_RECENTS,
            )
        }
        val togglePi = PendingIntent.getActivity(
            context,
            2,
            toggleIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val label = if (vpnActive) "\u0642\u0637\u0639 \u0627\u062a\u0635\u0627\u0644" else "\u0627\u062a\u0635\u0627\u0644"
        val actionIcon = if (vpnActive) {
            android.R.drawable.ic_menu_close_clear_cancel
        } else {
            android.R.drawable.ic_menu_manage
        }
        builder.addAction(actionIcon, label, togglePi)

        builder
            .setContentTitle(title)
            .setContentText(text)
            .setStyle(Notification.BigTextStyle().bigText(text))
            .setSmallIcon(icon)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setShowWhen(false)

        if (contentPi != null) {
            builder.setContentIntent(contentPi)
        }

        // Cancel legacy duplicate IDs from older builds (speed + status used to stack).
        manager.cancel(4243)
        manager.notify(NOTIFICATION_ID, builder.build())
    }

    fun hide(context: Context) {
        val manager =
            context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        manager.cancel(NOTIFICATION_ID)
    }
}
