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
import org.json.JSONObject
import java.io.File
import kotlin.concurrent.thread

/**
 * اجرای هسته‌ی Aether به‌صورت یک پردازه‌ی فرزند داخل Foreground Service.
 *
 * Aether یک فایل اجرایی مستقل (ELF) است که با نام libaether.so در jniLibs
 * قرار می‌گیرد؛ چون extractNativeLibs=true است، اندروید آن را در
 * nativeLibraryDir استخراج می‌کند و از همان‌جا قابل اجراست (اجرا از filesDir
 * روی اندروید ۱۰ به بالا ممنوع است).
 *
 * تمام تنظیمات از طریق متغیرهای محیطی (AETHER_*) داده می‌شود تا پردازه هیچ‌وقت
 * منتظر ورودی تعاملی نماند. هویت WARP (aether*.toml) در filesDir ذخیره می‌شود
 * و بین اجراها می‌ماند.
 */
class AetherService : Service() {

    companion object {
        private const val TAG = "AetherService"
        private const val CHANNEL_ID = "aether_core"
        private const val NOTIFICATION_ID = 4242
        private const val EXTRA_ENV = "env"
        private const val EXTRA_REMARK = "remark"
        private const val BINARY_NAME = "libaether.so"
        private const val PID_FILE = "aether.pid"
        private const val TAIL_SIZE = 60

        private val ANSI = Regex("\u001B\\[[0-9;?]*[ -/]*[@-~]")

        private val lock = Any()

        @Volatile
        private var instance: AetherService? = null

        private var process: Process? = null
        private var processPid = -1
        private var generation = 0L
        private var running = false
        private var exited = false
        private var exitCode: Int? = null
        private var lastLine = ""
        private var lastError: String? = null
        private val tail = mutableListOf<String>()

        // ------------------------------------------------------------ public

        fun binaryFile(context: Context): File =
            File(context.applicationInfo.nativeLibraryDir, BINARY_NAME)

        fun info(context: Context): Map<String, Any?> {
            val binary = binaryFile(context)
            val abi = Build.SUPPORTED_ABIS.firstOrNull() ?: "unknown"
            val present = binary.isFile
            val executable = present && binary.canExecute()
            val elf = if (present) readElfSummary(binary) else emptyMap()

            val identity = context.filesDir.listFiles()?.any {
                it.isFile && it.name.startsWith("aether") && it.name.endsWith(".toml")
            } == true

            val err = when {
                !present ->
                    "Aether core ($BINARY_NAME) is not bundled for this device " +
                        "(CPU: $abi). Use the arm64 build."
                !executable ->
                    "$BINARY_NAME found but not executable (path=${binary.absolutePath})"
                else -> null
            }

            SafeLog.i(TAG, "info present=$present exec=$executable path=${binary.absolutePath} elf=$elf")

            return mapOf(
                "binary" to (present && executable),
                "abi" to abi,
                "path" to binary.absolutePath,
                "size" to if (present) binary.length() else 0L,
                "elf" to elf,
                "hasIdentity" to identity,
                "error" to err,
            )
        }

        /** 64 بایت اول ELF را می‌خواند و کلاس/اندیان/ماشین را برمی‌گرداند. */
        private fun readElfSummary(file: File): Map<String, Any?> {
            return try {
                val buf = ByteArray(64)
                file.inputStream().use { n ->
                    val read = n.read(buf)
                    if (read < 20) return mapOf("error" to "short read $read")
                }
                val magic = buf.copyOfRange(0, 4).joinToString("") { "%02x".format(it) }
                val eiClass = buf[4].toInt() and 0xff // 1=32, 2=64
                val eiData = buf[5].toInt() and 0xff  // 1=LE, 2=BE
                val eType = ((buf[17].toInt() and 0xff) shl 8) or (buf[16].toInt() and 0xff)
                val eMachine = ((buf[19].toInt() and 0xff) shl 8) or (buf[18].toInt() and 0xff)
                mapOf(
                    "magic" to magic,
                    "class" to when (eiClass) { 1 -> "ELF32"; 2 -> "ELF64"; else -> "unknown($eiClass)" },
                    "data" to when (eiData) { 1 -> "LE"; 2 -> "BE"; else -> "unknown($eiData)" },
                    "type" to eType,
                    "machine" to when (eMachine) {
                        0xB7 -> "AArch64"
                        0x28 -> "ARM"
                        0x3E -> "x86_64"
                        0x03 -> "x86"
                        else -> "0x${"%x".format(eMachine)}"
                    },
                )
            } catch (e: Exception) {
                mapOf("error" to (e.message ?: e.javaClass.simpleName))
            }
        }

        /**
         * اجرای `libaether.so --version` (یا بدون آرگومان با timeout کوتاه)
         * برای تشخیص مشکل dlopen/اجرا روی دستگاه.
         */
        fun testBinary(context: Context): Map<String, Any?> {
            val binary = binaryFile(context)
            if (!binary.isFile) {
                return mapOf(
                    "ok" to false,
                    "error" to "$BINARY_NAME not found in ${binary.parent}",
                    "path" to binary.absolutePath,
                )
            }
            return try {
                // بعضی بیلدهای Aether فقط `help`/`--help`/`-v` را می‌شناسند.
                val argsList = listOf(
                    listOf(binary.absolutePath, "--version"),
                    listOf(binary.absolutePath, "-v"),
                    listOf(binary.absolutePath, "help"),
                )
                var lastOut = ""
                var lastErr = ""
                var lastCode = -1
                for (args in argsList) {
                    SafeLog.i(TAG, "testBinary cmd=${args.joinToString(" ")}")
                    val pb = ProcessBuilder(args)
                        .directory(context.filesDir)
                        .redirectErrorStream(true)
                    val env = pb.environment()
                    env["HOME"] = context.filesDir.absolutePath
                    env["TMPDIR"] = context.cacheDir.absolutePath
                    env["NO_COLOR"] = "1"
                    env["AETHER_LOG_LEVEL"] = "error"
                    val proc = pb.start()
                    val stdout = StringBuilder()
                    val reader = Thread {
                        try {
                            proc.inputStream.bufferedReader().forEachLine { line ->
                                stdout.appendLine(line)
                            }
                        } catch (_: Exception) {}
                    }
                    reader.isDaemon = true
                    reader.start()
                    val finished = proc.waitFor(8, java.util.concurrent.TimeUnit.SECONDS)
                    if (!finished) {
                        proc.destroyForcibly()
                        lastOut = stdout.toString()
                        lastErr = "timeout after 8s"
                        lastCode = -1
                        continue
                    }
                    reader.join(1000)
                    lastOut = stdout.toString().trim()
                    lastCode = proc.exitValue()
                    SafeLog.i(TAG, "testBinary exit=$lastCode out=${lastOut.take(200)}")
                    if (lastOut.isNotEmpty() || lastCode == 0) {
                        return mapOf(
                            "ok" to true,
                            "exitCode" to lastCode,
                            "stdout" to lastOut,
                            "stderr" to lastErr,
                            "cmd" to args.joinToString(" "),
                            "path" to binary.absolutePath,
                            "elf" to readElfSummary(binary),
                        )
                    }
                    lastErr = "empty output exit=$lastCode"
                }
                mapOf(
                    "ok" to false,
                    "exitCode" to lastCode,
                    "stdout" to lastOut,
                    "stderr" to lastErr,
                    "path" to binary.absolutePath,
                    "elf" to readElfSummary(binary),
                )
            } catch (e: Exception) {
                SafeLog.e(TAG, "testBinary failed", e)
                mapOf(
                    "ok" to false,
                    "error" to (e.message ?: e.javaClass.simpleName),
                    "path" to binary.absolutePath,
                    "elf" to readElfSummary(binary),
                )
            }
        }

        fun start(context: Context, envJson: String, remark: String): Boolean {
            val binary = binaryFile(context)
            if (!binary.isFile) {
                synchronized(lock) { lastError = "$BINARY_NAME not found in ${binary.parent}" }
                return false
            }

            return try {
                synchronized(lock) {
                    // وضعیت تلاش قبلی نباید به تلاش جدید نشت کند.
                    running = false
                    exited = false
                    exitCode = null
                    lastLine = ""
                    lastError = null
                    tail.clear()
                }

                val intent = Intent(context, AetherService::class.java)
                    .putExtra(EXTRA_ENV, envJson)
                    .putExtra(EXTRA_REMARK, remark)

                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    context.startForegroundService(intent)
                } else {
                    context.startService(intent)
                }
                true
            } catch (error: Exception) {
                SafeLog.e(TAG, "Unable to start service", error)
                synchronized(lock) { lastError = error.message ?: error.javaClass.simpleName }
                false
            }
        }

