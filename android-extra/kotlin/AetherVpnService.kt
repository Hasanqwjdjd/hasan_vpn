package com.hasan.hasan_vpn

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.net.ProxyInfo
import android.net.VpnService
import android.os.Build
import android.os.IBinder
import android.os.ParcelFileDescriptor
import android.util.Log
import java.io.File
import java.net.InetSocketAddress
import java.net.Socket
import kotlin.concurrent.thread

class AetherVpnService : VpnService() {

    companion object {
        private const val TAG = "AetherVpnService"
        private const val CHANNEL_ID = "aether_vpn_channel"
        private const val NOTIFICATION_ID = 4242

        const val SOCKS_PORT = 1819
        const val HTTP_PORT = 1820

        @Volatile
        private var vpnInterface: ParcelFileDescriptor? = null

        @Volatile
        private var aetherProcess: Process? = null

        @Volatile
        private var connected = false

        @Volatile
        private var lastError: String? = null

        @Volatile
        private var activeProtocol = "auto"

        fun start(
            context: Context,
            scanMode: String,
            protocolMode: String,
            upstreamProxy: String,
            remark: String,
        ): Boolean {
            return try {
                val intent = Intent(context, AetherVpnService::class.java).apply {
                    putExtra("scanMode", scanMode)
                    putExtra("protocolMode", protocolMode)
                    putExtra("upstreamProxy", upstreamProxy)
                    putExtra("remark", remark)
                }

                connected = false
                lastError = null

                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    context.startForegroundService(intent)
                } else {
                    context.startService(intent)
                }

                true
            } catch (error: Exception) {
                lastError = error.message ?: error.javaClass.simpleName
                Log.e(TAG, "Unable to start Aether service", error)
                false
            }
        }

        fun stop(context: Context) {
            try {
                context.stopService(
                    Intent(context, AetherVpnService::class.java),
                )
            } catch (error: Exception) {
                Log.e(TAG, "Unable to stop Aether service", error)
            }

            connected = false
            lastError = null
        }

