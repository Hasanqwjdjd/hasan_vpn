package com.hasan.hasan_vpn

import android.content.Context
import java.io.BufferedReader
import java.io.File
import java.io.FileOutputStream
import java.io.InputStreamReader
import java.util.concurrent.atomic.AtomicBoolean

/**
 * مدیریت Tor در Android:
 *  - کپی باینری‌ها از nativeLibraryDir به filesDir (چون اندروید ۱۰+ اجرای مستقیم از nativeLibraryDir را ممنوع کرده)
 *  - ساخت torrc بر اساس نوع پل
 *  - اجرای libtor.so و خواندن خروجی برای نمایش پیشرفت Bootstrap
 *  - برگرداندن پورت SOCKS (پیش‌فرض 9050)
 */
object TorService {
    private const val TAG = "TorService"

    @Volatile private var running = false
    @Volatile private var lastError: String? = null
    @Volatile private var bootstrapPercent = 0
    @Volatile private var bootstrapMessage = ""
    @Volatile private var socksPort = 9050
    private var torProcess: Process? = null
    private var logThread: Thread? = null
    private val lock = Any()

    fun isRunning(): Boolean = running
    fun getBootstrapPercent(): Int = bootstrapPercent
    fun getBootstrapMessage(): String = bootstrapMessage
    fun getSocksPort(): Int = socksPort
    fun getLastError(): String? = lastError

    /** نقطه‌ی شروع. bridgeType: 'vanilla','obfs4','snowflake','meek_lite','conjure','dnstt' */
    fun start(context: Context, bridgeType: String, customBridges: List<String>?, sni: String? = null): Map<String, Any> {
        synchronized(lock) {
            if (running) return mapOf("ok" to true, "socksPort" to socksPort, "alreadyRunning" to true)

            lastError = null
            bootstrapPercent = 0
            bootstrapMessage = "شروع..."

            try {
                val nativeDir = context.applicationInfo.nativeLibraryDir
                val filesDir = context.filesDir
                val torDir = File(filesDir, "tor")
                if (!torDir.exists()) torDir.mkdirs()
                val dataDir = File(torDir, "data")
                if (!dataDir.exists()) dataDir.mkdirs()

                // ۱. باینری Tor را مستقیما از nativeLibraryDir اجرا می‌کنیم
                //    (چون Android 10+ اجازه اجرای از filesDir را نمی‌دهد)
                val torBinPath = File(nativeDir, "libtor.so").absolutePath
                if (!File(torBinPath).exists()) {
                    lastError = "libtor.so در nativeLibraryDir نیست"
                    return mapOf("ok" to false, "error" to lastError!!)
                }

                // ۲. مسیر پلاگین‌ها هم از nativeLibraryDir
                val obfs4Path = File(nativeDir, "libobfs4proxy.so").absolutePath
                val snowflakePath = File(nativeDir, "libsnowflake.so").absolutePath
                val conjurePath = File(nativeDir, "libconjure.so").absolutePath
                val dnsttPath = File(nativeDir, "libdnstt.so").absolutePath

                // ۳. ساخت torrc
                val torrc = File(torDir, "torrc")
                val torrcText = buildTorrc(
                    dataDir,
                    bridgeType,
                    customBridges,
                    obfs4Path.takeIf { File(it).exists() },
                    snowflakePath.takeIf { File(it).exists() },
                    conjurePath.takeIf { File(it).exists() },
                    dnsttPath.takeIf { File(it).exists() },
                    sni,
                )
                torrc.writeText(torrcText)
                SafeLog.d(TAG, "torrc content:\n$torrcText")

                // ۴. اجرا از nativeLibraryDir با محیط کاری torDir
                val pb = ProcessBuilder(torBinPath, "-f", torrc.absolutePath)
                pb.directory(torDir)
                pb.redirectErrorStream(true)
                pb.environment()["HOME"] = torDir.absolutePath
                pb.environment()["TOR_HOME"] = torDir.absolutePath
                pb.environment()["LD_LIBRARY_PATH"] = nativeDir
                val proc = pb.start()
                torProcess = proc
                running = true

                // ۵. خواندن لاگ
                logThread = Thread {
                    try {
                        val reader = BufferedReader(InputStreamReader(proc.inputStream))
                        var line: String?
                        val bootstrapRegex = Regex("Bootstrapped (\\d+)%")
                        while (reader.readLine().also { line = it } != null) {
                            val l = line ?: continue
                            SafeLog.d(TAG, "[tor] $l")
                            val m = bootstrapRegex.find(l)
                            if (m != null) {
                                bootstrapPercent = m.groupValues[1].toIntOrNull() ?: 0
                                bootstrapMessage = l.substringAfter("):").trim()
                                if (bootstrapPercent >= 100) bootstrapMessage = "آماده"
                            }
                        }
                    } catch (_: Exception) {}
                    try { proc.waitFor() } catch (_: Exception) {}
                    running = false
                }.also { it.isDaemon = true; it.start() }

                Thread.sleep(300)
                // سرویس foreground را راه بینداز تا Tor در پس‌زمینه زنده بماند
                try {
                    TorForegroundService.start(context)
                } catch (e: Exception) {
                    SafeLog.w(TAG, "Failed to start foreground service", e)
                }
                return mapOf("ok" to true, "socksPort" to socksPort)
            } catch (e: Throwable) {
                lastError = e.message ?: e.toString()
                SafeLog.e(TAG, "start failed", e)
                try { torProcess?.destroy() } catch (_: Exception) {}
                torProcess = null
                running = false
                return mapOf("ok" to false, "error" to lastError!!)
            }
        }
    }

