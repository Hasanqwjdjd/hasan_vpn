package com.hasan.hasan_vpn

import android.app.Service
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.IBinder
import java.io.File
import java.net.InetSocketAddress
import java.net.Socket
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean

/**
 * WARP MASQUE/H2 — runs `libwarpmasque.so` (usque) as a foreground service.
 *
 * Flow:
 *   1. `register -n <device> --accept-tos` creates config.json
 *   2. `-c config.json socks -b 127.0.0.1 -p 1819 -P 443 -s <sni> -d <dns> --http2`
 *      opens a local SOCKS5 on 127.0.0.1:1819 that tunnels via MASQUE/H2.
 *   3. Xray is started with socks5-outbound → 127.0.0.1:1819.
 *
 * This is a trimmed-down version of PingNG's WarpMasqueBridge (single
 * endpoint, no parallel scan) — enough for personal use.
 */
class WarpMasqueService : Service() {

    companion object {
        private const val TAG = "WarpMasqueService"
        private const val ACTION_START = "com.hasan.hasan_vpn.WMQ_START"
        private const val ACTION_STOP = "com.hasan.hasan_vpn.WMQ_STOP"
        private const val EXTRA_ENDPOINT = "endpoint"   // host:port
        private const val EXTRA_SNI = "sni"
        private const val EXTRA_DNS = "dns"
        private const val EXTRA_HTTP2 = "http2"

        const val SOCKS_PORT = 1819
        private const val DEFAULT_ENDPOINT = "162.159.198.238:443"
        private const val DEFAULT_SNI = "soft98.ir"
        private const val DEFAULT_DNS = "1.1.1.1,1.0.0.1"

        @Volatile private var process: Process? = null
        private val cancelled = AtomicBoolean(false)

        fun isActive(): Boolean = process?.isAlive == true

        fun start(
            context: Context,
            endpoint: String = DEFAULT_ENDPOINT,
            sni: String = DEFAULT_SNI,
            dns: String = DEFAULT_DNS,
            http2: Boolean = true,
        ) {
            val i = Intent(context, WarpMasqueService::class.java).apply {
                action = ACTION_START
                putExtra(EXTRA_ENDPOINT, endpoint)
                putExtra(EXTRA_SNI, sni)
                putExtra(EXTRA_DNS, dns)
                putExtra(EXTRA_HTTP2, http2)
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(i)
            } else {
                context.startService(i)
            }
        }

        fun stop(context: Context) {
            context.startService(Intent(context, WarpMasqueService::class.java).apply {
                action = ACTION_STOP
            })
        }

        fun cancelStartup() {
            cancelled.set(true)
            process?.destroyForcibly()
        }
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_STOP -> {
                stopSelf()
                return START_NOT_STICKY
            }
            ACTION_START -> {
                val endpoint = intent.getStringExtra(EXTRA_ENDPOINT) ?: DEFAULT_ENDPOINT
                val sni = intent.getStringExtra(EXTRA_SNI) ?: DEFAULT_SNI
                val dns = intent.getStringExtra(EXTRA_DNS) ?: DEFAULT_DNS
                val http2 = intent.getBooleanExtra(EXTRA_HTTP2, true)
                startForegroundSafe("WARP MASQUE · $endpoint")
                Thread({ runMasque(endpoint, sni, dns, http2) }, "WarpMasqueRunner").start()
            }
        }
        return START_NOT_STICKY
    }

    private fun runMasque(endpoint: String, sni: String, dns: String, http2: Boolean) {
        try {
            cancelled.set(false)

            val binary = File(applicationInfo.nativeLibraryDir, "libwarpmasque.so")
            if (!binary.isFile) {
                notifyError("libwarpmasque.so missing")
                stopSelf()
                return
            }

            val root = File(filesDir, "warp-masque").apply { mkdirs() }
            val configFile = File(root, "config.json")

            // ---- 1. register (فقط اگه config وجود نداره یا ناقصه)
            if (!isRegistered(configFile)) {
                // پاک کردن config قدیمی
                if (configFile.exists()) runCatching { configFile.delete() }
                val regConfig = File(root, "register-temp.json")
                if (regConfig.exists()) runCatching { regConfig.delete() }

                notifyText("Registering WARP MASQUE device…")
                val registerProc = ProcessBuilder(
                    binary.absolutePath, "register",
                    "-n", "Hasan-VPN",
                    "--accept-tos",
                ).directory(root).redirectErrorStream(true).start()

                val out = StringBuilder()
                registerProc.inputStream.bufferedReader().useLines { lines ->
                    lines.forEach { out.appendLine(it) }
                }
                runCatching { registerProc.outputStream.close() }
                if (!registerProc.waitFor(60, TimeUnit.SECONDS)) {
                    registerProc.destroyForcibly()
                    notifyError("register timed out")
                    stopSelf()
                    return
                }
                if (registerProc.exitValue() != 0) {
                    notifyError("register failed: exit ${registerProc.exitValue()}")
                    stopSelf()
                    return
                }
                // مسیر پیش‌فرض خروجی: runtimeDir/config.json
                if (!isRegistered(configFile)) {
                    // اگه register یه فایل دیگه ساخت، بگرد
                    val found = root.listFiles()?.firstOrNull {
                        it.name == "config.json" && isRegistered(it)
                    }
                    if (found == null) {
                        notifyError("register produced no valid config")
                        stopSelf()
                        return
                    }
                    if (found != configFile) found.copyTo(configFile, overwrite = true)
                }
            }

            // ---- 2. شروع socks
            val hostPort = endpoint.split(":")
            val host = hostPort.getOrNull(0) ?: "162.159.198.238"
            val endpointPort = hostPort.getOrNull(1)?.toIntOrNull() ?: 443

            notifyText("Starting MASQUE socks…")
            val args = mutableListOf(
                binary.absolutePath,
                "-c", configFile.absolutePath,
                "socks",
                "-b", "127.0.0.1",
                "-p", SOCKS_PORT.toString(),
                "-P", endpointPort.toString(),
                "-s", sni,
            )
            // dns جدا با کاما
            dns.split(",").map { it.trim() }.filter { it.isNotEmpty() }.forEach {
                args.add("-d"); args.add(it)
            }
            if (http2) args.add("--http2")

            val proc = ProcessBuilder(args)
                .directory(root)
                .redirectErrorStream(true)
                .start()
            process = proc

            // ---- 3. پارس log + انتظار برای listen
            val logFile = File(root, "masque.log")
            var listening = false

            proc.inputStream.bufferedReader().useLines { lines ->
                for (line in lines) {
                    try {
                        java.io.FileOutputStream(logFile, true)
                            .bufferedWriter().use { it.appendLine(line) }
                    } catch (_: Exception) {}
                    SafeLog.d(TAG, line)

                    val low = line.lowercase()
                    if (!listening && (low.contains("listening") ||
                            low.contains("socks") && low.contains("bound"))) {
                        listening = true
                        try {
                            MainActivity.warpMasqueChannel?.invokeMethod("onReady", null)
                        } catch (_: Exception) {}
                    }
                }
            }

            // اگه proc هنوز فعاله، یعنی تموم شد
            if (process === proc) process = null

        } catch (e: Exception) {
            SafeLog.e(TAG, "MASQUE failed", e)
            notifyError(e.message ?: "unknown error")
        } finally {
            try { stopForeground(STOP_FOREGROUND_REMOVE) } catch (_: Exception) {}
            stopSelf()
        }
    }

    private fun isRegistered(f: File): Boolean {
        if (!f.isFile) return false
        return try {
            val t = f.readText()
            t.contains("\"private_key\"") || t.contains("private_key")
        } catch (_: Exception) { false }
    }

    private fun startForegroundSafe(text: String) {
        val n = NotificationHelper.build(
            this,
            NotificationHelper.ID_TUNNEL,
            "Hasan VPN — WARP MASQUE",
            text,
        )
        NotificationHelper.startForegroundSafe(this, NotificationHelper.ID_TUNNEL, n)
    }

    private fun notifyText(text: String) {
        try {
            val n = NotificationHelper.build(
                this, NotificationHelper.ID_TUNNEL,
                "Hasan VPN — WARP MASQUE", text,
            )
            val mgr = getSystemService(Context.NOTIFICATION_SERVICE)
                    as android.app.NotificationManager
            mgr.notify(NotificationHelper.ID_TUNNEL, n)
        } catch (_: Exception) {}
    }

    private fun notifyError(msg: String) {
        try {
            MainActivity.warpMasqueChannel?.invokeMethod("onError", msg)
        } catch (_: Exception) {}
    }

    override fun onDestroy() {
        try {
            process?.let {
                it.destroy()
                if (!it.waitFor(600, TimeUnit.MILLISECONDS)) it.destroyForcibly()
            }
        } catch (_: Exception) {}
        process = null
        super.onDestroy()
    }
}
