package com.hasan.hasan_vpn.game

import android.util.Log
import org.json.JSONObject
import java.io.BufferedReader
import java.io.InputStreamReader
import java.net.HttpURLConnection
import java.net.URL

/**
 * Optional Cloudflare-worker style DNS. Without a configured worker URL this is a no-op
 * that returns empty results (safe for builds that never set one).
 */
object DedicatedDnsResolver {

    private const val TAG = "DedicatedDnsResolver"

    data class DnsRegion(val code: String, val label: String)

    data class RegionRaceResult(
        val region: DnsRegion,
        val latencyMs: Long,
        val ips: List<String>,
    )

    val regions: List<DnsRegion> = listOf(
        DnsRegion("ME", "Middle East"),
        DnsRegion("EU", "Europe"),
        DnsRegion("AS", "Asia"),
        DnsRegion("US", "United States"),
    )

    fun regionByCode(code: String?): DnsRegion =
        regions.find { it.code.equals(code, ignoreCase = true) } ?: regions.first()

    fun cacheKeyFor(gameId: String): String = "dns_best_region_$gameId"

    /**
     * Resolve [hostname] via optional worker. [workerUrl] empty -> empty list.
     * No hardcoded worker URL is shipped.
     */
    fun resolveViaWorker(workerUrl: String, hostname: String, region: String): List<String> {
        if (workerUrl.isBlank()) return emptyList()
        return try {
            val url = URL(
                workerUrl.trimEnd('/') +
                    "/resolve?name=${hostname}&type=A&ecs=$region"
            )
            val conn = (url.openConnection() as HttpURLConnection).apply {
                connectTimeout = 4000
                readTimeout = 4000
                requestMethod = "GET"
            }
            val code = conn.responseCode
            val body = if (code in 200..299) {
                BufferedReader(InputStreamReader(conn.inputStream)).use { it.readText() }
            } else null
            conn.disconnect()
            if (body.isNullOrEmpty()) return emptyList()
            val answers = JSONObject(body).optJSONArray("Answer") ?: return emptyList()
            val ips = mutableListOf<String>()
            for (i in 0 until answers.length()) {
                val a = answers.getJSONObject(i)
                if (a.optInt("type") == 1) ips.add(a.getString("data"))
            }
            ips
        } catch (e: Exception) {
            Log.d(TAG, "resolveViaWorker failed: ${e.message}")
            emptyList()
        }
    }

    fun testAllRegions(workerUrl: String, hostname: String): List<RegionRaceResult> {
        if (workerUrl.isBlank()) return emptyList()
        return regions.mapNotNull { region ->
            val t0 = System.nanoTime()
            val ips = resolveViaWorker(workerUrl, hostname, region.code)
            if (ips.isEmpty()) null
            else RegionRaceResult(
                region = region,
                latencyMs = ((System.nanoTime() - t0) / 1_000_000L).coerceAtLeast(1L),
                ips = ips,
            )
        }.sortedBy { it.latencyMs }
    }
}
