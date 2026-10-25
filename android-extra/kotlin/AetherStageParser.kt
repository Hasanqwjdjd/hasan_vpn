package com.hasan.hasan_vpn

/**
 * پارسر مرحله‌ای خروجی هسته‌ی Aether — پورت ۱:۱ از MLM VPN
 * (app/src/main/java/com/mlmvpn/core/aether/AetherStage.kt، نسخه‌ی 1.2.42).
 *
 * باینری libaether.so (aether 1.4.0 — همان بیلدی که MLM توزیع می‌کند) خطوط
 * لاگ پایدار تولید می‌کند؛ این کلاس آن‌ها را به یک واژگان محدود از مراحل
 * ترجمه می‌کند تا UI بتواند پیشرفت اتصال را قدم‌به‌قدم نشان دهد و لایه‌ی
 * اتصال بفهمد که «واقعاً» به CONNECTED رسیده یا نه.
 *
 * نکات هم‌ارزی با نسخه‌ی MLM:
 *  - فهرست مراحل یکی است؛ desktop driver (aether-manager.js) هم همین را دارد.
 *  - «provision» مانند «identity» نمایش داده می‌شود.
 *  - مراحل پایانی (failed/crashed) در forUi مقدار null می‌دهند.
 */
enum class AetherStage(val fa: String) {
    IDLE("خاموش"),
    STARTING("در حال راه‌اندازی موتور"),
    IDENTITY("هویت"),
    QUICKCHECK("بررسی سرور قبلی"),
    SCAN("اسکن سرور"),
    SELECTED("انتخاب سرور"),
    HANDSHAKE("دست‌دادن"),
    TUNNEL("برقراری تونل"),
    VALIDATE("اعتبارسنجی عبور داده"),
    CONNECTED("متصل شد"),
    RECONNECTING("قطع شد — اتصال مجدد"),
    STOPPED("متوقف شد"),
    FAILED("خطا"),
    CRASHED("کرش موتور");

    /**
     * جایگاه روی مسیر سالم، یا 1- برای مراحل خارج از مسیر.
     *
     * لازم است چون خطوط لاگ موتور همیشه به‌ترتیب علّی نمی‌رسند؛ مثلاً
     * «masque tunnel validated» از تسک تونل و «socks5 server listening»
     * از تسک دیگر می‌آید و هرکدام ممکن است اول برسند. بدون رتبه، یک خط
     * دیرهنگام UI را از CONNECTED به VALIDATE برمی‌گرداند و چون connected
     * دقیقاً یعنی stage==CONNECTED، تونلِ سالم «قطع‌شده» گزارش می‌شد در
     * حالی که پورت SOCKS باز بود.
     *
     * پس فقط سیگنال‌های صریحِ قطع‌شدن (isRegression) مجاز به حرکت به عقب‌اند.
     */
    val progressRank: Int
        get() = when (this) {
            STARTING -> 0
            IDENTITY -> 1
            QUICKCHECK -> 2
            SCAN -> 3
            SELECTED -> 4
            HANDSHAKE -> 5
            TUNNEL -> 6
            VALIDATE -> 7
            CONNECTED -> 8
            else -> -1
        }

    /** آیا رسیدن به این مرحله یعنی تونل واقعاً از دست رفته/هرگز ساخته نشد؟ */
    val isRegression: Boolean
        get() = this == RECONNECTING || this == FAILED || this == CRASHED || this == STOPPED

    /** نگاشت معنایی برای UI. */
    fun forUi(): String? = when (this) {
        STARTING -> "identity"
        RECONNECTING -> "tunnel"
        IDLE, STOPPED, FAILED, CRASHED -> null
        else -> name.lowercase()
    }
}

/** جزئیات استخراج‌شده از یک خط لاگ. */
data class AetherLogDetail(
    val server: String? = null,   // "162.159.193.10:2408"
    val rtt: String? = null,      // "117ms"
    val profile: String? = null,  // پروفایل مبهم‌سازی (firewall, balanced, ...)
    val socks: String? = null,    // "127.0.0.1:1819"
)

