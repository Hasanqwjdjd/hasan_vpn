package com.hasan.hasan_vpn.game

/**
 * UAE dedicated resolver - safe no-op.
 *
 * The MLM build pointed at a private server; that endpoint is not shipped
 * here. Always returns an empty list so callers fall back to DnsRaceTester
 * / system DNS without crashing.
 */
object UaeDnsResolver {

    fun resolve(hostname: String, region: String = "AE"): List<String> {
        // Intentionally empty: no remote worker URL is bundled.
        return emptyList()
    }
}
