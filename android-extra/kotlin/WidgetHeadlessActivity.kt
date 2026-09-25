package com.hasan.hasan_vpn

import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Activity کاملاً نامرئی (Theme.Translucent.NoDisplay) که یک FlutterEngine
 * *واقعی* — با ActivityPluginBinding متصل — برای اتصال/قطع پس‌زمینه‌ی
 * ویجت ۱×۱ میزبانی می‌کند. هیچ پنجره‌ای هرگز رندر نمی‌شود.
 *
 * چرا این روش لازم بود (نه یک FlutterEngine کاملاً headless در Service):
 * پلاگین flutter_vless برای requestPermission()/VpnService به یک Activity
 * متصل (ActivityAware.onAttachedToActivity) نیاز دارد. یک FlutterEngine که
 * مستقیماً داخل Service ساخته می‌شود (بدون هیچ Activity) هرگز این نیاز را
 * برآورده نمی‌کند و connectFromWidget با ok=false شکست می‌خورد.
 *
 * FlutterActivity به‌صورت پیش‌فرض:
 *   ۱) GeneratedPluginRegistrant.registerWith(engine) را خودش صدا می‌زند
 *   ۲) engine.activityControlSurface.attachToActivity(...) را خودش انجام می‌دهد
 * پس با override کردن فقط نقطه‌ی ورود Dart، از کل زیرساخت رسمی Flutter
 * برای Activity attachment استفاده می‌کنیم — بدون کدنویسی دستی و شکننده.
 *
 * چون تم Theme.Translucent.NoDisplay است، این پنجره هرگز روی صفحه ترسیم
 * نمی‌شود (بدون فلش اپ)؛ تنها در حالت نادر (اولین بار / مجوز VPN لغوشده)
 * که سیستم دیالوگ مجوز VPN را نشان می‌دهد، آن دیالوگ سیستمی دیده می‌شود —
 * که کاملاً طبیعی و غیرقابل‌اجتناب است (دقیقاً مثل v2rayNG).
 *
 * Manifest (در build-apk.yml):
 * <activity android:name=".WidgetHeadlessActivity"
 *   android:theme="@android:style/Theme.Translucent.NoDisplay"
 *   android:excludeFromRecents="true"
 *   android:taskAffinity=""
 *   android:noHistory="true"
 *   android:exported="false" />
 */
class WidgetHeadlessActivity : FlutterActivity() {

    private var channel: MethodChannel? = null
    private var finished = false

    /// نقطه‌ی ورود سفارشی Dart — بدون نمایش هیچ صفحه‌ای از اپ اصلی.
    override fun getDartEntrypointFunctionName(): String = "widgetHeadlessMain"

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        try {
            window?.setBackgroundDrawableResource(android.R.color.transparent)
        } catch (_: Exception) {
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        // این هم پلاگین‌ها را رجیستر می‌کند و هم زیرساخت لازم برای
        // اتصال Activity را برپا می‌کند — چیزی دستی لازم نیست.
        super.configureFlutterEngine(flutterEngine)

        // ثبت کانال Tor (چون MainActivity اینجا نیست)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.hasan.hasan_vpn/tor")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "status" -> result.success(TorService.status())
                    "start" -> {
                        val bt = call.argument<String>("bridgeType") ?: "vanilla"
                        val cb = call.argument<List<String>>("customBridges")
                        val sni = call.argument<String>("sni")
                        Thread {
                            val map = TorService.start(applicationContext, bt, cb, sni)
                            runOnUiThread { result.success(map) }
                        }.start()
                    }
                    "stop" -> { TorService.stopWithContext(applicationContext); result.success(true) }
                    else -> result.notImplemented()
                }
            }

        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
        channel!!.setMethodCallHandler { call, result ->
            when (call.method) {
                // Dart در ابتدای widgetHeadlessMain این را صدا می‌زند تا
                // بفهمد باید وصل شود یا قطع، و به کدام سرور.
                "getHeadlessArgs" -> {
                    result.success(
                        mapOf(
                            "type" to (intent.getStringExtra(EXTRA_TYPE) ?: "server"),
                            "payload" to (intent.getStringExtra(EXTRA_PAYLOAD) ?: ""),
                            "title" to (intent.getStringExtra(EXTRA_TITLE) ?: ""),
                            "action" to (intent.getStringExtra(EXTRA_ACTION) ?: "connect"),
                        ),
                    )
                }
                // Dart بعد از پایان عملیات (موفق یا ناموفق) این را صدا می‌زند.
                "headlessDone" -> {
                    val ok = call.argument<Boolean>("ok") ?: false
                    val err = call.argument<String>("error")
                    result.success(true)
                    finishHeadless(ok, err)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun finishHeadless(ok: Boolean, err: String?) {
        if (finished) return
        finished = true
        try {
            pendingResult?.invoke(ok, err)
        } catch (_: Exception) {
        } finally {
            pendingResult = null
        }
        try {
            finishAndRemoveTask()
        } catch (_: Exception) {
            finish()
        }
    }

    override fun onDestroy() {
        // اگر این Activity به هر دلیلی (کرش، kill شدن توسط سیستم) بدون
        // فراخوانی headlessDone نابود شد، Service منتظر همیشگی نماند.
        if (!finished) finishHeadless(false, "activity destroyed before result")
        try {
            channel?.setMethodCallHandler(null)
        } catch (_: Exception) {
        }
        super.onDestroy()
    }

    companion object {
        const val CHANNEL = "com.hasan.hasan_vpn/widget_headless"
        const val EXTRA_TYPE = "h_type"
        const val EXTRA_PAYLOAD = "h_payload"
        const val EXTRA_TITLE = "h_title"
        const val EXTRA_ACTION = "h_action" // "connect" | "disconnect"

        /// WidgetConnectService قبل از باز کردن این Activity این callback را
        /// ست می‌کند تا از نتیجه مطلع شود (هر دو در یک پروسه اجرا می‌شوند،
        /// پس نیازی به IPC اضافه نیست).
        var pendingResult: ((ok: Boolean, error: String?) -> Unit)? = null
    }
}
