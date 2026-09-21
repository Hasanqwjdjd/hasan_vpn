package com.hasan.hasan_vpn

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * پل Flutter ↔ هسته‌های بومی:
 *  - com.hasan.hasan_vpn/aether  → Aether/WARP
 *  - com.hasan.hasan_vpn/psiphon → Psiphon واقعی
 */
class MainActivity : FlutterActivity() {

    private val aetherChannel = "com.hasan.hasan_vpn/aether"
    private val psiphonChannel = "com.hasan.hasan_vpn/psiphon"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

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
                        // start may block up to timeout — run off main if needed
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
    }
}
