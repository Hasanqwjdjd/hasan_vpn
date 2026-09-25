package com.hasan.hasan_vpn

import android.content.Context
import android.util.Log
import java.io.File
import java.util.concurrent.atomic.AtomicReference

/**
 * Hev TUN launcher using a real hev-socks5-tunnel YAML config
 * (https://github.com/heiher/hev-socks5-tunnel) — NOT fake HEV_* env vars.
 *
 * Binary resolution: filesDir/hev-socks5-tunnel or nativeLibraryDir.
 * If the binary is not present, start() returns false (feature not shipped
 * in the default APK; jniLibs uses tun2socks, not hev).
 */
object HevLauncher {
    private const val TAG = "HasanHevLauncher"
    private val processRef = AtomicReference<Process?>(null)

    @Volatile var logLevel: String = "warn"
    @Volatile var tcpTimeoutMs: Int = 300000
    @Volatile var udpTimeoutMs: Int = 60000
    @Volatile var mtu: Int = 8500
    @Volatile var socksPort: Int = 10808
    @Volatile var socksAddress: String = "127.0.0.1"

    @JvmStatic
    fun update(logLevel: String?, tcpTimeoutSec: Int?, udpTimeoutSec: Int?, mtu: Int?) {
        if (!logLevel.isNullOrBlank()) this.logLevel = logLevel
        // UI stores seconds; YAML expects milliseconds for read-write timeouts.
        if (tcpTimeoutSec != null && tcpTimeoutSec > 0) {
            this.tcpTimeoutMs = tcpTimeoutSec * 1000
        }
        if (udpTimeoutSec != null && udpTimeoutSec > 0) {
            this.udpTimeoutMs = udpTimeoutSec * 1000
        }
        if (mtu != null && mtu in 1280..9000) this.mtu = mtu
        Log.i(TAG, "params log=$logLevel tcpMs=$tcpTimeoutMs udpMs=$udpTimeoutMs mtu=$mtu")
    }

    /**
     * Write hev-socks5-tunnel.yml and spawn ProcessBuilder(binary, yamlPath).
     */
    @JvmStatic
    fun start(context: Context, configPathIgnored: String? = null): Boolean {
        stop()
        val binary = resolveBinary(context)
        if (binary == null) {
            Log.e(TAG, "hev-socks5-tunnel binary NOT FOUND under filesDir or nativeLibraryDir — feature not shipped")
            return false
        }
        if (!binary.canExecute()) {
            binary.setExecutable(true)
        }
        val yaml = File(context.filesDir, "hev-socks5-tunnel.yml")
        val yamlBody = """
            |tunnel:
            |  mtu: $mtu
            |socks5:
            |  port: $socksPort
            |  address: $socksAddress
            |  udp: 'udp'
            |misc:
            |  task-stack-size: 20480
            |  tcp-read-write-timeout: $tcpTimeoutMs
            |  udp-read-write-timeout: $udpTimeoutMs
            |  log-level: $logLevel
            """.trimMargin()
        yaml.writeText(yamlBody)
        Log.i(TAG, "wrote YAML ${yaml.absolutePath}:\n$yamlBody")

        return try {
            val args = listOf(binary.absolutePath, yaml.absolutePath)
            val pb = ProcessBuilder(args)
                .directory(context.filesDir)
                .redirectErrorStream(true)
            Log.i(TAG, "ProcessBuilder cmd=$args")
            val proc = pb.start()
            processRef.set(proc)
            Thread.sleep(200)
            if (proc.isAlive) {
                true
            } else {
                val out = proc.inputStream.bufferedReader().readText()
                Log.e(TAG, "hev exited immediately: $out")
                false
            }
        } catch (e: Exception) {
            Log.e(TAG, "ProcessBuilder.start failed: ${e.message}", e)
            false
        }
    }

    @JvmStatic
    fun stop() {
        processRef.getAndSet(null)?.let { p ->
            try {
                p.destroy()
                p.waitFor()
            } catch (_: Exception) {
            }
        }
    }

    @JvmStatic
    fun isRunning(): Boolean {
        val p = processRef.get() ?: return false
        return try {
            p.exitValue()
            false
        } catch (_: IllegalThreadStateException) {
            true
        }
    }

    @JvmStatic
    fun binaryExists(context: Context): Boolean = resolveBinary(context) != null

    private fun resolveBinary(context: Context): File? {
        val candidates = listOf(
            File(context.filesDir, "hev-socks5-tunnel"),
            File(context.applicationInfo.nativeLibraryDir, "libhev-socks5-tunnel.so"),
            File(context.applicationInfo.nativeLibraryDir, "hev-socks5-tunnel"),
        )
        val found = candidates.firstOrNull { it.exists() }
        if (found == null) {
            Log.w(TAG, "searched: ${candidates.map { it.absolutePath }}")
        }
        return found
    }
}
