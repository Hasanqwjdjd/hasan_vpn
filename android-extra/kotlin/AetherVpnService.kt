# مسیر مقصد در ریپو: android-extra/kotlin/AetherVpnService.kt  --  NEW, copy into android/app/src/main/kotlin/com/hasan/hasan_vpn/
# ------------------------------------------------------------
package com.hasan.hasan_vpn

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.net.ProxyInfo
import android.net.VpnService
import android.os.Build
import android.os.ParcelFileDescriptor
import android.util.Log
import java.io.File
import java.net.InetSocketAddress
import java.net.Socket

/**
 * سرویس VPN که هسته‌ی Aether (github.com/CluvexStudio/Aether) را اجرا می‌کند.
 *
 * === این فایل چه کاری *واقعاً* انجام می‌دهد ===
 * 1) باینری بومی aether را (که باید در jniLibs هر ABI با نام libaether.so
 *    قرار داده باشید - توضیح در android-extra/README.md) با ProcessBuilder
 *    اجرا می‌کند و منتظر می‌ماند تا پراکسی محلی SOCKS5 (پیش‌فرض 127.0.0.1:1819)
 *    و HTTP CONNECT (پیش‌فرض 127.0.0.1:1820) آن بالا بیاید.
 * 2) یک VpnService واقعی برپا می‌کند (برای گرفتن آیکن VPN سیستم و ثبت‌شدن
 *    به‌عنوان شبکه‌ی فعال) و آدرس HTTP Proxy سیستم را با setHttpProxy روی
 *    پراکسی محلی Aether تنظیم می‌کند. این باعث می‌شود مرورگرها و اکثر
 *    اپ‌هایی که از تنظیمات پراکسی سیستم پیروی می‌کنند از تونل Aether رد شوند.
 *
 * === محدودیت شناخته‌شده ===
 * برای تونل‌کردن *کامل و شفاف* همه‌ی ترافیک دستگاه (هر اپ، هر پروتکل،
 * بدون نیاز به آگاهی از پراکسی) باید یک لایه‌ی tun2socks هم اضافه شود که
 * بسته‌های خام IP را از فایل‌دیسکریپتور TUN بخواند و به SOCKS5 روی پورت 1819
 * فوروارد کند - دقیقاً کاری که اپ‌هایی مثل PattNG با یک باینری/کتابخانه‌ی
 * جدا (مثلاً hev-socks5-tunnel) انجام می‌دهند. آن بخش را نمی‌شد بدون خودِ
 * باینری‌های واقعی و کامپایل/تست در این محیط پیاده کرد، برای همین اینجا با
 * TODO مشخص شده تا خودتان (یا هر توسعه‌دهنده) یک باینری tun2socks اضافه و
 * در متد runTun2Socks() صدا بزند. تا آن زمان، ترافیک HTTP/HTTPS اپ‌هایی که
 * پراکسی سیستم را رعایت می‌کنند از Aether رد می‌شود؛ بقیه‌ی ترافیک از تونل
 * رد نمی‌شود (نه اینکه قطع شود - چون آدرس 0.0.0.0/0 را روت نکرده‌ایم).
 */
class AetherVpnService : VpnService() {

