package com.hasan.hasan_vpn

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper

/**
 * سرویس اتصال از ویجت ۱×۱ — بدون ماندن روی UI (رفتار نزدیک به v2rayNG).
 *
 * جریان:
 * 1) ویجت این سرویس را start می‌کند (نه Activity کامل)
 * 2) درخواست در SharedPreferences نوشته می‌شود
 * 3) Activity شفاف خیلی کوتاه Main را بیدار می‌کند و فوراً به پس‌زمینه می‌رود
 *
 * Manifest:
 * <service
 *   android:name=".WidgetConnectService"
 *   android:exported="false"
 *   android:foregroundServiceType="specialUse" />
 */
class WidgetConnectService : Service() {

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val type = intent?.getStringExtra(EXTRA_TYPE) ?: "server"
        val payload = intent?.getStringExtra(EXTRA_PAYLOAD) ?: ""
        val title = intent?.getStringExtra(EXTRA_TITLE) ?: ""

        try {
            startFgQuiet()
        } catch (_: Exception) {
        }

        // ذخیره برای Flutter
        try {
            val prefs = getSharedPreferences("FlutterSharedPreferences", MODE_PRIVATE)
            prefs.edit()
                .putString("flutter.widget_pending_action", "bg_connect")
                .putString("flutter.widget_pending_type", type)
                .putString("flutter.widget_pending_payload", payload)
                .putString("flutter.widget_pending_title", title)
                .putBoolean("flutter.widget_pending_auto", true)
                .putLong("flutter.widget_pending_ts", System.currentTimeMillis())
                .apply()
        } catch (_: Exception) {
        }

        // بیدار کردن اپ با Activity شفاف (VPN روی Android معمولاً Context می‌خواهد)
        try {
            val launch = Intent(this, WidgetBgConnectActivity::class.java).apply {
                putExtra("widget_type", type)
                putExtra("widget_payload", payload)
                putExtra("widget_title", title)
                putExtra("widget_bg_connect", true)
                putExtra("widget_from_service", true)
                addFlags(
                    Intent.FLAG_ACTIVITY_NEW_TASK or
                        Intent.FLAG_ACTIVITY_NO_ANIMATION or
                        Intent.FLAG_ACTIVITY_EXCLUDE_FROM_RECENTS,
                )
            }
            startActivity(launch)
        } catch (_: Exception) {
        }

        // توقف سرویس بعد از چند ثانیه
        Handler(Looper.getMainLooper()).postDelayed({
            try {
                stopForeground(STOP_FOREGROUND_REMOVE)
            } catch (_: Exception) {
            }
            stopSelf()
        }, 2500)

        return START_NOT_STICKY
    }

    private fun startFgQuiet() {
        val channelId = "widget_connect_quiet"
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val nm = getSystemService(NotificationManager::class.java)
            val ch = NotificationChannel(
                channelId,
                "Quick connect",
                NotificationManager.IMPORTANCE_MIN,
            ).apply {
                setShowBadge(false)
                description = "Background widget connect"
            }
            nm?.createNotificationChannel(ch)
        }
        val n: Notification = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, channelId)
                .setContentTitle("Hasan VPN")
                .setContentText("Connecting…")
                .setSmallIcon(android.R.drawable.ic_lock_lock)
                .setOngoing(true)
                .build()
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
                .setContentTitle("Hasan VPN")
                .setContentText("Connecting…")
                .setSmallIcon(android.R.drawable.ic_lock_lock)
                .setOngoing(true)
                .build()
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(4245, n, android.content.pm.ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE)
        } else {
            startForeground(4245, n)
        }
    }

    companion object {
        const val EXTRA_TYPE = "type"
        const val EXTRA_PAYLOAD = "payload"
        const val EXTRA_TITLE = "title"

        fun start(context: Context, type: String, payload: String, title: String) {
            val i = Intent(context, WidgetConnectService::class.java).apply {
                putExtra(EXTRA_TYPE, type)
                putExtra(EXTRA_PAYLOAD, payload)
                putExtra(EXTRA_TITLE, title)
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(i)
            } else {
                context.startService(i)
            }
        }
    }
}
