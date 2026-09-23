package com.hasan.hasan_vpn

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Context
import android.content.Intent
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper

/**
 * سرویس دیسپچر برای ویجت ۱×۱ — یک نوتیفیکیشن foreground نشان می‌دهد و
 * تصمیم می‌گیرد که باید «وصل» یا «قطع» انجام شود (toggle)، سپس کار واقعی
 * را به WidgetHeadlessActivity (نامرئی، بدون فلش) می‌سپارد.
 *
 * این سرویس دیگر خودش FlutterEngine نمی‌سازد — چون یک FlutterEngine بدون
 * Activity متصل نمی‌تواند درخواست مجوز VPN پلاگین flutter_vless را هندل
 * کند. به‌جایش WidgetHeadlessActivity (که واقعاً FlutterActivity است، فقط
 * با تم Theme.Translucent.NoDisplay) این کار را انجام می‌دهد.
 *
 * جریان:
 * 1) ویجت روی این سرویس کلیک می‌کند
 * 2) startForeground با نوتیفیکیشن «در حال اتصال…» یا «در حال قطع…»
 * 3) وضعیت فعلی VPN از طریق ConnectivityManager (نه Dart) خوانده می‌شود —
 *    چون هر بار یک isolate/Engine تازه اجرا می‌شود و state درون‌حافظه‌ای
 *    Dart بین اجراها baقی نمی‌ماند؛ ConnectivityManager تنها منبع واقعی و
 *    قابل‌اعتماد وضعیت VPN است.
 * 4) WidgetHeadlessActivity نامرئی باز می‌شود با action=connect یا disconnect
 * 5) نتیجه از طریق callback برمی‌گردد → نوتیفیکیشن به‌روز و سرویس بسته می‌شود
 *
 * نیاز به Manifest:
 * <service
 *   android:name=".WidgetConnectService"
 *   android:exported="false"
 *   android:foregroundServiceType="specialUse" />
 */
class WidgetConnectService : Service() {

    private val handler = Handler(Looper.getMainLooper())

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        // ★ اول از همه startForeground را صدا بزن — وگرنه Android سرویس را
        // حداکثر تا ۵ ثانیه kill می‌کند (ForegroundServiceDidNotStartInTimeException).
        // این باید قبل از هر read، check، یا activity launch باشد.
        val initialAction = if (isVpnConnected()) ACTION_DISCONNECT else ACTION_CONNECT
        try {
            startFgQuiet(initialAction)
        } catch (_: Exception) {}

        val origType = intent?.getStringExtra(EXTRA_TYPE) ?: "server"
        val origPayload = intent?.getStringExtra(EXTRA_PAYLOAD) ?: ""
        val origTitle = intent?.getStringExtra(EXTRA_TITLE) ?: ""
        val widgetId = intent?.getIntExtra(EXTRA_WIDGET_ID, -1) ?: -1

        // اگر از ویجت اومده، binding مخصوص همون ویجت رو بخون
        var type = origType
        var payload = origPayload
        var title = origTitle

