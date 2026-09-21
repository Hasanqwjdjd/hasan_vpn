package com.hasan.hasan_vpn

import android.Manifest
import android.content.pm.PackageManager
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * پل Flutter ↔ بخش بومی:
 *  - com.hasan.hasan_vpn/aether  → Aether/WARP
 *  - com.hasan.hasan_vpn/psiphon → Psiphon
 *  - com.hasan.hasan_vpn/device  → ABI، مجوز نوتیفیکیشن، تله‌متری
 */
class MainActivity : FlutterActivity() {

    private val aetherChannel = "com.hasan.hasan_vpn/aether"
    private val psiphonChannel = "com.hasan.hasan_vpn/psiphon"
    private val deviceChannel = "com.hasan.hasan_vpn/device"
    private val torChannel = "com.hasan.hasan_vpn/tor"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // لاگ بومی فقط در بیلد debuggable روشن است.
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
                            result.success(
                                AetherService.start(applicationContext, env, remark),
                            )
                        }
                    }
                    "status" -> result.success(AetherService.status())
                    "stop" -> {
                        AetherService.stop(applicationContext)
                        result.success(true)
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
                            val map = PsiphonService.start(
                                applicationContext,
                                config,
                                timeout.toLong(),
                            )
                            runOnUiThread { result.success(map) }
                        }.start()
                    }
                    "stop" -> {
                        PsiphonService.stop(applicationContext)
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, deviceChannel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "abis" -> result.success(Build.SUPPORTED_ABIS.toList())
                    "notifPermission" -> {
                        requestNotificationPermission()
                        result.success(true)
                    }
                    "telemetryShow" -> {
                        val title = call.argument<String>("title") ?: "Hasan VPN"
                        val text = call.argument<String>("text") ?: ""
                        TelemetryNotifier.show(applicationContext, title, text)
                        result.success(true)
                    }
                    "telemetryHide" -> {
                        TelemetryNotifier.hide(applicationContext)
                        result.success(true)
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
                        Thread {
                            val map = TorService.start(
                                applicationContext,
                                bridgeType,
                                customBridges,
                            )
                            runOnUiThread { result.success(map) }
                        }.start()
                    }
                    "stop" -> {
                        TorService.stop(applicationContext)
                        result.success(true)
                    }
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
}
