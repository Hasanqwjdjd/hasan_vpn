package com.hasan.hasan_vpn

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Intent
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.os.Build
import android.os.IBinder
import android.util.Log
import androidx.core.app.NotificationCompat
import dalvik.system.DexClassLoader
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.lang.reflect.InvocationHandler
import java.lang.reflect.Method
import java.lang.reflect.Proxy
import java.util.Locale
import java.util.concurrent.atomic.AtomicBoolean

/**
 * Hosts the Psiphon gomobile runtime in its own Android process.
 *
 * Xray and Psiphon both contain a gomobile go.Seq / libgojni runtime. Loading
 * both in the Xray process makes Android bind duplicate JNI symbols to the
 * wrong Go runtime and ends in `fatal error: unknown caller pc`. Keeping this
 * service in :PingNGPsiphon gives Psiphon a clean process and leaves only its
 * local SOCKS listener shared through 127.0.0.1.
 *
 * Adapted from PingNG (rezakhosh78/PingNG). The DEX asset
 * (pingng_psiphon_runtime.dex) embeds ca.psiphon.PsiphonTunnel; the native
 * library libpingng_psiphon.so is loaded through a private ClassLoader so its
 * go.Seq does not collide with Xray's copy.
 */
class PsiphonRuntimeService : Service() {

    companion object {
        const val TAG = "Hasan-PsiphonRuntime"
        const val CHANNEL_ID = "hasan_psiphon_runtime"
        const val NOTIFICATION_ID = 7301
        const val RUNTIME_DEX_ASSET = "pingng_psiphon_runtime.dex"
        const val RUNTIME_DEX_FILE = "pingng_psiphon_runtime_ro_v3.dex"
        const val RUNTIME_DIR_PREFIX = "pingng-psiphon-runtime-"
        const val CONFIG_ASSET = "pingng_psiphon_config.json"
        const val ENTRIES_ASSET = "pingng_psiphon_server_entries.txt"
        const val NATIVE_NAME = "libpingng_psiphon.so"

        // ---- Intent contract (kept local to this file) ----
        const val ACTION_RUNTIME = "com.hasan.hasan_vpn.action.psiphon_runtime"
        const val RUNTIME_START = "start"
        const val RUNTIME_STOP = "stop"
        const val EXTRA_GUID = "psiphon_guid"
        const val EXTRA_REGION = "psiphon_region"
        const val EXTRA_MODE = "psiphon_mode"
        const val EXTRA_CDN_IPS = "psiphon_cdn_ips"
        const val EXTRA_CDN_SNI = "psiphon_cdn_sni"
        const val EXTRA_CDN_SETS = "psiphon_cdn_sets"
        const val EXTRA_UPSTREAM_PORT = "psiphon_upstream_port"
        const val EXTRA_STATE = "psiphon_state"
        const val EXTRA_SOCKS_PORT = "psiphon_socks_port"
        const val EXTRA_MESSAGE = "psiphon_message"
        const val EXTRA_CONFIG_JSON = "psiphon_config_json"

        // Psiphon is always chained through Hasan's local HTTP upstream.
        val CHAINED_TUNNEL_PROTOCOLS = listOf(
            "SSH",
            "OSSH",
            "TLS-OSSH",
            "UNFRONTED-MEEK-OSSH",
            "UNFRONTED-MEEK-HTTPS-OSSH",
            "UNFRONTED-MEEK-SESSION-TICKET-OSSH",
            "SHADOWSOCKS-OSSH",
            "FRONTED-MEEK-OSSH",
            "FRONTED-MEEK-CDN-OSSH",
            "FRONTED-MEEK-HTTP-OSSH",
            "FRONTED-MEEK-CDN-HTTP-OSSH",
        )
        val CDN_TUNNEL_PROTOCOLS = listOf(
            "FRONTED-MEEK-CDN-OSSH",
            "FRONTED-MEEK-CDN-HTTP-OSSH",
        )
    }

