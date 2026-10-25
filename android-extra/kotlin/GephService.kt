package com.hasan.hasan_vpn

import android.app.Service
import android.content.Context
import android.content.Intent
import android.os.IBinder
import kotlin.concurrent.thread

/**
 * اجرای هستهٔ Geph (libgeph.so) به‌صورت پردازهٔ فرزند داخل Foreground Service.
 *
 * پورت «GephProcess» از MLM VPN (نسخهٔ 1.2.42) با یک تفاوت عمدی: به‌جای
 * گذراندن fd تونل به خود هسته (--vpn-fd 0)، از گوشِ SOCKS5 استفاده می‌کنیم
 * (socks5_listen در config) و مثل Psiphon/Tor مسیر را با هستهٔ Xray
 * می‌بندیم. این هم با معماری برنامه سازگار است و هم همان مسیرِ رسمی
 * geph5-client است که در crates.io مستند شده.
 *
 * باینری از استور می‌آید (فایل‌های برنامه — نه jniLibs) و چون اجرا از
 * filesDir روی اندروید ۱۰+ ممنوع است، از لینکر سیستم اجرا می‌شود:
 *   /system/bin/linker64 <path>/libgeph.so --config <config.json>
 * همان روش StoreEngines.kt در MLM.
 *
 * Config دقیقاً از GephConfig.kt ساخته می‌شود (سمت Dart) — کلیدهای مجاز
 * سرور geph5-client با #[serde(deny_unknown_fields)] پین شده‌اند.
 */
class GephService : Service() {

    companion object {
        private const val TAG = "GephService"
        private const val EXTRA_BINARY = "binary"
        private const val EXTRA_CONFIG = "config"
        private const val EXTRA_PORT = "port"
        private const val EXTRA_REMARK = "remark"
        private const val TAIL_SIZE = 60

        private val lock = Any()

        @Volatile
        private var instance: GephService? = null

        private var process: Process? = null
        private var generation = 0L
        private var running = false
        private var exited = false
        private var exitCode: Int? = null
        private var lastLine = ""
        private var lastError: String? = null
        private val tail = mutableListOf<String>()

        @Volatile
        private var socksPort = 0

        fun start(
            context: Context,
            binaryPath: String,
            configPath: String,
            port: Int,
            remark: String,
        ): Boolean {
            synchronized(lock) {
                if (running) {
                    // تلاش دوم برای همان پورت — بگذار بالاست.
                    return true
                }
            }
            lastError = null
            exited = false
            exitCode = null
            lastLine = ""
            synchronized(tail) { tail.clear() }
            socksPort = port

            val intent = Intent(context, GephService::class.java)
                .putExtra(EXTRA_BINARY, binaryPath)
                .putExtra(EXTRA_CONFIG, configPath)
                .putExtra(EXTRA_PORT, port)
                .putExtra(EXTRA_REMARK, remark)
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
                "exited" to exited,
                "exitCode" to exitCode,
                "socksPort" to socksPort,
                "lastLine" to lastLine,
                "error" to lastError,
                "log" to synchronized(tail) { tail.takeLast(20).joinToString("\n") },
            )
        }

        fun stop(context: Context) {
            try {
                context.stopService(Intent(context, GephService::class.java))
            } catch (_: Exception) {
            }
            val victim: Process? = synchronized(lock) { process }
            if (victim == null) {
                // بدون پردازهٔ زنده — فقط فلگ‌ها را ببند
                synchronized(lock) {
                    running = false
                    exited = true
                }
                return
            }
            // ترتیب teardown مثل MLM GephEngine.stop: destroy → waitFor → kill
            try {
                victim.destroy()
            } catch (e: Exception) {
                SafeLog.w(TAG, "Could not stop process", e)
            }
            thread(name = "geph-stop") {
                try {
                    victim.waitFor()
                } catch (_: InterruptedException) {
                }
            }
        }
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        instance = this
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val notification = NotificationHelper.build(
            this,
            NotificationHelper.ID_GEPH,
            "Geph",
            "در حال اتصال…",
            showAction = false,
        )
        NotificationHelper.startForegroundSafe(
            this,
            NotificationHelper.ID_GEPH,
            notification,
        )

        val binary = intent?.getStringExtra(EXTRA_BINARY)
        val config = intent?.getStringExtra(EXTRA_CONFIG)
        val port = intent?.getIntExtra(EXTRA_PORT, 0) ?: 0
        val remark = intent?.getStringExtra(EXTRA_REMARK) ?: "Geph"

        if (binary == null || config == null) {
            SafeLog.e(TAG, "Geph start: binary/config missing")
            stopSelf()
            return START_NOT_STICKY
        }

        thread(name = "geph-runner") {
            val gen: Long = synchronized(lock) { ++generation }
            try {
                val cmd = listOf(
                    "/system/bin/linker64",
                    binary,
                    "--config",
                    config,
                )
                SafeLog.i(TAG, "[GEPH] exec: $cmd")
                val pb = ProcessBuilder(cmd)
                pb.redirectErrorStream(true)
                pb.environment().clear()
                pb.environment()["HOME"] = filesDir.absolutePath
                pb.environment()["TMPDIR"] = cacheDir.absolutePath
                pb.environment()["RUST_BACKTRACE"] = "1"
                val proc = pb.start()
                synchronized(lock) {
                    process = proc
                    running = true
                }

                proc.inputStream.bufferedReader().forEachLine { raw ->
                    val line = raw.trim()
                    if (line.isEmpty()) return@forEachLine
                    synchronized(lock) {
                        lastLine = line.take(300)
                        synchronized(tail) {
                            tail.add(lastLine)
                            if (tail.size > TAIL_SIZE) tail.removeAt(0)
                        }
                    }
                    SafeLog.i(TAG, "[GEPH] $line")
                    // بستن زودهنگام اگر نسلی عوض شد
                    if (synchronized(lock) { generation != gen }) {
                        try {
                            proc.destroy()
                        } catch (_: Exception) {
                        }
                        return@forEachLine
                    }
                }
                val code = proc.waitFor()
                synchronized(lock) {
                    if (generation == gen) {
                        running = false
                        exited = true
                        exitCode = code
                        process = null
                        if (code != 0 && lastError == null) {
                            lastError = "Geph exited (code $code)"
                        }
                    }
                }
                SafeLog.i(TAG, "[GEPH] exited code=$code")
            } catch (e: Exception) {
                synchronized(lock) {
                    running = false
                    exited = true
                    if (lastError == null) lastError = e.message
                }
                SafeLog.e(TAG, "Geph runner failed", e)
            } finally {
                stopSelf()
            }
        }
        return START_NOT_STICKY
    }

}
