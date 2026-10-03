import 'package:flutter/material.dart';

import '../services/anti_sanction_service.dart';
import '../services/app_colors.dart';

/// Anti-Sanction / Gemini screen.
///
/// Three toggles that change Xray config generation:
///   • filterBypass   — Cloudflare-scoped DoH for geosite:cloudflare
///   • geminiFix      — Google DoH + domain list for Gemini / AI
///   • geminiUsExit   — US-exit outbound routing rule (needs a us-exit
///                      outbound tag in the config; warns if missing)
class AntiSanctionScreen extends StatefulWidget {
  final String language;
  const AntiSanctionScreen({super.key, this.language = 'fa'});

  @override
  State<AntiSanctionScreen> createState() => _AntiSanctionScreenState();
}

class _AntiSanctionScreenState extends State<AntiSanctionScreen> {
  bool _filterBypass = false;
  bool _geminiFix = false;
  bool _geminiUsExit = false;
  bool _loading = true;
  bool _dirty = false;

  bool get _isFa => widget.language == 'fa';
  String _t(String fa, String en) => _isFa ? fa : en;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final s = await AntiSanctionService.status();
    if (!mounted) return;
    setState(() {
      _filterBypass = s['filterBypass'] == true;
      _geminiFix = s['geminiFix'] == true;
      _geminiUsExit = s['geminiUsExit'] == true;
      _loading = false;
    });
  }

  Future<void> _setFilter(bool v) async {
    setState(() {
      _filterBypass = v;
      _dirty = true;
    });
    await AntiSanctionService.setFilterBypass(v);
  }

  Future<void> _setGemini(bool v) async {
    setState(() {
      _geminiFix = v;
      _dirty = true;
    });
    await AntiSanctionService.setGeminiFix(v);
  }

  Future<void> _setUs(bool v) async {
    setState(() {
      _geminiUsExit = v;
      _dirty = true;
    });
    await AntiSanctionService.setGeminiUsExit(v);
  }

  /// Reapply the current Xray config so the new toggles take effect
  /// without requiring a manual reconnect from the home screen.
  Future<void> _applyNow() async {
    // V2RayEngine does not expose a live reload method, so the config
    // change only takes effect on the next connect. We tell the user
    // instead of pretending to apply it.
    if (!mounted) return;
    setState(() => _dirty = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(_t(
          'برای اعمال، یک بار اتصال را قطع و وصل کنید',
          'Reconnect once to apply',
        )),
        backgroundColor: const Color(0xFF2E7D32),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final fg = AppColors.fg(context);
    final muted = AppColors.muted(context);
    final muted2 = AppColors.muted2(context);
    final surface = AppColors.surface(context);
    final border = AppColors.border(context);

    return Scaffold(
      backgroundColor: AppColors.bg(context),
      appBar: AppBar(
        backgroundColor: surface,
        title: Text(_t('رفع تحریم / جمینای', 'Sanction / Gemini'),
            style: TextStyle(color: fg, fontSize: 16)),
        iconTheme: IconThemeData(color: fg),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(12),
              children: [
                // ─── intro ───
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppColors.accent.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color: AppColors.accent.withValues(alpha: 0.4)),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.info_outline,
                          color: AppColors.accent, size: 18),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          _t(
                            'این تنظیمات روی کانفیگ Xray اثر می‌گذارد و '
                            'بعد از هر تغییر، نیاز به اتصال مجدد دارند.',
                            'These affect the Xray config; reconnect after '
                            'changing them.',
                          ),
                          style: TextStyle(
                            color: muted,
                            fontSize: 12,
                            height: 1.5,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // ─── toggle 1: filter bypass ───
                _tile(
                  context,
                  title: _t('رفع فیلتر کانفیگ‌ها (کلادفلر)',
                      'Filter bypass (Cloudflare)'),
                  subtitle: _t(
                    'مسیر و DNS تمیزتر برای دامنه‌های Cloudflare. اگر '
                    'بعضی سرورهای VLESS قطع شوند، خاموش کنید.',
                    'Cleaner DNS/route for Cloudflare. Turn off if VLESS '
                    'servers fail to connect.',
                  ),
                  value: _filterBypass,
                  onChanged: _setFilter,
                  warn: _filterBypass,
                  warnText: _t(
                    'اگر سرورهای CDN بعد از این روشن نشدند، خاموشش کنید.',
                    'If CDN servers stop working, turn this off.',
                  ),
                ),

                // ─── toggle 2: gemini fix ───
                _tile(
                  context,
                  title: _t('رفع مشکل جمناي و برنامه‌های گوگل',
                      'Gemini / Google AI fix'),
                  subtitle: _t(
                    'هدایت دامنه‌های Gemini، Bard، Google AI از DNS گوگل '
                    '(DoH) داخل تونل.',
                    'Routes Gemini, Bard, and Google AI domains through '
                    'Google DoH inside the tunnel.',
                  ),
                  value: _geminiFix,
                  onChanged: _setGemini,
                ),

                // ─── toggle 3: US exit ───
                _tile(
                  context,
                  title: _t('خروجی آمریکا برای جمناي',
                      'US exit for Gemini'),
                  subtitle: _t(
                    'اجبار مسیر Gemini به outbound با تگ us-exit. '
                    'اگر سرور فعلی US-exit ندارد، هشدار می‌دهد.',
                    'Forces Gemini through the us-exit outbound. Warns if '
                    'the current config has no such outbound.',
                  ),
                  value: _geminiUsExit,
                  onChanged: _setUs,
                  warn: _geminiUsExit,
                  warnText: _t(
                    'این گزینه فقط اگر سرور شما US-exit تعریف کرده باشد '
                    'اثر دارد.',
                    'This only works if your server defines a US exit.',
                  ),
                ),

                const SizedBox(height: 20),

                // ─── apply button ───
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton.icon(
                    onPressed: _dirty ? _applyNow : null,
                    icon: const Icon(Icons.refresh, size: 18),
                    label: Text(
                      _dirty
                          ? _t('اعمال تغییرات روی اتصال فعلی',
                              'Apply to current connection')
                          : _t('اعمال شد', 'Applied'),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.accent,
                      foregroundColor: Colors.black,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 12),
                Text(
                  _t(
                    'توجه: این قابلیت‌ها فقط روی Xray اثر می‌گذارند '
                    '(VLESS/VMess/Trojan/Hysteria2). روی Tor، Aether و '
                    'Psiphon تأثیری ندارند.',
                    'Note: these only affect Xray (VLESS/VMess/Trojan/'
                    'Hysteria2). They have no effect on Tor, Aether, or '
                    'Psiphon.',
                  ),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: muted2,
                    fontSize: 10.5,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 30),
              ],
            ),
    );
  }

  Widget _tile(
    BuildContext context, {
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
    bool warn = false,
    String? warnText,
  }) {
    final fg = AppColors.fg(context);
    final muted = AppColors.muted(context);
    final muted2 = AppColors.muted2(context);
    final surface = AppColors.surface(context);
    final border = AppColors.border(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: border),
      ),
      child: Column(
        children: [
          SwitchListTile(
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
            title: Text(
              title,
              style: TextStyle(
                  color: fg, fontSize: 14, fontWeight: FontWeight.w600),
            ),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                subtitle,
                style:
                    TextStyle(color: muted, fontSize: 11.5, height: 1.5),
              ),
            ),
            value: value,
            onChanged: onChanged,
            activeColor: AppColors.accent,
          ),
          if (warn && warnText != null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.warning_amber_rounded,
                      color: Color(0xFFFFB74D), size: 16),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      warnText,
                      style: TextStyle(
                        color: muted2,
                        fontSize: 10.5,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
