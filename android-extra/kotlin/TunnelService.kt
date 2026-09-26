package com.hasan.hasan_vpn

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import kotlin.concurrent.thread

/**
 * اجرای هسته‌های تونل DNS/QUIC (DNSTT، NoizDNS، VayDNS، Slipstream) به‌صورت
 * یک پردازهٔ فرزند داخل Foreground Service. باینری‌ها ELF هستند و با نام
 * lib*.so در jniLibs قرار می‌گیرند (extractNativeLibs=true).
 *
 * همهٔ آرگومان‌ها و env از Dart می‌آید — این Service فقط process management
 * می‌کند تا برای همهٔ انواع تونل یکسان کار کند.
 */
class TunnelService : Service() {

    companion object {
        private const val TAG = "TunnelService"
        private const val CHANNEL_ID = "tunnel_core"
        private const val NOTIFICATION_ID = 4243
        private const val EXTRA_BINARY = "binary"
        private const val EXTRA_ARGS = "args"
        private const val EXTRA_ENV = "env"
        private const val EXTRA_REMARK = "remark"
        private const val PID_FILE = "tunnel.pid"
        private const val TAIL_SIZE = 80

        private val ANSI = Regex("\u001B\\[[0-9;?]*[ -/]*[@-~]")
        private val lock = Any()

        @Volatile private var instance: TunnelService? = null
        private var process: Process? = null
        private var processPid = -1
        private var generation = 0L
        private var running = false
        private var exited = false
        private var exitCode: Int? = null
        private var lastLine = ""
        private var lastError: String? = null
        private val tail = mutableListOf<String>()

        fun binaryFile(context: Context, name: String): File =
            File(context.applicationInfo.nativeLibraryDir, name)

        fun start(
            context: Context,
            binaryName: String,
            args: List<String>,
            env: Map<String, String>,
            remark: String,
        ): Boolean {
            val binary = binaryFile(context, binaryName)
            if (!binary.isFile) {
                synchronized(lock) { lastError = "$binaryName not found at ${binary.absolutePath}" }
                return false
            }
            return try {
                synchronized(lock) {
                    running = false; exited = false; exitCode = null
                    lastLine = ""; lastError = null; tail.clear()
                }
                val intent = Intent(context, TunnelService::class.java)
                    .putExtra(EXTRA_BINARY, binaryName)
                    .putExtra(EXTRA_ARGS, JSONArray(args).toString())
                    .putExtra(EXTRA_ENV, JSONObject(env as Map<*, *>).toString())
                    .putExtra(EXTRA_REMARK, remark)
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    context.startForegroundService(intent)
                } else {
                    context.startService(intent)
                }
                true
            } catch (e: Exception) {
                SafeLog.e(TAG, "start failed", e)
                synchronized(lock) { lastError = e.message ?: e.javaClass.simpleName }
                false
            }
        }

        fun stop(context: Context) {
            destroyProcess()
            try {
                context.stopService(Intent(context, TunnelService::class.java))
            } catch (e: Exception) {
                SafeLog.w(TAG, "stopService failed", e)
            }
        }

        fun status(): Map<String, Any?> = synchronized(lock) {
            mapOf(
                "running" to running,
                "exited" to exited,
                "exitCode" to exitCode,
                "lastLine" to lastLine,
                "error" to lastError,
                "log" to tail.takeLast(30).joinToString("\n"),
            )
        }

        private fun destroyProcess() {
            var victim: Process? = null
            var victimPid = -1
            synchronized(lock) {
                victim = process
                victimPid = processPid
                process = null
                processPid = -1
                generation++
                running = false
            }
            val target = victim ?: return
            try { target.destroy() } catch (e: Exception) { SafeLog.w(TAG, "destroy", e) }
            thread(name = "tunnel-reaper", isDaemon = true) {
                try {
                    Thread.sleep(1500)
                    val alive = try { target.exitValue(); false } catch (_: IllegalThreadStateException) { true }
                    if (alive && victimPid > 0) android.os.Process.killProcess(victimPid)
                } catch (_: Exception) {}
            }
        }

        private fun pidOf(proc: Process): Int {
            try {
                val m = proc.javaClass.getMethod("pid")
                return (m.invoke(proc) as Number).toInt()
            } catch (_: Exception) {}
            return try {
                val f = proc.javaClass.getDeclaredField("pid")
                f.isAccessible = true
                f.getInt(proc)
            } catch (_: Exception) { -1 }
        }
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val binaryName = intent?.getStringExtra(EXTRA_BINARY)
        val argsJson = intent?.getStringExtra(EXTRA_ARGS)
        val envJson = intent?.getStringExtra(EXTRA_ENV)
        val remark = intent?.getStringExtra(EXTRA_REMARK) ?: "Tunnel"
        instance = this

        try {
            enterForeground(remark)
        } catch (e: Exception) {
            SafeLog.e(TAG, "startForeground failed", e)
            fail("foreground failed: ${e.message}")
            return START_NOT_STICKY
        }

        if (binaryName.isNullOrEmpty()) {
            fail("Missing binary name")
            return START_NOT_STICKY
        }