object AetherStageParser {

    // قواعد مرحله. از خاص‌ترین به عمومی؛ اولین تطابق برنده است.
    // این‌ها پورت مستقیم STAGE_RULES از MLM هستند و با خطوط لاگِ
    // تأییدشده‌ی باینری aether 1.4.0 (strings) مطابقت دارند.
    private val STAGE_RULES = listOf(
        Triple(Regex("""no (warp|masque) identity found|provisioning dedicated""", RegexOption.IGNORE_CASE),
            AetherStage.IDENTITY, "ساخت هویت جدید روی کلادفلر"),
        Triple(Regex("""enrolling masque key""", RegexOption.IGNORE_CASE),
            AetherStage.IDENTITY, "ثبت کلید MASQUE"),
        Triple(Regex("""loaded existing (warp|masque) identity""", RegexOption.IGNORE_CASE),
            AetherStage.IDENTITY, "هویت ذخیره‌شده بارگذاری شد"),
        Triple(Regex("""identity ready: device=(\S+)""", RegexOption.IGNORE_CASE),
            AetherStage.IDENTITY, "هویت آماده است"),
        Triple(Regex("""verifying cached gateway|verifying cached wireguard endpoint""", RegexOption.IGNORE_CASE),
            AetherStage.QUICKCHECK, "بررسی گیت‌وی قبلی"),
        Triple(Regex("""cached (gateway|endpoint) .* still works""", RegexOption.IGNORE_CASE),
            AetherStage.QUICKCHECK, "گیت‌وی قبلی سالم است — بدون اسکن"),
        Triple(Regex("""cached (gateway|endpoint) .* no longer works""", RegexOption.IGNORE_CASE),
            AetherStage.SCAN, "گیت‌وی قبلی از کار افتاده — اسکن مجدد"),
        Triple(Regex("""candidate ok (\S+):(\d+)""", RegexOption.IGNORE_CASE),
            AetherStage.SCAN, "سرور سالم پیدا شد"),
        Triple(Regex("""hunting for a working (masque gateway|wireguard endpoint)""", RegexOption.IGNORE_CASE),
            AetherStage.SCAN, "جستجوی سرور سالم"),
        Triple(Regex("""selected (masque gateway|wireguard endpoint) (\S+):(\d+)""", RegexOption.IGNORE_CASE),
            AetherStage.SELECTED, "سرور انتخاب شد"),
        Triple(Regex("""using forced peer""", RegexOption.IGNORE_CASE),
            AetherStage.SELECTED, "استفاده از سرور دستی"),
        Triple(Regex("""using cloudflare edge""", RegexOption.IGNORE_CASE),
            AetherStage.SELECTED, "اتصال به لبه‌ی کلادفلر"),
        Triple(Regex("""confirming wireguard handshake""", RegexOption.IGNORE_CASE),
            AetherStage.HANDSHAKE, "دست‌دادن WireGuard"),
        Triple(Regex("""handshake successful""", RegexOption.IGNORE_CASE),
            AetherStage.HANDSHAKE, "دست‌دادن موفق"),
        Triple(Regex("""establishing (outer|inner) warp tunnel""", RegexOption.IGNORE_CASE),
            AetherStage.HANDSHAKE, "برقراری تونل WARP"),
        Triple(Regex("""inner endpoint tunneled through outer warp""", RegexOption.IGNORE_CASE),
            AetherStage.HANDSHAKE, "تونل داخلی از دل تونل بیرونی رد شد"),
        Triple(Regex("""masque transport: http/3""", RegexOption.IGNORE_CASE),
            AetherStage.TUNNEL, "تونل MASQUE روی HTTP/3 (QUIC)"),
        Triple(Regex("""masque transport: http/2""", RegexOption.IGNORE_CASE),
            AetherStage.TUNNEL, "تونل MASQUE روی HTTP/2 (TCP)"),
        Triple(Regex("""validating (masque )?data-plane""", RegexOption.IGNORE_CASE),
            AetherStage.VALIDATE, "اعتبارسنجی عبور واقعی داده"),
        Triple(Regex("""(masque|wireguard) tunnel validated""", RegexOption.IGNORE_CASE),
            AetherStage.VALIDATE, "عبور داده تأیید شد"),
        Triple(Regex("""tunnel validated \(end-to-end data confirmed\); exposing socks5""", RegexOption.IGNORE_CASE),
            AetherStage.CONNECTED, "متصل شد — پراکسی آماده است"),
        Triple(Regex("""socks5 (server )?(listening|exposed) on""", RegexOption.IGNORE_CASE),
            AetherStage.CONNECTED, "متصل شد — پراکسی آماده است"),
        Triple(Regex("""tunnel (closed|ended|exited).*(reconnect)""", RegexOption.IGNORE_CASE),
            AetherStage.RECONNECTING, "قطع شد — اتصال مجدد"),
        Triple(Regex("""no usable masque gateway found""", RegexOption.IGNORE_CASE),
            AetherStage.SCAN, "گیت‌وی سالمی پیدا نشد — اسکن مجدد"),
        Triple(Regex("""found no data-plane endpoint.*trying next profile""", RegexOption.IGNORE_CASE),
            AetherStage.SCAN, "این پروفایل جواب نداد — پروفایل بعدی"),
        Triple(Regex("""prober: no clean endpoint found|no clean endpoint found""", RegexOption.IGNORE_CASE),
            AetherStage.FAILED, "هیچ اندپوینت سالمی پیدا نشد"),
        Triple(Regex("""handshake failed""", RegexOption.IGNORE_CASE),
            AetherStage.FAILED, "دست‌دادن ناموفق"),
        Triple(Regex("""scan deadline reached with no (endpoint|gateway)""", RegexOption.IGNORE_CASE),
            AetherStage.FAILED, "مهلت اسکن تمام شد — سرور سالمی پیدا نشد"),
        Triple(Regex("""tunnel exited before (data-plane )?validation""", RegexOption.IGNORE_CASE),
            AetherStage.SCAN, "تونل قبل از اعتبارسنجی بسته شد — کاندید بعدی"),

        // واچ‌داگ WireGuard (wireguard.rs). این خط کلمه‌ی reconnect ندارد،
        // پس بدون این قاعده UI در تمام چرخه‌ی stale/reconnect سبز می‌ماند و
            // تنها علامت، تونلِ سبزِ بی‌ترافیك است — دقیقاً همان باگ گزارش‌شده.
        Triple(Regex("""no valid data from peer|tunnel considered dead|wireguard tunnel stale""", RegexOption.IGNORE_CASE),
            AetherStage.RECONNECTING, "پاسخی از سرور نرسید — اتصال مجدد"),
        Triple(Regex("""no usable.*(endpoint|gateway) found""", RegexOption.IGNORE_CASE),
            AetherStage.SCAN, "اندپوینت سالمی پیدا نشد — اسکن مجدد"),
        Triple(Regex("""last known-good .* no longer responds|rescanning|scanning fresh""", RegexOption.IGNORE_CASE),
            AetherStage.SCAN, "اسکن مجدد"),
        // Catch-all، آخرِ همه: هر خط خاص‌تر بالاتر قانون خودش را دارد.
        Triple(Regex("""tunnel (closed|ended|exited)""", RegexOption.IGNORE_CASE),
            AetherStage.RECONNECTING, "تونل قطع شد — اتصال مجدد"),
    )

