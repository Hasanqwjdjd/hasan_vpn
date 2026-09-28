package com.hasan.hasan_vpn

import android.app.Service
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.IBinder
import android.util.Log
import org.json.JSONObject
import java.io.File
import java.io.InputStream
import java.net.InetSocketAddress
import java.net.Socket
import java.util.Collections
import java.util.concurrent.Callable
import java.util.concurrent.CompletionService
import java.util.concurrent.ExecutorCompletionService
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicInteger
import java.util.concurrent.atomic.AtomicReference

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
        private const val EXTRA_DESYNC_ENABLED = "desyncEnabled"
        private const val EXTRA_DESYNC_PORT = "desyncSocksPort"
        private const val EXTRA_ENDPOINT_CANDIDATES = "endpointCandidates"

        private const val MAX_PARALLEL_MASQUE_ATTEMPTS = 6
        private const val MAX_PARALLEL_ENDPOINT_PROBES = 64
        private const val FALLBACK_POOL = (
            "162.159.198.0/24:443," +
                "162.159.199.0/24:443," +
                "8.6.112.0/24:443"
            )

        const val SOCKS_PORT = 1819
        private const val DEFAULT_ENDPOINT = "162.159.198.238:443"
        private const val DEFAULT_SNI = "soft98.ir"
        private const val DEFAULT_DNS = "1.1.1.1,1.0.0.1"

        @Volatile private var progressCallback: ((Map<String, Any?>) -> Unit)? = null
        fun setProgressCallback(cb: ((Map<String, Any?>) -> Unit)?) {
            progressCallback = cb
        }

        private fun emitProgress(
            phase: String,
            tested: Int = 0,
            total: Int = 0,
            endpoint: String = "",
            ms: Int = 0,
            done: Boolean = false,
            error: String = "",
        ) {
            try {
                progressCallback?.invoke(
                    mapOf(
                        "phase" to phase,
                        "tested" to tested,
                        "total" to total,
                        "endpoint" to endpoint,
                        "ms" to ms,
                        "done" to done,
                        "error" to error,
                    )
                )
            } catch (_: Throwable) {}
        }

        @Volatile private var process: Process? = null
        private val cancelled = AtomicBoolean(false)

        fun isActive(): Boolean = process?.isAlive == true

        fun start(
            context: Context,
            endpoint: String = DEFAULT_ENDPOINT,
            endpointCandidates: String? = null,
            sni: String = DEFAULT_SNI,
            dns: String = DEFAULT_DNS,
            http2: Boolean = true,
            desyncEnabled: Boolean = false,
            desyncSocksPort: Int = 0,
        ) {
            val i = Intent(context, WarpMasqueService::class.java).apply {
                action = ACTION_START
                putExtra(EXTRA_ENDPOINT, endpoint)
                putExtra(EXTRA_ENDPOINT_CANDIDATES, endpointCandidates)
                putExtra(EXTRA_SNI, sni)
                putExtra(EXTRA_DNS, dns)
                putExtra(EXTRA_HTTP2, http2)
                putExtra(EXTRA_DESYNC_ENABLED, desyncEnabled)
                putExtra(EXTRA_DESYNC_PORT, desyncSocksPort)
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
                val endpointCandidates = intent.getStringExtra(EXTRA_ENDPOINT_CANDIDATES)
                val sni = intent.getStringExtra(EXTRA_SNI) ?: DEFAULT_SNI
                val dns = intent.getStringExtra(EXTRA_DNS) ?: DEFAULT_DNS
                val http2 = intent.getBooleanExtra(EXTRA_HTTP2, true)
                val desyncEnabled = intent.getBooleanExtra(EXTRA_DESYNC_ENABLED, false)
                val desyncPort = intent.getIntExtra(EXTRA_DESYNC_PORT, 0)
                startForegroundSafe("WARP MASQUE · $endpoint")
                Thread(
                    { runMasque(endpoint, endpointCandidates, sni, dns, http2, desyncEnabled, desyncPort) },
                    "WarpMasqueRunner"
                ).start()
            }
        }
        return START_NOT_STICKY
    }

    private fun runMasque(
        endpoint: String,
        endpointCandidates: String?,
        sni: String,
        dns: String,
        http2: Boolean,
        desyncEnabled: Boolean,
        desyncPort: Int,
    ) {
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

            // ---- 1. register (اگه config نداریم)
            if (!isRegistered(configFile)) {
                if (!registerDevice(binary, root, configFile)) {
                    stopSelf()
                    return
                }
            }

            // ---- 2. Desync proxy setup
            var desyncProxyUrl: String? = null
            if (desyncEnabled && desyncPort in 1..65535) {
                try {
                    desyncProxyUrl = WarpMasqueDesyncProxy.start(desyncPort)
                    Log.i(TAG, "WARP MASQUE outer TLS via Desync: $desyncProxyUrl")
                } catch (e: Throwable) {
                    Log.e(TAG, "Desync proxy start failed", e)
                    desyncProxyUrl = null
                }
            }

            // ---- 3. اول primary endpoint رو امتحان کن
            val primary = parseEndpoint(endpoint)
            if (primary != null) {
                notifyText("Testing primary ${primary.rendered}…")
                emitProgress(
                    phase = "Testing primary",
                    tested = 1,
                    total = 1,
                    endpoint = primary.rendered,
                )
                val started = startEndpoint(
                    binary, root, configFile, primary,
                    sni, dns, http2, desyncProxyUrl,
                    SOCKS_PORT, verifyWarmup = true,
                )
                if (started != null) {
                    Log.i(TAG, "Primary endpoint ${primary.rendered} connected")
                    streamProcess(started.process)
                    return
                }
                Log.i(TAG, "Primary ${primary.rendered} failed; entering fallback scan")
                emitProgress(
                    phase = "Primary failed; scanning pool",
                    tested = 1,
                    total = 1,
                    endpoint = primary.rendered,
                    error = "primary failed",
                )
            }

            // ---- 4. Parallel fallback scan
            val pool = buildCandidatePool(endpointCandidates, primary)
            notifyText("Scanning ${pool.size} MASQUE endpoints…")
            Log.i(TAG, "MASQUE fallback scan: ${pool.size} candidates")

            val winner = findHealthyFallback(
                binary, root, configFile, pool,
                sni, dns, http2, desyncProxyUrl,
            )
            if (winner == null) {
                notifyError("WARP MASQUE could not establish an HTTP/2 tunnel")
                stopSelf()
                return
            }

            // ---- 5. برنده رو روی پورت اصلی راه‌اندازی کن
            Log.i(TAG, "Winner ${winner.endpoint.rendered}; restarting on $SOCKS_PORT")
            destroyProcess(winner.process)
            runCatching { winner.configFile.delete() }

            val finalProc = startEndpoint(
                binary, root, configFile, winner.endpoint,
                sni, dns, http2, desyncProxyUrl,
                SOCKS_PORT, verifyWarmup = true,
            )
            if (finalProc == null) {
                notifyError("Winner ${winner.endpoint.rendered} failed on final start")
                emitProgress(
                    phase = "Failed",
                    endpoint = winner.endpoint.rendered,
                    done = true,
                    error = "final start failed",
                )
                stopSelf()
                return
            }
            emitProgress(
                phase = "Connected",
                endpoint = winner.endpoint.rendered,
                done = true,
            )
            streamProcess(finalProc.process)

        } catch (e: Exception) {
            SafeLog.e(TAG, "MASQUE failed", e)
            notifyError(e.message ?: "unknown error")
        } finally {
            try { WarpMasqueDesyncProxy.stop() } catch (_: Exception) {}
            try { stopForeground(STOP_FOREGROUND_REMOVE) } catch (_: Exception) {}
            stopSelf()
        }
    }

    /** ثبت دستگاه MASQUE — true اگه config آماده شد. */
    private fun registerDevice(binary: File, root: File, configFile: File): Boolean {
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
            return false
        }
        if (registerProc.exitValue() != 0) {
            notifyError("register failed: exit ${registerProc.exitValue()}")
            return false
        }
        if (!isRegistered(configFile)) {
            val found = root.listFiles()?.firstOrNull {
                it.name == "config.json" && isRegistered(it)
            } ?: run {
                notifyError("register produced no valid config")
                return false
            }
            if (found != configFile) found.copyTo(configFile, overwrite = true)
        }
        return true
    }

    /** یک usque process روی پورت مشخص راه‌اندازی + verify. */
    private fun startEndpoint(
        binary: File,
        root: File,
        baseConfig: File,
        endpoint: Endpoint,
        sni: String,
        dns: String,
        http2: Boolean,
        desyncProxyUrl: String?,
        listenPort: Int,
        verifyWarmup: Boolean,
    ): StartedEndpoint? {
        val attemptConfig = File(
            root,
            "attempt-${endpoint.host.replace(Regex("[^A-Za-z0-9_.-]"), "_")}-$listenPort.json"
        )
        try {
            baseConfig.copyTo(attemptConfig, overwrite = true)
            patchHttpProxy(attemptConfig, desyncProxyUrl)

            val args = mutableListOf(
                binary.absolutePath,
                "-c", attemptConfig.absolutePath,
                "socks",
                "-b", "127.0.0.1",
                "-p", listenPort.toString(),
                "-P", endpoint.port.toString(),
                "-s", sni,
            )
            dns.split(",").map { it.trim() }.filter { it.isNotEmpty() }.forEach {
                args.add("-d"); args.add(it)
            }
            if (http2) args.add("--http2")

            val pb = ProcessBuilder(args)
                .directory(root)
                .redirectErrorStream(true)
            if (desyncProxyUrl != null) {
                pb.environment().apply {
                    put("HTTP_PROXY", desyncProxyUrl)
                    put("HTTPS_PROXY", desyncProxyUrl)
                    put("http_proxy", desyncProxyUrl)
                    put("https_proxy", desyncProxyUrl)
                    put("NO_PROXY", "127.0.0.1,localhost")
                }
            }
            val proc = pb.start()

            // گوش دادن به log برای "listening" + "connected to masque"
            val listening = AtomicBoolean(false)
            val masqueOk = AtomicBoolean(false)
            consumeLog(proc, endpoint, listening, masqueOk)

            if (!waitForFlag(proc, listening, 6000)) {
                destroyProcess(proc)
                runCatching { attemptConfig.delete() }
                return null
            }

            if (verifyWarmup) {
                val warmupSocket = openWarmupSocks(listenPort)
                val ready = warmupSocket != null && waitForFlag(proc, masqueOk, 6000)
                runCatching { warmupSocket?.close() }
                if (!ready) {
                    destroyProcess(proc)
                    runCatching { attemptConfig.delete() }
                    return null
                }
            }

            return StartedEndpoint(proc, endpoint, listenPort, attemptConfig)
        } catch (e: Throwable) {
            runCatching { attemptConfig.delete() }
            Log.d(TAG, "startEndpoint ${endpoint.rendered} failed: ${e.message}")
            return null
        }
    }

    /** اسکن موازی: ۶ تا در هر batch. اولین برنده برمی‌گرده. */
    private fun findHealthyFallback(
        binary: File,
        root: File,
        configFile: File,
        candidates: List<Endpoint>,
        sni: String,
        dns: String,
        http2: Boolean,
        desyncProxyUrl: String?,
    ): StartedEndpoint? {
        if (candidates.isEmpty()) return null
        emitProgress(phase = "Scanning MASQUE pool", total = candidates.size)
        val parallelism = MAX_PARALLEL_MASQUE_ATTEMPTS
        val executor = Executors.newFixedThreadPool(parallelism)
        val tempPortBase = SOCKS_PORT + 100
        try {
            for ((batchIdx, batch) in candidates.chunked(parallelism).withIndex()) {
                if (cancelled.get()) return null
                val winner = AtomicReference<StartedEndpoint?>(null)
                val running = Collections.synchronizedSet(mutableSetOf<StartedEndpoint>())
                val completion: CompletionService<StartedEndpoint?> =
                    ExecutorCompletionService(executor)

                repeat(batch.size) { i ->
                    val ep = batch[i]
                    val tempPort = tempPortBase + batchIdx * parallelism + i
                    completion.submit(Callable {
                        var started: StartedEndpoint? = null
                        try {
                            Log.i(TAG, "Probing MASQUE ${ep.rendered} on temp $tempPort")
                            emitProgress(
                                phase = "Probing",
                                endpoint = ep.rendered,
                            )
                            started = startEndpoint(
                                binary, root, configFile, ep,
                                sni, dns, http2, desyncProxyUrl,
                                tempPort, verifyWarmup = true,
                            )
                        } catch (e: Throwable) {
                            Log.d(TAG, "Probe exception ${ep.rendered}: ${e.message}")
                        }
                        val ready = started ?: return@Callable null
                        running += ready
                        emitProgress(
                            phase = "Probe OK",
                            endpoint = ep.rendered,
                            done = false,
                        )
                        if (winner.compareAndSet(null, ready)) ready
                        else {
                            destroyStarted(ready)
                            running -= ready
                            null
                        }
                    })
                }

                var completed = 0
                while (completed < batch.size && winner.get() == null && !cancelled.get()) {
                    val r = runCatching { completion.take().get() }.getOrNull()
                    completed++
                    if (r != null) winner.compareAndSet(null, r)
                }
                val selected = winner.get()
                if (selected != null) {
                    synchronized(running) {
                        running.filter { it !== selected }.forEach(::destroyStarted)
                        running.removeIf { it !== selected }
                    }
                    Log.i(TAG, "Fallback winner ${selected.endpoint.rendered}")
                    return selected
                }
            }
        } finally {
            executor.shutdownNow()
        }
        return null
    }

    /** گوش دادن به stdout و تایید نشانه‌ها. */
    private fun consumeLog(
        proc: Process,
        endpoint: Endpoint,
        listening: AtomicBoolean,
        masqueOk: AtomicBoolean,
    ) {
        Thread {
            runCatching {
                proc.inputStream.bufferedReader().useLines { lines ->
                    for (line in lines) {
                        SafeLog.d(TAG, line)
                        val low = line.lowercase()
                        if (low.contains("listening") ||
                            (low.contains("socks") && low.contains("bound"))
                        ) listening.set(true)
                        if (low.contains("connected to masque server")) {
                            masqueOk.set(true)
                        }
                    }
                }
            }
        }.apply { isDaemon = true }.start()
    }

    /** صبر برای یک flag با deadline. */
    private fun waitForFlag(proc: Process, flag: AtomicBoolean, ms: Int): Boolean {
        val end = System.currentTimeMillis() + ms
        while (System.currentTimeMillis() < end) {
            if (!proc.isAlive) return false
            if (flag.get()) return true
            Thread.sleep(60)
        }
        return false
    }

    /** یک warmup SOCKS5 CONNECT که handshake واقعی رو ایجاد می‌کند. */
    private fun openWarmupSocks(port: Int): Socket? = runCatching {
        Socket().also { s ->
            s.soTimeout = 2500
            s.connect(InetSocketAddress("127.0.0.1", port), 2500)
            val i = s.getInputStream()
            val o = s.getOutputStream()
            o.write(byteArrayOf(0x05, 0x01, 0x00)); o.flush()
            val hello = ByteArray(2); readFully(i, hello)
            check(hello[0].toInt() == 5 && hello[1].toInt() == 0)
            // CONNECT به 1.1.1.1:443
            o.write(byteArrayOf(0x05, 0x01, 0x00, 0x01, 1, 1, 1, 1, 0x01, 0xBB.toByte()))
            o.flush()
        }
    }.getOrNull()

    private fun readFully(input: InputStream, target: ByteArray) {
        var off = 0
        while (off < target.size) {
            val r = input.read(target, off, target.size - off)
            check(r > 0)
            off += r
        }
    }

    /** main loop: log رو تا پایان stream می‌کنه. */
    private fun streamProcess(proc: Process) {
        val logFile = File(filesDir, "warp-masque/masque.log")
        var listening = false
        try {
            proc.inputStream.bufferedReader().useLines { lines ->
                for (line in lines) {
                    runCatching {
                        java.io.FileOutputStream(logFile, true)
                            .bufferedWriter().use { it.appendLine(line) }
                    }
                    SafeLog.d(TAG, line)
                    val low = line.lowercase()
                    if (!listening && (low.contains("listening") ||
                            (low.contains("socks") && low.contains("bound")))
                    ) {
                        listening = true
                        try {
                            MainActivity.warpMasqueChannel?.invokeMethod("onReady", null)
                        } catch (_: Exception) {}
                    }
                }
            }
        } catch (_: Exception) {}
    }

    private fun destroyStarted(started: StartedEndpoint) {
        destroyProcess(started.process)
        runCatching { started.configFile.delete() }
    }

    private fun destroyProcess(proc: Process) {
        runCatching { proc.destroy() }
        runCatching { proc.waitFor(250, TimeUnit.MILLISECONDS) }
        if (proc.isAlive) runCatching { proc.destroyForcibly() }
    }

    /** parse "1.2.3.4:443" → Endpoint. */
    private fun parseEndpoint(raw: String?): Endpoint? {
        val text = raw?.trim().orEmpty()
        if (text.isEmpty()) return null
        val sep = text.lastIndexOf(':')
        if (sep <= 0) return null
        val host = text.substring(0, sep)
        val port = text.substring(sep + 1).toIntOrNull() ?: return null
        if (port !in 1..65535) return null
        return Endpoint(host, port)
    }

    /** ساخت pool از CIDR یا host:port جدا شده با کاما. */
    private fun buildCandidatePool(
        candidatesRaw: String?,
        primary: Endpoint?,
    ): List<Endpoint> {
        val out = mutableListOf<Endpoint>()
        val seen = mutableSetOf<String>()

        fun add(ep: Endpoint) {
            val key = ep.rendered
            if (seen.add(key)) out.add(ep)
        }

        // ۱) لیست کاربر/پیش‌فرض
        val source = candidatesRaw?.takeIf { it.isNotBlank() } ?: FALLBACK_POOL
        source.split(',', ';', '\n', '\r', ' ', '\t')
            .map { it.trim() }
            .filter { it.isNotEmpty() }
            .forEach { token ->
                expandToken(token).forEach(::add)
            }

        // ۲) primary رو از pool حذف کن (قبلاً fail شد)
        if (primary != null) out.removeAll { it == primary }

        // ۳) نمونه‌گیری اگر خیلی بزرگه
        if (out.size > 96) {
            out.shuffle()
            return out.take(96)
        }
        return out
    }

    /** "1.2.3.0/24:443" → 254 endpoint یا "1.2.3.4:443" → 1 endpoint. */
    private fun expandToken(token: String): List<Endpoint> {
        val slash = token.indexOf('/')
        if (slash > 0) {
            val base = token.substring(0, slash)
            val rest = token.substring(slash + 1)
            val port = rest.substringAfter(':', "443").toIntOrNull() ?: 443
            val prefix = rest.substringBefore(':').toIntOrNull() ?: 24
            if (prefix == 24) {
                val parts = base.split('.')
                if (parts.size == 4) {
                    val a = parts[0].toIntOrNull() ?: return emptyList()
                    val b = parts[1].toIntOrNull() ?: return emptyList()
                    val c = parts[2].toIntOrNull() ?: return emptyList()
                    return (1..254).map { Endpoint("$a.$b.$c.$it", port) }
                }
            }
            return emptyList()
        }
        val ep = parseEndpoint(token) ?: return emptyList()
        return listOf(ep)
    }

    private data class Endpoint(val host: String, val port: Int) {
        val rendered: String get() = "$host:$port"
    }

    private data class StartedEndpoint(
        val process: Process,
        val endpoint: Endpoint,
        val listenPort: Int,
        val configFile: File,
    )

    private fun patchHttpProxy(configFile: File, proxyUrl: String?) {
        try {
            val raw = configFile.readText()
            val root = org.json.JSONObject(raw)
            val current = root.optString("http_proxy", "")
            val desired = proxyUrl ?: ""
            if (current == desired) return
            if (desired.isBlank()) {
                root.remove("http_proxy")
            } else {
                root.put("http_proxy", desired)
            }
            configFile.writeText(root.toString())
            Log.i(TAG, "config.json http_proxy -> ${desired.ifBlank { "(none)" }}")
        } catch (e: Throwable) {
            Log.e(TAG, "patchHttpProxy failed", e)
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