        launch(binaryName, argsJson ?: "[]", envJson ?: "{}")
        return START_NOT_STICKY
    }

    override fun onDestroy() {
        if (instance === this) {
            instance = null
            destroyProcess()
        }
        super.onDestroy()
    }

    private fun fail(message: String) {
        SafeLog.e(TAG, message)
        synchronized(lock) {
            lastError = message
            running = false
        }
        stopSelf()
    }

    private fun launch(binaryName: String, argsJson: String, envJson: String) {
        val binary = binaryFile(this, binaryName)
        if (!binary.isFile) {
            fail("$binaryName not found")
            return
        }

        val args = try {
            val arr = JSONArray(argsJson)
            (0 until arr.length()).map { arr.getString(it) }
        } catch (e: Exception) {
            fail("Invalid args: ${e.message}")
            return
        }

        val env = try {
            val obj = JSONObject(envJson)
            val m = LinkedHashMap<String, String>()
            val keys = obj.keys()
            while (keys.hasNext()) {
                val k = keys.next()
                m[k] = obj.optString(k, "")
            }
            m
        } catch (e: Exception) {
            fail("Invalid env: ${e.message}")
            return
        }

        killLeftover()
        destroyProcess()

        val cmd = mutableListOf(binary.absolutePath)
        cmd.addAll(args)
        val builder = ProcessBuilder(cmd)
            .directory(filesDir)
            .redirectErrorStream(true)

        val environment = builder.environment()
        environment["HOME"] = filesDir.absolutePath
        environment["TMPDIR"] = cacheDir.absolutePath
        environment["NO_COLOR"] = "1"
        environment.putAll(env)

        SafeLog.i(TAG, "launch cmd=${cmd.joinToString(" ")}")

        val proc = try {
            builder.start()
        } catch (e: Exception) {
            SafeLog.e(TAG, "ProcessBuilder.start failed", e)
            fail("start failed: ${e.message}")
            return
        }

        val pid = pidOf(proc)
        var cur = 0L
        synchronized(lock) {
            generation++
            cur = generation
            process = proc
            processPid = pid
            running = true
            exited = false
            exitCode = null
        }
        val gen = cur
        writePid(pid)
        SafeLog.i(TAG, "Tunnel started (binary=$binaryName pid=$pid)")

        thread(name = "tunnel-log", isDaemon = true) { readLoop(proc, gen) }
        thread(name = "tunnel-wait", isDaemon = true) {
            val code = try {
                proc.waitFor()
            } catch (_: InterruptedException) {
                return@thread
            }
            synchronized(lock) {
                if (generation == gen) {
                    running = false
                    exited = true
                    exitCode = code
                }
            }
            SafeLog.w(TAG, "Tunnel exited with code $code")
            clearPid()
        }
    }

    private fun readLoop(proc: Process, gen: Long) {
        try {
            proc.inputStream.bufferedReader().forEachLine { raw ->
                val line = ANSI.replace(raw, "").trim()
                if (line.isNotEmpty()) {
                    synchronized(lock) {
                        if (generation == gen) {
                            lastLine = line
                            tail.add(line)
                            if (tail.size > TAIL_SIZE) tail.removeAt(0)
                        }
                    }
                    SafeLog.d(TAG, "[tunnel] $line")
                }
            }
        } catch (e: Exception) {
            SafeLog.d(TAG, "log reader stopped: ${e.message}")
        }
    }

    private fun pidFile() = File(filesDir, PID_FILE)

    private fun writePid(pid: Int) {
        if (pid <= 0) return
        try { pidFile().writeText(pid.toString()) } catch (_: Exception) {}
    }

    private fun clearPid() {
        try { pidFile().delete() } catch (_: Exception) {}
    }

    private fun killLeftover() {
        try {
            val f = pidFile()
            if (!f.isFile) return
            val pid = f.readText().trim().toIntOrNull() ?: return
            f.delete()
            if (pid <= 1 || pid == android.os.Process.myPid()) return
            try {
                val cmd = File("/proc/$pid/cmdline").readText()
                if (cmd.contains("dnstt") || cmd.contains("slipstream") ||
                    cmd.contains("noiz") || cmd.contains("vay") ||
                    cmd.contains("tunnel")) {
                    SafeLog.w(TAG, "Killing leftover tunnel process $pid")
                    android.os.Process.killProcess(pid)
                }
            } catch (_: Exception) {}
        } catch (_: Exception) {}
    }

    private fun enterForeground(remark: String) {
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            manager.createNotificationChannel(
                NotificationChannel(CHANNEL_ID, "Tunnel", NotificationManager.IMPORTANCE_LOW),
            )
        }
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
        }
        val icon = if (applicationInfo.icon != 0) applicationInfo.icon else android.R.drawable.ic_dialog_info
        builder.setContentTitle("Tunnel").setContentText(remark).setSmallIcon(icon).setOngoing(true)
        packageManager.getLaunchIntentForPackage(packageName)?.let { li ->
            builder.setContentIntent(
                PendingIntent.getActivity(
                    this, 0, li,
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
                ),
            )
        }
        val n = builder.build()
        if (Build.VERSION.SDK_INT >= 34) {
            startForeground(NOTIFICATION_ID, n, ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE)
        } else {
            startForeground(NOTIFICATION_ID, n)
        }
    }
}