    companion object {
        private const val TAG = "AetherVpnService"
        private const val CHANNEL_ID = "aether_vpn_channel"
        private const val NOTIF_ID = 4242

        const val SOCKS_PORT = 1819
        const val HTTP_PORT = 1820

        @Volatile private var vpnInterface: ParcelFileDescriptor? = null
        @Volatile private var aetherProcess: Process? = null
        @Volatile private var connected = false
        @Volatile private var activeProtocol = "auto"

        fun start(
            context: Context,
            scanMode: String,
            protocolMode: String,
            upstreamProxy: String,
            remark: String,
        ): Boolean {
            return try {
                val intent = Intent(context, AetherVpnService::class.java).apply {
                    putExtra("scanMode", scanMode)
                    putExtra("protocolMode", protocolMode)
                    putExtra("upstreamProxy", upstreamProxy)
                    putExtra("remark", remark)
                }
                context.startService(intent)
                true
            } catch (e: Exception) {
                Log.e(TAG, "start() failed", e)
                false
            }
        }

        fun stop(context: Context) {
            context.stopService(Intent(context, AetherVpnService::class.java))
        }

        fun statusMap(): Map<String, Any?> = mapOf(
            "connected" to connected,
            "protocol" to activeProtocol,
            "socksPort" to SOCKS_PORT,
            "httpPort" to HTTP_PORT,
        )
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val scanMode = intent?.getStringExtra("scanMode") ?: "balanced"
        val protocolMode = intent?.getStringExtra("protocolMode") ?: "auto"
        val upstreamProxy = intent?.getStringExtra("upstreamProxy") ?: ""
        val remark = intent?.getStringExtra("remark") ?: "Aether"
        activeProtocol = protocolMode

        startForeground(NOTIF_ID, buildNotification(remark))

        Thread {
            try {
                runAetherCore(scanMode, protocolMode, upstreamProxy)
                val socksUp = waitForPort("127.0.0.1", SOCKS_PORT, timeoutMs = 20_000)
                if (!socksUp) {
                    Log.e(TAG, "Aether SOCKS5 proxy did not come up in time")
                    connected = false
                    stopSelf()
                    return@Thread
                }
                establishVpn()
                connected = true
            } catch (e: Exception) {
                Log.e(TAG, "Failed to start Aether tunnel", e)
                connected = false
                stopSelf()
            }
        }.start()

        return START_STICKY
    }

    /** اجرای باینری بومی aether (libaether.so در nativeLibraryDir). */
    private fun runAetherCore(scanMode: String, protocolMode: String, upstreamProxy: String) {
        val binaryPath = File(applicationInfo.nativeLibraryDir, "libaether.so")
        if (!binaryPath.exists()) {
            throw IllegalStateException(
                "libaether.so پیدا نشد در ${binaryPath.absolutePath} - " +
                "باینری Aether را طبق android-extra/README.md در jniLibs قرار دهید."
            )
        }

        // lyrebird (پلاگابل ترنسپورت اختیاری برای حالت Tor-bridge) اگر موجود
        // باشد، طبق مستندات Aether باید در یک پوشه‌ی pt/ کنار باینری باشد.
        // چون nativeLibraryDir صاف است (بدون زیرپوشه)، آن را هر بار به
        // filesDir/pt/lyrebird کپی می‌کنیم و مسیرش را با AETHER_TOR_PT_DIR می‌دهیم.
        val lyrebirdSrc = File(applicationInfo.nativeLibraryDir, "liblyrebird.so")
        var torPtDir: String? = null
        if (lyrebirdSrc.exists()) {
            try {
                val ptDir = File(filesDir, "pt").apply { mkdirs() }
                val lyrebirdDst = File(ptDir, "lyrebird")
                lyrebirdSrc.copyTo(lyrebirdDst, overwrite = true)
                lyrebirdDst.setExecutable(true, false)
                torPtDir = ptDir.absolutePath
            } catch (e: Exception) {
                Log.w(TAG, "Could not stage lyrebird pluggable transport", e)
            }
        }

        val env = mutableMapOf(
            "AETHER_SOCKS" to SOCKS_PORT.toString(),
            "AETHER_HTTP" to HTTP_PORT.toString(),
            "AETHER_SCAN" to scanMode,        // fast | balanced | full
            "AETHER_PROTOCOL" to protocolMode, // auto | masque | wireguard | gool
        )
        if (upstreamProxy.isNotEmpty()) {
            env["AETHER_UPSTREAM_PROXY"] = upstreamProxy
        }
        // اختیاری: فقط وقتی مفید است که خودتان با فلگ --tor حالت Tor-bridge را
        // هم فعال کنید؛ صرفاً وجود lyrebird چیزی را به‌تنهایی روشن نمی‌کند.
        if (torPtDir != null) {
            env["AETHER_TOR_PT_DIR"] = torPtDir
        }

        val pb = ProcessBuilder(binaryPath.absolutePath)
        pb.environment().putAll(env)
        pb.redirectErrorStream(true)
        pb.directory(filesDir)

        val proc = pb.start()
        aetherProcess = proc

        // لاگ خروجی aether برای دیباگ (logcat).
        Thread {
            try {
                proc.inputStream.bufferedReader().forEachLine { line ->
                    Log.d(TAG, "[aether] $line")
                }
            } catch (_: Exception) {
            }
        }.start()
    }

