package com.hasan.hasan_vpn.game

import android.content.Context
import android.content.Intent
import android.os.Build
import android.util.Log
import com.hasan.hasan_vpn.GameDnsVpnService

/**
 * Thin facade over DNS race / game catalog / DNS-only VPN boost.
 * No MLM MyVpnService / Aether / XrayJsonGenerator dependencies.
 */
object GameBoosterManager {

    private const val TAG = "GameBoosterManager"

    @Volatile private var activeResolver: String? = null
    @Volatile private var activeSecondary: String? = null

    fun isBoostRunning(): Boolean = GameDnsVpnService.isRunning

    fun status(): Map<String, Any?> = mapOf(
        "running" to GameDnsVpnService.isRunning,
        "resolver" to activeResolver,
        "secondary" to activeSecondary,
    )

    fun raceDns(
        hostname: String = "pubgmobile.com",
        extraIps: List<String> = emptyList(),
    ): Map<String, Any?> {
        return try {
            val results = DnsRaceTester.findWorkingDnsServers(hostname, extraIps)
            val mapped = results.map { r ->
                mapOf(
                    "ip" to r.dnsServer.ip,
                    "name" to r.dnsServer.name,
                    "category" to r.dnsServer.category.name,
                    "port" to r.port,
                    "latencyMs" to r.latencyMs,
                    "resolved" to r.resolvedIp,
                )
            }
            val winner = results.firstOrNull()
            mapOf(
                "ok" to results.isNotEmpty(),
                "results" to mapped,
                "winner" to winner?.let {
                    mapOf(
                        "ip" to it.dnsServer.ip,
                        "name" to it.dnsServer.name,
                        "latencyMs" to it.latencyMs,
                        "resolved" to it.resolvedIp,
                    )
                },
            )
        } catch (e: Exception) {
            Log.e(TAG, "raceDns failed", e)
            mapOf("ok" to false, "error" to (e.message ?: "race failed"), "results" to emptyList<Any>())
        }
    }

    fun listGames(context: Context): Map<String, Any?> {
        val sorted = GameDatabase.getAllGamesSorted(context)
        val games = sorted.map { (g, installed) ->
            mapOf(
                "id" to g.id,
                "name" to g.name,
                "packageName" to g.packageName,
                "iconEmoji" to g.iconEmoji,
                "category" to g.category,
                "installed" to installed,
                "defaultRegion" to g.defaultRegion,
                "regions" to g.servers.map { s ->
                    mapOf(
                        "region" to s.region,
                        "displayName" to s.displayName,
                        "endpoints" to s.testEndpoints,
                        "port" to s.port,
                    )
                },
            )
        }
        return mapOf("games" to games)
    }

    fun pingGame(id: String, region: String? = null): Map<String, Any?> {
        val game = GameDatabase.findById(id)
            ?: return mapOf("ok" to false, "error" to "unknown game id")
        val server = game.servers.find { it.region.equals(region ?: game.defaultRegion, true) }
            ?: game.servers.firstOrNull()
            ?: return mapOf("ok" to false, "error" to "no server")
        val host = server.testEndpoints.firstOrNull()
            ?: return mapOf("ok" to false, "error" to "no endpoint")
        val (median, jitter) = GamePingTester.pingWithJitter(host, server.port)
        return mapOf(
            "ok" to (median > 0),
            "pingMs" to median,
            "jitterMs" to jitter,
            "endpoint" to host,
            "port" to server.port,
            "region" to server.region,
        )
    }

    fun startDnsBoost(context: Context, resolver: String, secondary: String? = null): Map<String, Any?> {
        if (resolver.isBlank()) {
            return mapOf("ok" to false, "error" to "resolver is empty")
        }
        return try {
            activeResolver = resolver.trim()
            activeSecondary = secondary?.trim()?.takeIf { it.isNotEmpty() }
            val intent = Intent(context, GameDnsVpnService::class.java).apply {
                action = GameDnsVpnService.ACTION_START
                putExtra(GameDnsVpnService.EXTRA_DNS_PRIMARY, activeResolver)
                putExtra(GameDnsVpnService.EXTRA_DNS_SECONDARY, activeSecondary)
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
            mapOf("ok" to true, "resolver" to activeResolver, "secondary" to activeSecondary)
        } catch (e: Exception) {
            Log.e(TAG, "startDnsBoost failed", e)
            mapOf("ok" to false, "error" to (e.message ?: "start failed"))
        }
    }

    fun stopDnsBoost(context: Context): Map<String, Any?> {
        return try {
            val intent = Intent(context, GameDnsVpnService::class.java).apply {
                action = GameDnsVpnService.ACTION_STOP
            }
            context.startService(intent)
            activeResolver = null
            activeSecondary = null
            mapOf("ok" to true)
        } catch (e: Exception) {
            mapOf("ok" to false, "error" to (e.message ?: "stop failed"))
        }
    }
}