    fun stop() {
        synchronized(lock) {
            try {
                torProcess?.destroy()
            } catch (_: Exception) {}
            torProcess = null
            running = false
            bootstrapPercent = 0
            bootstrapMessage = ""
        }
    }

    /** نسخه‌ی stop که Context می‌گیرد تا سرویس foreground را هم متوقف کند. */
    fun stopWithContext(context: Context) {
        stop()
        try {
            TorForegroundService.stop(context)
        } catch (e: Exception) {
            SafeLog.w(TAG, "Failed to stop foreground service", e)
        }
    }

    /** برای هماهنگی با MainActivity: stop(context) */
    fun stop(context: Context) {
        stop()
    }

    /** وضعیت کامل برای Flutter */
    fun status(): Map<String, Any?> {
        return mapOf(
            "running" to running,
            "bootstrapPercent" to bootstrapPercent,
            "bootstrapMessage" to bootstrapMessage,
            "socksPort" to socksPort,
            "error" to lastError,
        )
    }

    /** کپی یک باینری از nativeLibraryDir به مقصد و دادن مجوز اجرا. */
    private fun copyBin(context: Context, name: String, destDir: File): File? {
        return try {
            val src = File(context.applicationInfo.nativeLibraryDir, name)
            if (!src.exists()) return null
            val dst = File(destDir, name)
            // اگر نسخه‌ی قبلی هست و همان حجم است، دوباره کپی نکن
            if (dst.exists() && dst.length() == src.length()) {
                dst.setExecutable(true, false)
                return dst
            }
            src.inputStream().use { input ->
                FileOutputStream(dst).use { output -> input.copyTo(output) }
            }
            dst.setExecutable(true, false)
            dst.setReadable(true, false)
            dst
        } catch (e: Exception) {
            SafeLog.e(TAG, "copyBin failed: $name", e)
            null
        }
    }

    /** ساخت محتوای torrc. */
    private fun buildTorrc(
        dataDir: File,
        bridgeType: String,
        customBridges: List<String>?,
        obfs4Path: String?, snowflakePath: String?, conjurePath: String?, dnsttPath: String?,
        sni: String?,
    ): String {
        val sb = StringBuilder()
        sb.appendLine("SocksPort $socksPort")
        sb.appendLine("DataDirectory ${dataDir.absolutePath}")
        sb.appendLine("Log notice stdout")
        sb.appendLine("SafeLogging 0")
        sb.appendLine("AvoidDiskWrites 1")

        when (bridgeType) {
            "vanilla" -> {
                // بدون پل
            }
            "obfs4" -> {
                if (obfs4Path != null) {
                    sb.appendLine("UseBridges 1")
                    sb.appendLine("ClientTransportPlugin obfs4 exec ${obfs4Path}")
                    sb.appendLine("ClientTransportPlugin obfs3 exec ${obfs4Path}")
                    sb.appendLine("ClientTransportPlugin scramblesuit exec ${obfs4Path}")
                    customBridges?.forEach { sb.appendLine("Bridge $it") }
                }
            }
            "meek_lite" -> {
                if (obfs4Path != null) {
                    sb.appendLine("UseBridges 1")
                    sb.appendLine("ClientTransportPlugin meek_lite exec ${obfs4Path}")
                    if (!customBridges.isNullOrEmpty()) {
                        customBridges.forEach { sb.appendLine("Bridge $it") }
                    } else {
                        // اگر پل شخصی نده، از SNI برای ساخت پل use می‌کنیم
                        val host = sni ?: "certum.pl"
                        sb.appendLine("Bridge meek_lite 192.0.2.2:443 url=https://$host/ front=$host")
                    }
                }
            }
            "snowflake" -> {
                if (snowflakePath != null) {
                    sb.appendLine("UseBridges 1")
                    val frontArg = if (!sni.isNullOrEmpty()) " -front=$sni" else ""
                    sb.appendLine("ClientTransportPlugin snowflake exec ${snowflakePath}$frontArg")
                    sb.appendLine("Bridge snowflake 192.0.2.3:1 2B280B23E1107BB62ABFC40DDCC8824814F80A72")
                }
            }
            "conjure" -> {
                if (conjurePath != null) {
                    sb.appendLine("UseBridges 1")
                    sb.appendLine("ClientTransportPlugin conjure exec ${conjurePath}")
                    customBridges?.forEach { sb.appendLine("Bridge $it") }
                }
            }
            "dnstt" -> {
                if (dnsttPath != null) {
                    sb.appendLine("UseBridges 1")
                    sb.appendLine("ClientTransportPlugin dnstt exec ${dnsttPath}")
                    customBridges?.forEach { sb.appendLine("Bridge $it") }
                }
            }
        }
        return sb.toString()
    }
}
