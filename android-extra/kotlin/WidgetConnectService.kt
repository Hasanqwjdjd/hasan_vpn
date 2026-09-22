package com.hasan.hasan_vpn

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.embedding.engine.loader.FlutterLoader
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugins.GeneratedPluginRegistrant

/**
 * سرویس اتصال از ویجت ۱×۱ — کاملاً بدون UI (v2rayNG-style headless).
 *
 * جریان:
 * 1) ویجت روی این سرویس کلیک می‌کند
 * 2) startForeground با نوتیفیکیشن کم‌اهمیت
 * 3) FlutterEngine headless ساخته می‌شود (بدون Activity)
 * 4) entry point "widgetHeadlessMain" از Dart اجرا می‌شود
 * 5) از طریق MethodChannel درخواست اتصال ارسال می‌شود
 * 6) نتیجه گرفته می‌شود و سرویس بعد از مدتی خودش را می‌بندد
 *
 * نیاز به Manifest:
 * <service
 *   android:name=".WidgetConnectService"
 *   android:exported="false"
 *   android:foregroundServiceType="specialUse" />
 */
class WidgetConnectService : Service() {

    private var engine: FlutterEngine? = null
    private var channel: MethodChannel? = null
    private var engineReady = false
    private var pendingConnect: Map<String, String>? = null
    private val handler = Handler(Looper.getMainLooper())

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val origType = intent?.getStringExtra(EXTRA_TYPE) ?: "server"
        val origPayload = intent?.getStringExtra(EXTRA_PAYLOAD) ?: ""
        val origTitle = intent?.getStringExtra(EXTRA_TITLE) ?: ""
        val widgetId = intent?.getIntExtra(EXTRA_WIDGET_ID, -1) ?: -1

        try {
            startFgQuiet()
        } catch (_: Exception) {}

        // اگر از ویجت اومده، binding مخصوص همون ویجت رو بخون
        var type = origType
        var payload = origPayload
        var title = origTitle

        if (widgetId > 0) {
            val bound = readWidgetBinding(widgetId)
            if (bound == null) {
                // binding نداره → MainActivity رو باز کن تا کاربر انتخاب کنه
                openAppForWidgetSelection(widgetId)
                return START_NOT_STICKY
            }
            type = bound.first
            payload = bound.second
            title = bound.third
        }

        if (payload.isEmpty()) {
            stopSoon()
            return START_NOT_STICKY
        }

        // اگر موتور آماده است، مستقیم درخواست بفرست
        if (engineReady && channel != null) {
            sendConnect(type, payload, title)
        } else {
            // در غیر این صورت ذخیره کن تا وقتی آماده شد ارسال شود
            pendingConnect = mapOf(
                "type" to type,
                "payload" to payload,
                "title" to title,
            )
            startHeadlessEngine()
        }

        // سرویس حداکثر ۱۵ ثانیه زنده باشد
        handler.postDelayed({ stopSoon() }, 15000)

