package com.hasan.hasan_vpn.game

/**
 * DNS servers raced to pick the fastest working resolver for game traffic.
 * Not shown to the user; only the winner is applied via GameDnsVpnService.
 */
object GameDnsList {

    data class DnsServer(
        val ip: String,
        val name: String,
        val category: DnsCategory,
    )

    enum class DnsCategory { GAMING_IR, BYPASS_IR, PUBLIC_INTL }

    val servers: List<DnsServer> = listOf(
        DnsServer("10.202.10.10", "RadarGame-1", DnsCategory.GAMING_IR),
        DnsServer("10.202.10.11", "RadarGame-2", DnsCategory.GAMING_IR),
        DnsServer("78.157.42.100", "Electro-1", DnsCategory.GAMING_IR),
        DnsServer("78.157.42.101", "Electro-2", DnsCategory.GAMING_IR),
        DnsServer("78.157.32.202", "Electro-Verified", DnsCategory.GAMING_IR),
        DnsServer("178.22.122.111", "Shecan-1", DnsCategory.BYPASS_IR),
        DnsServer("185.51.200.2", "Shecan-2", DnsCategory.BYPASS_IR),
        DnsServer("178.22.122.100", "Shecan-Classic-1", DnsCategory.BYPASS_IR),
        DnsServer("178.22.122.101", "Shecan-Alt-1", DnsCategory.BYPASS_IR),
        DnsServer("185.51.200.1", "Shecan-Alt-2", DnsCategory.BYPASS_IR),
        DnsServer("10.202.10.202", "Begzar-1", DnsCategory.BYPASS_IR),
        DnsServer("10.202.10.102", "Begzar-2", DnsCategory.BYPASS_IR),
        DnsServer("1.1.1.1", "Cloudflare", DnsCategory.PUBLIC_INTL),
        DnsServer("8.8.8.8", "Google", DnsCategory.PUBLIC_INTL),
        DnsServer("9.9.9.9", "Quad9", DnsCategory.PUBLIC_INTL),
    )

    val ips: List<String> get() = servers.map { it.ip }
}
