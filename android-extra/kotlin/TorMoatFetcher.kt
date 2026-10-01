package com.hasan.hasan_vpn

import org.json.JSONArray
import org.json.JSONObject
import java.io.BufferedReader
import java.io.InputStreamReader
import java.io.OutputStreamWriter
import java.net.HttpURLConnection
import java.net.URL

/**
 * Fetches Tor bridge lines via the Moat / circumvention API.
 * Primary: POST /moat/circumvention/settings
 * Fallback: /moat/circumvention/defaults, then legacy /moat/fetch + /moat/check
 * Exposed via MethodChannel com.hasan.hasan_vpn/tor -> fetchMoatBridges(type)
 */
object TorMoatFetcher {
    private const val TAG = "TorMoatFetcher"
    private const val BASE = "https://bridges.torproject.org/moat"
    private const val TIMEOUT_MS = 20_000

    fun fetch(type: String, country: String = "ir"): Map<String, Any?> {
        val transport = type.trim().lowercase().let {
            if (it == "meek") "meek_lite" else it
        }
        if (transport !in setOf("obfs4", "snowflake", "meek_lite", "conjure", "webtunnel")) {
            return mapOf(
                "ok" to false,
                "error" to "unsupported type: $type",
                "bridges" to emptyList<String>()
            )
        }
        try {
            val r = fetchSettings(transport, country)
            if (r.first) return mapOf(
                "ok" to true, "bridges" to r.second, "source" to "settings"
            )
        } catch (e: Exception) {
            SafeLog.w(TAG, "settings failed: ${e.message}")
        }
        try {
            val r = fetchDefaults(transport)
            if (r.first) return mapOf(
                "ok" to true, "bridges" to r.second, "source" to "defaults"
            )
        } catch (e: Exception) {
            SafeLog.w(TAG, "defaults failed: ${e.message}")
        }
        try {
            val challenge = fetchChallenge(transport)
            if (challenge != null) {
                val bridges = submitChallenge(
                    transport = challenge["transport"] as? String ?: transport,
                    challenge = challenge["challenge"] as? String ?: "",
                    solution = "",
                )
                if (bridges.isNotEmpty()) {
                    return mapOf(
                        "ok" to true, "bridges" to bridges, "source" to "challenge"
                    )
                }
            }
        } catch (e: Exception) {
            SafeLog.w(TAG, "challenge path failed: ${e.message}")
        }
        return mapOf(
            "ok" to false,
            "error" to "Moat returned no bridges for $transport",
            "bridges" to emptyList<String>()
        )
    }

    private fun fetchSettings(
        transport: String, country: String
    ): Pair<Boolean, List<String>> {
        val body = JSONObject().apply {
            put("transports", JSONArray().put(transport))
            put("country", country.lowercase())
        }.toString()
        return parseSettingsResponse(
            httpPost("$BASE/circumvention/settings", body, "application/json"),
            transport,
        )
    }

    private fun fetchDefaults(transport: String): Pair<Boolean, List<String>> {
        val body = JSONObject().apply {
            put("transports", JSONArray().put(transport))
        }.toString()
        return parseSettingsResponse(
            httpPost("$BASE/circumvention/defaults", body, "application/json"),
            transport,
        )
    }

    private fun parseSettingsResponse(
        raw: String?, transport: String
    ): Pair<Boolean, List<String>> {
        if (raw.isNullOrBlank()) return false to emptyList()
        return try {
            val root = JSONObject(raw)
            val out = mutableListOf<String>()
            val settings = root.optJSONArray("settings") ?: return false to emptyList()
            for (i in 0 until settings.length()) {
                val item = settings.optJSONObject(i) ?: continue
                val bridges = item.optJSONObject("bridges") ?: continue
                val strings = bridges.optJSONArray("bridge_strings")
                    ?: bridges.optJSONArray("bridges")
                    ?: continue
                for (j in 0 until strings.length()) {
                    val line = strings.optString(j, "").trim()
                    if (line.isNotEmpty()) out.add(line)
                }
            }
            (out.isNotEmpty()) to out.distinct()
        } catch (e: Exception) {
            SafeLog.w(TAG, "parse settings: ${e.message}")
            false to emptyList()
        }
    }

    private fun fetchChallenge(transport: String): Map<String, Any?>? {
        val body = JSONObject().apply {
            put("data", JSONArray().put(JSONObject().apply {
                put("type", "client-transports")
                put("version", "0.1.0")
                put("supported", JSONArray().put(transport))
            }))
        }.toString()
        val raw = httpPost("$BASE/fetch", body, "application/vnd.api+json") ?: return null
        return try {
            val data = JSONObject(raw).optJSONArray("data")?.optJSONObject(0) ?: return null
            mapOf(
                "challenge" to data.optString("challenge", ""),
                "transport" to (data.optJSONArray("transport")?.optString(0) ?: transport),
            )
        } catch (_: Exception) { null }
    }

    private fun submitChallenge(
        transport: String, challenge: String, solution: String
    ): List<String> {
        if (challenge.isEmpty()) return emptyList()
        val body = JSONObject().apply {
            put("data", JSONArray().put(JSONObject().apply {
                put("id", "1")
                put("type", "moat-solution")
                put("version", "0.1.0")
                put("transport", transport)
                put("challenge", challenge)
                put("solution", solution)
                put("qrcode", false)
            }))
        }.toString()
        val raw = httpPost("$BASE/check", body, "application/vnd.api+json")
            ?: return emptyList()
        return try {
            val bridges = JSONObject(raw)
                .optJSONArray("data")?.optJSONObject(0)?.optJSONArray("bridges")
                ?: return emptyList()
            val out = mutableListOf<String>()
            for (i in 0 until bridges.length()) {
                val line = bridges.optString(i, "").trim()
                if (line.isNotEmpty()) out.add(line)
            }
            out
        } catch (_: Exception) { emptyList() }
    }

    private fun httpPost(
        urlStr: String, body: String, contentType: String
    ): String? {
        var conn: HttpURLConnection? = null
        return try {
            conn = (URL(urlStr).openConnection() as HttpURLConnection).apply {
                requestMethod = "POST"
                connectTimeout = TIMEOUT_MS
                readTimeout = TIMEOUT_MS
                doOutput = true
                doInput = true
                setRequestProperty("Content-Type", contentType)
                setRequestProperty(
                    "Accept", "application/json, application/vnd.api+json"
                )
                setRequestProperty(
                    "User-Agent",
                    "Mozilla/5.0 (Linux; Android 12) HasanVPN",
                )
                instanceFollowRedirects = true
            }
            OutputStreamWriter(conn.outputStream, Charsets.UTF_8).use { it.write(body) }
            val code = conn.responseCode
            val stream = if (code in 200..299) conn.inputStream else conn.errorStream
            val text = stream?.let {
                BufferedReader(InputStreamReader(it, Charsets.UTF_8))
                    .use { r -> r.readText() }
            }
            if (code !in 200..299) {
                SafeLog.w(TAG, "HTTP $code for $urlStr: ${text?.take(200)}")
                return null
            }
            text
        } catch (e: Exception) {
            SafeLog.w(TAG, "httpPost $urlStr: ${e.message}")
            null
        } finally {
            try { conn?.disconnect() } catch (_: Exception) {}
        }
    }
}
