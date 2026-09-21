package com.hasan.hasan_vpn

import android.content.Context
import android.util.Log
import org.json.JSONObject
import java.io.File
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicInteger

/**
 * پل بومی برای هستهٔ واقعی Psiphon (ca.psiphon.PsiphonTunnel).
 *
 * اگر AAR روی classpath نباشد، start با خطای واضح برمی‌گردد تا
 * لایهٔ Dart بتواند به Gool fallback کند.
 *
 * کانال MethodChannel در MainActivity: com.hasan.hasan_vpn/psiphon
 *   start(configJson) -> Map { ok, socksPort, httpPort, error }
 *   stop()            -> Bool
 *   status()          -> Map { running, socksPort, httpPort, region, error }
 */
object PsiphonService {
    private const val TAG = "PsiphonService"

    @Volatile private var running = false
    @Volatile private var lastError: String? = null
    @Volatile private var region: String? = null
    private val socksPort = AtomicInteger(0)
    private val httpPort = AtomicInteger(0)

    // reflective handle so compile works even if AAR missing at edit-time
    @Volatile private var tunnelObj: Any? = null

    fun status(): Map<String, Any?> = mapOf(
        "running" to running,
        "socksPort" to socksPort.get(),
        "httpPort" to httpPort.get(),
        "region" to region,
        "error" to lastError,
        "libraryPresent" to isLibraryPresent(),
    )

    fun isLibraryPresent(): Boolean {
        return try {
            Class.forName("ca.psiphon.PsiphonTunnel")
            true
        } catch (_: ClassNotFoundException) {
            false
        }
    }

    @Synchronized
    fun start(context: Context, configJson: String, timeoutSec: Long = 90): Map<String, Any?> {
        stop(context)
        lastError = null
        region = null
        socksPort.set(0)
        httpPort.set(0)

        if (!isLibraryPresent()) {
            lastError = "Psiphon library (ca.psiphon.aar) is not bundled in this build"
            return status().toMutableMap().apply { put("ok", false) }
        }

        return try {
            val host = HostBridge(context, configJson)
            val clazz = Class.forName("ca.psiphon.PsiphonTunnel")
            val newMethod = clazz.getMethod("newPsiphonTunnel", Class.forName("ca.psiphon.PsiphonTunnel\$HostService"))
            // HostService is interface implemented by HostBridge via dynamic proxy if needed
            // Prefer concrete: some versions use PsiphonTunnel.HostService
            val tunnel = try {
                val ctorHost = Class.forName("ca.psiphon.PsiphonTunnel\$HostService")
                clazz.getMethod("newPsiphonTunnel", ctorHost)
                    .invoke(null, host)
            } catch (_: Throwable) {
                // fallback: implement via reflection helper class registered as HostService
                host.asHostService()?.let { hs ->
                    clazz.getMethod("newPsiphonTunnel", hs.javaClass.interfaces.first())
                        .invoke(null, hs)
                } ?: throw IllegalStateException("Cannot create PsiphonTunnel")
            }

            tunnelObj = tunnel
            val startMethod = clazz.getMethod("startTunneling", String::class.java)
            startMethod.invoke(tunnel, "") // embedded config from HostService

            val connected = host.awaitConnected(timeoutSec)
            if (!connected) {
                lastError = host.failReason ?: "Psiphon connect timeout"
                stop(context)
                return status().toMutableMap().apply { put("ok", false) }
            }

            running = true
            status().toMutableMap().apply { put("ok", true) }
        } catch (t: Throwable) {
            lastError = t.message ?: t.toString()
            Log.e(TAG, "start failed", t)
            running = false
            tunnelObj = null
            status().toMutableMap().apply { put("ok", false) }
        }
    }

    @Synchronized
    fun stop(context: Context? = null) {
        try {
            val t = tunnelObj
            if (t != null) {
                t.javaClass.getMethod("stop").invoke(t)
            }
        } catch (t: Throwable) {
            Log.w(TAG, "stop: ${t.message}")
        }
        tunnelObj = null
        running = false
        socksPort.set(0)
        httpPort.set(0)
    }

