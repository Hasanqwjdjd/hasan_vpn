package com.hasan.hasan_vpn

import android.content.Context
import ca.psiphon.PsiphonTunnel
import org.json.JSONObject
import java.io.File
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicInteger
import java.util.concurrent.atomic.AtomicLong

/**
 * پل بومی Psiphon با AAR رسمی (ca.psiphon:psiphontunnel).
 *   start(configJson) -> Map { ok, socksPort, httpPort, error }
 *   stop()            -> Unit
 *   status()          -> Map { running, socksPort, httpPort, region, regions, error, libraryPresent }
 *
 * هر start() یک generation می‌گیرد. فقط generation برنده‌ی فعلی می‌تواند
 * state را تغییر دهد؛ callbackهای دیرهنگام از attempt قبلی نادیده گرفته
 * می‌شوند (رفع race روی WiFi که attempt 1 بعد از وصل شدن attempt 2، stop می‌زد).
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

    /** نسل فعلی اتصال؛ هر start نسل را افزایش می‌دهد. */
    private val generation = AtomicLong(0)

    /** آخرین نسلی که صراحتاً stop شده. */
    private val stoppedGeneration = AtomicLong(-1)

    fun isLibraryPresent(): Boolean = true

    fun status(): Map<String, Any?> = mapOf(
        "running" to running,
        "socksPort" to socksPort.get(),
        "httpPort" to httpPort.get(),
        "region" to region,
        "regions" to regions,
        "error" to lastError,
        "libraryPresent" to true,
        "generation" to generation.get(),
    )

    private fun failed(): Map<String, Any?> =
        status().toMutableMap().apply { put("ok", false) }

    fun start(context: Context, configJson: String, timeoutSec: Long = 90): Map<String, Any?> {
        val myGen = generation.incrementAndGet()
        SafeLog.d(TAG, "attempt START gen=$myGen timeout=${timeoutSec}s")

        val host = Host(context.applicationContext, configJson, myGen)

        synchronized(lock) {
            // tunnel نسل قبلی را ببند (اگر وجود دارد).
            try {
                tunnel?.stop()
            } catch (e: Throwable) {
                SafeLog.w(TAG, "pre-start stop gen=$myGen: ${e.message}")
            }
            tunnel = null
            running = false
            lastError = null
            region = null
            socksPort.set(0)
            httpPort.set(0)
            try {
                val t = PsiphonTunnel.newPsiphonTunnel(host)
                if (generation.get() != myGen) {
                    SafeLog.w(TAG, "gen=$myGen superseded before startTunneling")
                    try { t.stop() } catch (_: Throwable) {}
                    return failed()
                }
                tunnel = t
                val entries = loadEmbeddedServerEntries(context)
                SafeLog.d(TAG, "gen=$myGen startTunneling entriesLen=${entries.length}")
                t.startTunneling(entries)
            } catch (e: Throwable) {
                SafeLog.e(TAG, "gen=$myGen start failed", e)
                lastError = e.message ?: e.toString()
                try { tunnel?.stop() } catch (_: Throwable) {}
                tunnel = null
                running = false
                return failed()
            }
        }

        val ok = try {
            host.latch.await(timeoutSec, TimeUnit.SECONDS) && host.connected
        } catch (e: InterruptedException) {
            false
        }

        if (generation.get() != myGen) {
            SafeLog.w(TAG, "gen=$myGen lost race after await (current=${generation.get()})")
            return failed()
        }

        if (!ok) {
            lastError = host.failReason ?: host.lastDiag ?: "Psiphon connect timeout after ${timeoutSec}s"
            SafeLog.w(TAG, "gen=$myGen connect failed: $lastError")
            synchronized(lock) {
                if (generation.get() == myGen) {
                    try { tunnel?.stop() } catch (_: Throwable) {}
                    tunnel = null
                    running = false
                    socksPort.set(0)
                    httpPort.set(0)
                }
            }
            return failed()
        }

        val t = tunnel
        if (socksPort.get() == 0 && t != null) {
            socksPort.set(t.getLocalSocksProxyPort())
        }
        if (socksPort.get() == 0) {
            lastError = "Psiphon connected but SOCKS port is unknown"
            SafeLog.w(TAG, "gen=$myGen no socks port")
            synchronized(lock) {
                if (generation.get() == myGen) {
                    try { tunnel?.stop() } catch (_: Throwable) {}
                    tunnel = null
                    running = false
                }
            }
            return failed()
        }

        if (stoppedGeneration.get() >= myGen) {
            SafeLog.w(TAG, "gen=$myGen was explicitly stopped before win")
            return failed()
        }

        running = true
        SafeLog.d(TAG, "gen=$myGen WIN socks=${socksPort.get()} region=$region")
        return status().toMutableMap().apply { put("ok", true) }
    }

    private fun loadEmbeddedServerEntries(context: Context): String {
        return try {
            context.assets.open("server_entries.txt").bufferedReader().use { it.readText() }
        } catch (e: Exception) {
            SafeLog.d(TAG, "no embedded server_entries.txt: ${e.message}")
            ""
        }
    }

    fun stop(context: Context? = null) {
        val g = generation.get()
        stoppedGeneration.set(g)
        SafeLog.d(TAG, "explicit STOP gen=$g")
        synchronized(lock) {
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
    }

    /** callbackها روی thread کتابخانه می‌آیند؛ هیچ‌وقت stop() را از داخلشان صدا نزن. */
    private class Host(
        private val appContext: Context,
        private val configJson: String,
        private val myGen: Long,
    ) : PsiphonTunnel.HostService {

        val latch = CountDownLatch(1)

        @Volatile var connected = false
        @Volatile var failReason: String? = null
        @Volatile var lastDiag: String? = null

        private fun stillCurrent(): Boolean = generation.get() == myGen

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
                if (stillCurrent()) SafeLog.d(TAG, "gen=$myGen $message")
            }
        }

        override fun onListeningSocksProxyPort(port: Int) {
            if (stillCurrent()) PsiphonService.socksPort.set(port)
        }

        override fun onListeningHttpProxyPort(port: Int) {
            if (stillCurrent()) PsiphonService.httpPort.set(port)
        }

        override fun onSocksProxyPortInUse(port: Int) {
            if (stillCurrent()) failReason = "SOCKS port $port is in use"
        }

        override fun onUpstreamProxyError(message: String?) {
            if (stillCurrent()) failReason = message
        }

        override fun onAvailableEgressRegions(regions: MutableList<String>?) {
            if (!stillCurrent()) return
            val clean = regions.orEmpty()
                .map { it.trim().uppercase() }
                .filter { it.length == 2 && it.all { c -> c in 'A'..'Z' } }
                .distinct()
                .sorted()
            if (clean.isNotEmpty()) PsiphonService.regions = clean
        }

        override fun onConnectedServerRegion(region: String?) {
            if (stillCurrent()) PsiphonService.region = region
        }

        override fun onConnected() {
            if (!stillCurrent()) {
                SafeLog.d(TAG, "gen=$myGen onConnected IGNORED (stale)")
                return
            }
            connected = true
            latch.countDown()
        }

        override fun onExiting() {
            if (!stillCurrent()) {
                SafeLog.d(TAG, "gen=$myGen onExiting IGNORED (stale)")
                return
            }
            SafeLog.d(TAG, "gen=$myGen onExiting")
            latch.countDown()
        }
    }
}