        if (widgetId > 0) {
            val bound = readWidgetBinding(widgetId)
            if (bound == null) {
                // binding نداره → MainActivity رو باز کن تا کاربر انتخاب کنه
                // startForeground قبلاً صدا زده شده، پس safe است
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

        // Toggle: اگه الان یک VPN فعاله → این تپ یعنی قطع؛ وگرنه یعنی وصل.
        val action = if (isVpnConnected()) ACTION_DISCONNECT else ACTION_CONNECT

        // startForeground قبلاً صدا زده شده؛ فقط notification را با action به‌روز کن
        try {
            startFgQuiet(action)
        } catch (_: Exception) {}

        launchHeadless(type, payload, title, action)

        // سرویس حداکثر ۲۰ ثانیه زنده بماند (کمی بیشتر از قبل، چون این‌بار
        // واقعاً یک اتصال VPN واقعی از طریق Activity متصل کامل می‌شود).
        handler.postDelayed({ stopSoon() }, 20000)

        return START_NOT_STICKY
    }

    /// آیا الان یک تونل VPN فعال روی دستگاه برقرار است؟ (منبع حقیقت واحد،
    /// مستقل از هر state داخلی Dart که بین اجراهای headless پایدار نیست.)
    private fun isVpnConnected(): Boolean {
        return try {
            val cm = getSystemService(Context.CONNECTIVITY_SERVICE) as? ConnectivityManager
                ?: return false
            val active = cm.activeNetwork ?: return false
            val caps = cm.getNetworkCapabilities(active) ?: return false
            caps.hasTransport(NetworkCapabilities.TRANSPORT_VPN)
        } catch (_: Exception) {
            false
        }
    }

    /// اجرای واقعی وصل/قطع را به Activity نامرئی می‌سپارد.
    private fun launchHeadless(type: String, payload: String, title: String, action: String) {
        WidgetHeadlessActivity.pendingResult = { ok, err ->
            handler.post {
                // SHOW_REAL_ERROR
                if (!ok && err != null) {
                    SafeLog.d("WidgetConnect", "$action failed: $err")
                }
                updateFgNotification(action, ok, err)
                handler.postDelayed({ stopSoon() }, 5000)
            }
        }
        try {
            val launch = Intent(this, WidgetHeadlessActivity::class.java).apply {
                putExtra(WidgetHeadlessActivity.EXTRA_TYPE, type)
                putExtra(WidgetHeadlessActivity.EXTRA_PAYLOAD, payload)
                putExtra(WidgetHeadlessActivity.EXTRA_TITLE, title)
                putExtra(WidgetHeadlessActivity.EXTRA_ACTION, action)
                addFlags(
                    Intent.FLAG_ACTIVITY_NEW_TASK or
                        Intent.FLAG_ACTIVITY_NO_ANIMATION or
                        Intent.FLAG_ACTIVITY_MULTIPLE_TASK or
                        Intent.FLAG_ACTIVITY_EXCLUDE_FROM_RECENTS,
                )
            }
            startActivity(launch)
        } catch (ex: Exception) {
            SafeLog.d("WidgetConnect", "launch headless activity failed: ${ex.message}")
            WidgetHeadlessActivity.pendingResult = null
            updateFgNotification(action, false, null)
            handler.postDelayed({ stopSoon() }, 3000)
        }
    }

    private fun updateFgNotification(action: String, ok: Boolean, err: String? = null) {
        try {
            val nm = getSystemService(NotificationManager::class.java) ?: return
            val text = when {
                action == ACTION_CONNECT && ok -> "Connected"
                action == ACTION_CONNECT && !ok -> {
                    val e = err ?: "unknown"
                    // خطا رو کوتاه کن که توی notification جا بشه
                    if (e.length > 120) e.substring(0, 120) + "..." else e
                }
                action == ACTION_DISCONNECT && ok -> "Disconnected"
                else -> {
                    val e = err ?: "unknown"
                    if (e.length > 120) e.substring(0, 120) + "..." else e
                }
            }
            val ongoing = action == ACTION_CONNECT && ok
            val n = buildNotification(text, ongoing)
            nm.notify(4245, n)
        } catch (_: Exception) {}
    }

    private fun buildNotification(text: String, ongoing: Boolean): Notification {
        val channelId = "widget_connect_quiet"
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, channelId)
                .setContentTitle("Hasan VPN")
                .setContentText(text)
                .setSmallIcon(android.R.drawable.ic_lock_lock)
                .setOngoing(ongoing)
                .build()
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
                .setContentTitle("Hasan VPN")
                .setContentText(text)
                .setSmallIcon(android.R.drawable.ic_lock_lock)
                .setOngoing(ongoing)
                .build()
        }
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
        WidgetHeadlessActivity.pendingResult = null
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

    private fun startFgQuiet(action: String) {
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
        val text = if (action == ACTION_CONNECT) "Connecting…" else "Disconnecting…"
        val n = buildNotification(text, true)
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

        const val ACTION_CONNECT = "connect"
        const val ACTION_DISCONNECT = "disconnect"

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
