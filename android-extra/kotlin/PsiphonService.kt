package com.hasan.hasan_vpn

import android.content.Context
import ca.psiphon.PsiphonTunnel
import org.json.JSONObject
import java.io.File
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicInteger

/**
 * پل بومی Psiphon با AAR رسمی (ca.psiphon:psiphontunnel).
 *   start(configJson) -> Map { ok, socksPort, httpPort, error }
 *   stop()            -> Unit
 *   status()          -> Map { running, socksPort, httpPort, region, regions, error, libraryPresent }
 */
object PsiphonService {
    private const val TAG = "PsiphonService"

    private val lock = Any()

    @Volatile private var tunnel: PsiphonTunnel? = null
    @Volatile private var running = false
    @Volatile private var lastError: String? = null
    @Volatile private var region: String? = null
    @Volatile private var regions: List<String> = emptyList()
    private val socksPort = AtomicInteger(0)
    private val httpPort = AtomicInteger(0)

    fun isLibraryPresent(): Boolean = true

    fun status(): Map<String, Any?> = mapOf(
        "running" to running,
        "socksPort" to socksPort.get(),
        "httpPort" to httpPort.get(),
        "region" to region,
        "regions" to regions,
        "error" to lastError,
        "libraryPresent" to true,
    )

    private fun failed(): Map<String, Any?> =
        status().toMutableMap().apply { put("ok", false) }

    fun start(context: Context, configJson: String, timeoutSec: Long = 90): Map<String, Any?> {
        val host = Host(context.applicationContext, configJson)

        synchronized(lock) {
            stopLocked()
            lastError = null
            region = null
            socksPort.set(0)
            httpPort.set(0)
            try {
                val t = PsiphonTunnel.newPsiphonTunnel(host)
                tunnel = t
                t.startTunneling(loadEmbeddedServerEntries(context))
            } catch (e: Throwable) {
                SafeLog.e(TAG, "start failed", e)
                lastError = e.message ?: e.toString()
                stopLocked()
                return failed()
            }
        }

        val ok = try {
            host.latch.await(timeoutSec, TimeUnit.SECONDS) && host.connected
        } catch (e: InterruptedException) {
            false
        }

        if (!ok) {
            lastError = host.failReason ?: host.lastDiag ?: "Psiphon connect timeout"
            synchronized(lock) { stopLocked() }
            return failed()
        }

        val t = tunnel
        if (socksPort.get() == 0 && t != null) {
            socksPort.set(t.getLocalSocksProxyPort())
        }
        if (socksPort.get() == 0) {
            lastError = "Psiphon connected but SOCKS port is unknown"
            synchronized(lock) { stopLocked() }
            return failed()
        }

        running = true
        return status().toMutableMap().apply { put("ok", true) }
    }

    /**
     * لیست سرورهای توکار (اختیاری): اگر فایل assets/server_entries.txt در بیلد
     * باشد به هسته داده می‌شود تا بدون دانلود لیست سرور هم بتواند شروع کند.
     * نبودنش مشکلی ایجاد نمی‌کند.
     */
    private fun loadEmbeddedServerEntries(context: Context): String = try {
        // FIX_SKIP_EMBEDDED: بذار SDK خودش از S3 دانلود کنه
        // چون لیست embedded ما (از 2024) احتمالاً همه‌شون برای ISP ایران بلاک شدن
        if (true) return ""
        context.applicationContext.assets.open("server_entries.txt")
            .bufferedReader().use { it.readText().trim() }
    } catch (_: Throwable) {
        ""
    }

    fun stop(context: Context? = null) {
        synchronized(lock) { stopLocked() }
    }

    private fun stopLocked() {
        try {
            tunnel?.stop()
        } catch (e: Throwable) {
            SafeLog.w(TAG, "stop: ${e.message}")
        }
        tunnel = null
        running = false
        socksPort.set(0)
        httpPort.set(0)
    }

    /** callbackها روی thread کتابخانه می‌آیند؛ هیچ‌وقت stop() را از داخلشان صدا نزن. */
    private class Host(
        private val appContext: Context,
        private val configJson: String,
    ) : PsiphonTunnel.HostService {

        val latch = CountDownLatch(1)

        @Volatile var connected = false
        @Volatile var failReason: String? = null
        @Volatile var lastDiag: String? = null

        override fun getContext(): Context = appContext

        override fun getPsiphonConfig(): String {
            return try {
                val obj = JSONObject(configJson)
                val root = File(appContext.filesDir, "psiphon").apply { mkdirs() }
                obj.put("DataRootDirectory", root.absolutePath)
                if (!obj.has("LocalSocksProxyPort")) obj.put("LocalSocksProxyPort", 0)
                if (!obj.has("DisableLocalHTTPProxy")) obj.put("DisableLocalHTTPProxy", true)
                obj.toString()
            } catch (e: Exception) {
                configJson
            }
        }

        override fun onDiagnosticMessage(message: String?) {
            if (message != null) {
                lastDiag = message
                SafeLog.d(TAG, message)
            }
        }

        override fun onListeningSocksProxyPort(port: Int) {
            PsiphonService.socksPort.set(port)
        }

        override fun onListeningHttpProxyPort(port: Int) {
            PsiphonService.httpPort.set(port)
        }

        override fun onSocksProxyPortInUse(port: Int) {
            failReason = "SOCKS port $port is in use"
        }

        override fun onUpstreamProxyError(message: String?) {
            failReason = message
        }

        override fun onAvailableEgressRegions(regions: MutableList<String>?) {
            val clean = regions.orEmpty()
                .map { it.trim().uppercase() }
                .filter { it.length == 2 && it.all { c -> c in 'A'..'Z' } }
                .distinct()
                .sorted()
            if (clean.isNotEmpty()) PsiphonService.regions = clean
        }

        override fun onConnectedServerRegion(region: String?) {
            PsiphonService.region = region
        }

        override fun onConnected() {
            connected = true
            latch.countDown()
        }

        override fun onExiting() {
            latch.countDown()
        }
    }
}
