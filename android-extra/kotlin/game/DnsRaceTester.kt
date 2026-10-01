package com.hasan.hasan_vpn.game

import android.util.Log
import org.json.JSONObject
import java.io.BufferedReader
import java.io.InputStreamReader
import java.net.DatagramPacket
import java.net.DatagramSocket
import java.net.HttpURLConnection
import java.net.InetAddress
import java.net.URL
import java.util.concurrent.Callable
import java.util.concurrent.ConcurrentLinkedQueue
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit

/**
 * Parallel DNS race over [GameDnsList] (UDP + optional DoH fallback).
 * No OkHttp / coroutines — plain threads + DatagramSocket / HttpURLConnection.
 */
object DnsRaceTester {

    private const val TAG = "DnsRaceTester"
    private const val QUERY_TIMEOUT_MS = 2000

    /** Alt ports tried for Iranian resolvers (port-53 interception bypass). */
    private val alternatePorts = listOf(53, 5353, 1053, 8053, 5300)

    data class DnsResult(
        val dnsServer: GameDnsList.DnsServer,
        val port: Int,
        val latencyMs: Long,
        val resolvedIp: String?,
    )

    /**
     * Race all DNS servers for [hostname]. Returns sorted-by-latency successful results.
     */
    fun findWorkingDnsServers(testHostname: String): List<DnsResult> {
        val pool = Executors.newFixedThreadPool(8)
        val out = ConcurrentLinkedQueue<DnsResult>()
        try {
            val jobs = mutableListOf<Callable<Unit>>()
            for (dns in GameDnsList.servers) {
                val ports = if (dns.category == GameDnsList.DnsCategory.PUBLIC_INTL) {
                    listOf(53)
                } else {
                    alternatePorts
                }
                for (port in ports) {
                    jobs.add(Callable {
                        val r = queryDns(dns, port, testHostname)
                        if (r != null && r.resolvedIp != null) out.add(r)
                    })
                }
            }
            pool.invokeAll(jobs, 6, TimeUnit.SECONDS)
        } catch (e: Exception) {
            Log.w(TAG, "race error: ${e.message}")
        } finally {
            pool.shutdownNow()
        }
        val list = out.toList().sortedBy { it.latencyMs }
        if (list.isEmpty()) {
            val ips = resolveViaDoh(testHostname)
            if (ips.isNotEmpty()) {
                val cf = GameDnsList.servers.find { it.ip == "1.1.1.1" }
                    ?: GameDnsList.DnsServer("1.1.1.1", "DoH", GameDnsList.DnsCategory.PUBLIC_INTL)
                return listOf(DnsResult(cf, 443, 50, ips.first()))
            }
        }
        return list
    }

    fun resolveViaDoh(hostname: String): List<String> {
        val attempts = listOf(
            "https://dns.google/resolve?name=$hostname&type=A" to null,
            "https://cloudflare-dns.com/dns-query?name=$hostname&type=A" to "application/dns-json",
        )
        for ((urlStr, accept) in attempts) {
            try {
                val conn = (URL(urlStr).openConnection() as HttpURLConnection).apply {
                    connectTimeout = 3000
                    readTimeout = 3000
                    requestMethod = "GET"
                    if (accept != null) setRequestProperty("Accept", accept)
                    else setRequestProperty("Accept", "application/dns-json")
                }
                val code = conn.responseCode
                val body = if (code in 200..299) {
                    BufferedReader(InputStreamReader(conn.inputStream)).use { it.readText() }
                } else null
                conn.disconnect()
                if (body.isNullOrEmpty()) continue
                val answers = JSONObject(body).optJSONArray("Answer") ?: continue
                val ips = mutableListOf<String>()
                for (i in 0 until answers.length()) {
                    val a = answers.getJSONObject(i)
                    if (a.optInt("type") == 1) ips.add(a.getString("data"))
                }
                if (ips.isNotEmpty()) return ips
            } catch (e: Exception) {
                Log.d(TAG, "DoH failed: ${e.message}")
            }
        }
        return emptyList()
    }

    private fun queryDns(dns: GameDnsList.DnsServer, port: Int, hostname: String): DnsResult? {
        var socket: DatagramSocket? = null
        return try {
            socket = DatagramSocket()
            socket.soTimeout = QUERY_TIMEOUT_MS
            val query = buildDnsQuery(hostname)
            val addr = InetAddress.getByName(dns.ip)
            val packet = DatagramPacket(query, query.size, addr, port)
            val t0 = System.nanoTime()
            socket.send(packet)
            val buf = ByteArray(512)
            val resp = DatagramPacket(buf, buf.size)
            socket.receive(resp)
            val latency = ((System.nanoTime() - t0) / 1_000_000L).coerceAtLeast(1L)
            val ip = parseDnsResponse(buf, resp.length)
            DnsResult(dns, port, latency, ip)
        } catch (_: Exception) {
            null
        } finally {
            try { socket?.close() } catch (_: Exception) {}
        }
    }

    private fun buildDnsQuery(hostname: String): ByteArray {
        val labels = hostname.trimEnd('.').split('.')
        val nameBytes = labels.flatMap { label ->
            listOf(label.length.toByte()) + label.toByteArray(Charsets.US_ASCII).toList()
        } + listOf(0.toByte())
        val header = byteArrayOf(
            0x12, 0x34, // id
            0x01, 0x00, // standard query
            0x00, 0x01, // qdcount
            0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        )
        val question = nameBytes.toByteArray() + byteArrayOf(0x00, 0x01, 0x00, 0x01) // A IN
        return header + question
    }

    private fun parseDnsResponse(data: ByteArray, length: Int): String? {
        if (length < 12) return null
        val ancount = ((data[6].toInt() and 0xff) shl 8) or (data[7].toInt() and 0xff)
        if (ancount == 0) return null
        var pos = 12
        while (pos < length) {
            val len = data[pos].toInt() and 0xff
            if (len == 0) { pos++; break }
            if (len >= 0xc0) { pos += 2; break }
            pos += 1 + len
        }
        if (pos + 4 > length) return null
        pos += 4
        for (a in 0 until ancount) {
            if (pos >= length) break
            val len0 = data[pos].toInt() and 0xff
            if (len0 >= 0xc0) pos += 2 else {
                while (pos < length) {
                    val l = data[pos].toInt() and 0xff
                    if (l == 0) { pos++; break }
                    if (l >= 0xc0) { pos += 2; break }
                    pos += 1 + l
                }
            }
            if (pos + 10 > length) return null
            val type = ((data[pos].toInt() and 0xff) shl 8) or (data[pos + 1].toInt() and 0xff)
            val rdlength = ((data[pos + 8].toInt() and 0xff) shl 8) or (data[pos + 9].toInt() and 0xff)
            pos += 10
            if (type == 1 && rdlength == 4 && pos + 4 <= length) {
                return "${data[pos].toInt() and 0xff}.${data[pos + 1].toInt() and 0xff}." +
                    "${data[pos + 2].toInt() and 0xff}.${data[pos + 3].toInt() and 0xff}"
            }
            pos += rdlength
        }
        return null
    }
}
