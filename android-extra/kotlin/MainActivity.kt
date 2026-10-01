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
import android.os.Bundle
import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    private val deviceChannel = "com.hasan.hasan_vpn/device"
    private val aetherChannel = "com.hasan.hasan_vpn/aether"
    private val psiphonChannel = "com.hasan.hasan_vpn/psiphon"
    private val torChannel = "com.hasan.hasan_vpn/tor"
    private val monitorChannel = "com.hasan.hasan_vpn/monitor"
    private val widgetChannel = "com.hasan.hasan_vpn/widget"
    private val logsChannel = "com.hasan.hasan_vpn/logs"
    private val desyncChannelName = "com.hasan.hasan_vpn/desync"
    private val gameBoosterChannel = "com.hasan.hasan_vpn/game_booster"
    private val sanctionChannel = "com.hasan.hasan_vpn/sanction"

    private var widgetChannelRef: MethodChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, deviceChannel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getBatteryOptStatus" -> result.success(mapOf("ignored" to false))
                    "requestBatteryOpt" -> result.success(true)
                    "openBatterySettings" -> result.success(true)
                    "getInstalledApps" -> result.success(emptyList<Map<String, Any>>())
                    "startHev" -> {
                        val config = call.argument<String>("config") ?: ""
                        Thread {
                            val ok = try {
                                HevLauncher.start(applicationContext, config)
                            } catch (e: Exception) { false }
                            runOnUiThread { result.success(ok) }
                        }.start()
                    }
                    "stopHev" -> {
                        HevLauncher.stop()
                        result.success(true)
                    }
                    "isXrayVpnServiceRunning" -> {
                        result.success(isXrayVpnServiceRunning())
                    }
                    else -> result.notImplemented()
                }
            }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, torChannel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "start" -> {
                        val bridgeType = call.argument<String>("bridgeType") ?: "vanilla"
                        val customBridges = call.argument<List<String>>("customBridges")
                        val sni = call.argument<String>("sni")
                        Thread {
                            val map = TorService.startWithContext(
                                applicationContext, bridgeType, customBridges, sni
                            )
                            runOnUiThread { result.success(map) }
                        }.start()
                    }
                    "status" -> result.success(TorService.status())
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

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, aetherChannel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    else -> result.notImplemented()
                }
            }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, psiphonChannel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    else -> result.notImplemented()
                }
            }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, monitorChannel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
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

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, gameBoosterChannel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "raceDns" -> {
                        val hostname = call.argument<String>("hostname") ?: "pubgmobile.com"
                        Thread {
                            val map = com.hasan.hasan_vpn.game.GameBoosterManager.raceDns(hostname)
                            runOnUiThread { result.success(map) }
                        }.start()
                    }
                    "listGames" -> {
                        Thread {
                            val map = com.hasan.hasan_vpn.game.GameBoosterManager.listGames(applicationContext)
                            runOnUiThread { result.success(map) }
                        }.start()
                    }
                    "pingGame" -> {
                        val id = call.argument<String>("id") ?: ""
                        val region = call.argument<String>("region")
                        Thread {
                            val map = com.hasan.hasan_vpn.game.GameBoosterManager.pingGame(id, region)
                            runOnUiThread { result.success(map) }
                        }.start()
                    }
                    "startDnsBoost" -> {
                        val resolver = call.argument<String>("resolver") ?: ""
                        val secondary = call.argument<String>("secondary")
                        Thread {
                            val map = com.hasan.hasan_vpn.game.GameBoosterManager.startDnsBoost(
                                applicationContext, resolver, secondary
                            )
                            runOnUiThread { result.success(map) }
                        }.start()
                    }
                    "stopDnsBoost" -> {
                        Thread {
                            val map = com.hasan.hasan_vpn.game.GameBoosterManager.stopDnsBoost(applicationContext)
                            runOnUiThread { result.success(map) }
                        }.start()
                    }
                    "status" -> {
                        result.success(com.hasan.hasan_vpn.game.GameBoosterManager.status())
                    }
                    else -> result.notImplemented()
                }
            }

        
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, sanctionChannel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "status" -> result.success(AntiSanctionManager.status(applicationContext))
                    "setFilterBypass" -> {
                        val enabled = call.argument<Boolean>("enabled") ?: false
                        result.success(AntiSanctionManager.setFilterBypass(applicationContext, enabled))
                    }
                    "setGeminiFix" -> {
                        val enabled = call.argument<Boolean>("enabled") ?: false
                        result.success(AntiSanctionManager.setGeminiFix(applicationContext, enabled))
                    }
                    "setGeminiUsExit" -> {
                        val enabled = call.argument<Boolean>("enabled") ?: false
                        result.success(AntiSanctionManager.setGeminiUsExit(applicationContext, enabled))
                    }
                    else -> result.notImplemented()
                }
            }

        widgetChannelRef = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, widgetChannel)
        widgetChannelRef?.setMethodCallHandler { call, result ->
            when (call.method) {
                else -> result.notImplemented()
            }
        }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, desyncChannelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    else -> result.notImplemented()
                }
            }
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