    // چتِ هر-بسته که در سطح debug بی‌ارزش می‌شود؛ شمردن به‌جای چاپ، لاگ را
    // روی اتصال شلوغ خوانا نگه می‌دارد و مانع پرشدن لوله‌ی stdout می‌شود.
    private val NOISE_RE = Regex(
        """\] (junk(\[\d+\]|_after\[\d+\])? sent|signature i\d sent|sending \d+ junk|obfuscation pre-handshake complete|verify recv \d+ bytes|recv \d+ bytes (from|type=)|tls verification: )"""
    )

    fun isNoise(line: String): Boolean = NOISE_RE.containsMatchIn(line)

    /**
     * خطوط ردشدن کاندید از aether::prober (سطح TRACE)، مثلاً:
     *   `probe 162.159.192.1:443 -> timed out`
     * به‌ازای هر کاندید ردشده یکی از این‌ها می‌آید — هزاران بار در هر اسکن —
     * پس هرگز تک‌تک لاگ نمی‌شوند؛ فقط دلیلشان شمرده می‌شود تا هیستوگرام
     * دلایل گزارش شود (تفاوت «UDP بلاک است» با «TLS دستکاری می‌شود»).
     */
    private val PROBE_FAIL_RE =
        Regex("""\b(?:h2 )?probe \S+ -> (.+)$""", RegexOption.IGNORE_CASE)

