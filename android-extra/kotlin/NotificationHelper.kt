package com.hasan.hasan_vpn

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build

/**
 * Notification helper — کانال و استایل واحد برای همه‌ی سرویس‌های Hasan VPN.
 *
 * فلسفه:
 *  - همه‌ی سرویس‌ها یک CHANNEL مشترک دارن → کاربر یه گروه توی تنظیمات
 *    نوتیفیکیشن می‌بینه، نه ۵ تا گروه جدا.
 *  - هر سرویس foreground یه NOTIFICATION_ID مخصوص خودش داره (الزام
 *    اندروید: هر foreground service باید ID یکتا داشته باشه). ولی فقط
 *    یکی از اون‌ها در لحظه visible ه — وقتی سرویس قدیمی stop می‌شه،
 *    notification اش پاک می‌شه.
 *  - استایل یکسان: title = «Hasan VPN — <Type>»، same icon، same action.
 */
object NotificationHelper {
    /// کانال اصلی — همه‌ی سرویس‌ها از این استفاده می‌کنن.
    const val CHANNEL_ID = "hasan_vpn_main"
    private const val CHANNEL_NAME = "Hasan VPN"
    private const val CHANNEL_DESC = "اتصال VPN و وضعیت تونل"

    /// All notifications share this group key so Android stacks them under
    /// one header in the shade instead of showing several separate rows.
    const val GROUP_KEY = "hasan_vpn_group"

    /// Notification ID های یکتا برای هر سرویس foreground.
    /// اینا نباید تغییر کنن چون به startForeground گره خوردن.
    const val ID_TELEMETRY = 4240
    const val ID_TOR = 4241
    const val ID_AETHER = 4242
    const val ID_TUNNEL = 4243
    const val ID_WIDGET = 4245
    const val ID_XRAY = 4244  // برای XrayVPNService (forked plugin)

    /// ساخت/به‌روزرسانی کانال. idempotent.
    fun ensureChannel(context: Context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        try {
            val manager =
                context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            val channel = NotificationChannel(
                CHANNEL_ID,
                CHANNEL_NAME,
                NotificationManager.IMPORTANCE_LOW,
            ).apply {
                description = CHANNEL_DESC
                setShowBadge(false)
                setSound(null, null)
                enableVibration(false)
                setLockscreenVisibility(Notification.VISIBILITY_PRIVATE)
            }
            manager.createNotificationChannel(channel)
        } catch (_: Exception) {}
    }

    /// ساخت builder با تنظیمات پیش‌فرض (channel واحد).
    fun builder(context: Context): Notification.Builder {
        ensureChannel(context)
        val b = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(context, CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(context)
        }
        // Stack every Hasan VPN notification under one group header.
        b.setGroup(GROUP_KEY)
        // Update the same row instead of buzzing on every progress tick.
        b.setOnlyAlertOnce(true)
        return b
    }

    /// آیکون کوچک امن.
    fun smallIcon(context: Context): Int {
        val appIcon = context.applicationInfo.icon
        return if (appIcon != 0) appIcon else android.R.drawable.ic_dialog_info
    }

    /// PendingIntent به MainActivity (برای tap روی نوتیفیکیشن).
    fun contentIntent(context: Context): PendingIntent? {
        return try {
            val launch = context.packageManager.getLaunchIntentForPackage(context.packageName)
                ?: return null
            launch.flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
            PendingIntent.getActivity(
                context,
                1,
                launch,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
        } catch (_: Exception) {
            null
        }
    }

    /// خواندن وضعیت vpn_active از SharedPreferences فلاتر.
    fun isVpnActive(context: Context): Boolean = try {
        context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            .getBoolean("flutter.vpn_active", false)
    } catch (_: Exception) {
        false
    }

    /// PendingIntent برای toggle (connect/disconnect) بدون باز کردن UI.
    fun toggleIntent(context: Context): PendingIntent {
        val active = isVpnActive(context)
        val intent = Intent(context, WidgetHeadlessActivity::class.java).apply {
            putExtra(WidgetHeadlessActivity.EXTRA_TYPE, "current")
            putExtra(WidgetHeadlessActivity.EXTRA_PAYLOAD, "")
            putExtra(WidgetHeadlessActivity.EXTRA_TITLE, "Notification")
            putExtra(
                WidgetHeadlessActivity.EXTRA_ACTION,
                if (active) "disconnect" else "connect",
            )
            addFlags(
                Intent.FLAG_ACTIVITY_NEW_TASK or
                    Intent.FLAG_ACTIVITY_NO_ANIMATION or
                    Intent.FLAG_ACTIVITY_EXCLUDE_FROM_RECENTS,
            )
        }
        return PendingIntent.getActivity(
            context,
            2,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }

    /// ساخت نوتیفیکیشن کامل با title/text/action/tap.
    fun build(
        context: Context,
        idForService: Int,
        title: String,
        text: String,
        showAction: Boolean = true,
    ): Notification {
        val b = builder(context)
        val icon = smallIcon(context)

        b.setContentTitle(title)
            .setContentText(text)
            .setStyle(Notification.BigTextStyle().bigText(text))
            .setSmallIcon(icon)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setShowWhen(false)
            .setCategory(Notification.CATEGORY_SERVICE)

        contentIntent(context)?.let { b.setContentIntent(it) }

        if (showAction) {
            val active = isVpnActive(context)
            val label = if (active) "قطع اتصال" else "اتصال"
            val actionIcon = if (active) {
                android.R.drawable.ic_menu_close_clear_cancel
            } else {
                android.R.drawable.ic_menu_manage
            }
            b.addAction(actionIcon, label, toggleIntent(context))
        }
        return b.build()
    }

    /// startForeground امن (با API 34 type).
    fun startForegroundSafe(
        service: android.app.Service,
        id: Int,
        notification: Notification,
    ) {
        if (Build.VERSION.SDK_INT >= 34) {
            service.startForeground(
                id,
                notification,
                android.content.pm.ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE,
            )
        } else {
            service.startForeground(id, notification)
        }
    }

    /// cancel کردن همه‌ی نوتیفیکیشن‌های Hasan VPN (برای cleanup).
    fun cancelAll(context: Context) {
        try {
            val manager =
                context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            for (id in intArrayOf(
                ID_TELEMETRY, ID_TOR, ID_AETHER, ID_TUNNEL, ID_XRAY, ID_WIDGET,
            )) {
                manager.cancel(id)
            }
        } catch (_: Exception) {}
    }
}
