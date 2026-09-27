package com.hasan.hasan_vpn

import android.app.Service
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.IBinder
import android.util.Log
import java.io.File
import java.io.FileOutputStream
import java.net.InetSocketAddress
import java.net.Socket
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean

/**
 * MasterDNS — runs `libmasterdns.so` as a foreground service, exposes
 * a local SOCKS5 on 127.0.0.1:18000 that Xray can use as an outbound.
 *
 * Architecture mirrors TunnelService.kt: foreground service +
 * ProcessBuilder + progress parsing from stdout.
 */
class MasterDnsService : Service() {

    companion object {
        private const val TAG = "MasterDnsService"
        private const val CHANNEL = "com.hasan.hasan_vpn/masterdns"
        private const val ACTION_START = "com.hasan.hasan_vpn.MDNS_START"
        private const val ACTION_STOP = "com.hasan.hasan_vpn.MDNS_STOP"
        private const val EXTRA_DOMAIN = "domain"
        private const val EXTRA_KEY = "key"
        private const val EXTRA_METHOD = "method"
        private const val EXTRA_RESOLVERS = "resolvers"
        private const val EXTRA_ADVANCED = "advanced"

        const val PORT = 18000
        @Volatile private var process: Process? = null
        private val cancelled = AtomicBoolean(false)

        fun isActive(): Boolean = process?.isAlive == true

        fun start(
            context: Context,
            domain: String,
            key: String,
            method: Int,
            resolvers: String,
            advancedToml: String?,
        ) {
            val i = Intent(context, MasterDnsService::class.java).apply {
                action = ACTION_START
                putExtra(EXTRA_DOMAIN, domain)
                putExtra(EXTRA_KEY, key)
                putExtra(EXTRA_METHOD, method)
                putExtra(EXTRA_RESOLVERS, resolvers)
                putExtra(EXTRA_ADVANCED, advancedToml)
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(i)
            } else {
                context.startService(i)
            }
        }

        fun stop(context: Context) {
            val i = Intent(context, MasterDnsService::class.java).apply {
                action = ACTION_STOP
            }
            context.startService(i)
        }

        fun cancelStartup() {
            cancelled.set(true)
            process?.destroyForcibly()
        }
    }

