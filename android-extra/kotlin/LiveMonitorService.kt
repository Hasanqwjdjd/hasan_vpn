package com.hasan.hasan_vpn

import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.BatteryManager
import android.net.TrafficStats
import java.io.File

/**
 * سرویس مانیتور زنده — CPU، RAM، باتری، سرعت شبکه.
 * همه داده‌ها از /proc و BatteryManager خوانده می‌شوند.
 * این یک object ساده است (نه سرویس) چون از روش‌های خود Android
 * (TrafficStats, BatteryManager) استفاده می‌کند که نیاز به permission ندارند.
 */
object LiveMonitorService {

    private var lastCpuIdle: Long = 0
    private var lastCpuTotal: Long = 0

    fun snapshot(context: Context): Map<String, Any?> {
        val result = mutableMapOf<String, Any?>()

        // --- CPU ---
        // نمونهٔ اول همیشه ۰ بود؛ برای اندازه‌گیری واقعی دو خواندن با فاصله لازم است.
        try {
            var idleTotal = readCpuStat()
            var idle = idleTotal.first
            var total = idleTotal.second
            if (lastCpuTotal <= 0L || total <= lastCpuTotal) {
                lastCpuIdle = idle
                lastCpuTotal = total
                try { Thread.sleep(80) } catch (_: InterruptedException) {}
                idleTotal = readCpuStat()
                idle = idleTotal.first
                total = idleTotal.second
            }
            if (lastCpuTotal > 0L && total > lastCpuTotal) {
                val totalDelta = total - lastCpuTotal
                val idleDelta = idle - lastCpuIdle
                val usage = if (totalDelta > 0) {
                    ((totalDelta - idleDelta) * 100.0 / totalDelta)
                } else 0.0
                result["cpu"] = usage.coerceIn(0.0, 100.0)
            } else {
                result["cpu"] = 0.0
            }
            lastCpuIdle = idle
            lastCpuTotal = total
        } catch (_: Throwable) {
            result["cpu"] = 0.0
        }

        // --- RAM ---
        try {
            val (usedMb, totalMb) = readMemInfo()
            result["memUsedMb"] = usedMb
            result["memTotalMb"] = totalMb
            result["memPercent"] = if (totalMb > 0) {
                usedMb * 100.0 / totalMb
            } else 0.0
        } catch (_: Throwable) {
            result["memUsedMb"] = 0
            result["memTotalMb"] = 0
            result["memPercent"] = 0.0
        }

        // --- Battery ---
        try {
            val bm = context.getSystemService(Context.BATTERY_SERVICE) as? BatteryManager
            if (bm != null) {
                val level = bm.getIntProperty(BatteryManager.BATTERY_PROPERTY_CAPACITY)
                result["battery"] = if (level in 0..100) level else 0
            } else {
                result["battery"] = 0
            }
        } catch (_: Throwable) {
            result["battery"] = 0
        }

        // --- Temperature (از /sys/class/thermal) ---
        try {
            val temp = readBatteryTemperature(context)
            result["temp"] = temp
        } catch (_: Throwable) {
            result["temp"] = 0.0
        }

        // --- Network traffic ---
        // TrafficStats گاهی UNSUPPORTED (-1) برمی‌گرداند؛ در آن صورت ۰ می‌گذاریم.
        try {
            var rx = TrafficStats.getTotalRxBytes()
            var tx = TrafficStats.getTotalTxBytes()
            if (rx < 0L) rx = 0L
            if (tx < 0L) tx = 0L
            // به صورت Number بفرست تا Dart هم int و هم long را درست بخواند
            result["rxBytes"] = rx
            result["txBytes"] = tx
        } catch (_: Throwable) {
            result["rxBytes"] = 0L
            result["txBytes"] = 0L
        }

        return result
    }

    // --------------------------------------------------------------

    /** خواندن /proc/stat → (idle, total) بر حسب jiffies. */
    private fun readCpuStat(): Pair<Long, Long> {
        val line = File("/proc/stat").useLines { lines ->
            lines.firstOrNull { it.startsWith("cpu ") }
        } ?: return 0L to 0L

        val parts = line.trim().split(Regex("\\s+"))
        // parts[0] = "cpu"
        val nums = parts.drop(1).mapNotNull { it.toLongOrNull() }
        if (nums.size < 5) return 0L to 0L

        val idle = nums[3] + nums[4]  // idle + iowait
        val total = nums.sum()
        return idle to total
    }

    /** خواندن /proc/meminfo → (usedMb, totalMb). */
    private fun readMemInfo(): Pair<Long, Long> {
        var totalKb = 0L
        var freeKb = 0L
        var availKb = 0L
        File("/proc/meminfo").forEachLine { line ->
            when {
                line.startsWith("MemTotal:") -> {
                    totalKb = line.filter { it.isDigit() }.toLongOrNull() ?: 0L
                }
                line.startsWith("MemFree:") -> {
                    freeKb = line.filter { it.isDigit() }.toLongOrNull() ?: 0L
                }
                line.startsWith("MemAvailable:") -> {
                    availKb = line.filter { it.isDigit() }.toLongOrNull() ?: 0L
                }
            }
        }
        val usedKb = if (availKb > 0) (totalKb - availKb) else (totalKb - freeKb)
        return (usedKb / 1024) to (totalKb / 1024)
    }

    /**
     * حرارت باتری: اول از sticky Intent (دقیق‌ترین و بدون permission)،
     * اگر نشد از thermal_zone ها میانگین بگیر.
     */
    private fun readBatteryTemperature(context: Context): Double {
        // روش استاندارد Android: EXTRA_TEMPERATURE در ACTION_BATTERY_CHANGED
        // واحد آن tenths of a degree Celsius است (مثلاً 320 = 32.0°C)
        try {
            val intent = context.registerReceiver(
                null,
                IntentFilter(Intent.ACTION_BATTERY_CHANGED)
            )
            if (intent != null) {
                val tenths = intent.getIntExtra(BatteryManager.EXTRA_TEMPERATURE, -1)
                if (tenths > 0) {
                    return tenths / 10.0
                }
            }
        } catch (_: Throwable) {}

        // Fallback: میانگین چند thermal_zone
        try {
            val base = File("/sys/class/thermal")
            if (!base.exists()) return 0.0
            val zones = base.listFiles { f -> f.name.startsWith("thermal_zone") } ?: return 0.0
            var sum = 0.0
            var count = 0
            for (z in zones.take(8)) {
                try {
                    val tempFile = File(z, "temp")
                    if (tempFile.exists()) {
                        val raw = tempFile.readText().trim().toLongOrNull() ?: continue
                        // بیشتر دستگاه‌ها milli-Celsius می‌دهند
                        val celsius = if (raw > 1000) raw / 1000.0 else raw.toDouble()
                        // فیلتر مقادیر غیرمنطقی
                        if (celsius in 10.0..80.0) {
                            sum += celsius
                            count++
                        }
                    }
                } catch (_: Throwable) {}
            }
            return if (count > 0) sum / count else 0.0
        } catch (_: Throwable) {
            return 0.0
        }
    }
}

