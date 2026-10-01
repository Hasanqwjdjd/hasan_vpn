package com.hasan.hasan_vpn.game

import java.net.InetSocketAddress
import java.net.Socket
import java.net.DatagramPacket
import java.net.DatagramSocket
import java.net.InetAddress

/**
 * TCP / UDP latency probes for game endpoints. Blocking — call from a worker thread.
 */
object GamePingTester {

    /**
     * TCP connect RTT in ms, or -1 on failure.
     */
    fun directPing(host: String, port: Int, timeoutMs: Int = 3000): Long {
        val t0 = System.nanoTime()
        return try {
            Socket().use { sock ->
                sock.connect(InetSocketAddress(host, port), timeoutMs)
            }
            ((System.nanoTime() - t0) / 1_000_000L).coerceAtLeast(1L)
        } catch (_: Exception) {
            -1L
        }
    }

    /**
     * Three TCP samples → median RTT + simple jitter (max-min). Returns Pair(median, jitter),
     * or (-1, 0) if all failed.
     */
    fun pingWithJitter(host: String, port: Int, samples: Int = 3, timeoutMs: Int = 2500): Pair<Long, Long> {
        val rtts = mutableListOf<Long>()
        repeat(samples) {
            val r = directPing(host, port, timeoutMs)
            if (r > 0) rtts.add(r)
            if (it < samples - 1) {
                try { Thread.sleep(40) } catch (_: Exception) {}
            }
        }
        if (rtts.isEmpty()) return -1L to 0L
        rtts.sort()
        val median = rtts[rtts.size / 2]
        val jitter = if (rtts.size >= 2) rtts.last() - rtts.first() else 0L
        return median to jitter
    }

    /**
     * Lightweight UDP "ping": send 1 empty datagram and wait for any reply or timeout.
     * Many game servers won't reply; still useful for open UDP ports.
     */
    fun udpPing(host: String, port: Int, timeoutMs: Int = 2000): Long {
        var socket: DatagramSocket? = null
        return try {
            socket = DatagramSocket()
            socket.soTimeout = timeoutMs
            val addr = InetAddress.getByName(host)
            val payload = ByteArray(4)
            val packet = DatagramPacket(payload, payload.size, addr, port)
            val t0 = System.nanoTime()
            socket.send(packet)
            val buf = ByteArray(64)
            val resp = DatagramPacket(buf, buf.size)
            socket.receive(resp)
            ((System.nanoTime() - t0) / 1_000_000L).coerceAtLeast(1L)
        } catch (_: Exception) {
            -1L
        } finally {
            try { socket?.close() } catch (_: Exception) {}
        }
    }
}
