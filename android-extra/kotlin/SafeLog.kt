package com.hasan.hasan_vpn

import android.util.Log

/**
 * لاگ + ring buffer.
 * - در حافظه: آخرین ۲۰۰۰ خط نگه داشته می‌شود (برای نمایش در Log Viewer).
 * - روی logcat فقط در بیلد debuggable.
 *
 * ساختار هر خط: ts (ms) | level (d/i/w/e) | tag | msg
 */
object SafeLog {
    @Volatile
    var enabled: Boolean = false

    private const val MAX = 2000

    data class Entry(
        val ts: Long,
        val level: Char,
        val tag: String,
        val msg: String,
    )

    private val buffer = ArrayDeque<Entry>()
    private val lock = Any()

    private fun record(level: Char, tag: String, msg: String, t: Throwable?) {
        val full = if (t != null) "$msg\n${t.stackTraceToString()}" else msg
        synchronized(lock) {
            if (buffer.size >= MAX) buffer.removeFirst()
            buffer.addLast(Entry(System.currentTimeMillis(), level, tag, full))
        }
    }

    fun d(tag: String, msg: String, t: Throwable? = null) {
        record('d', tag, msg, t)
        if (!enabled) return
        if (t != null) Log.d(tag, msg, t) else Log.d(tag, msg)
    }

    fun i(tag: String, msg: String, t: Throwable? = null) {
        record('i', tag, msg, t)
        if (!enabled) return
        if (t != null) Log.i(tag, msg, t) else Log.i(tag, msg)
    }

    fun w(tag: String, msg: String, t: Throwable? = null) {
        record('w', tag, msg, t)
        if (!enabled) return
        if (t != null) Log.w(tag, msg, t) else Log.w(tag, msg)
    }

    fun e(tag: String, msg: String, t: Throwable? = null) {
        record('e', tag, msg, t)
        if (!enabled) return
        if (t != null) Log.e(tag, msg, t) else Log.e(tag, msg)
    }

    /** خروجی به‌صورت لیستی از mapها برای انتقال از طریق MethodChannel. */
    fun dump(): List<Map<String, Any>> = synchronized(lock) {
        buffer.map { e ->
            mapOf<String, Any>(
                "ts" to e.ts,
                "level" to e.level.toString(),
                "tag" to e.tag,
                "msg" to e.msg,
            )
        }
    }

    fun clear() = synchronized(lock) { buffer.clear() }
}
