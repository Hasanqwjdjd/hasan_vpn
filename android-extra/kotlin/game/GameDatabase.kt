package com.hasan.hasan_vpn.game

import android.content.Context
import android.content.pm.PackageManager

data class GameInfo(
    val id: String,
    val name: String,
    val packageName: String,
    val alternatePackages: List<String> = emptyList(),
    val iconEmoji: String,
    val servers: List<GameServer>,
    val defaultRegion: String = "ME",
    val category: String = "shooter",
)

data class GameServer(
    val region: String,
    val displayName: String,
    val testEndpoints: List<String>,
    val port: Int = 443,
)

object GameDatabase {

    val games: List<GameInfo> = listOf(
        GameInfo(
            id = "codm",
            name = "Call of Duty Mobile",
            packageName = "com.activision.callofduty.shooter",
            alternatePackages = listOf("com.garena.game.codm"),
            iconEmoji = "🔫",
            category = "shooter",
            servers = listOf(
                GameServer("ME", "خاورمیانه", listOf("profile.callofduty.com", "cod.activision.com"), 443),
                GameServer("EU", "اروپا", listOf("profile.callofduty.com", "callofduty.com"), 443),
            ),
        ),
        GameInfo(
            id = "pubg",
            name = "PUBG Mobile",
            packageName = "com.tencent.ig",
            alternatePackages = listOf("com.pubg.krmobile", "com.rekoo.pubgm", "com.pubg.imobile"),
            iconEmoji = "🪖",
            category = "battle_royale",
            servers = listOf(
                GameServer("ME", "خاورمیانه", listOf("pubgmobile.com", "www.pubgmobile.com"), 443),
                GameServer("EU", "اروپا", listOf("pubgmobile.com"), 443),
            ),
        ),
        GameInfo(
            id = "mlbb",
            name = "Mobile Legends",
            packageName = "com.mobile.legends",
            iconEmoji = "⚔️",
            category = "moba",
            servers = listOf(
                GameServer("ME", "خاورمیانه", listOf("moba.mobilelegends.com", "api.mobilelegends.com"), 443),
                GameServer("AS", "آسیا", listOf("api.mobilelegends.com"), 443),
            ),
        ),
        GameInfo(
            id = "freefire",
            name = "Free Fire",
            packageName = "com.dts.freefireth",
            alternatePackages = listOf("com.dts.freefiremax"),
            iconEmoji = "🔥",
            category = "battle_royale",
            servers = listOf(
                GameServer("ME", "خاورمیانه", listOf("ff.garena.com", "loginbp.common.ggbluefox.com"), 443),
                GameServer("AS", "آسیا", listOf("ff.garena.com"), 443),
            ),
        ),
        GameInfo(
            id = "clashofclans",
            name = "Clash of Clans",
            packageName = "com.supercell.clashofclans",
            iconEmoji = "🏰",
            category = "strategy",
            servers = listOf(
                GameServer("EU", "اروپا", listOf("game.clashofclans.com"), 9339),
            ),
        ),
        GameInfo(
            id = "genshin",
            name = "Genshin Impact",
            packageName = "com.miHoYo.GenshinImpact",
            iconEmoji = "🌟",
            category = "rpg",
            servers = listOf(
                GameServer("AS", "آسیا", listOf("dispatchosglobal.yuanshen.com"), 443),
                GameServer("EU", "اروپا", listOf("oseurodispatch.yuanshen.com"), 443),
            ),
        ),
        GameInfo(
            id = "brawlstars",
            name = "Brawl Stars",
            packageName = "com.supercell.brawlstars",
            iconEmoji = "💥",
            category = "shooter",
            servers = listOf(
                GameServer("EU", "اروپا", listOf("game.brawlstarsgame.com"), 9339),
            ),
        ),
        GameInfo(
            id = "bloodstrike",
            name = "Blood Strike",
            packageName = "com.netease.newspike.na",
            alternatePackages = listOf("com.netease.newspike.gl"),
            iconEmoji = "🩸",
            category = "shooter",
            servers = listOf(
                GameServer("ME", "خاورمیانه", listOf("bloodstrike.com", "www.bloodstrike.com"), 443),
                GameServer("EU", "اروپا", listOf("bloodstrike.com"), 443),
            ),
        ),
        GameInfo(
            id = "stumbleguys",
            name = "Stumble Guys",
            packageName = "com.kitkagames.fallbuddies",
            iconEmoji = "🏃",
            category = "party",
            servers = listOf(
                GameServer("ME", "خاورمیانه", listOf("stumbleguys.com"), 443),
                GameServer("EU", "اروپا", listOf("stumbleguys.com"), 443),
            ),
        ),
        GameInfo(
            id = "fifamobile",
            name = "FIFA Mobile",
            packageName = "com.ea.gp.fifamobile",
            iconEmoji = "⚽",
            category = "sports",
            servers = listOf(
                GameServer("ME", "خاورمیانه", listOf("fifa.ea.com", "accounts.ea.com"), 443),
                GameServer("EU", "اروپا", listOf("fifa.ea.com"), 443),
            ),
        ),
        GameInfo(
            id = "efootball",
            name = "eFootball",
            packageName = "jp.konami.pesam",
            iconEmoji = "⚽",
            category = "sports",
            servers = listOf(
                GameServer("ME", "خاورمیانه", listOf("efootball-web.konami.net"), 443),
                GameServer("EU", "اروپا", listOf("efootball-web.konami.net"), 443),
            ),
        ),
        GameInfo(
            id = "roblox",
            name = "Roblox",
            packageName = "com.roblox.client",
            iconEmoji = "🧱",
            category = "sandbox",
            servers = listOf(
                GameServer("ME", "خاورمیانه", listOf("gamejoin.roblox.com", "clientsettings.roblox.com"), 443),
                GameServer("EU", "اروپا", listOf("gamejoin.roblox.com"), 443),
            ),
        ),
    )

    fun getInstalledGames(context: Context): List<GameInfo> {
        val pm = context.packageManager
        return games.filter { game ->
            (listOf(game.packageName) + game.alternatePackages).any { pkg ->
                try {
                    @Suppress("DEPRECATION")
                    pm.getPackageInfo(pkg, 0)
                    true
                } catch (_: PackageManager.NameNotFoundException) {
                    false
                } catch (_: Exception) {
                    false
                }
            }
        }
    }

    fun getAllGamesSorted(context: Context): List<Pair<GameInfo, Boolean>> {
        val pm = context.packageManager
        return games.map { game ->
            val installed = (listOf(game.packageName) + game.alternatePackages).any { pkg ->
                try {
                    @Suppress("DEPRECATION")
                    pm.getPackageInfo(pkg, 0)
                    true
                } catch (_: Exception) {
                    false
                }
            }
            game to installed
        }.sortedByDescending { it.second }
    }

    fun findById(id: String): GameInfo? = games.find { it.id == id }
}
