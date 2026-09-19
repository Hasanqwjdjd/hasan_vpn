# مسیر مقصد در ریپو: android-extra/kotlin/MainActivity.kt  --  NEW, copy into android/app/src/main/kotlin/com/hasan/hasan_vpn/
# ------------------------------------------------------------
package com.hasan.hasan_vpn

import android.app.Activity
import android.content.Intent
import android.net.VpnService
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.Result

/**
 * این فایل را جایگزین android/app/src/main/kotlin/com/hasan/hasan_vpn/MainActivity.kt
 * (که Flutter موقع `flutter create` می‌سازد) کنید.
 *
 * کانال متد: com.hasan.hasan_vpn/aether
 *   - prepare()  -> Boolean   : اجازه‌ی VpnService را از کاربر می‌گیرد
 *   - start(args)-> Boolean   : AetherVpnService را با تنظیمات داده‌شده روشن می‌کند
 *   - stop()     -> Boolean   : سرویس را متوقف می‌کند
 *   - status()   -> Map       : وضعیت فعلی (connected, protocol, socksPort, httpPort)
 */
class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.hasan.hasan_vpn/aether"
    private val VPN_REQUEST_CODE = 24601

    private var pendingPrepareResult: Result? = null
    private var pendingStartArgs: Map<String, Any?>? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "prepare" -> {
                        val intent = VpnService.prepare(this)
                        if (intent != null) {
                            pendingPrepareResult = result
                            startActivityForResult(intent, VPN_REQUEST_CODE)
                        } else {
                            result.success(true)
                        }
                    }
                    "start" -> {
                        @Suppress("UNCHECKED_CAST")
                        val args = call.arguments as? Map<String, Any?> ?: emptyMap()
                        val started = AetherVpnService.start(
                            this,
                            scanMode = args["scanMode"] as? String ?: "balanced",
                            protocolMode = args["protocolMode"] as? String ?: "auto",
                            upstreamProxy = args["upstreamProxy"] as? String ?: "",
                            remark = args["remark"] as? String ?: "Aether",
                        )
                        result.success(started)
                    }
                    "stop" -> {
                        AetherVpnService.stop(this)
                        result.success(true)
                    }
                    "status" -> {
                        result.success(AetherVpnService.statusMap())
                    }
                    else -> result.notImplemented()
                }
            }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (requestCode == VPN_REQUEST_CODE) {
            val granted = resultCode == Activity.RESULT_OK
            pendingPrepareResult?.success(granted)
            pendingPrepareResult = null
            return
        }
        super.onActivityResult(requestCode, resultCode, data)
    }
}
