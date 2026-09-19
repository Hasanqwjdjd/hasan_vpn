import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../services/app_colors.dart';
import '../services/settings_service.dart';

class SettingsScreen extends StatefulWidget {
  final String themeMode;
  final String language;
  final Function(String) onThemeChanged;
  final Function(String) onLanguageChanged;

  const SettingsScreen({
    super.key,
    required this.themeMode,
    required this.language,
    required this.onThemeChanged,
    required this.onLanguageChanged,
  });

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late String _theme;
  late String _lang;
  bool _checkingUpdate = false;

  @override
  void initState() {
    super.initState();
    _theme = widget.themeMode;
    _lang = widget.language;
  }

  String _t(String fa, String en) => _lang == 'fa' ? fa : en;

  Future<void> _openUrl(String url) async {
    try {
      final uri = Uri.parse(url);
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (e) {
      await Clipboard.setData(ClipboardData(text: url));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_t('لینک کپی شد — توی مرورگر پیست کن', 'Link copied — paste in browser')), duration: const Duration(seconds: 4)),
        );
      }
    }
  }

  int _compareVersion(String a, String b) {
    final pa = a.split('.').map((e) => int.tryParse(e) ?? 0).toList();
    final pb = b.split('.').map((e) => int.tryParse(e) ?? 0).toList();
    final len = pa.length > pb.length ? pa.length : pb.length;
    for (var i = 0; i < len; i++) {
      final va = i < pa.length ? pa[i] : 0;
      final vb = i < pb.length ? pb[i] : 0;
      if (va != vb) return va - vb;
    }
    return 0;
  }

  Future<void> _checkUpdate() async {
    setState(() => _checkingUpdate = true);
    try {
      final resp = await http.get(
        Uri.parse('https://api.github.com/repos/Hasanqwjdjd/hasan_vpn/releases/latest'),
        headers: {'Accept': 'application/vnd.github+json'},
      ).timeout(const Duration(seconds: 15));

      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body);
        final rawTag = (data['tag_name'] ?? '').toString();
        final tag = rawTag.replaceAll('v', '').split('.').take(3).join('.');
        final url = data['html_url'] ?? '';

        final cmp = _compareVersion(tag, SettingsService.currentVersion);
        final isNewer = cmp > 0;

        if (!mounted) return;
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: AppColors.elevated(ctx),
            title: Text(
              isNewer ? _t('بروزرسانی موجود است', 'Update Available') : _t('برنامه بروز است', 'App is up to date'),
              style: TextStyle(color: AppColors.fg(ctx)),
            ),
            content: Text(
              isNewer
                  ? _t('نسخه فعلی: ${SettingsService.currentVersion}\nنسخه جدید: $tag', 'Current: ${SettingsService.currentVersion}\nNew: $tag')
                  : _t('نسخه فعلی: ${SettingsService.currentVersion}\nشما آخرین نسخه را دارید ✅', 'Current: ${SettingsService.currentVersion}\nYou have the latest version ✅'),
              style: TextStyle(color: AppColors.muted(ctx), height: 1.7),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text(_t('بستن', 'Close'), style: TextStyle(color: AppColors.muted(ctx))),
              ),
              if (isNewer && url.isNotEmpty)
                TextButton(
                  onPressed: () async {
                    Navigator.pop(ctx);
                    await _openUrl(url);
                  },
                  child: Text(_t('دانلود', 'Download'), style: const TextStyle(color: AppColors.accent)),
                ),
            ],
          ),
        );
      } else {
        _showMsg(_t('گیت‌هاب پاسخ نداد (${resp.statusCode})', 'GitHub did not respond (${resp.statusCode})'));
      }
    } catch (e) {
      _showMsg(_t('خطا در بررسی بروزرسانی', 'Error checking for update'));
    } finally {
      if (mounted) setState(() => _checkingUpdate = false);
    }
  }

  void _showMsg(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg(context),
      appBar: AppBar(
        backgroundColor: AppColors.bg(context),
        elevation: 0,
        iconTheme: IconThemeData(color: AppColors.fg(context)),
        title: Text(_t('تنظیمات', 'Settings'), style: TextStyle(color: AppColors.fg(context))),
        centerTitle: true,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // تم
          _sectionTitle(_t('تم برنامه', 'Theme')),
          _card(
            context,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.brightness_6, color: AppColors.muted(context), size: 20),
                    const SizedBox(width: 12),
                    Text(
                      _theme == 'dark' ? _t('تاریک', 'Dark') : _theme == 'light' ? _t('روشن', 'Light') : _t('سیستم', 'System'),
                      style: TextStyle(color: AppColors.fg(context), fontSize: 14),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    _themeChip(context, 'dark', _t('تاریک', 'Dark')),
                    const SizedBox(width: 6),
                    _themeChip(context, 'light', _t('روشن', 'Light')),
                    const SizedBox(width: 6),
                    _themeChip(context, 'system', _t('سیستم', 'System')),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          // زبان
          _sectionTitle(_t('زبان', 'Language')),
          _card(
            context,
            child: Row(
              children: [
                Icon(Icons.language, color: AppColors.muted(context), size: 20),
                const SizedBox(width: 12),
                Expanded(
                  child: Row(
                    children: [
                      _langChip(context, 'fa', '🇮🇷 فارسی'),
                      const SizedBox(width: 6),
                      _langChip(context, 'en', '🇬🇧 English'),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          // بروزرسانی
          _sectionTitle(_t('بروزرسانی', 'Update')),
          _card(
            context,
            child: InkWell(
              onTap: _checkingUpdate ? null : _checkUpdate,
              child: Row(
                children: [
                  Icon(Icons.system_update_alt, color: AppColors.muted(context), size: 20),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(_t('بررسی بروزرسانی برنامه', 'Check for app updates'), style: TextStyle(color: AppColors.fg(context), fontSize: 14)),
                        const SizedBox(height: 2),
                        Text('v${SettingsService.currentVersion}', style: TextStyle(color: AppColors.muted2(context), fontSize: 11)),
                      ],
                    ),
                  ),
                  if (_checkingUpdate)
                    const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.accent))
                  else
                    Icon(Icons.chevron_left, color: AppColors.muted2(context), size: 20),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          // درباره
          _sectionTitle(_t('درباره برنامه', 'About')),
          _card(
            context,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.code, color: AppColors.muted(context), size: 20),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        _t('حسن - نسخه ${SettingsService.currentVersion}', 'Hasan - v${SettingsService.currentVersion}'),
                        style: TextStyle(color: AppColors.fg(context), fontSize: 14, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  _lang == 'fa'
                      ? 'این برنامه با تلاش حسن کله‌کیری برای یه عده کسخل مثل کباب السگ نوشته شده است'
                      : 'This app was made with the effort of Hasan Kale-kiri for some losers like Kebab Al-Sag',
                  style: TextStyle(color: AppColors.muted(context), fontSize: 12, height: 1.7),
                ),
                const SizedBox(height: 14),
                InkWell(
                  onTap: () => _openUrl('https://github.com/Hasanqwjdjd/hasan_vpn'),
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: AppColors.elevated(context),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppColors.border(context)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.open_in_new, color: AppColors.muted(context), size: 16),
                        const SizedBox(width: 8),
                        Text(_t('مشاهده در گیت‌هاب', 'View on GitHub'), style: TextStyle(color: AppColors.fg(context), fontSize: 13)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 40),
        ],
      ),
    );
  }

  Widget _sectionTitle(String text) => Padding(
        padding: const EdgeInsets.only(right: 8, bottom: 8),
        child: Text(text, style: const TextStyle(color: AppColors.accent, fontSize: 12, fontWeight: FontWeight.w600)),
      );

  Widget _card(BuildContext context, {required Widget child}) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.surface(context),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border(context)),
        ),
        child: child,
      );

  Widget _themeChip(BuildContext context, String value, String label) {
    final active = _theme == value;
    return GestureDetector(
      onTap: () { setState(() => _theme = value); widget.onThemeChanged(value); },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: active ? AppColors.accent.withOpacity(0.15) : AppColors.elevated(context),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: active ? AppColors.accent : AppColors.border(context)),
        ),
        child: Text(label, style: TextStyle(color: active ? AppColors.accent : AppColors.muted(context), fontSize: 11)),
      ),
    );
  }

  Widget _langChip(BuildContext context, String value, String label) {
    final active = _lang == value;
    return Expanded(
      child: GestureDetector(
        onTap: () { setState(() => _lang = value); widget.onLanguageChanged(value); },
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: active ? AppColors.accent.withOpacity(0.15) : AppColors.elevated(context),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: active ? AppColors.accent : AppColors.border(context)),
          ),
          child: Text(label, textAlign: TextAlign.center, style: TextStyle(color: active ? AppColors.accent : AppColors.muted(context), fontSize: 12)),
        ),
      ),
    );
  }
}
