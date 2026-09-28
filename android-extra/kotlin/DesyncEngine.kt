package com.hasan.hasan_vpn

import android.util.Log
import com.v2ray.ang.core.PingNGProxy

/**
 * Manages a single in-process PingNG Desync listener.
 *
 * The Kotlin side is intentionally dumb: the Dart layer builds the
 * command-line arguments (presets + custom tuning) and only asks us to
 * run them. This keeps the argument grammar in one place, next to the UI.
 *
 *   start(args, port)  → prepares the JNI socket + spawns a daemon thread
 *   stop()             → destroys the listener and joins the thread
 *   activePort()       → 0 when idle, otherwise 1..65535
 */
object DesyncEngine {
    private const val TAG = "DesyncEngine"

    @Volatile private var proxy: PingNGProxy? = null
    @Volatile private var worker: Thread? = null
    @Volatile private var currentPort: Int = 0
    @Volatile private var lastError: String? = null

    fun activePort(): Int = currentPort
    fun isActive(): Boolean = proxy != null
    fun getLastError(): String? = lastError

    @Synchronized
    fun start(args: List<String>, port: Int): Int {
        stop()
        if (port !in 1..65535) {
            lastError = "invalid port: $port"
            return -1
        }
        val cmd = args.toMutableList()
        // Ensure the SOCKS bind address is explicit; the native parser does
        // not fall back to a default when --ip / --port are missing.
        if (!cmd.contains("--ip") && !cmd.contains("-i")) {
            cmd += listOf("--ip", "127.0.0.1")
        }
        if (!cmd.contains("--port") && !cmd.contains("-p")) {
            cmd += listOf("--port", port.toString())
        }
        return try {
            val p = PingNGProxy()
            p.prepare(cmd.toTypedArray())
            proxy = p
            currentPort = port
            lastError = null
            val t = Thread({
                val result = try {
                    p.runLoop()
                } catch (e: Throwable) {
                    Log.e(TAG, "Desync loop failed", e)
                    lastError = e.message
                    -1
                }
                if (proxy === p) {
                    proxy = null
                    worker = null
                    currentPort = 0
                }
                Log.i(TAG, "Desync loop exited with code $result")
            }, "PingNG-Desync")
            t.isDaemon = true
            worker = t
            t.start()
            Log.i(TAG, "Desync started on 127.0.0.1:$port")
            port
        } catch (e: Throwable) {
            Log.e(TAG, "Desync start failed", e)
            lastError = e.message
            proxy = null
            worker = null
            currentPort = 0
            -1
        }
    }

    @Synchronized
    fun stop() {
        val p = proxy
        val t = worker
        proxy = null
        worker = null
        currentPort = 0
        if (p != null) {
            try { p.stop() } catch (e: Throwable) {
                Log.e(TAG, "Desync stop failed", e)
            }
        }
        if (t != null && t !== Thread.currentThread()) {
            try { t.join(500L) } catch (_: InterruptedException) {}
        }
    }
}
