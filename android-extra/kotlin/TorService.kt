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
                lastError = null
                bootstrapPercent = 0
                bootstrapMessage = "starting"

                val recentLogs = StringBuilder()

                // ۵. خواندن لاگ
                logThread = Thread {
                    try {
                        val reader = BufferedReader(InputStreamReader(proc.inputStream))
                        var line: String?
                        val bootstrapRegex = Regex("Bootstrapped (\\d+)%")
                        while (reader.readLine().also { line = it } != null) {
                            val l = line ?: continue
                            SafeLog.d(TAG, "[tor] $l")
                            if (recentLogs.length < 4000) {
                                recentLogs.append(l).append('\n')
                            }
                            val lower = l.lowercase()
                            if (lower.contains("error") || lower.contains("failed") ||
                                lower.contains("could not") || lower.contains("no bridges")
                            ) {
                                lastError = l.take(200)
                            }
                            val m = bootstrapRegex.find(l)
                            if (m != null) {
                                bootstrapPercent = m.groupValues[1].toIntOrNull() ?: 0
                                bootstrapMessage = l.substringAfter("):").trim()
                                if (bootstrapPercent >= 100) bootstrapMessage = "آماده"
                            }
                        }
                    } catch (_: Exception) {}
                    try { proc.waitFor() } catch (_: Exception) {}
                    if (bootstrapPercent < 100) {
                        lastError = lastError ?: "Tor process exited early (bootstrap $bootstrapPercent%)"
                    }
                    running = false
                }.also { it.isDaemon = true; it.start() }

                // کمی صبر کن؛ اگر پروسه فوری مرد (مثل DNSTT خراب)، خطا برگردان
                Thread.sleep(1200)
                try {
                    // exitValue فقط اگر مرده باشد کار می‌کند
                    val code = proc.exitValue()
                    running = false
                    torProcess = null
                    lastError = when {
                        bridgeType == "dnstt" ->
                            "DNSTT failed (exit $code). libdnstt may need a valid domain/resolver bridge line."
                        else ->
                            "Tor exited immediately (code $code). Check bridges / plugins."
                    }
                    return mapOf("ok" to false, "error" to lastError!!)
                } catch (_: IllegalThreadStateException) {
                    // هنوز زنده است — خوب
                }

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
        // AvoidDiskWrites removed — allows caching consensus/guards/circuits to disk for faster reconnect
        // بهینه‌سازی سرعت/پایداری مدار
        sb.appendLine("CircuitBuildTimeout 15")
        sb.appendLine("LearnCircuitBuildTimeout 1")
        sb.appendLine("CircuitStreamTimeout 15")
        sb.appendLine("KeepalivePeriod 60")
        sb.appendLine("NewCircuitPeriod 30")
        sb.appendLine("MaxCircuitDirtiness 600")
        sb.appendLine("EnforceDistinctSubnets 0")
        sb.appendLine("ClientOnly 1")
        sb.appendLine("ConnectionPadding 0")
        sb.appendLine("ReducedConnectionPadding 1")
        // ─── بهینه‌سازی سرعت ───
        sb.appendLine("NumEntryGuards 3")
        sb.appendLine("NumDirectoryGuards 2")
        sb.appendLine("UseEntryGuards 1")
        sb.appendLine("StrictNodes 0")
        // دانلود سریع‌تر consensus
        sb.appendLine("ClientBootstrapConsensusAuthorityDownloadInitialDelay 0")
        sb.appendLine("ClientBootstrapConsensusAuthorityDownloadSchedule 0, 1, 2, 4")
        sb.appendLine("ClientBootstrapConsensusFallbackDownloadInitialDelay 0")
        sb.appendLine("ClientBootstrapConsensusFallbackDownloadSchedule 0, 1, 2, 4")

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
                    // حداکثر ۳–۴ پل → اتصال سریع‌تر از ۸ پل همزمان
                    val bridges = if (!customBridges.isNullOrEmpty()) {
                        customBridges
                    } else {
                        defaultObfs4Bridges
                    }
                    bridges.take(2).forEach { sb.appendLine("Bridge $it") }
                }
            }
            "meek_lite" -> {
                if (obfs4Path != null) {
                    sb.appendLine("UseBridges 1")
                    sb.appendLine("ClientTransportPlugin meek_lite exec ${obfs4Path}")
                    if (!customBridges.isNullOrEmpty()) {
                        customBridges.take(1).forEach { sb.appendLine("Bridge $it") }
                    } else {
                        val host = if (!sni.isNullOrEmpty()) sni!! else "certum.pl"
                        sb.appendLine("Bridge meek_lite 192.0.2.2:443 url=https://$host/ front=$host")
                    }
                }
            }
            "snowflake" -> {
                if (snowflakePath != null) {
                    sb.appendLine("UseBridges 1")
                    // snowflake به خودی خود کند است؛ front درست کمک می‌کند
                    val front = if (!sni.isNullOrEmpty()) sni else "cdn.sstatic.net"
                    sb.appendLine(
                        "ClientTransportPlugin snowflake exec ${snowflakePath}" +
                            " -url https://snowflake-broker.torproject.net.global.prod.fastly.net/" +
                            " -front $front" +
                            " -ice stun:stun.l.google.com:19302,stun:stun.antisip.com:3478"
                    )
                    if (!customBridges.isNullOrEmpty()) {
                        customBridges.take(1).forEach { sb.appendLine("Bridge $it") }
                    } else {
                        sb.appendLine("Bridge snowflake 192.0.2.3:1 2B280B23E1107BB62ABFC40DDCC8824814F80A72")
                    }
                }
            }
            "conjure" -> {
                if (conjurePath != null) {
                    sb.appendLine("UseBridges 1")
                    sb.appendLine("ClientTransportPlugin conjure exec ${conjurePath}")
                    val bridges = if (!customBridges.isNullOrEmpty()) {
                        customBridges
                    } else {
                        listOf("conjure 192.0.2.3:80 url=https://registration.refraction.network/api")
                    }
                    bridges.take(2).forEach { sb.appendLine("Bridge $it") }
                }
            }
            "dnstt" -> {
                if (dnsttPath != null) {
                    // Slipnet-style DNSTT: -udp RESOLVER + Bridge dnstt DOMAIN
                    sb.appendLine("UseBridges 1")
                    val bridges = if (!customBridges.isNullOrEmpty()) {
                        customBridges
                    } else {
                        emptyList()
                    }
                    var resolver = "8.8.8.8:53"
                    if (bridges.isNotEmpty()) {
                        val m = Regex("""resolver=([^\\s]+)""").find(bridges.first())
                        if (m != null) resolver = m.groupValues[1]
                    }
                    sb.appendLine(
                        "ClientTransportPlugin dnstt exec ${dnsttPath} -udp ${resolver}"
                    )
                    if (bridges.isNotEmpty()) {
                        bridges.take(3).forEach { line ->
                            val t = line.trim()
                            if (t.startsWith("Bridge ", ignoreCase = true)) {
                                sb.appendLine(t)
                            } else {
                                sb.appendLine("Bridge $t")
                            }
                        }
                    }
                }
            }
        }
        return sb.toString()
    }

    /** پل‌های obfs4 رایگان پیش‌فرض (Tor Project) */
    private val defaultObfs4Bridges = listOf(
        "obfs4 85.31.186.98:443 011F2599C0E9B27EE74B353155E244813763C3E5 cert=ayq0XzCwhpdysn5o0EyDUbmSOx3X/oTEbzDMvczHOdBJKlvIdHHLJGkZARtT4dcBFArPPg iat-mode=0",
        "obfs4 85.31.186.26:443 91A6354697E6B02A386312F68D82CF86824D3606 cert=PBwr+S8JTVoY5s2ZoU4crfN3+7iRHvBkthvS7X6nJDMqLmRU+aGWDsBqsjt8tgALri8DA iat-mode=0",
        "obfs4 193.11.166.194:27015 2D82C2E354D531A68469ADF7F878FA6060C6BEB4 cert=4TLQPJrTSaDffMK7Nbao6LC7G9OW/NHkUwIdjLSS3KYf0Nv4/nQiiI8dY2TcsQx01NniOg iat-mode=0",
        "obfs4 193.11.166.194:27020 86AC7B8D43B3F0A5B7EC1B0D3D22AC2ABDC1BF76 cert=hn+QhFuKUvNJKZQZoqk0pWXBjNq9NbqmxTBna0e+7OxsSJqhvz0j7BF9+YyRzTXj9wW4Ig iat-mode=0",
        "obfs4 193.11.166.194:27025 1AE2AC633B43DFE098342A6951ADFA3B523137D2 cert=H7dp/KfIY8kJsKtv1hnPYFxnDM1hF2t4A2UgAp/1KzXQjVo1Z+zkd4CJxZ3N3jq5LZCFIA iat-mode=0",
        "obfs4 209.148.46.65:443 74FAD13168806246602538555B9351E037946476 cert=ssH+9rP8dG2NLDN2XuFw63hWP/zAYy2N6MzYqTgxfDQ iat-mode=0",
        "obfs4 146.57.248.225:22 10A6CD36A537FCE513A322361547444B393989F0 cert=K1gDtDAIcUfeLqbstggjIw2rtgI3xdX2xmnFTIqqpAH8mLuVKhM1WT3S40/b9aU2vz75XQ iat-mode=0",
        "obfs4 45.145.95.6:27015 C5B7CD6946FF10C5B3E89691A7D3F2C122D2117C cert=TD7PbUO0/0k6xYHMvW7T2wEbmTm6x2D5aQh5v4mQzqE iat-mode=0",
    )
}
