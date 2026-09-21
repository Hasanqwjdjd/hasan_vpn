package com.hasan.hasan_vpn

import android.util.Log

/**
 * لاگ فقط در بیلد debuggable. در نسخهٔ نهایی هیچ چیزی (آدرس سرور، خروجی هسته،
 * خطاها) روی logcat نمی‌رود.
 */
object SafeLog {
    @Volatile
    var enabled: Boolean = false

    fun d(tag: String, msg: String, t: Throwable? = null) {
        if (!enabled) return
        if (t != null) Log.d(tag, msg, t) else Log.d(tag, msg)
    }

    fun i(tag: String, msg: String, t: Throwable? = null) {
        if (!enabled) return
        if (t != null) Log.i(tag, msg, t) else Log.i(tag, msg)
    }

    fun w(tag: String, msg: String, t: Throwable? = null) {
        if (!enabled) return
        if (t != null) Log.w(tag, msg, t) else Log.w(tag, msg)
    }

    fun e(tag: String, msg: String, t: Throwable? = null) {
        if (!enabled) return
        if (t != null) Log.e(tag, msg, t) else Log.e(tag, msg)
    }
}
