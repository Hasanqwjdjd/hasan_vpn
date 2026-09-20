package com.hasan.hasan_vpn

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * پل بین Flutter و هسته‌ی بومی Aether.
 *
 * کانال: com.hasan.hasan_vpn/aether
 *   - info()            -> Map  : آیا باینری برای این CPU هست؟ آیا هویت WARP ساخته شده؟
 *   - start(env,remark) -> Bool : Aether را با متغیرهای محیطی داده‌شده اجرا می‌کند
 *   - status()          -> Map  : running / exited / exitCode / lastLine / error / log
 *   - stop()            -> Bool : پردازه و سرویس را متوقف می‌کند
 *
 * مجوز VPN و خود تونل را افزونه‌ی flutter_vless مدیریت می‌کند؛ این‌جا فقط
 * پراکسی SOCKS محلی Aether اجرا می‌شود.
 */
class MainActivity : FlutterActivity() {

    private val channelName = "com.hasan.hasan_vpn/aether"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
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
    }
}
