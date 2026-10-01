package com.hasan.hasan_vpn

import android.Manifest
import android.app.ActivityManager
import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    private val aetherChannel = "com.hasan.hasan_vpn/aether"
    private val psiphonChannel = "com.hasan.hasan_vpn/psiphon"
    private val deviceChannel = "com.hasan.hasan_vpn/device"
    private val torChannel = "com.hasan.hasan_vpn/tor"
    private val monitorChannel = "com.hasan.hasan_vpn/monitor"
    private val widgetChannel = "com.hasan.hasan_vpn/widget"
    private val logsChannel = "com.hasan.hasan_vpn/logs"
    private val desyncChannelName = "com.hasan.hasan_vpn/desync"

    private var widgetChannelRef: MethodChannel? = null

    companion object {
    }

    /// When the activity is being destroyed, sweep any notification this
    /// app left behind. Foreground-service notifications are normally
    /// removed by STOP_FOREGROUND_REMOVE when the service stops, but a
    /// crash or an unclean process kill leaves the row in the shade.
    /// cancelAll() is idempotent — safe to call even when nothing is left.
    override fun onDestroy() {
        try {
            NotificationHelper.cancelAll(applicationContext)
        } catch (_: Exception) {}
        super.onDestroy()
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        SafeLog.enabled =
            (applicationInfo.flags and android.content.pm.ApplicationInfo.FLAG_DEBUGGABLE) != 0

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, aetherChannel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "info" -> result.success(AetherService.info(applicationContext))
                    "start" -> {
                        val env = call.argument<String>("env")
                        val remark = call.argument<String>("remark") ?: "Aether"
                        if (env.isNullOrEmpty()) {
                            result.error("bad_args", "env is missing", null)
                        } else {
                            result.success(AetherService.start(applicationContext, env, remark))
                        }
                    }
                    "status" -> result.success(AetherService.status())
                    "stop" -> { AetherService.stop(applicationContext); result.success(true) }
                    "resetIdentity" -> result.success(AetherService.resetIdentity(applicationContext))
                    "testBinary" -> {
                        Thread {
                            val map = AetherService.testBinary(applicationContext)
                            runOnUiThread { result.success(map) }
                        }.start()
                    }
                    else -> result.notImplemented()
                }
            }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, psiphonChannel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "status" -> result.success(PsiphonService.status())
                    "start" -> {
                        val config = call.argument<String>("config") ?: ""
                        val timeout = call.argument<Int>("timeoutSec") ?: 90
                        Thread {
                            val map = PsiphonService.start(applicationContext, config, timeout.toLong())
                            runOnUiThread { result.success(map) }
                        }.start()
                    }
                    "stop" -> { PsiphonService.stop(applicationContext); result.success(true) }
                    else -> result.notImplemented()
                }
            }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, deviceChannel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "abis" -> result.success(Build.SUPPORTED_ABIS.toList())
                    "notifPermission" -> { requestNotificationPermission(); result.success(true) }
                    "telemetryShow" -> {
                        val title = call.argument<String>("title") ?: "Hasan VPN"
                        val text = call.argument<String>("text") ?: ""
                        TelemetryNotifier.show(applicationContext, title, text)
                        result.success(true)
                    }
                    "telemetryHide" -> { TelemetryNotifier.hide(applicationContext); result.success(true) }
                    "listApps" -> {
                        Thread {
                            try {
                                val pm = applicationContext.packageManager
                                val myPkg = applicationContext.packageName
                                // همه اپ‌های نصب‌شده — نه فقط آن‌هایی که آیکون لانچر دارند
                                val packages = if (android.os.Build.VERSION.SDK_INT >= 33) {
                                    pm.getInstalledPackages(android.content.pm.PackageManager.PackageInfoFlags.of(0L))
                                } else {
                                    @Suppress("DEPRECATION")
                                    pm.getInstalledPackages(0)
                                }
                                val out = ArrayList<Map<String, Any?>>()
                                val seen = HashSet<String>()
                                for (pi in packages) {
                                    val pkg = pi.packageName ?: continue
                                    if (pkg == myPkg) continue
                                    if (seen.contains(pkg)) continue
                                    seen.add(pkg)
                                    val appInfo = pi.applicationInfo ?: continue
                                    val label = try {
                                        pm.getApplicationLabel(appInfo).toString()
                                    } catch (_: Exception) {
                                        pkg
                                    }
                                    val isSystem = (appInfo.flags and android.content.pm.ApplicationInfo.FLAG_SYSTEM) != 0
                                    var iconB64: String? = null
                                    try {
                                        val drawable = pm.getApplicationIcon(appInfo)
                                        val bmp = if (drawable is android.graphics.drawable.BitmapDrawable) {
                                            drawable.bitmap
                                        } else {
                                            val w = if (drawable.intrinsicWidth > 0) drawable.intrinsicWidth else 48
                                            val h = if (drawable.intrinsicHeight > 0) drawable.intrinsicHeight else 48
                                            val b = android.graphics.Bitmap.createBitmap(w, h, android.graphics.Bitmap.Config.ARGB_8888)
                                            val c = android.graphics.Canvas(b)
                                            drawable.setBounds(0, 0, c.width, c.height)
                                            drawable.draw(c)
                                            b
                                        }
                                        val scaled = android.graphics.Bitmap.createScaledBitmap(bmp, 48, 48, true)
                                        val bos = java.io.ByteArrayOutputStream()
                                        scaled.compress(android.graphics.Bitmap.CompressFormat.PNG, 80, bos)
                                        iconB64 = android.util.Base64.encodeToString(bos.toByteArray(), android.util.Base64.NO_WRAP)
                                    } catch (_: Exception) {}
                                    out.add(mapOf(
                                        "package" to pkg,
                                        "label" to label,
                                        "isSystem" to isSystem,
                                        "icon" to iconB64,
                                    ))
                                }
                                out.sortBy { (it["label"] as? String)?.lowercase() ?: "" }
                                runOnUiThread { result.success(out) }
                            } catch (e: Exception) {
                                runOnUiThread { result.error("listApps", e.message, null) }
                            }
                        }.start()
                    }
                    // Fetch یه URL از طریق SOCKS محلی (Tor 9050 یا Xray 10808).
                    // برای مواقعی که تلگرام در ایران فیلتره و http مستقیم
                    // Dart کار نمی‌کنه — این مسیر از داخل تونل رد می‌شه.
                    "fetchViaSocks" -> {
                        val urlStr = call.argument<String>("url")
                        val port = call.argument<Int>("port") ?: 9050
                        if (urlStr.isNullOrBlank()) {
                            result.error("fetchViaSocks", "missing url", null)
                        } else {
                            Thread {
                                try {
                                    val proxy = java.net.Proxy(
                                        java.net.Proxy.Type.SOCKS,
                                        java.net.InetSocketAddress("127.0.0.1", port),
                                    )
                                    val conn = java.net.URL(urlStr)
                                        .openConnection(proxy) as java.net.HttpURLConnection
                                    conn.connectTimeout = 20000
                                    conn.readTimeout = 30000
                                    conn.instanceFollowRedirects = true
                                    conn.setRequestProperty(
                                        "User-Agent",
                                        "Mozilla/5.0 (Linux; Android 12) " +
                                            "AppleWebKit/537.36 Chrome/120 Mobile",
                                    )
                                    conn.requestMethod = "GET"
                                    val code = conn.responseCode
                                    if (code in 200..299) {
                                        val body = conn.inputStream
                                            .bufferedReader().use { it.readText() }
                                        runOnUiThread { result.success(body) }
                                    } else {
                                        runOnUiThread {
                                            result.error("fetchViaSocks", "HTTP $code", null)
                                        }
                                    }
                                } catch (e: Exception) {
                                    runOnUiThread {
                                        result.error(
                                            "fetchViaSocks",
                                            e.message ?: "err",
                                            null,
                                        )
                                    }
                                }
                            }.start()
                        }
                    }
                    // POST یه URL از طریق SOCKS محلی — برای WARP register
                    // که باید از api.cloudflareclient.com رد شه و در
                    // ایران فیلتره.
                    "postViaSocks" -> {
                        val urlStr = call.argument<String>("url")
                        val port = call.argument<Int>("port") ?: 10808
                        val bodyStr = call.argument<String>("body") ?: ""
                        @Suppress("UNCHECKED_CAST")
                        val headers = call.argument<Map<String, String>>("headers")
                            ?: emptyMap()
                        if (urlStr.isNullOrBlank()) {
                            result.error("postViaSocks", "missing url", null)
                        } else {
                            Thread {
                                try {
                                    val proxy = java.net.Proxy(
                                        java.net.Proxy.Type.SOCKS,
                                        java.net.InetSocketAddress("127.0.0.1", port),
                                    )
                                    val conn = java.net.URL(urlStr)
                                        .openConnection(proxy) as java.net.HttpURLConnection
                                    conn.connectTimeout = 30000
                                    conn.readTimeout = 30000
                                    conn.instanceFollowRedirects = true
                                    conn.doOutput = true
                                    conn.requestMethod = "POST"
                                    for ((k, v) in headers) conn.setRequestProperty(k, v)
                                    conn.setRequestProperty("Content-Type", "application/json; charset=UTF-8")
                                    conn.outputStream.use { it.write(bodyStr.toByteArray(Charsets.UTF_8)) }
                                    val code = conn.responseCode
                                    val stream = if (code in 200..299) conn.inputStream
                                                 else conn.errorStream
                                    val body = stream?.bufferedReader()?.use { it.readText() } ?: ""
                                    runOnUiThread {
                                        result.success(mapOf("code" to code, "body" to body))
                                    }
                                } catch (e: Exception) {
                                    runOnUiThread {
                                        result.error(
                                            "postViaSocks",
                                            e.message ?: "err",
                                            null,
                                        )
                                    }
                                }
                            }.start()
                        }
                    }
                    // BLOCKER 2 — MTU / IPv6 / DNS for VpnService.Builder
                    "setVpnTunParams" -> {
                        val mtu = call.argument<Int>("mtu")
                        val enableIpv6 = call.argument<Boolean>("enableIpv6")
                        @Suppress("UNCHECKED_CAST")
                        val dns = call.argument<List<String>>("dns")
                        @Suppress("UNCHECKED_CAST")
                        val dns6 = call.argument<List<String>>("dns6")
                        VpnTuner.update(mtu, enableIpv6, dns, dns6)
                        VpnTuner.persist(applicationContext)
                        result.success(true)
                    }
                    // BLOCKER 4 — geo asset directory the core reads
                    "setAssetDir" -> {
                        val dir = (call.arguments as? String)
                            ?: call.argument<String>("dir")
                            ?: ""
                        VpnTuner.applyAssetDir(dir)
                        VpnTuner.persist(applicationContext)
                        VpnTuner.ensureAssetSymlinks(applicationContext)
                        result.success(true)
                    }
                    // BLOCKER 3 — Hev TUN CLI params
                    "setHevParams" -> {
                        val logLevel = call.argument<String>("logLevel")
                        val tcp = call.argument<Int>("tcpTimeout")
                        val udp = call.argument<Int>("udpTimeout")
                        val mtu = call.argument<Int>("mtu")
                        HevLauncher.update(logLevel, tcp, udp, mtu)
                        result.success(true)
                    }
                    "startHev" -> {
                        val cfg = call.argument<String>("configPath") ?: ""
                        Thread {
                            val ok = HevLauncher.start(applicationContext, cfg)
                            runOnUiThread { result.success(ok) }
                        }.start()
                    }
                    "stopHev" -> {
                        HevLauncher.stop()
                        result.success(true)
                    }
                    // 0001: OS-level truth — is XrayVPNService still alive?
                    "isXrayVpnServiceRunning" -> {
                        result.success(isXrayVpnServiceRunning())
                    }
                    else -> result.notImplemented()
                }
            }


        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, torChannel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "status" -> result.success(TorService.status())
                    "start" -> {
                        val bridgeType = call.argument<String>("bridgeType") ?: "vanilla"
                        val customBridges = call.argument<List<String>>("customBridges")
                        val sni = call.argument<String>("sni")
                        Thread {
                            val map = TorService.start(applicationContext, bridgeType, customBridges, sni)
                            runOnUiThread { result.success(map) }
                        }.start()
                    }
                    "stop" -> { TorService.stopWithContext(applicationContext); result.success(true) }
                    "fetchMoatBridges" -> {
                        val type = call.argument<String>("type")
                            ?: call.argument<String>("bridgeType")
                            ?: "obfs4"
                        val country = call.argument<String>("country") ?: "ir"
                        Thread {
                            val map = TorMoatFetcher.fetch(type, country)
                            runOnUiThread { result.success(map) }
                        }.start()
                    }
                    else -> result.notImplemented()
                }
            }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, monitorChannel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "snapshot" -> {
                        try { result.success(LiveMonitorService.snapshot(applicationContext)) }
                        catch (e: Exception) { result.error("monitor_error", e.message, null) }
                    }
                    else -> result.notImplemented()
                }
            }


        val desyncCh = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, desyncChannelName)
        desyncCh.setMethodCallHandler { call, result ->
                when (call.method) {
                    "start" -> {
                        val args = call.argument<List<String>>("args") ?: emptyList()
                        val port = call.argument<Int>("port") ?: 0
                        val actualPort = DesyncEngine.start(args, port)
                        if (actualPort > 0) {
                            result.success(actualPort)
                        } else {
                            result.error("start_failed", DesyncEngine.getLastError() ?: "unknown", null)
                        }
                    }
                    "stop" -> {
                        DesyncEngine.stop()
                        result.success(true)
                    }
                    "status" -> {
                        result.success(mapOf(
                            "running" to DesyncEngine.isActive(),
                            "port" to DesyncEngine.activePort(),
                        ))
                    }
                    else -> result.notImplemented()
                }
            }


        // Stubs for channels whose Kotlin services were removed but whose
        // Dart counterparts (master_dns_session_service.dart,
        // tunnel_session_service.dart, warp_masque_session_service.dart)
        // still call invokeMethod on init. Without these, the very first
        // call throws MissingPluginException inside the connect flow and
        // aborts it before VpnService.prepare() ever runs, which is why
        // Aether showed "connected" in the UI but the VPN key icon never
        // appeared. Returning success(false/null) lets the Dart side move
        // on without an exception.
        for (name in listOf(
            "com.hasan.hasan_vpn/masterdns",
            "com.hasan.hasan_vpn/tunnel",
            "com.hasan.hasan_vpn/warpmasque",
        )) {
            MethodChannel(flutterEngine.dartExecutor.binaryMessenger, name)
                .setMethodCallHandler { call, result ->
                    when (call.method) {
                        "status" -> result.success(
                            mapOf("running" to false, "ok" to false)
                        )
                        else -> result.success(false)
                    }
                }
        }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, logsChannel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getLogs" -> result.success(SafeLog.dump())
                    "clearLogs" -> { SafeLog.clear(); result.success(true) }
                    else -> result.notImplemented()
                }
            }

        widgetChannelRef = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, widgetChannel)
        widgetChannelRef!!.setMethodCallHandler { call, result ->
            when (call.method) {
                "updateWidgets" -> { refreshAllWidgets(); result.success(true) }
                "updateAllWidgets" -> { QuickConnectWidget1x1.updateAllWidgets(this@MainActivity); result.success(true) }
                "getInitialIntent" -> result.success(intentToMap(intent))
                "getLaunchExtras" -> result.success(intentToMap(intent))
                "moveTaskToBack" -> { moveTaskToBack(true); result.success(true) }
                else -> result.notImplemented()
            }
        }

    }

    private var autoMoveToBackOnWidget = false

    override fun onResume() {
        super.onResume()
        // اگر اپ از ویجت ۱×۱ بیدار شده، بدون نمایش UI به پس‌زمینه برو
        if (intent?.getBooleanExtra("widget_bg_connect", false) == true) {
            intent.removeExtra("widget_bg_connect")
            autoMoveToBackOnWidget = true
            // یک تأخیر کوچک تا Flutter engine کامل initialize شود
            window?.decorView?.postDelayed({
                if (autoMoveToBackOnWidget) {
                    moveTaskToBack(true)
                    autoMoveToBackOnWidget = false
                }
            }, 150)
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        val map = intentToMap(intent)
        if (map.isNotEmpty()) {
            try {
                widgetChannelRef?.invokeMethod("onWidgetIntent", map)
            } catch (_: Exception) { }
        }
    }

    private fun intentToMap(intent: Intent?): Map<String, Any?> {
        if (intent == null) return emptyMap()

        val needsServer = intent.getBooleanExtra("widget_needs_server", false)
        val widgetId = intent.getIntExtra("widget_id", -1)
        val action = intent.getStringExtra("widget_action")

        // اگر درخواست انتخاب سرور برای ویجت آمده، بدون widget_action هم برمی‌گردانیم
        if (needsServer && widgetId > 0) {
            val map = mutableMapOf<String, Any?>(
                "widget_needs_server" to true,
                "widget_id" to widgetId,
            )
            intent.removeExtra("widget_needs_server")
            intent.removeExtra("widget_id")
            return map
        }

        if (action == null) return emptyMap()

        val map = mutableMapOf<String, Any?>(
            "widget_action" to action,
            "widget_id" to widgetId,
            "widget_type" to intent.getStringExtra("widget_type"),
            "widget_payload" to intent.getStringExtra("widget_payload"),
            "widget_title" to intent.getStringExtra("widget_title"),
            "widget_slot" to intent.getIntExtra("widget_slot", 0),
            "widget_auto_connect" to intent.getBooleanExtra("widget_auto_connect", false),
            "widget_bg_connect" to intent.getBooleanExtra("widget_bg_connect", false),
        )
        intent.removeExtra("widget_action")
        return map
    }

    private fun refreshAllWidgets() {
        val mgr = AppWidgetManager.getInstance(this)
        try {
            val w1 = ComponentName(this, QuickConnectWidget1x1::class.java)
            for (id in mgr.getAppWidgetIds(w1)) QuickConnectWidget1x1.updateAppWidget(this, mgr, id)
        } catch (_: Exception) { }
    }

    private fun requestNotificationPermission() {
        if (Build.VERSION.SDK_INT >= 33) {
            if (checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS)
                != PackageManager.PERMISSION_GRANTED
            ) {
                requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), 7001)
            }
        }
    }

    /**
     * 0001 — true if XrayVPNService is running in this app process.
     * ActivityManager sees same-app services by full class name even when
     * the class lives in the flutter_vless plugin module.
     * Fallback: ConnectivityManager TRANSPORT_VPN.
     */
    private fun isXrayVpnServiceRunning(): Boolean {
        try {
            @Suppress("DEPRECATION")
            val am = getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
            @Suppress("DEPRECATION")
            val running = am.getRunningServices(Integer.MAX_VALUE)
            val target = "com.github.tfox.flutter_vless.xray.service.XrayVPNService"
            if (running.any { it.service.className == target }) return true
        } catch (_: Exception) {}

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
}
