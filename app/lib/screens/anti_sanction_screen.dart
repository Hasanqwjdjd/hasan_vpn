import 'package:flutter/material.dart';

import '../services/anti_sanction_service.dart';
import '../services/app_colors.dart';

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
    setState(() => _filterBypass = v);
    await AntiSanctionService.setFilterBypass(v);
  }

  Future<void> _setGemini(bool v) async {
    setState(() => _geminiFix = v);
    await AntiSanctionService.setGeminiFix(v);
  }

  Future<void> _setUs(bool v) async {
    setState(() => _geminiUsExit = v);
    await AntiSanctionService.setGeminiUsExit(v);
  }

  @override
  Widget build(BuildContext context) {
    final fg = AppColors.fg(context);
    final muted = AppColors.muted(context);
    final surface = AppColors.surface(context);

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
                Text(
                  _t(
                    'این گزینه‌ها روی کانفیگ Xray بعدی اعمال می‌شوند. بعد از تغییر، یک‌بار قطع و وصل کنید.',
                    'These apply on the next Xray config. Reconnect after changing.',
                  ),
                  style: TextStyle(color: muted, fontSize: 12),
                ),
                const SizedBox(height: 12),
                Card(
                  color: surface,
                  child: SwitchListTile(
                    title: Text(
                      'رفع فیلتر کانفیگ‌ها (کلادفلر)',
                      style: TextStyle(color: fg, fontSize: 14),
                    ),
                    subtitle: Text(
                      _t('DNS/مسیر تمیزتر برای کلادفلر',
                          'Cleaner DNS/route for Cloudflare'),
                      style: TextStyle(color: muted, fontSize: 11),
                    ),
                    value: _filterBypass,
                    onChanged: _setFilter,
                    activeColor: AppColors.accent,
                  ),
                ),
                Card(
                  color: surface,
                  child: SwitchListTile(
                    title: Text(
                      'رفع مشکل جمناي و برنامه‌های گوگل',
                      style: TextStyle(color: fg, fontSize: 14),
                    ),
                    subtitle: Text(
                      _t('هدایت دامنه‌های Gemini/Google AI از پروکسی',
                          'Steer Gemini/Google AI domains via proxy'),
                      style: TextStyle(color: muted, fontSize: 11),
                    ),
                    value: _geminiFix,
                    onChanged: _setGemini,
                    activeColor: AppColors.accent,
                  ),
                ),
                Card(
                  color: surface,
                  child: SwitchListTile(
                    title: Text(
                      'خروجی آمریکا برای جمناي',
                      style: TextStyle(color: fg, fontSize: 14),
                    ),
                    subtitle: Text(
                      _t('ترجیح DNS عمومی (۸.۸.۸.۸ / ۱.۱.۱.۱)',
                          'Prefer public US-friendly DNS'),
                      style: TextStyle(color: muted, fontSize: 11),
                    ),
                    value: _geminiUsExit,
                    onChanged: _setUs,
                    activeColor: AppColors.accent,
                  ),
                ),
              ],
            ),
    );
  }
}
