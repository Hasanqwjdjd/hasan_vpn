package com.hasan.hasan_vpn

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder

/**
 * Foreground Service برای Tor. این سرویس Tor را در پس‌زمینه زنده نگه می‌دارد
 * و نوتیفیکیشن دائمی نشان می‌دهد تا Android فرایند برنامه را نکشد.
 *
 * توجه: این سرویس خودش Tor را اجرا نمی‌کند؛ فقط وضعیت foreground را نگه می‌دارد.
 * اجرای واقعی Tor در TorService انجام می‌شود که یک object است.
 */
/** FG notif ID 4241 — separate from unified status notif 4240 (TelemetryNotifier). */
class TorForegroundService : Service() {

    companion object {
        private const val TAG = "TorForegroundService"

        fun start(context: Context) {
            try {
                val intent = Intent(context, TorForegroundService::class.java)
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    context.startForegroundService(intent)
                } else {
                    context.startService(intent)
                }
                SafeLog.d(TAG, "Foreground service started")
            } catch (e: Exception) {
                SafeLog.e(TAG, "Unable to start foreground service", e)
            }
        }

        fun stop(context: Context) {
            try {
                context.stopService(
                    Intent(context, TorForegroundService::class.java)
                )
                SafeLog.d(TAG, "Foreground service stopped")
            } catch (e: Exception) {
                SafeLog.w(TAG, "Unable to stop foreground service", e)
            }
        }
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(
        intent: Intent?,
        flags: Int,
        startId: Int,
    ): Int {
        try {
            createChannel()
            val notification = buildNotification()
            NotificationHelper.startForegroundSafe(
                this,
                NotificationHelper.ID_TOR,
                notification,
            )
        } catch (e: Exception) {
            SafeLog.e(TAG, "startForeground failed", e)
            return START_NOT_STICKY
        }
        // START_NOT_STICKY: با بستن کامل برنامه سرویس دوباره زنده نشود
        return START_NOT_STICKY
    }

    override fun onTaskRemoved(rootIntent: Intent?) {
        // کاربر برنامه را از Recent بست → Tor و نوتیفیکیشن را متوقف کن
        try {
            TorService.stop()
        } catch (_: Exception) {
        }
        try {
            stopForeground(STOP_FOREGROUND_REMOVE)
        } catch (_: Exception) {
        }
        stopSelf()
        super.onTaskRemoved(rootIntent)
    }

    private fun createChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "Tor Connection",
                NotificationManager.IMPORTANCE_LOW,
            )
            channel.description = "Tor VPN connection status"
            channel.setShowBadge(false)
            val manager = getSystemService(NotificationManager::class.java)
            manager.createNotificationChannel(channel)
        }
    }

    private fun buildNotification(): Notification {
        // FIX: از helper مشترک استفاده کن.
        return NotificationHelper.build(
            this,
            NotificationHelper.ID_TOR,
            "Hasan VPN — Tor",
            "متصل به Tor · پورت SOCKS 9050",
        )
    }
}
