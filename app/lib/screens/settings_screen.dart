import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

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

  Future<void> _checkUpdate() async {
    setState(() => _checkingUpdate = true);
    try {
      final resp = await http.get(
        Uri.parse('https://api.github.com/repos/Hasanqwjdjd/hasan_vpn/releases/latest'),
        headers: {'Accept': 'application/vnd.github+json'},
      ).timeout(const Duration(seconds: 10));

      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body);
        final tag = data['tag_name'] ?? '?';
        final url = data['html_url'] ?? '';

        if (mounted) {
          showDialog(
            context: context,
            builder: (ctx) => AlertDialog(
              backgroundColor: const Color(0xFF1A1D25),
              title: Text(_t('بروزرسانی', 'Update'),
                  style: const TextStyle(color: Colors.white)),
              content: Text(
                _t('آخرین نسخه: $tag\n\nاگه می‌خوای دانلود کنی، دکمه پایین رو بزن.',
                    'Latest version: $tag\n\nTap below to download.'),
                style: const TextStyle(color: Colors.white70),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: Text(_t('بستن', 'Close'),
                      style: const TextStyle(color: Colors.white54)),
                ),
                if (url.isNotEmpty)
                  TextButton(
                    onPressed: () async {
                      Navigator.pop(ctx);
                      final uri = Uri.parse(url);
                      if (await canLaunchUrl(uri)) {
                        await launchUrl(uri,
                            mode: LaunchMode.externalApplication);
                      }
                    },
                    child: Text(_t('دانلود', 'Download'),
                        style: const TextStyle(color: Color(0xFF3DCF9A))),
                  ),
              ],
            ),
          );
        }
      } else {
        _showMsg(_t('گیت‌هاب پاسخ نداد', 'GitHub did not respond'));
      }
    } catch (e) {
      _showMsg(_t('خطا در بررسی بروزرسانی', 'Error checking for update'));
    } finally {
      if (mounted) setState(() => _checkingUpdate = false);
    }
  }

  void _showMsg(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _openGithub() async {
    final uri = Uri.parse('https://github.com/Hasanqwjdjd/hasan_vpn');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF08090C),
      appBar: AppBar(
        backgroundColor: const Color(0xFF08090C),
        elevation: 0,
        title: Text(_t('تنظیمات', 'Settings'),
            style: const TextStyle(color: Colors.white)),
        centerTitle: true,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ═══ تم ═══
          _sectionTitle(_t('تم برنامه', 'Theme')),
          _card(
            child: Row(
              children: [
                const Icon(Icons.brightness_6, color: Colors.white70, size: 20),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _theme == 'dark'
                            ? _t('تاریک', 'Dark')
                            : _theme == 'light'
                                ? _t('روشن', 'Light')
                                : _t('سیستم', 'System'),
                        style: const TextStyle(
                            color: Colors.white, fontSize: 14),
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          _themeChip('dark', _t('تاریک', 'Dark')),
                          const SizedBox(width: 6),
                          _themeChip('light', _t('روشن', 'Light')),
                          const SizedBox(width: 6),
                          _themeChip('system', _t('سیستم', 'System')),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // ═══ زبان ═══
          _sectionTitle(_t('زبان', 'Language')),
          _card(
            child: Row(
              children: [
                const Icon(Icons.language, color: Colors.white70, size: 20),
                const SizedBox(width: 12),
                Expanded(
                  child: Row(
                    children: [
                      _langChip('fa', '🇮🇷 فارسی'),
                      const SizedBox(width: 6),
                      _langChip('en', '🇬🇧 English'),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // ═══ بروزرسانی ═══
          _sectionTitle(_t('بروزرسانی', 'Update')),
          _card(
            child: InkWell(
              onTap: _checkingUpdate ? null : _checkUpdate,
              child: Row(
                children: [
                  const Icon(Icons.system_update_alt,
                      color: Colors.white70, size: 20),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _t('بررسی بروزرسانی برنامه',
                          'Check for app updates'),
                      style: const TextStyle(color: Colors.white, fontSize: 14),
                    ),
                  ),
                  if (_checkingUpdate)
                    const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Color(0xFF3DCF9A)),
                    )
                  else
                    const Icon(Icons.chevron_left,
                        color: Colors.white38, size: 20),
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),

          // ═══ درباره ═══
          _sectionTitle(_t('درباره برنامه', 'About')),
          _card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.code, color: Colors.white70, size: 20),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        _t('حسن - نسخه ۵.۰', 'Hasan - v5.0'),
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  _lang == 'fa'
                      ? 'این برنامه با تلاش حسن کله‌کیری برای یه عده کسخل مثل کباب السگ نوشته شده است'
                      : 'This app was made with the effort of Hasan Kale-kiri for some losers like Kebab Al-Sag',
                  style: const TextStyle(
                      color: Colors.white54, fontSize: 12, height: 1.7),
                ),
                const SizedBox(height: 12),
                InkWell(
                  onTap: _openGithub,
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF12141A),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.white12),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.open_in_new,
                            color: Colors.white70, size: 16),
                        const SizedBox(width: 6),
                        Text(
                          _t('گیت‌هاب برنامه', 'GitHub Repository'),
                          style: const TextStyle(
                              color: Colors.white70, fontSize: 12),
                        ),
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
        child: Text(
          text,
          style: const TextStyle(
              color: Colors.white54,
              fontSize: 12,
              fontWeight: FontWeight.w600),
        ),
      );

  Widget _card({required Widget child}) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFF12141A),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white12),
        ),
        child: child,
      );

  Widget _themeChip(String value, String label) {
    final active = _theme == value;
    return GestureDetector(
      onTap: () {
        setState(() => _theme = value);
        widget.onThemeChanged(value);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: active
              ? const Color(0xFF3DCF9A).withOpacity(0.15)
              : const Color(0xFF1A1D25),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: active ? const Color(0xFF3DCF9A) : Colors.white12,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: active ? const Color(0xFF3DCF9A) : Colors.white54,
            fontSize: 11,
          ),
        ),
      ),
    );
  }

  Widget _langChip(String value, String label) {
    final active = _lang == value;
    return Expanded(
      child: GestureDetector(
        onTap: () {
          setState(() => _lang = value);
          widget.onLanguageChanged(value);
        },
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: active
                ? const Color(0xFF3DCF9A).withOpacity(0.15)
                : const Color(0xFF1A1D25),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: active ? const Color(0xFF3DCF9A) : Colors.white12,
            ),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: active ? const Color(0xFF3DCF9A) : Colors.white54,
              fontSize: 12,
            ),
          ),
        ),
      ),
    );
  }
}
