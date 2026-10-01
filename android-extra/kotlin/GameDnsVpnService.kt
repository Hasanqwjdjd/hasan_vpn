package com.hasan.hasan_vpn

import android.app.ActivityManager
import android.content.Context
import android.content.Intent
import android.net.VpnService
import android.os.ParcelFileDescriptor
import android.util.Log
import java.io.FileInputStream
import java.io.FileOutputStream
import java.net.DatagramPacket
import java.net.DatagramSocket
import java.net.InetAddress
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors

/**
 * DNS-only VpnService for Game Booster.
 *
 * The TUN only routes ONE fake resolver address (10.255.255.2/32). The system
 * resolver is pointed at it, so every DNS query lands in the TUN; this service
 * forwards each UDP/53 query to the chosen real resolver over a protect()ed
 * socket (it bypasses the TUN) and writes the answer back. All other traffic
 * never enters the TUN, so this is NOT a full tunnel.
 *
 * Android allows one VPN per user: starting this while the main Xray tunnel is
 * up would revoke it. [GameBoosterManager] refuses to start in that case and
 * [isXrayRunning] is the shared check.
 */
class GameDnsVpnService : VpnService() {

    companion object {
        private const val TAG = "GameDnsVpn"
        const val ACTION_START = "com.hasan.hasan_vpn.game.START"
        const val ACTION_STOP = "com.hasan.hasan_vpn.game.STOP"
        const val EXTRA_DNS_PRIMARY = "dns_primary"
        const val EXTRA_DNS_SECONDARY = "dns_secondary"

        private const val FAKE_DNS = "10.255.255.2"
        private const val TUN_ADDR = "10.255.255.1"

        @Volatile var isRunning: Boolean = false
        @Volatile var lastError: String? = null

        @Suppress("DEPRECATION")
        fun isXrayRunning(ctx: Context): Boolean = try {
            val am = ctx.getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
            am.getRunningServices(Int.MAX_VALUE).any {
                it.service.className.endsWith("XrayVPNService")
            }
        } catch (_: Exception) { false }
    }

