package com.hasan.hasan_vpn

import android.content.Context

/** جایگزین وقتی ریپوی Maven سایفون در بیلد در دسترس نبود. */
object PsiphonService {
    fun isLibraryPresent(): Boolean = false

    fun status(): Map<String, Any?> = mapOf(
        "running" to false,
        "socksPort" to 0,
        "httpPort" to 0,
        "region" to null,
        "error" to "Psiphon AAR is not bundled in this build",
        "libraryPresent" to false,
    )

    fun start(context: Context, configJson: String, timeoutSec: Long = 90): Map<String, Any?> =
        status().toMutableMap().apply { put("ok", false) }

    fun stop(context: Context? = null) {}
}
