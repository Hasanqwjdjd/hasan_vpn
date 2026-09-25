package com.hasan.hasan_vpn

import android.content.Context
import android.net.VpnService
import android.util.Log
import java.io.File

/**
 * MTU + IPv6 + DNS injection for the active VPN tunnel.
 *
 * Runtime consumer (DEFECT 1 FIXED):
 *   android-extra/plugins/flutter_vless_android/.../XrayVPNService.kt
 *   calls VpnTuner.load(context) + VpnTuner.applyToBuilder(builder)
 *   via reflection immediately BEFORE builder.establish().
 *
 * Prefs keys (FlutterSharedPreferences, "flutter." prefix):
 *   vpn_tun_mtu, vpn_tun_ipv6, vpn_tun_dns, vpn_tun_dns6, vpn_asset_dir
 */
object VpnTuner {
    private const val TAG = "HasanVpnTuner"
    private const val PREFS = "FlutterSharedPreferences"

    @Volatile var mtu: Int = 1500
    @Volatile var enableIpv6: Boolean = false
    @Volatile var dns: List<String> = listOf("1.1.1.1", "8.8.8.8")
    @Volatile var dns6: List<String> = emptyList()
    @Volatile var assetDir: String = ""

    @JvmStatic
    fun update(
        mtu: Int?,
        enableIpv6: Boolean?,
        dns: List<String>?,
        dns6: List<String>?,
    ) {
        if (mtu != null && mtu in 1280..9000) this.mtu = mtu
        if (enableIpv6 != null) this.enableIpv6 = enableIpv6
        if (dns != null && dns.isNotEmpty()) this.dns = dns
        if (dns6 != null) this.dns6 = dns6
        Log.i(TAG, "params mtu=${this.mtu} ipv6=${this.enableIpv6} dns=${this.dns}")
    }

    @JvmStatic
    fun applyAssetDir(dir: String) {
        assetDir = dir
        Log.i(TAG, "assetDir=$assetDir")
    }

    @JvmStatic
    fun persist(context: Context) {
        val p = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        p.edit()
            .putLong("flutter.vpn_tun_mtu", mtu.toLong())
            .putBoolean("flutter.vpn_tun_ipv6", enableIpv6)
            .putString("flutter.vpn_tun_dns", dns.joinToString(","))
            .putString("flutter.vpn_tun_dns6", dns6.joinToString(","))
            .putString("flutter.vpn_asset_dir", assetDir)
            .apply()
    }

    @JvmStatic
    fun load(context: Context) {
        val p = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        mtu = p.getLong("flutter.vpn_tun_mtu", 1500L).toInt().coerceIn(1280, 9000)
        enableIpv6 = p.getBoolean("flutter.vpn_tun_ipv6", false)
        val d = p.getString("flutter.vpn_tun_dns", null)
        if (!d.isNullOrBlank()) {
            dns = d.split(",").map { it.trim() }.filter { it.isNotEmpty() }
        }
        val d6 = p.getString("flutter.vpn_tun_dns6", null)
        if (!d6.isNullOrBlank()) {
            dns6 = d6.split(",").map { it.trim() }.filter { it.isNotEmpty() }
        }
        assetDir = p.getString("flutter.vpn_asset_dir", "") ?: ""
        Log.i(TAG, "load mtu=$mtu ipv6=$enableIpv6 dns=$dns assetDir=$assetDir")
    }

    /**
     * Called from forked XrayVPNService.setupVpn immediately before establish().
     * Overrides the plugin's hardcoded setMtu(1500) / DNS / routes.
     */
    @JvmStatic
    fun applyToBuilder(builder: VpnService.Builder) {
        try {
            builder.setMtu(mtu)
            Log.i(TAG, "Builder.setMtu($mtu)")
        } catch (e: Exception) {
            Log.w(TAG, "setMtu failed: ${e.message}")
        }
        for (d in dns) {
            try {
                builder.addDnsServer(d)
            } catch (e: Exception) {
                Log.w(TAG, "addDnsServer($d): ${e.message}")
            }
        }
        if (enableIpv6) {
            try {
                // Local IPv6 address on the TUN interface
                builder.addAddress("fd00:1:1:1::1", 128)
                Log.i(TAG, "added IPv6 address fd00:1:1:1::1/128")
            } catch (e: Exception) {
                Log.w(TAG, "addAddress IPv6 failed: ${e.message}")
            }
            try {
                builder.addRoute("2000::", 3)
                Log.i(TAG, "added IPv6 route 2000::/3")
            } catch (e: Exception) {
                try {
                    builder.addRoute("::", 0)
                    Log.i(TAG, "added IPv6 route ::/0")
                } catch (e2: Exception) {
                    Log.w(TAG, "IPv6 route failed: ${e2.message}")
                }
            }
            for (d in dns6) {
                try {
                    builder.addDnsServer(d)
                } catch (e: Exception) {
                    Log.w(TAG, "addDnsServer6($d): ${e.message}")
                }
            }
        }
    }

    /**
     * Copy user-downloaded geoip/geosite into context.filesDir, which is the
     * directory XrayCoreManager sets as XRAY_LOCATION_ASSET
     * (Utilities.getUserAssetsPath = filesDir).
     */
    @JvmStatic
    fun ensureAssetSymlinks(context: Context) {
        if (assetDir.isEmpty()) return
        try {
            val src = File(assetDir)
            if (!src.isDirectory) return
            val dest = context.filesDir // == XRAY_LOCATION_ASSET
            src.listFiles()?.forEach { f ->
                if (f.isFile && f.name.endsWith(".dat")) {
                    val target = File(dest, f.name)
                    if (!target.exists() || target.length() != f.length()) {
                        f.copyTo(target, overwrite = true)
                        Log.i(TAG, "geo asset ${f.name} -> ${target.absolutePath}")
                    }
                }
            }
        } catch (e: Exception) {
            Log.w(TAG, "ensureAssetSymlinks: ${e.message}")
        }
    }
}
