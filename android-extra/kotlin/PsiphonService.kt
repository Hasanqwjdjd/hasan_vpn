package com.hasan.hasan_vpn

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.Build
import android.util.Log
import androidx.core.content.ContextCompat
import org.json.JSONObject
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicReference

/**
 * Facade over [PsiphonRuntimeService]. The old AAR-based PsiphonService loaded
 * ca.psiphon.PsiphonTunnel in the Xray process, which collided on the gomobile
 * go.Seq / libgojni symbols. Psiphon now runs out-of-process in
 * :PingNGPsiphon, and this class only:
 *   1. starts the runtime foreground service,
 *   2. waits for its CONNECTED / FAILED broadcast,
 *   3. returns the status Map the Dart side already expects.
 */
object PsiphonService {
    private const val TAG = "PsiphonService"

    @Volatile private var cachedStatus: Map<String, Any?> = emptyMap()

    fun isLibraryPresent(): Boolean = true

    fun status(): Map<String, Any?> = if (cachedStatus.isEmpty()) {
        baseStatus()
    } else {
        cachedStatus
    }

    private fun baseStatus(): Map<String, Any?> = mapOf(
        "running" to false,
        "socksPort" to 0,
        "httpPort" to 0,
        "region" to null,
        "regions" to emptyList<String>(),
        "error" to null,
        "libraryPresent" to true,
    )

    /**
     * Starts Psiphon and blocks until it reports CONNECTED / FAILED or the
     * timeout expires. [configJson] is the entire Psiphon config document
     * built by the Dart side; the runtime service rewrites only the data
     * directories and adds a missing upstream URL.
     */
    fun start(context: Context, configJson: String, timeoutSec: Long = 90): Map<String, Any?> {
        val guid = "singleton-${System.currentTimeMillis()}"
        val latch = CountDownLatch(1)
        val resultRef = AtomicReference<Map<String, Any?>?>(null)

        val receiver = object : BroadcastReceiver() {
            override fun onReceive(ctx: Context?, intent: Intent?) {
                val id = intent?.getStringExtra(PsiphonRuntimeService.EXTRA_GUID)
                if (id != guid) return
                when (intent.getStringExtra(PsiphonRuntimeService.EXTRA_STATE).orEmpty()) {
                    PsiphonStatus.CONNECTED -> {
                        val port = intent.getIntExtra(PsiphonRuntimeService.EXTRA_SOCKS_PORT, 0)
                        resultRef.compareAndSet(
                            null,
                            baseStatus() + mapOf(
                                "ok" to true,
                                "running" to true,
                                "socksPort" to port,
                            ),
                        )
                        latch.countDown()
                    }
                    PsiphonStatus.FAILED -> {
                        val msg = intent.getStringExtra(PsiphonRuntimeService.EXTRA_MESSAGE).orEmpty()
                        resultRef.compareAndSet(
                            null,
                            baseStatus() + mapOf(
                                "ok" to false,
                                "error" to msg.ifBlank { "Psiphon failed" },
                            ),
                        )
                        latch.countDown()
                    }
                }
            }
        }

        try {
            ContextCompat.registerReceiver(
                context,
                receiver,
                IntentFilter(PsiphonRuntimeService.ACTION_RUNTIME),
                ContextCompat.RECEIVER_NOT_EXPORTED,
            )
        } catch (e: Throwable) {
            Log.e(TAG, "register receiver failed", e)
            return baseStatus() + mapOf("ok" to false, "error" to (e.message ?: "receiver failed"))
        }

        try {
            val intent = Intent(context, PsiphonRuntimeService::class.java).apply {
                action = PsiphonRuntimeService.RUNTIME_START
                putExtra(PsiphonRuntimeService.EXTRA_GUID, guid)
                putExtra(PsiphonRuntimeService.EXTRA_CONFIG_JSON, configJson)
                putExtra(PsiphonRuntimeService.EXTRA_UPSTREAM_PORT, extractUpstreamPort(configJson))
            }
            ContextCompat.startForegroundService(context, intent)
        } catch (e: Throwable) {
            runCatching { context.unregisterReceiver(receiver) }
            Log.e(TAG, "startForegroundService failed", e)
            return baseStatus() + mapOf("ok" to false, "error" to (e.message ?: "start failed"))
        }

        val done = try {
            latch.await(timeoutSec, TimeUnit.SECONDS)
        } catch (_: InterruptedException) {
            false
        }
        runCatching { context.unregisterReceiver(receiver) }

        if (!done) {
            stop(context)
            val result = baseStatus() + mapOf(
                "ok" to false,
                "error" to "Psiphon connect timeout after ${timeoutSec}s",
            )
            cachedStatus = result
            return result
        }

        val result = resultRef.get()
            ?: (baseStatus() + mapOf("ok" to false, "error" to "no result received"))
        if (result["ok"] == true) cachedStatus = result
        return result
    }

    fun stop(context: Context? = null) {
        if (context == null) return
        try {
            val intent = Intent(context, PsiphonRuntimeService::class.java).apply {
                action = PsiphonRuntimeService.RUNTIME_STOP
            }
            context.startService(intent)
        } catch (_: Throwable) {}
        try {
            context.stopService(Intent(context, PsiphonRuntimeService::class.java))
        } catch (_: Throwable) {}
        cachedStatus = baseStatus()
    }

    private fun extractUpstreamPort(configJson: String): Int = try {
        val url = JSONObject(configJson).optString("UpstreamProxyUrl", "")
        if (url.isBlank()) 0 else {
            val port = url.substringAfterLast(':').toIntOrNull() ?: 0
            if (port in 1..65535) port else 0
        }
    } catch (_: Throwable) {
        0
    }
}