    private var tun: ParcelFileDescriptor? = null
    private var reader: Thread? = null
    private var pool: ExecutorService? = null
    @Volatile private var active = false

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_STOP -> { shutdown(); stopSelf(); return START_NOT_STICKY }
            ACTION_START -> {
                val p = intent.getStringExtra(EXTRA_DNS_PRIMARY)?.trim().orEmpty()
                val s = intent.getStringExtra(EXTRA_DNS_SECONDARY)?.trim()?.takeIf { it.isNotEmpty() }
                if (p.isEmpty()) { lastError = "no resolver"; stopSelf(); return START_NOT_STICKY }
                if (isXrayRunning(this)) {
                    lastError = "main VPN is active"
                    stopSelf(); return START_NOT_STICKY
                }
                start(p, s)
            }
        }
        return START_NOT_STICKY
    }

    private fun start(primary: String, secondary: String?) {
        shutdown()
        lastError = null
        try {
            val b = Builder()
                .setSession("Hasan DNS Boost")
                .addAddress(TUN_ADDR, 24)
                .addDnsServer(FAKE_DNS)
                .addRoute(FAKE_DNS, 32)
                .setMtu(1500)
            val fd = b.establish()
            if (fd == null) {
                lastError = "VPN permission not granted"
                stopSelf(); return
            }
            tun = fd
            active = true
            isRunning = true
            pool = Executors.newFixedThreadPool(4)
            val resolvers = listOfNotNull(primary, secondary)
            reader = Thread { pump(fd, resolvers) }.also { it.isDaemon = true; it.start() }
        } catch (e: Exception) {
            Log.e(TAG, "start failed", e)
            lastError = e.message ?: "start failed"
            shutdown(); stopSelf()
        }
    }

    private fun pump(fd: ParcelFileDescriptor, resolvers: List<String>) {
        val input = FileInputStream(fd.fileDescriptor)
        val output = FileOutputStream(fd.fileDescriptor)
        val buf = ByteArray(32767)
        while (active) {
            val n = try { input.read(buf) } catch (_: Exception) { -1 }
            if (n < 0) break
            if (n < 28) continue
            if ((buf[0].toInt() shr 4) != 4) continue          // IPv4 only
            val ihl = (buf[0].toInt() and 0x0F) * 4
            if (buf[9].toInt() != 17 || n < ihl + 8) continue    // UDP only
            val dstPort = ((buf[ihl + 2].toInt() and 0xFF) shl 8) or (buf[ihl + 3].toInt() and 0xFF)
            if (dstPort != 53) continue
            val srcPort = ((buf[ihl].toInt() and 0xFF) shl 8) or (buf[ihl + 1].toInt() and 0xFF)
            val udpLen = ((buf[ihl + 4].toInt() and 0xFF) shl 8) or (buf[ihl + 5].toInt() and 0xFF)
            val plen = minOf(udpLen - 8, n - ihl - 8)
            if (plen <= 0) continue
            val query = buf.copyOfRange(ihl + 8, ihl + 8 + plen)
            val clientIp = buf.copyOfRange(12, 16)
            val serverIp = buf.copyOfRange(16, 20)
            pool?.execute {
                val answer = forward(query, resolvers) ?: return@execute
                val pkt = buildReply(serverIp, clientIp, srcPort, answer)
                try { synchronized(output) { output.write(pkt) } } catch (_: Exception) {}
            }
        }
    }

    private fun forward(query: ByteArray, resolvers: List<String>): ByteArray? {
        for (r in resolvers) {
            var sock: DatagramSocket? = null
            try {
                sock = DatagramSocket()
                if (!protect(sock)) { Log.w(TAG, "protect() failed"); return null }
                sock.soTimeout = 2500
                val host = r.substringBefore(':')
                val port = r.substringAfter(':', "53").toIntOrNull() ?: 53
                val addr = InetAddress.getByName(host)
                sock.send(DatagramPacket(query, query.size, addr, port))
                val rb = ByteArray(4096)
                val dp = DatagramPacket(rb, rb.size)
                sock.receive(dp)
                return rb.copyOf(dp.length)
            } catch (_: Exception) {
            } finally {
                try { sock?.close() } catch (_: Exception) {}
            }
        }
        return null
    }

    /** IPv4+UDP reply: src=fake resolver:53 -> dst=client:clientPort. */
    private fun buildReply(srcIp: ByteArray, dstIp: ByteArray, dstPort: Int, payload: ByteArray): ByteArray {
        val total = 20 + 8 + payload.size
        val p = ByteArray(total)
        p[0] = 0x45; p[2] = (total shr 8).toByte(); p[3] = total.toByte()
        p[6] = 0x40                       // DF
        p[8] = 64; p[9] = 17
        System.arraycopy(srcIp, 0, p, 12, 4)
        System.arraycopy(dstIp, 0, p, 16, 4)
        var sum = 0
        for (i in 0 until 20 step 2) sum += ((p[i].toInt() and 0xFF) shl 8) or (p[i + 1].toInt() and 0xFF)
        while (sum shr 16 != 0) sum = (sum and 0xFFFF) + (sum shr 16)
        val ck = sum.inv() and 0xFFFF
        p[10] = (ck shr 8).toByte(); p[11] = ck.toByte()
        p[20] = 0; p[21] = 53
        p[22] = (dstPort shr 8).toByte(); p[23] = dstPort.toByte()
        val ul = 8 + payload.size
        p[24] = (ul shr 8).toByte(); p[25] = ul.toByte()   // checksum 0 = none (legal for IPv4)
        System.arraycopy(payload, 0, p, 28, payload.size)
        return p
    }

    private fun shutdown() {
        active = false
        isRunning = false
        try { reader?.interrupt() } catch (_: Exception) {}
        try { pool?.shutdownNow() } catch (_: Exception) {}
        try { tun?.close() } catch (_: Exception) {}
        reader = null; pool = null; tun = null
    }

    override fun onRevoke() { shutdown(); stopSelf() }
    override fun onDestroy() { shutdown(); super.onDestroy() }
}