    private val starting = AtomicBoolean(false)
    private val runtimeSequence = java.util.concurrent.atomic.AtomicLong(0L)
    @Volatile private var tunnel: Any? = null
    @Volatile private var activeGuid: String? = null
    @Volatile private var runtimeLoader: ClassLoader? = null
    @Volatile private var localSocksPort: Int = 0
    @Volatile private var boundUnderlyingNetwork: Network? = null

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        startForeground(NOTIFICATION_ID, buildNotification())
        when (intent?.action) {
            RUNTIME_START -> {
                val guid = intent.getStringExtra(EXTRA_GUID).orEmpty()
                val region = intent.getStringExtra(EXTRA_REGION).orEmpty()
                val mode = intent.getStringExtra(EXTRA_MODE).orEmpty().ifBlank { "auto" }
                val cdnIps = intent.getStringExtra(EXTRA_CDN_IPS).orEmpty()
                val cdnSni = intent.getStringExtra(EXTRA_CDN_SNI).orEmpty()
                val cdnSets = intent.getStringExtra(EXTRA_CDN_SETS).orEmpty()
                val upstreamPort = intent.getIntExtra(EXTRA_UPSTREAM_PORT, 0)
                val configJson = intent.getStringExtra(EXTRA_CONFIG_JSON).orEmpty()
                if (guid.isNotBlank()) {
                    startRuntime(guid, region, mode, cdnIps, cdnSni, cdnSets, upstreamPort, configJson)
                } else {
                    emit(PsiphonStatus.FAILED, guid, message = "Invalid Psiphon startup parameters")
                    stopSelf(startId)
                }
            }
            RUNTIME_STOP -> {
                stopRuntime()
                stopSelf(startId)
            }
        }
        return START_NOT_STICKY
    }

    override fun onDestroy() {
        stopRuntime()
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    private fun startRuntime(
        guid: String,
        region: String,
        mode: String,
        cdnIps: String,
        cdnSni: String,
        cdnSets: String,
        upstreamPort: Int,
        configJson: String,
    ) {
        if (tunnel != null || starting.get()) {
            stopRuntime()
            starting.set(false)
        }
        if (!starting.compareAndSet(false, true)) return
        activeGuid = guid
        emit(PsiphonStatus.CONNECTING, guid)
        Thread {
            try {
                startInternal(guid, region, mode, cdnIps, cdnSni, cdnSets, upstreamPort, configJson)
            } catch (error: Throwable) {
                val cause = unwrapInvocation(error)
                Log.e(TAG, "Psiphon start failed", cause)
                tunnel = null
                emit(PsiphonStatus.FAILED, guid, message = cause.message.orEmpty())
                stopSelf()
            } finally {
                starting.set(false)
            }
        }.apply { name = "Hasan-Psiphon-runtime-start" }.start()
    }

    private fun startInternal(
        guid: String,
        region: String,
        mode: String,
        cdnIps: String,
        cdnSni: String,
        cdnSets: String,
        upstreamPort: Int,
        configJson: String,
    ) {
        bindToUnderlyingNetwork()
        cleanupStaleRuntimeDirectories()
        val runtimeDir = File(
            codeCacheDir,
            "$RUNTIME_DIR_PREFIX${System.currentTimeMillis()}-${runtimeSequence.incrementAndGet()}",
        ).apply { mkdirs() }
        val dexFile = materializeReadOnlyRuntimeDex(runtimeDir)
        val nativeDir = materializeRuntimeNativeLibrary(runtimeDir)
        val loader = PsiphonDexClassLoader(
            dexFile.absolutePath,
            runtimeDir.absolutePath,
            nativeDir.absolutePath,
            PsiphonRuntimeService::class.java.classLoader,
        )
        runtimeLoader = loader

        Class.forName("go.Seq", true, loader)
            .getMethod("setContext", android.content.Context::class.java)
            .invoke(null, applicationContext)
        Class.forName("psi.Psi", true, loader)
        Log.i(TAG, "Psiphon isolated runtime initialized")

        val tunnelClass = loader.loadClass("ca.psiphon.PsiphonTunnel")
        val hostClass = loader.loadClass("ca.psiphon.PsiphonTunnel\$HostService")
        val config = if (configJson.isNotBlank()) {
            mergeRuntimePaths(configJson, upstreamPort)
        } else {
            buildConfig(region, mode, cdnIps, cdnSni, cdnSets, upstreamPort)
        }
        val entries = assets.open(ENTRIES_ASSET).bufferedReader().use { it.readText() }
        val host = Proxy.newProxyInstance(
            loader,
            arrayOf(hostClass),
            InvocationHandler { _, method, args ->
                when (method.name) {
                    "getContext" -> this
                    "getPsiphonConfig" -> config
                    "loadLibrary" -> null
                    "bindToDevice" -> null
                    "onListeningSocksProxyPort" -> {
                        val port = (args?.firstOrNull() as? Int ?: 0)
                        if (port in 1..65535) {
                            localSocksPort = port
                            Log.i(TAG, "Psiphon SOCKS ready on 127.0.0.1:$port")
                        }
                        null
                    }
                    "onConnected" -> {
                        Thread {
                            repeat(40) {
                                if (activeGuid != guid || tunnel == null) return@Thread
                                val port = instanceSocksPort()
                                if (port in 1..65535) {
                                    localSocksPort = port
                                    Log.i(TAG, "Psiphon is working; SOCKS=127.0.0.1:$port")
                                    emit(PsiphonStatus.CONNECTED, guid, port = port)
                                    return@Thread
                                }
                                Thread.sleep(250L)
                            }
                            Log.w(TAG, "Psiphon connected without a usable SOCKS port")
                            emit(PsiphonStatus.FAILED, guid, message = "SOCKS port unavailable")
                        }.apply { name = "Hasan-Psiphon-connected" }.start()
                        null
                    }
                    "onConnecting" -> {
                        Log.i(TAG, "Psiphon tunnel is connecting")
                        null
                    }
                    "onAvailableEgressRegions" -> null
                    "onClientRegion" -> null
                    "onClientAddress" -> null
                    "onUpstreamProxyError" -> {
                        val message = args?.firstOrNull()?.toString().orEmpty()
                        Log.w(TAG, "Psiphon upstream proxy error: $message")
                        null
                    }
                    "onExiting" -> {
                        emit(PsiphonStatus.STOPPED, guid)
                        null
                    }
                    "onDiagnosticMessage" -> {
                        Log.d(TAG, args?.firstOrNull()?.toString().orEmpty())
                        null
                    }
                    else -> defaultValue(method)
                }
            },
        )

        val instance = tunnelClass.getMethod("newPsiphonTunnel", hostClass).invoke(null, host)
        instance.javaClass.getMethod("setVpnMode", Boolean::class.javaPrimitiveType!!).invoke(instance, false)
        tunnel = instance
        try {
            instance.javaClass.getMethod("startTunneling", String::class.java).invoke(instance, entries)
        } catch (error: Throwable) {
            tunnel = null
            throw unwrapInvocation(error)
        }

        Thread {
            repeat(60) {
                if (tunnel !== instance) return@Thread
                val port = runCatching {
                    instance.javaClass.getMethod("getLocalSocksProxyPort").invoke(instance) as Int
                }.getOrDefault(0)
                if (port in 1..65535) {
                    localSocksPort = port
                    return@Thread
                }
                Thread.sleep(250L)
            }
        }.apply { name = "Hasan-Psiphon-port" }.start()
    }

    @Synchronized
    private fun stopRuntime() {
        val active = tunnel
        tunnel = null
        localSocksPort = 0
        starting.set(false)
        if (active != null) {
            runCatching { active.javaClass.getMethod("stop").invoke(active) }
                .onFailure { Log.e(TAG, "Psiphon stop failed", it) }
        }
        activeGuid?.let { emit(PsiphonStatus.STOPPED, it) }
        activeGuid = null
        runtimeLoader = null
        unbindUnderlyingNetwork()
    }

    private fun bindToUnderlyingNetwork() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return
        val connectivity = getSystemService(ConnectivityManager::class.java) ?: return
        val candidates = connectivity.allNetworks.mapNotNull { network ->
            val caps = connectivity.getNetworkCapabilities(network) ?: return@mapNotNull null
            if (!caps.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET) ||
                !caps.hasCapability(NetworkCapabilities.NET_CAPABILITY_NOT_VPN) ||
                !caps.hasCapability(NetworkCapabilities.NET_CAPABILITY_NOT_RESTRICTED)
            ) return@mapNotNull null
            val validated = caps.hasCapability(NetworkCapabilities.NET_CAPABILITY_VALIDATED)
            val transportScore = when {
                caps.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) -> 3
                caps.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR) -> 2
                caps.hasTransport(NetworkCapabilities.TRANSPORT_ETHERNET) -> 1
                else -> 0
            }
            network to (if (validated) 100 else 0) + transportScore
        }
        val selected = candidates.maxByOrNull { it.second }?.first
        if (selected == null) {
            Log.w(TAG, "Psiphon runtime: no underlying non-VPN network to bind")
            return
        }
        if (runCatching { connectivity.bindProcessToNetwork(selected) }.getOrDefault(false)) {
            boundUnderlyingNetwork = selected
            Log.i(TAG, "Psiphon runtime bound to underlying network: $selected")
        }
    }

    private fun unbindUnderlyingNetwork() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return
        if (boundUnderlyingNetwork == null) return
        val connectivity = getSystemService(ConnectivityManager::class.java)
        runCatching { connectivity?.bindProcessToNetwork(null) }
            .onFailure { Log.w(TAG, "Could not clear Psiphon network binding", it) }
        boundUnderlyingNetwork = null
    }

    /**
     * Uses a caller-supplied Psiphon JSON config as the base, but forces the
     * data directories and adds the upstream URL if it is missing. The
     * runtime process has different filesDir than the caller, so the data
     * root must always be rewritten to this process's path.
     */
    private fun mergeRuntimePaths(raw: String, upstreamPort: Int): String {
        val root = JSONObject(raw)
        val dataRoot = File(filesDir, "pingng-psiphon")
        check(dataRoot.mkdirs() || dataRoot.isDirectory) {
            "Unable to create Psiphon data root: ${dataRoot.absolutePath}"
        }
        val dataStore = File(dataRoot, "datastore")
        check(dataStore.mkdirs() || dataStore.isDirectory) {
            "Unable to create Psiphon datastore: ${dataStore.absolutePath}"
        }
        val osl = File(filesDir, "osl")
        check(osl.mkdirs() || osl.isDirectory) {
            "Unable to create Psiphon OSL directory: ${osl.absolutePath}"
        }
        root.put("DataRootDirectory", dataRoot.absolutePath)
        root.put("DataStoreDirectory", dataStore.absolutePath)
        root.put("MigrateDataStoreDirectory", filesDir.absolutePath)
        root.put("MigrateObfuscatedServerListDownloadDirectory", osl.absolutePath)
        root.put("MigrateRemoteServerListDownloadFilename", File(filesDir, "remote_server_list").absolutePath)
        root.put("EstablishTunnelTimeoutSeconds", 0)
        root.put("UpstreamProxyAllowAllServerEntrySources", true)
        if (!root.has("TunnelWholeDevice")) root.put("TunnelWholeDevice", 0)
        val existingUpstream = root.optString("UpstreamProxyUrl", "")
        if (existingUpstream.isBlank() && upstreamPort in 1..65535) {
            root.put("UpstreamProxyUrl", "http://127.0.0.1:$upstreamPort")
        }
        if (!root.has("DeviceRegion")) root.put("DeviceRegion", Locale.getDefault().country)
        if (!root.has("ClientPlatform")) {
            root.put(
                "ClientPlatform",
                "Android_${Build.VERSION.RELEASE}_$packageName".replace(Regex("[^\\w\\-.]"), "_"),
            )
        }
        if (!root.has("ClientAPILevel")) root.put("ClientAPILevel", Build.VERSION.SDK_INT)
        return root.toString()
    }

    private fun buildConfig(
        region: String,
        mode: String,
        cdnIps: String,
        cdnSni: String,
        cdnSets: String,
        upstreamPort: Int,
    ): String {
        val base = assets.open(CONFIG_ASSET).bufferedReader().use { it.readText() }
        val root = JSONObject(base)
        val dataRoot = File(filesDir, "pingng-psiphon")
        check(dataRoot.mkdirs() || dataRoot.isDirectory) {
            "Unable to create Psiphon data root: ${dataRoot.absolutePath}"
        }
        val dataStore = File(dataRoot, "datastore")
        check(dataStore.mkdirs() || dataStore.isDirectory) {
            "Unable to create Psiphon datastore: ${dataStore.absolutePath}"
        }
        root.put("EgressRegion", normalizedEgressRegion(region))
        root.put("TunnelWholeDevice", 0)
        root.put("UpstreamProxyUrl", "http://127.0.0.1:$upstreamPort")
        root.put("DataRootDirectory", dataRoot.absolutePath)
        root.put("DataStoreDirectory", dataStore.absolutePath)
        root.put("MigrateDataStoreDirectory", filesDir.absolutePath)
        val osl = File(filesDir, "osl")
        check(osl.mkdirs() || osl.isDirectory) {
            "Unable to create Psiphon OSL directory: ${osl.absolutePath}"
        }
        root.put("MigrateObfuscatedServerListDownloadDirectory", osl.absolutePath)
        root.put("MigrateRemoteServerListDownloadFilename", File(filesDir, "remote_server_list").absolutePath)
        root.put("EstablishTunnelTimeoutSeconds", 0)
        root.put("UpstreamProxyAllowAllServerEntrySources", true)
        applyTunnelProtocolMode(root, mode)
        addCdnFrontingConfig(root, mode, cdnIps, cdnSni, cdnSets)
        root.put("DeviceRegion", Locale.getDefault().country)
        root.put("ClientPlatform", "Android_${Build.VERSION.RELEASE}_$packageName".replace(Regex("[^\\w\\-.]"), "_"))
        root.put("ClientAPILevel", Build.VERSION.SDK_INT)
        return root.toString()
    }

    private fun applyTunnelProtocolMode(root: JSONObject, mode: String) {
        val normalized = mode.trim().lowercase(Locale.ROOT)
        val protocols = when (normalized) {
            "cdn" -> CDN_TUNNEL_PROTOCOLS
            "direct" -> CHAINED_TUNNEL_PROTOCOLS.filterNot { it.startsWith("FRONTED-") }
            else -> CHAINED_TUNNEL_PROTOCOLS
        }
        root.put("LimitTunnelProtocols", JSONArray().also { values -> protocols.forEach(values::put) })
        if (normalized == "cdn" || normalized == "direct") root.put("DisableTactics", true)
    }

    private fun addCdnFrontingConfig(
        root: JSONObject,
        mode: String,
        cdnIps: String,
        cdnSni: String,
        cdnSets: String,
    ) {
        if (mode.trim().equals("direct", ignoreCase = true)) return
        fun candidates(raw: String): List<String> = raw.split(',', ';', ' ', '\t', '\n', '\r')
            .map(String::trim).filter(String::isNotBlank)
        val addresses = candidates(cdnIps)
        val names = candidates(cdnSni)
        val sets = candidates(cdnSets)
        if (!mode.trim().equals("cdn", ignoreCase = true) && addresses.isEmpty() && names.isEmpty() && sets.isEmpty()) return
        if (addresses.isNotEmpty()) {
            val spec = JSONObject().apply {
                add("IPCandidates", JSONArray().also { values -> addresses.forEach(values::put) })
                if (names.isNotEmpty()) {
                    add("SNIServerNames", JSONArray().also { values -> names.forEach(values::put) })
                }
            }
            root.put("FrontedMeekCDNScanSpec", spec)
        }
        if (addresses.isEmpty() || sets.isNotEmpty()) root.put("FrontedMeekCDNScanUseBuiltInSpec", true)
        if (sets.isNotEmpty()) {
            root.put("FrontedMeekCDNScanBuiltInSets", JSONArray().also { values -> sets.forEach(values::put) })
        }
    }

    private fun normalizedEgressRegion(region: String): String =
        region.trim().uppercase(Locale.ROOT)
            .takeUnless { it.isBlank() || it == "ANY" || it == "AUTO" }.orEmpty()

    private fun instanceSocksPort(): Int = runCatching {
        tunnel?.javaClass?.getMethod("getLocalSocksProxyPort")?.invoke(tunnel) as Int
    }.getOrDefault(localSocksPort)

    private fun materializeReadOnlyRuntimeDex(runtimeDir: File): File {
        val dexFile = File(runtimeDir, RUNTIME_DEX_FILE)
        if (!dexFile.isFile || dexFile.length() < 1024) {
            assets.open(RUNTIME_DEX_ASSET).use { input ->
                dexFile.outputStream().use { output -> input.copyTo(output) }
            }
        }
        dexFile.setReadable(true, false)
        dexFile.setWritable(false, false)
        dexFile.setExecutable(false, false)
        check(!dexFile.canWrite()) { "Psiphon runtime DEX is writable: ${dexFile.absolutePath}" }
        return dexFile
    }

    private fun materializeRuntimeNativeLibrary(runtimeDir: File): File {
        val source = File(applicationInfo.nativeLibraryDir, NATIVE_NAME)
        check(source.isFile) { "Psiphon native library not found: ${source.absolutePath}" }
        val nativeDir = File(runtimeDir, "lib").apply { mkdirs() }
        val target = File(nativeDir, "libgojni.so")
        if (!target.isFile || target.length() != source.length()) {
            source.copyTo(target, overwrite = true)
        }
        target.setReadable(true, false)
        target.setWritable(false, false)
        target.setExecutable(true, false)
        check(target.isFile && target.canRead()) { "Psiphon runtime library is not readable" }
        return nativeDir
    }

    private fun cleanupStaleRuntimeDirectories() {
        codeCacheDir.listFiles()
            ?.asSequence()
            ?.filter { it.isDirectory && it.name.startsWith(RUNTIME_DIR_PREFIX) }
            ?.forEach { stale ->
                runCatching { stale.deleteRecursively() }
                    .onFailure { Log.w(TAG, "Could not clean old Psiphon runtime cache", it) }
            }
    }

    private fun emit(state: String, guid: String?, port: Int = 0, message: String = "") {
        if (guid.isNullOrBlank()) return
        sendBroadcast(
            Intent(ACTION_RUNTIME)
                .setPackage(packageName)
                .putExtra(EXTRA_GUID, guid)
                .putExtra(EXTRA_STATE, state)
                .putExtra(EXTRA_SOCKS_PORT, port)
                .putExtra(EXTRA_MESSAGE, message),
        )
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            getSystemService(NotificationManager::class.java)?.createNotificationChannel(
                NotificationChannel(CHANNEL_ID, "Psiphon", NotificationManager.IMPORTANCE_LOW),
            )
        }
    }

    private fun buildNotification(): Notification = NotificationCompat.Builder(this, CHANNEL_ID)
        .setSmallIcon(android.R.drawable.ic_lock_idle_lock)
        .setContentTitle("Hasan VPN")
        .setContentText("Psiphon")
        .setCategory(NotificationCompat.CATEGORY_SERVICE)
        .setPriority(NotificationCompat.PRIORITY_LOW)
        .setOngoing(true)
        .build()

    private fun defaultValue(method: Method): Any? = when (method.returnType) {
        Boolean::class.javaPrimitiveType -> false
        Int::class.javaPrimitiveType -> 0
        Long::class.javaPrimitiveType -> 0L
        Float::class.javaPrimitiveType -> 0f
        Double::class.javaPrimitiveType -> 0.0
        Byte::class.javaPrimitiveType -> 0.toByte()
        Short::class.javaPrimitiveType -> 0.toShort()
        Char::class.javaPrimitiveType -> '\u0000'
        else -> null
    }

    private fun unwrapInvocation(error: Throwable): Throwable {
        val invocation = error as? java.lang.reflect.InvocationTargetException ?: return error
        return invocation.targetException?.let(::unwrapInvocation) ?: error
    }

    private class PsiphonDexClassLoader(
        dexPath: String,
        optimizedDirectory: String,
        librarySearchPath: String,
        parent: ClassLoader?,
    ) : DexClassLoader(dexPath, optimizedDirectory, librarySearchPath, parent) {
        private fun belongsToPsiphon(name: String): Boolean =
            name == "go" || name.startsWith("go.") ||
                name == "psi" || name.startsWith("psi.") ||
                name == "ca.psiphon" || name.startsWith("ca.psiphon.")

        override fun loadClass(name: String, resolve: Boolean): Class<*> = synchronized(this) {
            var loaded = findLoadedClass(name)
            if (loaded == null && belongsToPsiphon(name)) {
                loaded = runCatching { findClass(name) }.getOrNull()
            }
            if (loaded == null) loaded = super.loadClass(name, resolve)
            if (resolve) resolveClass(loaded)
            loaded
        }
    }
}
