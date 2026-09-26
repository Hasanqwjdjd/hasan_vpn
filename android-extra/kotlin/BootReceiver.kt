package com.hasan.hasan_vpn

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.util.Log

/**
 * Auto-connect on BOOT_COMPLETED when the user has enabled the toggle.
 * Preference key mirrors SettingsService / SharedPreferences used from Dart:
 *   settings_auto_connect_boot_v1 = true
 *
 * The actual VPN start is delegated to the Flutter engine via a headless
 * entry-point or by starting the existing VPN service if a last-server
 * preference is present. This receiver only schedules the connect; it does
 * not require UI interaction.
 */
class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent?) {
        val action = intent?.action ?: return
        if (action != Intent.ACTION_BOOT_COMPLETED &&
            action != "android.intent.action.QUICKBOOT_POWERON") {
            return
        }
        try {
            val prefs: SharedPreferences =
                context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            // Flutter SharedPreferences prefixes keys with "flutter."
            val enabled = prefs.getBoolean("flutter.settings_auto_connect_boot_v1", false)
            if (!enabled) {
                Log.i(TAG, "auto-connect on boot disabled")
                return
            }
            Log.i(TAG, "BOOT_COMPLETED — scheduling headless auto-connect")
            // کاربر باید سرور آخر رو توی prefs داشته باشه. بدون اون نمی‌تونیم
            // به چیزی وصل شیم.
            // نام درست: settings_last_server_v1 (کلید SettingsService)
            // و نسخه‌های قدیمی‌تر که ممکنه هنوز توی prefs باشن.
            val lastId = try {
                prefs.getString("flutter.settings_last_server_v1", null)
            } catch (_: Exception) { null }
            val lastId2 = lastId ?: try {
                prefs.getString("flutter.settings_last_server_id_v1", null)
            } catch (_: Exception) { null }

            if (lastId2.isNullOrBlank()) {
                Log.i(TAG, "no last server — skipping auto-connect")
                return
            }
            // خواندن shareLink و نام از سرور ذخیره‌شده در prefs (اگه هست)
            // سرورهای custom در custom_servers_v1 هستند؛ builtin در builtin_configs.
            // در سادگی، فقط «آخرین سرور» رو به headless می‌سپاریم و اون خودش
            // تصمیم می‌گیرد.
            try {
                val i = Intent(context, WidgetHeadlessActivity::class.java).apply {
                    putExtra(WidgetHeadlessActivity.EXTRA_TYPE, "current")
                    putExtra(WidgetHeadlessActivity.EXTRA_PAYLOAD, lastId2)
                    putExtra(WidgetHeadlessActivity.EXTRA_TITLE, "Boot")
                    putExtra(WidgetHeadlessActivity.EXTRA_ACTION, "connect")
                    addFlags(
                        Intent.FLAG_ACTIVITY_NEW_TASK or
                            Intent.FLAG_ACTIVITY_NO_ANIMATION or
                            Intent.FLAG_ACTIVITY_EXCLUDE_FROM_RECENTS,
                    )
                }
                context.startActivity(i)
            } catch (e: Exception) {
                Log.w(TAG, "could not start headless activity for auto-connect: ${e.message}")
            }
        } catch (e: Exception) {
            Log.e(TAG, "BootReceiver error: ${e.message}")
        }
    }

    companion object {
        private const val TAG = "HasanBootReceiver"
    }
}