        return START_NOT_STICKY
    }

    private fun startHeadlessEngine() {
        try {
            val loader = FlutterLoader()
            loader.startInitialization(applicationContext)
            loader.ensureInitializationComplete(applicationContext, null)

            engine = FlutterEngine(applicationContext).also { e ->
                // ثبت پلاگین‌های Flutter (auto-generated)
                try {
                    GeneratedPluginRegistrant.registerWith(e)
                } catch (_: Exception) {}

                channel = MethodChannel(
                    e.dartExecutor.binaryMessenger,
                    "com.hasan.hasan_vpn/widget_headless",
                ).also { ch ->
                    ch.setMethodCallHandler { call, result ->
                        when (call.method) {
                            "headlessReady" -> {
                                engineReady = true
                                pendingConnect?.let { p ->
                                    sendConnect(
                                        p["type"] ?: "server",
                                        p["payload"] ?: "",
                                        p["title"] ?: "",
                                    )
                                    pendingConnect = null
                                }
                                result.success(true)
                            }
                            "connectResult" -> {
                                val ok = call.argument<Boolean>("ok") ?: false
                                val err = call.argument<String>("error")
                                if (!ok && err != null) {
                                    SafeLog.d("WidgetConnect", "connect failed: $err")
                                }
                                // نوتیفیکیشن موفق/ناموفق به‌روز کن
                                updateFgNotification(ok)
                                result.success(true)
                                handler.postDelayed({ stopSoon() }, 3000)
                            }
                            else -> result.notImplemented()
                        }
                    }
                }

                // اجرای entry point سفارشی
                try {
                    val bundlePath = loader.findAppBundlePath()
                    val entrypoint = DartExecutor.DartEntrypoint(
                        bundlePath,
                        "widgetHeadlessMain",
                    )
                    e.dartExecutor.executeDartEntrypoint(entrypoint)
                } catch (ex: Exception) {
                    SafeLog.d("WidgetConnect", "entrypoint failed: ${ex.message}")
                    stopSoon()
                }
            }
        } catch (ex: Exception) {
            SafeLog.d("WidgetConnect", "engine start failed: ${ex.message}")
            stopSoon()
        }
    }

    private fun sendConnect(type: String, payload: String, title: String) {
        try {
            channel?.invokeMethod(
                "connectFromWidget",
                mapOf(
                    "type" to type,
                    "payload" to payload,
                    "title" to title,
                ),
                object : MethodChannel.Result {
                    override fun success(result: Any?) {
                        val ok = (result as? Map<*, *>)?.get("ok") == true
                        updateFgNotification(ok)
                        handler.postDelayed({ stopSoon() }, 3000)
                    }
                    override fun error(code: String, msg: String?, details: Any?) {
                        updateFgNotification(false)
                        handler.postDelayed({ stopSoon() }, 3000)
                    }
                    override fun notImplemented() {
                        handler.postDelayed({ stopSoon() }, 3000)
                    }
                },
            )
        } catch (ex: Exception) {
            SafeLog.d("WidgetConnect", "sendConnect failed: ${ex.message}")
            stopSoon()
        }
    }

    private fun updateFgNotification(ok: Boolean) {
        try {
            val nm = getSystemService(NotificationManager::class.java) ?: return
            val channelId = "widget_connect_quiet"
            val n: Notification = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                Notification.Builder(this, channelId)
                    .setContentTitle("Hasan VPN")
                    .setContentText(if (ok) "Connected" else "Connect failed")
                    .setSmallIcon(android.R.drawable.ic_lock_lock)
                    .setOngoing(ok)
                    .build()
            } else {
                @Suppress("DEPRECATION")
                Notification.Builder(this)
                    .setContentTitle("Hasan VPN")
                    .setContentText(if (ok) "Connected" else "Connect failed")
                    .setSmallIcon(android.R.drawable.ic_lock_lock)
                    .setOngoing(ok)
                    .build()
            }
            nm.notify(4245, n)
        } catch (_: Exception) {}
    }

    private fun stopSoon() {
        try {
            stopForeground(STOP_FOREGROUND_REMOVE)
        } catch (_: Exception) {}
        try {
            stopSelf()
        } catch (_: Exception) {}
    }

    override fun onDestroy() {
        try {
            channel?.setMethodCallHandler(null)
        } catch (_: Exception) {}
        try {
            engine?.destroy()
        } catch (_: Exception) {}
        engine = null
        channel = null
        super.onDestroy()
    }

    /// خواندن binding یک ویجت خاص از SharedPreferences Flutter
    private fun readWidgetBinding(widgetId: Int): Triple<String, String, String>? {
        return try {
            val prefs = getSharedPreferences("FlutterSharedPreferences", MODE_PRIVATE)
            val key = "flutter.widget_server_$widgetId"
            val raw = prefs.getString(key, null) ?: return null
            // فرمت: type|payload|title
            val parts = raw.split("|", limit = 3)
            if (parts.size != 3) return null
            Triple(parts[0], parts[1], parts[2])
        } catch (_: Exception) {
            null
        }
    }

    /// باز کردن اپ برای انتخاب سرور توسط کاربر (اولین بار)
    private fun openAppForWidgetSelection(widgetId: Int) {
        try {
            val launch = packageManager.getLaunchIntentForPackage(packageName)
            if (launch != null) {
                launch.putExtra("widget_needs_server", true)
                launch.putExtra("widget_id", widgetId)
                launch.addFlags(
                    Intent.FLAG_ACTIVITY_NEW_TASK or
                        Intent.FLAG_ACTIVITY_CLEAR_TOP or
                        Intent.FLAG_ACTIVITY_SINGLE_TOP,
                )
                startActivity(launch)
            }
        } catch (_: Exception) {}
        stopSoon()
    }

    private fun startFgQuiet() {
        val channelId = "widget_connect_quiet"
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val nm = getSystemService(NotificationManager::class.java)
            val ch = NotificationChannel(
                channelId,
                "Quick connect",
                NotificationManager.IMPORTANCE_MIN,
            ).apply {
                setShowBadge(false)
                description = "Background widget connect"
            }
            nm?.createNotificationChannel(ch)
        }
        val n: Notification = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, channelId)
                .setContentTitle("Hasan VPN")
                .setContentText("Connecting…")
                .setSmallIcon(android.R.drawable.ic_lock_lock)
                .setOngoing(true)
                .build()
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
                .setContentTitle("Hasan VPN")
                .setContentText("Connecting…")
                .setSmallIcon(android.R.drawable.ic_lock_lock)
                .setOngoing(true)
                .build()
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(
                4245,
                n,
                android.content.pm.ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE,
            )
        } else {
            startForeground(4245, n)
        }
    }

    companion object {
        const val EXTRA_TYPE = "type"
        const val EXTRA_PAYLOAD = "payload"
        const val EXTRA_TITLE = "title"
        const val EXTRA_WIDGET_ID = "widget_id"

        fun start(context: Context, type: String, payload: String, title: String, widgetId: Int = -1) {
            val i = Intent(context, WidgetConnectService::class.java).apply {
                putExtra(EXTRA_TYPE, type)
                putExtra(EXTRA_PAYLOAD, payload)
                putExtra(EXTRA_TITLE, title)
                putExtra(EXTRA_WIDGET_ID, widgetId)
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(i)
            } else {
                context.startService(i)
            }
        }
    }
}
