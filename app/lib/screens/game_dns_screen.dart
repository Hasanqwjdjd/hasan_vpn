import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/game_dns.dart';
import '../services/app_colors.dart';
import '../services/settings_service.dart';

/// صفحه‌ی انتخاب DNS مخصوص بازی.
/// فقط در حالت «فقط پروکسی» روی کانفیگ Xray اعمال می‌شود.
class GameDnsScreen extends StatefulWidget {
  final String language;

  const GameDnsScreen({super.key, this.language = 'fa'});

  @override
  State<GameDnsScreen> createState() => _GameDnsScreenState();
}

class _GameDnsScreenState extends State<GameDnsScreen> {
  int? _activeIndex;
  String _ipPref = 'ipv4';

  bool get _isFa => widget.language == 'fa';
  String _t(String fa, String en) => _isFa ? fa : en;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final primary = await SettingsService.getGameDnsPrimary();
    final pref = await SettingsService.getDnsIpPreference();
    if (!mounted) return;
    setState(() {
      _ipPref = pref;
      _activeIndex = kGameDnsList.indexWhere((d) => d.primary == primary);
      if (_activeIndex == -1) _activeIndex = null;
    });
  }

  Future<void> _select(GameDns dns) async {
    await SettingsService.setGameDns(dns.primary, dns.secondary);
    if (!mounted) return;
    setState(() => _activeIndex = kGameDnsList.indexOf(dns));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(_t('DNS فعال شد', 'DNS activated')),
        duration: const Duration(seconds: 1),
      ),
    );
  }

  Future<void> _clear() async {
    await SettingsService.clearGameDns();
    if (!mounted) return;
    setState(() => _activeIndex = null);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(_t('DNS پیش‌فرض فعال شد', 'Default DNS restored')),
        duration: const Duration(seconds: 1),
      ),
    );
  }

  void _copy(GameDns dns) {
    Clipboard.setData(ClipboardData(text: '${dns.primary}, ${dns.secondary}'));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(_t('کپی شد', 'Copied')),
        duration: const Duration(seconds: 1),
      ),
    );
  }

  Future<void> _setIpPref(String value) async {
    await SettingsService.setDnsIpPreference(value);
    if (!mounted) return;
    setState(() => _ipPref = value);
  }

  Widget _ipChip(String value, String label) {
    final active = _ipPref == value;
    return Expanded(
      child: GestureDetector(
        onTap: () => _setIpPref(value),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: active
                ? AppColors.accent.withOpacity(0.15)
                : AppColors.elevated(context),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: active ? AppColors.accent : AppColors.border(context),
            ),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: active ? AppColors.accent : AppColors.muted(context),
              fontSize: 12.5,
              fontWeight: active ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg(context),
      appBar: AppBar(
        backgroundColor: AppColors.bg(context),
        elevation: 0,
        iconTheme: IconThemeData(color: AppColors.fg(context)),
        title: Text(
          _t('DNS بازی', 'Game DNS'),
          style: TextStyle(color: AppColors.fg(context)),
        ),
        actions: [
          if (_activeIndex != null)
            IconButton(
              icon: const Icon(Icons.clear, color: AppColors.danger),
              tooltip: _t('حذف انتخاب', 'Clear'),
              onPressed: _clear,
            ),
        ],
      ),
      body: Column(
        children: [
          Container(
            margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.surface(context),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.border(context)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _t('نسخه‌ی IP', 'IP version'),
                  style: TextStyle(
                    color: AppColors.muted(context),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    _ipChip('ipv4', 'IPv4'),
                    const SizedBox(width: 6),
                    _ipChip('ipv6', 'IPv6'),
                    const SizedBox(width: 6),
                    _ipChip('both', _t('هر دو', 'Both')),
                  ],
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.all(12),
            margin: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.accent.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.accent.withOpacity(0.3)),
            ),
            child: Row(
              children: [
                const Icon(Icons.info_outline,
                    color: AppColors.accent, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _t(
                      'این DNS فقط در حالت «فقط پروکسی» اعمال می‌شود. اول از تنظیمات، حالت اتصال را روی «فقط پروکسی» بگذار و بعد یکی از این‌ها را انتخاب کن.',
                      'These DNS only apply in "proxy only" mode. First set the connection mode to "proxy only" in Settings, then pick one here.',
                    ),
                    style: TextStyle(
                      color: AppColors.fg(context),
                      fontSize: 12,
                      height: 1.6,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              itemCount: kGameDnsList.length,
              itemBuilder: (_, i) {
                final dns = kGameDnsList[i];
                final active = i == _activeIndex;
                return Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  decoration: BoxDecoration(
                    color: active
                        ? AppColors.accent.withOpacity(0.1)
                        : AppColors.surface(context),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: active
                          ? AppColors.accent
                          : AppColors.border(context),
                      width: active ? 1.5 : 1,
                    ),
                  ),
                  child: ListTile(
                    onTap: () => _select(dns),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 4,
                    ),
                    title: Text(
                      dns.name,
                      style: TextStyle(
                        color: AppColors.fg(context),
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    subtitle: Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        dns.primaryV6 != null
                            ? '${dns.primary}\n${dns.secondary}\n${dns.primaryV6}\n${dns.secondaryV6}'
                            : '${dns.primary}\n${dns.secondary}',
                        style: TextStyle(
                          color: AppColors.muted2(context),
                          fontSize: 11,
                          height: 1.5,
                        ),
                      ),
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: Icon(Icons.copy,
                              color: AppColors.muted(context), size: 18),
                          onPressed: () => _copy(dns),
                          tooltip: _t('کپی', 'Copy'),
                        ),
                        if (active)
                          const Icon(Icons.check_circle,
                              color: AppColors.accent, size: 22)
                        else
                          Icon(Icons.radio_button_unchecked,
                              color: AppColors.muted2(context), size: 22),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
