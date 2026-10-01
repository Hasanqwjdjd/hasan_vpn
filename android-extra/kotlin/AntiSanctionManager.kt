package com.hasan.hasan_vpn

import android.content.Context

/**
 * Three toggles for Gemini / Google AI / filter bypass.
 * Flags stored in SharedPreferences; Xray JSON injection is done on the Dart side
 * (XraySettings.applyToConfig) so we do not depend on MLM CloudManager.
 */
object AntiSanctionManager {

    private const val PREFS = "anti_sanction"
    private const val KEY_FILTER = "filter_bypass"
    private const val KEY_GEMINI = "gemini_fix"
    private const val KEY_US = "gemini_us_exit"

    /** Domains steered when geminiFix is on. */
    val GEMINI_DOMAINS: List<String> = listOf(
        "gemini.google.com",
        "bard.google.com",
        "generativelanguage.googleapis.com",
        "ai.google.dev",
        "googleapis.com",
        "googleusercontent.com",
        "gstatic.com",
        "google.com",
    )

    private fun prefs(ctx: Context) =
        ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    fun status(ctx: Context): Map<String, Any?> {
        val p = prefs(ctx)
        return mapOf(
            "filterBypass" to p.getBoolean(KEY_FILTER, false),
            "geminiFix" to p.getBoolean(KEY_GEMINI, false),
            "geminiUsExit" to p.getBoolean(KEY_US, false),
        )
    }

    fun setFilterBypass(ctx: Context, enabled: Boolean): Map<String, Any?> {
        prefs(ctx).edit().putBoolean(KEY_FILTER, enabled).apply()
        return status(ctx) + ("ok" to true)
    }

    fun setGeminiFix(ctx: Context, enabled: Boolean): Map<String, Any?> {
        prefs(ctx).edit().putBoolean(KEY_GEMINI, enabled).apply()
        return status(ctx) + ("ok" to true)
    }

    fun setGeminiUsExit(ctx: Context, enabled: Boolean): Map<String, Any?> {
        prefs(ctx).edit().putBoolean(KEY_US, enabled).apply()
        return status(ctx) + ("ok" to true)
    }
}
