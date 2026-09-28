package com.hasan.hasan_vpn

import java.io.Serializable

/** Runtime state broadcast by [PsiphonRuntimeService] for one profile. */
data class PsiphonStatus(
    val guid: String,
    val state: String,
) : Serializable {
    companion object {
        const val CONNECTING = "CONNECTING"
        const val CONNECTED = "CONNECTED"
        const val FAILED = "FAILED"
        const val STOPPED = "STOPPED"
    }
}