        fun stop(context: Context) {
            destroyProcess()
            try {
                context.stopService(Intent(context, AetherService::class.java))
            } catch (error: Exception) {
                SafeLog.w(TAG, "Unable to stop service", error)
            }
        }

        /**
         * حساب WARP فعلی (فایل‌های aether*.toml در filesDir) را حذف می‌کند تا
         * دفعه‌ی بعد که Aether اجرا شود، یک حساب رایگان تازه بسازد.
         * برای دکمه‌ی «دریافت کلید WARP جدید». وقتی پردازه در حال اجراست کاری
         * نمی‌کند (باید اول قطع شود) تا فایل هویتِ در حالِ استفاده خراب نشود.
         */
        fun resetIdentity(context: Context): Boolean {
            synchronized(lock) {
                if (running) return false
            }
            return try {
                val removed = context.filesDir.listFiles { f ->
                    f.isFile && f.name.startsWith("aether") && f.name.endsWith(".toml")
                }?.count { it.delete() } ?: 0
                SafeLog.i(TAG, "resetIdentity: removed $removed identity file(s)")
                true
            } catch (error: Exception) {
                SafeLog.w(TAG, "resetIdentity failed", error)
                false
            }
        }

        fun status(): Map<String, Any?> = synchronized(lock) {
            mapOf(
                "running" to running,
                "exited" to exited,
                "exitCode" to exitCode,
                "lastLine" to lastLine,
                "error" to lastError,
                "log" to tail.takeLast(20).joinToString("\n"),
            )
        }

