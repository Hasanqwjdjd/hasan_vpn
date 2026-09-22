package com.hasan.hasan_vpn

import android.app.Activity
import android.content.Intent
import android.os.Bundle
import android.os.Handler
import android.os.Looper

/**
 * Activity شفاف برای ویجت ۱×۱:
 * extras را در SharedPreferences می‌نویسد، سرویس/اپ را برای اتصال بیدار می‌کند
 * و فوراً finish می‌شود تا کاربر UI کامل نبیند (رفتار شبیه v2rayNG).
 *
 * Manifest:
 * <activity
 *   android:name=".WidgetBgConnectActivity"
 *   android:theme="@android:style/Theme.Translucent.NoTitleBar"
 *   android:excludeFromRecents="true"
 *   android:taskAffinity=""
 *   android:exported="true" />
 */
class WidgetBgConnectActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val type = intent.getStringExtra("widget_type") ?: "server"
        val payload = intent.getStringExtra("widget_payload") ?: ""
        val title = intent.getStringExtra("widget_title") ?: ""

        val prefs = getSharedPreferences("FlutterSharedPreferences", MODE_PRIVATE)
        prefs.edit()
            .putString("flutter.widget_pending_action", "bg_connect")
            .putString("flutter.widget_pending_type", type)
            .putString("flutter.widget_pending_payload", payload)
            .putString("flutter.widget_pending_title", title)
            .putBoolean("flutter.widget_pending_auto", true)
            .apply()

        // بیدار کردن MainActivity در پس‌زمینه (بدون ماندن روی UI)
        try {
            val launch = packageManager.getLaunchIntentForPackage(packageName)
            if (launch != null) {
                launch.putExtra("widget_action", "bg_connect")
                launch.putExtra("widget_type", type)
                launch.putExtra("widget_payload", payload)
                launch.putExtra("widget_title", title)
                launch.putExtra("widget_auto_connect", true)
                launch.putExtra("widget_bg_connect", true)
                launch.addFlags(
                    Intent.FLAG_ACTIVITY_NEW_TASK or
                        Intent.FLAG_ACTIVITY_CLEAR_TOP or
                        Intent.FLAG_ACTIVITY_SINGLE_TOP or
                        Intent.FLAG_ACTIVITY_NO_ANIMATION,
                )
                startActivity(launch)
            }
        } catch (_: Exception) {
        }

        Handler(Looper.getMainLooper()).postDelayed({ finish() }, 10)
    }

    override fun onResume() {
        super.onResume()
        // وقتی از ویجت بیدار می‌شویم، این Activity باید فوراً ناپدید شود
        val launch = packageManager.getLaunchIntentForPackage(packageName)
        if (launch == null) {
            finish()
            overridePendingTransition(0, 0)
            return
        }
    }

    override fun finish() {
        super.finish()
        overridePendingTransition(0, 0)
    }
}