    fun probeFailureReason(line: String): String? =
        PROBE_FAIL_RE.find(line)?.groupValues?.get(1)?.trim()?.take(80)

    /**
     * @return null اگر هیچ قاعده‌ای نخورد (بدون تغییر مرحله)؛ در غیر این صورت
     * مرحله + برچسب فارسی.
     */
    fun classify(line: String): Pair<AetherStage, String>? {
        for ((re, stage, fa) in STAGE_RULES) {
            if (re.containsMatchIn(line)) return stage to fa
        }
        return null
    }

    /**
     * فیلدهای نمایشی را از خط بیرون می‌کشد: IP انتخابی، RTT، پروفایل،
     * نشانی SOCKS در حال گوش‌دادن.
     */
    fun extractDetail(line: String): AetherLogDetail {
        val selected = Regex(
            """selected (?:MASQUE gateway|WireGuard endpoint) (\S+?):(\d+)(?:.*rtt ([^)]+))?""",
            RegexOption.IGNORE_CASE,
        ).find(line)
        if (selected != null) {
            val host = selected.groupValues[1]
            val port = selected.groupValues[2]
            val rtt = selected.groupValues[3].ifEmpty { null }
            return AetherLogDetail(server = "$host:$port", rtt = rtt)
        }
        val edge = Regex("""using cloudflare edge (\S+)""", RegexOption.IGNORE_CASE).find(line)
        if (edge != null) return AetherLogDetail(server = edge.groupValues[1])
        val prof = Regex(
            """obfuscation profile: (\S+)|aethernoize (?:primary )?profile: (\S+)|noize profile: (\S+)""",
            RegexOption.IGNORE_CASE,
        ).find(line)
        if (prof != null) {
            val p = listOf(prof.groupValues[1], prof.groupValues[2], prof.groupValues[3])
                .firstOrNull { it.isNotEmpty() }
            return AetherLogDetail(profile = p)
        }
        val socks = Regex("""socks5 (?:server )?(?:listening|exposed) on (\S+)""", RegexOption.IGNORE_CASE).find(line)
        if (socks != null) return AetherLogDetail(socks = socks.groupValues[1])
        return AetherLogDetail()
    }

    /** تشخیص panic واقعی Rust از خروج تمیز. */
    fun isPanicLine(line: String): Boolean =
        Regex("""panicked at|stack backtrace|RUST_BACKTRACE""", RegexOption.IGNORE_CASE)
            .containsMatchIn(line)

    /** شکست تماس API ثبت‌نام کلادفلر (شبکه‌ی فیلترشده). */
    fun isApiFailLine(line: String): Boolean =
        Regex("""Api\(.*cloudflareclient\.com|error sending request for url.*cloudflareclient""", RegexOption.IGNORE_CASE)
            .containsMatchIn(line)
}