        // ---------------------------------------------------------- internals

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
            val pid = victimPid

            try {
                target.destroy() // SIGTERM؛ Rust معمولاً تمیز بسته می‌شود.
            } catch (error: Exception) {
                SafeLog.w(TAG, "Could not stop process", error)
            }

            // اگر تا ۱.۵ ثانیه بسته نشد، اجباری می‌کُشیم (بدون API های ۲۶+).
            thread(name = "aether-reaper", isDaemon = true) {
                try {
                    Thread.sleep(1500)
                    val stillAlive = try {
                        target.exitValue()
                        false
                    } catch (error: IllegalThreadStateException) {
                        true
                    }
                    if (stillAlive && pid > 0) {
                        android.os.Process.killProcess(pid)
                    }
                } catch (error: Exception) {
                    SafeLog.w(TAG, "reaper: ${error.message}")
                }
            }
        }

        private fun pidOf(proc: Process): Int {
            try {
                val method = proc.javaClass.getMethod("pid")
                return (method.invoke(proc) as Number).toInt()
            } catch (error: Exception) {
                // ادامه با روش بعدی
            }
            return try {
                val field = proc.javaClass.getDeclaredField("pid")
                field.isAccessible = true
                field.getInt(proc)
            } catch (error: Exception) {
                -1
            }
        }
    }

    // ------------------------------------------------------------- lifecycle

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val envJson = intent?.getStringExtra(EXTRA_ENV)
        val remark = intent?.getStringExtra(EXTRA_REMARK) ?: "Aether"

        instance = this

        try {
            enterForeground(remark)
        } catch (error: Exception) {
            SafeLog.e(TAG, "startForeground failed", error)
            fail("Could not start foreground service: ${error.message}")
            return START_NOT_STICKY
        }

        if (envJson.isNullOrEmpty()) {
            fail("Missing environment for Aether")
            return START_NOT_STICKY
        }

        launch(envJson)
        return START_NOT_STICKY
    }

    override fun onDestroy() {
        if (instance === this) {
            instance = null
            destroyProcess()
        }
        super.onDestroy()
    }

    // ---------------------------------------------------------------- launch

    private fun fail(message: String) {
        SafeLog.e(TAG, message)
        synchronized(lock) {
            lastError = message
            running = false
        }
        stopSelf()
    }

    private fun parseEnv(json: String): Map<String, String> {
        val obj = JSONObject(json)
        val out = LinkedHashMap<String, String>()
        val keys = obj.keys()
        while (keys.hasNext()) {
            val key = keys.next()
            if (!key.startsWith("AETHER_")) continue
            out[key] = obj.optString(key, "")
        }
        return out
    }

    private fun launch(envJson: String) {
        val binary = binaryFile(this)
        if (!binary.isFile) {
            fail("$BINARY_NAME not found in ${binary.parent}")
            return
        }

        val env = try {
            parseEnv(envJson)
        } catch (error: Exception) {
            fail("Invalid Aether environment: ${error.message}")
            return
        }

        // اگر اپ قبلاً ناگهانی بسته شده باشد ممکن است یک Aether یتیم مانده باشد.
        killLeftover()
        destroyProcess()

        val builder = ProcessBuilder(binary.absolutePath)
            .directory(filesDir)
            .redirectErrorStream(true)

        val environment = builder.environment()
        environment["HOME"] = filesDir.absolutePath
        environment["TMPDIR"] = cacheDir.absolutePath
        environment["SSL_CERT_DIR"] = "/system/etc/security/cacerts"
        environment["NO_COLOR"] = "1"
        environment.putAll(env)

        SafeLog.i(TAG, "launch cmd=${binary.absolutePath} cwd=${filesDir.absolutePath} envKeys=${env.keys.sorted()}")
        val proc = try {
            builder.start()
        } catch (error: Exception) {
            SafeLog.e(TAG, "ProcessBuilder.start failed", error)
            fail("Cannot start Aether: ${error.message}")
            return
        }

        val pid = pidOf(proc)
        var current = 0L
        synchronized(lock) {
            generation++
            current = generation
            process = proc
            processPid = pid
            running = true
            exited = false
            exitCode = null
        }
        val gen = current

        writePid(pid)
        SafeLog.i(TAG, "Aether started (${env["AETHER_PROTOCOL"]}, ${env["AETHER_SCAN"]})")

        thread(name = "aether-log", isDaemon = true) { readLoop(proc, gen) }

        thread(name = "aether-wait", isDaemon = true) {
            val code = try {
                proc.waitFor()
            } catch (error: InterruptedException) {
                return@thread
            }
            synchronized(lock) {
                if (generation == gen) {
                    running = false
                    exited = true
                    exitCode = code
                }
            }
            SafeLog.w(TAG, "Aether exited with code $code")
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
                    SafeLog.d(TAG, "[aether] $line")
                }
            }
        } catch (error: Exception) {
            SafeLog.d(TAG, "log reader stopped: ${error.message}")
        }
    }

    // ------------------------------------------------------------- pid file

    private fun pidFile() = File(filesDir, PID_FILE)

    private fun writePid(pid: Int) {
        if (pid <= 0) return
        try {
            pidFile().writeText(pid.toString())
        } catch (error: Exception) {
            SafeLog.w(TAG, "Could not write pid file", error)
        }
    }

    private fun clearPid() {
        try {
            pidFile().delete()
        } catch (error: Exception) {
            SafeLog.w(TAG, "Could not delete pid file", error)
        }
    }

    private fun killLeftover() {
        try {
            val file = pidFile()
            if (!file.isFile) return
            val pid = file.readText().trim().toIntOrNull() ?: return
            file.delete()
            if (pid <= 1 || pid == android.os.Process.myPid()) return

            // فقط اگر واقعاً همان Aether باشد؛ شماره‌ی پردازه ممکن است دوباره
            // به یک برنامه‌ی دیگر داده شده باشد.
            val cmdline = File("/proc/$pid/cmdline").readText()
            if (cmdline.contains(BINARY_NAME)) {
                SafeLog.w(TAG, "Killing leftover Aether process $pid")
                android.os.Process.killProcess(pid)
            }
        } catch (error: Exception) {
            // پردازه‌ای نیست یا دسترسی نداریم؛ مشکلی نیست.
        }
    }

    // --------------------------------------------------------- notification

    private fun enterForeground(remark: String) {
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            manager.createNotificationChannel(
                NotificationChannel(CHANNEL_ID, "Aether", NotificationManager.IMPORTANCE_LOW),
            )
        }

        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
        }

        val icon = if (applicationInfo.icon != 0) {
            applicationInfo.icon
        } else {
            android.R.drawable.ic_dialog_info
        }

        builder
            .setContentTitle("Aether")
            .setContentText(remark)
            .setSmallIcon(icon)
            .setOngoing(true)

        packageManager.getLaunchIntentForPackage(packageName)?.let { launchIntent ->
            builder.setContentIntent(
                PendingIntent.getActivity(
                    this,
                    0,
                    launchIntent,
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
                ),
            )
        }

        val notification = builder.build()

        if (Build.VERSION.SDK_INT >= 34) {
            startForeground(
                NOTIFICATION_ID,
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE,
            )
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
    }
}
