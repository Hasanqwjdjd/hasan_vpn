package com.hasan.hasan_vpn

import android.app.Service
import android.content.Context
import android.content.Intent
import android.os.IBinder
import io.lantern.sdk.LanternManager

/**
 * سرویس هستهٔ Lantern (SDK رسمی getlantern/lanternsdk-android v1.0.1).
 *
 * مدل اجرا مثل MLM برای موتورهای in-process: proxyAllTraffic=false یعنی
 * Lantern فقط یک پروکسی HTTP محلی روی پورت مشخص بالا می‌آورد و تونل TUN
 * را هستهٔ Xray می‌بندد (outbound http → 127.0.0.1:port). این‌طوری
 * VpnService داخلی SDK دخالتی نمی‌کند و Go-runtime آن هم در پردازهٔ اصلی
 * با Xray پردازهٔ :RunSoLibXrayDaemon تداخل ندارد (هر Go runtime در
 * پردازهٔ خودش).
 */
class LanternService : Service() {

    companion object {
        private const val TAG = "LanternService"
        private const val EXTRA_PORT = "port"
        private const val EXTRA_APP = "app_name"

        private val lock = Any()

        @Volatile
        private var running = false

        @Volatile
        private var socksHttpPort = 0

        @Volatile
        private var lastError: String? = null

        fun start(context: Context, port: Int, appName: String): Boolean {
            synchronized(lock) {
                if (running) return true
            }
            lastError = null
            val intent = Intent(context, LanternService::class.java)
                .putExtra(EXTRA_PORT, port)
                .putExtra(EXTRA_APP, appName)
            return try {
                if (android.os.Build.VERSION.SDK_INT >= 26) {
                    context.startForegroundService(intent)
                } else {
                    context.startService(intent)
                }
                true
            } catch (e: Exception) {
                SafeLog.e(TAG, "startForegroundService failed", e)
                lastError = e.message
                false
            }
        }

        fun status(): Map<String, Any?> = synchronized(lock) {
            mapOf(
                "running" to running,
                "port" to socksHttpPort,
                "error" to lastError,
            )
        }

        fun stop(context: Context) {
            try {
                context.stopService(Intent(context, LanternService::class.java))
            } catch (_: Exception) {
            }
            try {
                LanternManager.stopLantern()
            } catch (e: Exception) {
                SafeLog.w(TAG, "stopLantern failed", e)
            }
            synchronized(lock) {
                running = false
                socksHttpPort = 0
            }
        }
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val port = intent?.getIntExtra(EXTRA_PORT, 0) ?: 0
        val appName = intent?.getStringExtra(EXTRA_APP) ?: "HasanVPN"
        if (port <= 0) {
            SafeLog.e(TAG, "Lantern start: bad port")
            stopSelf()
            return START_NOT_STICKY
        }

        val notification = NotificationHelper.build(
            this,
            NotificationHelper.ID_LANTERN,
            "Lantern",
            "در حال اتصال…",
            showAction = false,
        )
        NotificationHelper.startForegroundSafe(
            this,
            NotificationHelper.ID_LANTERN,
            notification,
        )

        kotlin.concurrent.thread(name = "lantern-runner") {
            try {
                SafeLog.i(TAG, "[LANTERN] setup(app=$appName) start(:$port)")
                LanternManager.setup(applicationContext, appName, "$appName/config")
                LanternManager.startLantern(":$port", false)
                synchronized(lock) {
                    running = true
                    socksHttpPort = port
                }
                SafeLog.i(TAG, "[LANTERN] started on :$port")
            } catch (e: Exception) {
                synchronized(lock) {
                    lastError = e.message
                    running = false
                }
                SafeLog.e(TAG, "Lantern start failed", e)
            } finally {
                stopSelf()
            }
        }
        return START_NOT_STICKY
    }

    override fun onDestroy() {
        // اگر سرویس بیرونی kill شد هم پروکسی را خاموش کن
        try {
            LanternManager.stopLantern()
        } catch (_: Exception) {
        }
        synchronized(lock) {
            running = false
            socksHttpPort = 0
        }
        super.onDestroy()
    }
}