    private var lastProgress = ""
    private var logFile: File? = null

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_STOP -> {
                SafeLog.i(TAG, "stopping MasterDNS")
                stopSelf()
                return START_NOT_STICKY
            }
            ACTION_START -> {
                val domain = intent.getStringExtra(EXTRA_DOMAIN)?.trim().orEmpty()
                val key = intent.getStringExtra(EXTRA_KEY)?.trim().orEmpty()
                val method = intent.getIntExtra(EXTRA_METHOD, 1)
                val resolvers = intent.getStringExtra(EXTRA_RESOLVERS).orEmpty()
                val advanced = intent.getStringExtra(EXTRA_ADVANCED)

                if (domain.isEmpty() || key.isEmpty()) {
                    SafeLog.e(TAG, "domain/key required")
                    notifyError("domain/key required")
                    stopSelf()
                    return START_NOT_STICKY
                }

                startForegroundSafe("MasterDNS · $domain")
                Thread({ runClient(domain, key, method, resolvers, advanced) },
                    "MasterDnsRunner").start()
            }
        }
        return START_NOT_STICKY
    }

    private fun runClient(
        domain: String,
        key: String,
        method: Int,
        resolversOverride: String,
        advancedOverride: String?,
    ) {
        try {
            cancelled.set(false)

            // libmasterdns.so — همان jniLibs
            val binary = File(applicationInfo.nativeLibraryDir, "libmasterdns.so")
            if (!binary.isFile) {
                SafeLog.e(TAG, "libmasterdns.so not found at ${binary.absolutePath}")
                notifyError("libmasterdns.so missing")
                stopSelf()
                return
            }

            // ساخت دایرکتوری کاری
            val root = File(filesDir, "masterdns").apply { mkdirs() }

            // خواندن TOML پیش‌فرض از assets
            val defaults = try {
                assets.open("masterdns_client_config.toml")
                    .bufferedReader().use { it.readText() }
            } catch (e: Exception) {
                SafeLog.w(TAG, "no default config in assets: ${e.message}")
                ""
            }

            val advanced = advancedOverride?.takeIf { it.isNotBlank() } ?: defaults

            // کلیدهای محافظت‌شده که کاربر نباید override کنه
            val reserved = setOf(
                "DOMAINS", "ENCRYPTION_KEY", "DATA_ENCRYPTION_METHOD",
                "PROTOCOL_TYPE", "LISTEN_IP", "LISTEN_PORT",
            )
            val filtered = advanced.lineSequence().filter { line ->
                val name = line.substringBefore('=').trim()
                name !in reserved
            }.joinToString("\n")

            val config = buildString {
                append("DOMAINS = [\"").append(escapeToml(domain)).append("\"]\n")
                append("ENCRYPTION_KEY = \"").append(escapeToml(key)).append("\"\n")
                append("DATA_ENCRYPTION_METHOD = ").append(method).append('\n')
                append("PROTOCOL_TYPE = \"SOCKS5\"\n")
                append("LISTEN_IP = \"127.0.0.1\"\n")
                append("LISTEN_PORT = ").append(PORT).append('\n')
                append(filtered).append('\n')
            }
            val configFile = File(root, "client_config.toml")
            configFile.writeText(config)

            // resolvers
            val resolvers = resolversOverride.trim().ifEmpty {
                try {
                    assets.open("masterdns_client_resolvers.txt")
                        .bufferedReader().use { it.readText() }
                } catch (_: Exception) {
                    "8.8.8.8\n1.1.1.1\n"
                }
            }
            val resolverFile = File(root, "client_resolvers.txt")
            resolverFile.writeText(resolvers)

            val log = File(root, "client.log")
            logFile = log

            val proc = ProcessBuilder(
                binary.absolutePath,
                "-config", configFile.absolutePath,
                "-resolvers", resolverFile.absolutePath,
            )
                .directory(root)
                .redirectErrorStream(true)
                .start()
            process = proc

            // پارس progress از stdout + نوشتن به log
            val progressRe = Regex("""(?:Accepted|Rejected) \((\d+)/(\d+)\)""")
            val catalogRe = Regex("""Connection Catalog: (\d+) domain-resolver pairs""")

            FileOutputStream(log, true).bufferedWriter().use { writer ->
                proc.inputStream.bufferedReader().useLines { lines ->
                    lines.forEach { line ->
                        writer.appendLine(line)
                        writer.flush()

                        val counts = progressRe.find(line)
                        val catalog = catalogRe.find(line)
                        val completed = counts?.groupValues?.get(1)?.toIntOrNull() ?: 0
                        val total = counts?.groupValues?.get(2)?.toIntOrNull()
                            ?: catalog?.groupValues?.get(1)?.toIntOrNull()

                        if (total != null && total > 0) {
                            val p = "$completed/$total"
                            if (p != lastProgress) {
                                lastProgress = p
                                notifyProgress(completed, total)
                            }
                        }

                        // log برای کاربر
                        SafeLog.d(TAG, line)
                    }
                }
            }

            // اگه proc همون process فعاله → clean exit
            if (process === proc) {
                process = null
            }
        } catch (e: Exception) {
            SafeLog.e(TAG, "MasterDNS exited", e)
            notifyError(e.message ?: "unknown error")
        } finally {
            try { stopForeground(STOP_FOREGROUND_REMOVE) } catch (_: Exception) {}
            stopSelf()
        }
    }

    private fun startForegroundSafe(text: String) {
        val n = NotificationHelper.build(
            this,
            NotificationHelper.ID_TUNNEL,
            "Hasan VPN — MasterDNS",
            text,
        )
        NotificationHelper.startForegroundSafe(this, NotificationHelper.ID_TUNNEL, n)
    }

    private fun notifyProgress(completed: Int, total: Int) {
        try {
            val n = NotificationHelper.build(
                this,
                NotificationHelper.ID_TUNNEL,
                "Hasan VPN — MasterDNS",
                "اسکن DNS: $completed/$total",
                showAction = true,
            )
            val mgr = getSystemService(Context.NOTIFICATION_SERVICE)
                    as android.app.NotificationManager
            mgr.notify(NotificationHelper.ID_TUNNEL, n)

            // ارسال به Flutter
            MainActivity.masterDnsChannel?.invokeMethod(
                "onProgress",
                mapOf("completed" to completed, "total" to total),
            )
        } catch (_: Exception) {}
    }

    private fun notifyError(msg: String) {
        try {
            MainActivity.masterDnsChannel?.invokeMethod("onError", msg)
        } catch (_: Exception) {}
    }

    private fun escapeToml(v: String): String = v
        .replace("\\", "\\\\")
        .replace("\"", "\\\"")
        .replace("\n", "\\n")

    override fun onDestroy() {
        try {
            process?.let { p ->
                p.destroy()
                if (!p.waitFor(700, TimeUnit.MILLISECONDS)) {
                    p.destroyForcibly()
                }
            }
        } catch (_: Exception) {}
        process = null
        super.onDestroy()
    }
}
