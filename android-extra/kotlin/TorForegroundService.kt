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
class TorForegroundService : Service() {

    companion object {
        private const val TAG = "TorForegroundService"
        private const val CHANNEL_ID = "tor_core"
        private const val NOTIFICATION_ID = 4243

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
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                startForeground(
                    NOTIFICATION_ID,
                    notification,
                    ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE,
                )
            } else {
                startForeground(NOTIFICATION_ID, notification)
            }
        } catch (e: Exception) {
            SafeLog.e(TAG, "startForeground failed", e)
            return START_NOT_STICKY
        }
        return START_STICKY
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
        val tapIntent = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or
                Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        val pi = PendingIntent.getActivity(
            this,
            0,
            tapIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

        val iconRes = resources.getIdentifier(
            "ic_launcher", "mipmap", packageName
        )
        val smallIcon = if (iconRes != 0) iconRes else android.R.drawable.ic_lock_lock

        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
        }

        return builder
            .setContentTitle("Tor")
            .setContentText("متصل به Tor · پورت SOCKS 9050")
            .setSmallIcon(smallIcon)
            .setContentIntent(pi)
            .setOngoing(true)
            .setShowWhen(false)
            .build()
    }
}
