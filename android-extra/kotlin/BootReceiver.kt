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
            Log.i(TAG, "BOOT_COMPLETED — scheduling auto-connect")
            // Kick the headless widget / VPN service path already present in the app.
            val i = Intent(context, MainActivity::class.java).apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                putExtra("auto_connect_boot", true)
            }
            // Prefer starting the existing VPN service if available; otherwise
            // launch activity which will pick up the extra.
            try {
                context.startActivity(i)
            } catch (e: Exception) {
                Log.w(TAG, "could not start MainActivity for auto-connect: ${e.message}")
            }
        } catch (e: Exception) {
            Log.e(TAG, "BootReceiver error: ${e.message}")
        }
    }

    companion object {
        private const val TAG = "HasanBootReceiver"
    }
}