    private fun waitForPort(host: String, port: Int, timeoutMs: Long): Boolean {
        val deadline = System.currentTimeMillis() + timeoutMs
        while (System.currentTimeMillis() < deadline) {
            try {
                Socket().use { s ->
                    s.connect(InetSocketAddress(host, port), 500)
                    return true
                }
            } catch (_: Exception) {
                Thread.sleep(300)
            }
        }
        return false
    }

    /**
     * یک رابط TUN حداقلی می‌سازد تا برنامه به‌عنوان VPN فعال سیستم ثبت شود،
     * و پراکسی HTTP سیستم را به پراکسی محلی Aether وصل می‌کند.
     *
     * توجه: چون routeهای 0.0.0.0/0 اضافه نکرده‌ایم، این TUN مسئول عبور همه‌ی
     * بسته‌ها نیست (چون آن بخش نیاز به tun2socks واقعی دارد - بالا توضیح
     * داده شد). این یعنی آیکن VPN فعال می‌شود و پراکسی HTTP سیستم اعمال
     * می‌شود، اما تونل کامل شفاف نیست تا وقتی tun2socks اضافه شود.
     */
    private fun establishVpn() {
        val builder = Builder()
            .setSession("Aether")
            .addAddress("10.10.10.2", 32)
            .addDnsServer("1.1.1.1")
            .addDnsServer("1.0.0.1")

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            builder.setHttpProxy(ProxyInfo.buildDirectProxy("127.0.0.1", HTTP_PORT))
        }

        // TODO: وقتی یک باینری/کتابخانه‌ی tun2socks اضافه کردید:
        //   1) builder.addRoute("0.0.0.0", 0) را اضافه کنید تا همه‌ی ترافیک به TUN بیاید
        //   2) vpnInterface را establish کنید و fd آن را به tun2socks بدهید که آن را
        //      به 127.0.0.1:SOCKS_PORT فوروارد کند (مثلاً hev-socks5-tunnel با JNI)
        //   3) اینجا آن پردازه/تابع JNI را صدا بزنید، مثل: runTun2Socks(fd, SOCKS_PORT)

        vpnInterface = builder.establish()
    }

    private fun buildNotification(remark: String): Notification {
        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID, "Aether VPN", NotificationManager.IMPORTANCE_LOW
            )
            nm.createNotificationChannel(channel)
        }

        val openAppIntent = packageManager.getLaunchIntentForPackage(packageName)
        val pendingIntent = PendingIntent.getActivity(
            this, 0, openAppIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        return Notification.Builder(this, CHANNEL_ID)
            .setContentTitle("Aether")
            .setContentText("در حال اتصال با $remark")
            .setSmallIcon(applicationInfo.icon)
            .setContentIntent(pendingIntent)
            .setOngoing(true)
            .build()
    }

    private fun teardown() {
        try {
            aetherProcess?.destroy()
        } catch (_: Exception) {
        }
        aetherProcess = null

        try {
            vpnInterface?.close()
        } catch (_: Exception) {
        }
        vpnInterface = null

        connected = false
    }

    override fun onDestroy() {
        teardown()
        super.onDestroy()
    }

    override fun onRevoke() {
        teardown()
        stopSelf()
        super.onRevoke()
    }
}