    /** Host callbacks bridged to PsiphonTunnel.HostService via reflection-friendly fields. */
    class HostBridge(
        private val appContext: Context,
        private val configJson: String,
    ) {
        private val latch = CountDownLatch(1)
        private val connectedFlag = AtomicBoolean(false)
        var failReason: String? = null
            private set

        fun awaitConnected(timeoutSec: Long): Boolean {
            latch.await(timeoutSec, TimeUnit.SECONDS)
            return connectedFlag.get()
        }

        fun getContext(): Context = appContext

        fun getPsiphonConfig(): String {
            // Ensure data root points to app files
            return try {
                val obj = JSONObject(configJson)
                val root = File(appContext.filesDir, "psiphon").apply { mkdirs() }
                obj.put("DataRootDirectory", root.absolutePath)
                if (!obj.has("ClientPlatform")) obj.put("ClientPlatform", "Android")
                if (!obj.has("ClientVersion")) obj.put("ClientVersion", "10")
                // Local proxy ports 0 = auto
                if (!obj.has("LocalSocksProxyPort")) obj.put("LocalSocksProxyPort", 0)
                if (!obj.has("LocalHttpProxyPort")) obj.put("LocalHttpProxyPort", 0)
                obj.toString()
            } catch (_: Exception) {
                configJson
            }
        }

        fun onDiagnosticMessage(message: String) {
            Log.i(TAG, message)
            if (message.contains("error", ignoreCase = true) ||
                message.contains("failed", ignoreCase = true)
            ) {
                failReason = message
            }
        }

        fun onListeningSocksProxyPort(port: Int) {
            socksPort.set(port)
            Log.i(TAG, "SOCKS on $port")
        }

        fun onListeningHttpProxyPort(port: Int) {
            httpPort.set(port)
            Log.i(TAG, "HTTP on $port")
        }

        fun onConnected() {
            connectedFlag.set(true)
            latch.countDown()
        }

        fun onConnecting() {
            Log.i(TAG, "connecting...")
        }

        fun onConnectedServerRegion(r: String) {
            region = r
        }

        fun onExiting() {
            running = false
            latch.countDown()
        }

        fun asHostService(): Any? {
            // Dynamic proxy for ca.psiphon.PsiphonTunnel$HostService
            return try {
                val iface = Class.forName("ca.psiphon.PsiphonTunnel\$HostService")
                java.lang.reflect.Proxy.newProxyInstance(
                    iface.classLoader,
                    arrayOf(iface),
                ) { _, method, args ->
                    when (method.name) {
                        "getContext" -> getContext()
                        "getAppName" -> "HasanVPN"
                        "getPsiphonConfig" -> getPsiphonConfig()
                        "onDiagnosticMessage" -> {
                            onDiagnosticMessage(args?.get(0)?.toString() ?: ""); null
                        }
                        "onAvailableEgressRegions" -> null
                        "onSocksProxyPortInUse" -> null
                        "onHttpProxyPortInUse" -> null
                        "onListeningSocksProxyPort" -> {
                            onListeningSocksProxyPort((args?.get(0) as? Int) ?: 0); null
                        }
                        "onListeningHttpProxyPort" -> {
                            onListeningHttpProxyPort((args?.get(0) as? Int) ?: 0); null
                        }
                        "onUpstreamProxyError" -> {
                            failReason = args?.get(0)?.toString(); null
                        }
                        "onConnecting" -> {
                            onConnecting(); null
                        }
                        "onConnected" -> {
                            onConnected(); null
                        }
                        "onConnectedServerRegion" -> {
                            onConnectedServerRegion(args?.get(0)?.toString() ?: ""); null
                        }
                        "onHomepage" -> null
                        "onClientUpgradeDownloaded" -> null
                        "onClientIsLatestVersion" -> null
                        "onUntunneledAddress" -> null
                        "onBytesTransferred" -> null
                        "onStartedWaitingForNetworkConnectivity" -> null
                        "onStoppedWaitingForNetworkConnectivity" -> null
                        "onActiveAuthorizationIDs" -> null
                        "onExiting" -> {
                            onExiting(); null
                        }
                        "onClientRegion" -> null
                        "onClientAddress" -> null
                        "onApplicationParameters" -> null
                        "onServerAlert" -> null
                        else -> {
                            if (method.returnType == Boolean::class.javaPrimitiveType) false
                            else if (method.returnType == Integer::class.javaPrimitiveType) 0
                            else null
                        }
                    }
                }
            } catch (t: Throwable) {
                Log.e(TAG, "proxy failed", t)
                null
            }
        }
    }
}
