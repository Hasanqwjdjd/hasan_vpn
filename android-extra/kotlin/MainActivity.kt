package com.hasan.hasan_vpn

import android.Manifest
import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.content.Intent
import android.content.pm.PackageManager
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
    private val widgetsChannel = "com.hasan.hasan_vpn/widgets"
    private val logsChannel = "com.hasan.hasan_vpn/logs"

    private var widgetChannelRef: MethodChannel? = null
    private var widgetsChannelRef: MethodChannel? = null

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
                "getInitialIntent" -> result.success(intentToMap(intent))
                "getLaunchExtras" -> result.success(intentToMap(intent))
                "moveTaskToBack" -> { moveTaskToBack(true); result.success(true) }
                else -> result.notImplemented()
            }
        }

        widgetsChannelRef = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, widgetsChannel)
        widgetsChannelRef!!.setMethodCallHandler { call, result ->
            when (call.method) {
                "updateWidgets" -> { refreshAllWidgets(); result.success(true) }
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

    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        val map = intentToMap(intent)
        if (map.isNotEmpty()) {
            try {
                widgetChannelRef?.invokeMethod("onWidgetIntent", map)
                widgetsChannelRef?.invokeMethod("onWidgetIntent", map)
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
            val w2 = ComponentName(this, QuickConnectWidget::class.java)
            for (id in mgr.getAppWidgetIds(w2)) QuickConnectWidget.updateAppWidget(this, mgr, id)
        } catch (_: Exception) { }
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
}