        fun statusMap(): Map<String, Any?> {
            return mapOf(
                "connected" to connected,
                "protocol" to activeProtocol,
                "socksPort" to SOCKS_PORT,
                "httpPort" to HTTP_PORT,
                "error" to lastError,
            )
        }
    }

    override fun onBind(intent: Intent?): IBinder? {
        return super.onBind(intent)
    }

    override fun onStartCommand(
        intent: Intent?,
        flags: Int,
        startId: Int,
    ): Int {
        val scanMode = intent?.getStringExtra("scanMode") ?: "balanced"
        val protocolMode = intent?.getStringExtra("protocolMode") ?: "auto"
        val upstreamProxy = intent?.getStringExtra("upstreamProxy") ?: ""
        val remark = intent?.getStringExtra("remark") ?: "Aether"

        activeProtocol = protocolMode
        connected = false
        lastError = null

        startForeground(
            NOTIFICATION_ID,
            buildNotification(remark),
        )

        teardownRuntime()

        thread(
            name = "aether-start",
            start = true,
        ) {
            try {
                runAetherCore(
                    scanMode = scanMode,
                    protocolMode = protocolMode,
                    upstreamProxy = upstreamProxy,
                )

                val socksReady = waitForPort(
                    host = "127.0.0.1",
                    port = SOCKS_PORT,
                    timeoutMs = 20_000L,
                )

                if (!socksReady) {
                    failAndStop(
                        "Aether SOCKS5 proxy did not become ready",
                    )
                    return@thread
                }

                val established = establishVpn()

                if (!established) {
                    failAndStop("Could not establish VPN interface")
                    return@thread
                }

                connected = true
                Log.i(TAG, "Aether service is ready")
            } catch (error: Exception) {
                Log.e(TAG, "Aether startup failed", error)
                failAndStop(
                    error.message ?: error.javaClass.simpleName,
                )
            }
        }

        return START_NOT_STICKY
    }

    /**
     * Aether باید یک فایل اجرایی ELF واقعی باشد.
     *
     * فایل shared library با نام libaether.so را نمی‌توان با ProcessBuilder
     * اجرا کرد. باینری اجرایی باید با نام aether در filesDir قرار بگیرد.
     */
    private fun runAetherCore(
        scanMode: String,
        protocolMode: String,
        upstreamProxy: String,
    ) {
        val executable = File(filesDir, "aether")

        if (!executable.exists()) {
            throw IllegalStateException(
                "Executable Aether was not found at " +
                    "${executable.absolutePath}. " +
                    "Add a real executable named 'aether'; " +
                    "a shared library named libaether.so cannot be " +
                    "started with ProcessBuilder.",
            )
        }

        if (!executable.setExecutable(true, false)) {
            Log.w(TAG, "Could not change executable permission")
        }

        val environment = mutableMapOf(
            "AETHER_SOCKS" to SOCKS_PORT.toString(),
            "AETHER_HTTP" to HTTP_PORT.toString(),
            "AETHER_SCAN" to scanMode,
            "AETHER_PROTOCOL" to protocolMode,
        )

        if (upstreamProxy.isNotBlank()) {
            environment["AETHER_UPSTREAM_PROXY"] = upstreamProxy
        }

        val process = ProcessBuilder(executable.absolutePath)
            .directory(filesDir)
            .redirectErrorStream(true)
            .apply {
                environment().putAll(environment)
            }
            .start()

        aetherProcess = process

        thread(
            name = "aether-log",
            start = true,
        ) {
            try {
                process.inputStream
                    .bufferedReader()
                    .forEachLine { line ->
                        Log.d(TAG, "[aether] $line")
                    }
            } catch (error: Exception) {
                Log.d(TAG, "Aether log reader stopped: ${error.message}")
            }
        }

        thread(
            name = "aether-watchdog",
            start = true,
        ) {
            try {
                val exitCode = process.waitFor()

                if (!connected && exitCode != 0) {
                    lastError = "Aether exited with code $exitCode"
                    Log.e(TAG, lastError!!)
                } else if (connected) {
                    connected = false
                    lastError = "Aether process stopped"
                    closeVpnInterface()
                }
            } catch (error: InterruptedException) {
                Thread.currentThread().interrupt()
            } catch (error: Exception) {
                Log.e(TAG, "Aether watchdog failed", error)
            }
        }
    }

    private fun waitForPort(
        host: String,
        port: Int,
        timeoutMs: Long,
    ): Boolean {
        val deadline = System.currentTimeMillis() + timeoutMs

        while (System.currentTimeMillis() < deadline) {
            try {
                Socket().use { socket ->
                    socket.connect(
                        InetSocketAddress(host, port),
                        500,
                    )
                }
                return true
            } catch (_: Exception) {
                try {
                    Thread.sleep(300)
                } catch (error: InterruptedException) {
                    Thread.currentThread().interrupt()
                    return false
                }
            }
        }

        return false
    }

    /**
     * فعلاً فقط پراکسی سیستم را تنظیم می‌کند.
     *
     * تا زمانی که tun2socks اضافه نشده، route پیش‌فرض اضافه نمی‌کنیم؛
     * چون addRoute("0.0.0.0", 0) بدون tun2socks باعث قطع یا سیاه‌چاله‌شدن
     * ترافیک دستگاه می‌شود.
     */
    private fun establishVpn(): Boolean {
        val builder = Builder()
            .setSession("Aether")
            .addAddress("10.10.10.2", 32)

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            builder.setHttpProxy(
                ProxyInfo.buildDirectProxy(
                    "127.0.0.1",
                    HTTP_PORT,
                ),
            )
        }

        val established = builder.establish()

        if (established == null) {
            return false
        }

        vpnInterface = established
        return true
    }

    private fun buildNotification(remark: String): Notification {
        val notificationManager =
            getSystemService(Context.NOTIFICATION_SERVICE)
                as NotificationManager

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "Aether VPN",
                NotificationManager.IMPORTANCE_LOW,
            )

            notificationManager.createNotificationChannel(channel)
        }

        val launchIntent =
            packageManager.getLaunchIntentForPackage(packageName)

        val pendingIntent = launchIntent?.let {
            PendingIntent.getActivity(
                this,
                0,
                it,
                PendingIntent.FLAG_UPDATE_CURRENT or
                    PendingIntent.FLAG_IMMUTABLE,
            )
        }

        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, CHANNEL_ID)
        } else {
            Notification.Builder(this)
        }

        builder
            .setContentTitle("Aether")
            .setContentText("در حال اتصال با $remark")
            .setSmallIcon(applicationInfo.icon)
            .setOngoing(true)

        if (pendingIntent != null) {
            builder.setContentIntent(pendingIntent)
        }

        return builder.build()
    }

    private fun failAndStop(message: String) {
        Log.e(TAG, message)
        lastError = message
        connected = false
        teardownRuntime()
        stopSelf()
    }

    private fun closeVpnInterface() {
        try {
            vpnInterface?.close()
        } catch (error: Exception) {
            Log.w(TAG, "Could not close VPN interface", error)
        } finally {
            vpnInterface = null
        }
    }

    private fun teardownRuntime() {
        connected = false

        try {
            aetherProcess?.destroy()
        } catch (error: Exception) {
            Log.w(TAG, "Could not stop Aether process", error)
        } finally {
            aetherProcess = null
        }

        closeVpnInterface()
    }

    override fun onDestroy() {
        teardownRuntime()
        super.onDestroy()
    }

    override fun onRevoke() {
        teardownRuntime()
        stopSelf()
        super.onRevoke()
    }
}
