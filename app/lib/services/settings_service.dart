import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/app_colors.dart';
import '../services/settings_service.dart';

/// صفحه‌ی «پراکسی هر برنامه» — سه حالت مثل v2rayNG.
class PerAppProxyScreen extends StatefulWidget {
  const PerAppProxyScreen({super.key, required this.language});
  final String language;

  @override
  State<PerAppProxyScreen> createState() => _PerAppProxyScreenState();
}

class _PerAppProxyScreenState extends State<PerAppProxyScreen> {
  static const _ch = MethodChannel('com.hasan.hasan_vpn/device');
  bool _loading = true;
  List<Map<String, dynamic>> _apps = [];
  final Set<String> _selected = {};
  String _mode = 'all'; // all | whitelist | blacklist
  String _q = '';

  String _t(String fa, String en) =>
      widget.language.startsWith('fa') ? fa : en;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final mode = await SettingsService.getProxyMode();
    final selected = await SettingsService.getBlockedApps();
    _mode = mode;
    _selected.addAll(selected);

    try {
      final raw = await _ch.invokeMethod<List<dynamic>>('listApps');
      final list = <Map<String, dynamic>>[];
      if (raw != null) {
        for (final e in raw) {
          if (e is Map) {
            list.add(Map<String, dynamic>.from(e));
          }
        }
      }
      list.sort((a, b) {
        final la = (a['label'] ?? '').toString().toLowerCase();
        final lb = (b['label'] ?? '').toString().toLowerCase();
        return la.compareTo(lb);
      });
      if (mounted) {
        setState(() {
          _apps = list;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _setMode(String mode) async {
    setState(() => _mode = mode);
    await SettingsService.setProxyMode(mode);
  }

  Future<void> _toggle(String pkg, bool on) async {
    setState(() {
      if (on) {
        _selected.add(pkg);
      } else {
        _selected.remove(pkg);
      }
    });
    await SettingsService.setBlockedApps(_selected.toList()..sort());
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _q.isEmpty
        ? _apps
        : _apps.where((a) {
            final l = '${a['label']} ${a['package']}'.toLowerCase();
            return l.contains(_q.toLowerCase());
          }).toList();

    final listEnabled = _mode != 'all';

    return Scaffold(
      backgroundColor: AppColors.bg(context),
      appBar: AppBar(
        title: Text(_t('پراکسی هر برنامه', 'Per-app proxy')),
        backgroundColor: AppColors.bg(context),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // ---- Segmented control ----
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _modeCard(
                        context,
                        key: 'all',
                        titleFa: 'همه برنامه‌ها تونل بشن',
                        titleEn: 'All apps through VPN',
                        subFa: 'تمام ترافیک برنامه‌ها از تونل عبور می‌کند (پیش‌فرض)',
                        subEn: 'All app traffic goes through the tunnel (default)',
                      ),
                      const SizedBox(height: 6),
                      _modeCard(
                        context,
                        key: 'blacklist',
                        titleFa: 'برنامه‌های انتخاب‌شده تونل نشن',
                        titleEn: 'Selected apps bypass VPN',
                        subFa: 'این برنامه‌ها از تونل مستثنی می‌شوند',
                        subEn: 'These apps are excluded from the tunnel',
                      ),
                      const SizedBox(height: 6),
                      _modeCard(
                        context,
                        key: 'whitelist',
                        titleFa: 'فقط برنامه‌های انتخاب‌شده تونل بشن',
                        titleEn: 'Only selected apps through VPN',
                        subFa: 'بقیه‌ی برنامه‌ها از تونل مستثنی می‌شوند',
                        subEn: 'All other apps bypass the tunnel',
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                // ---- Search ----
                if (listEnabled)
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: TextField(
                      decoration: InputDecoration(
                        hintText: _t('جستجو', 'Search'),
                        prefixIcon: const Icon(Icons.search),
                      ),
                      onChanged: (v) => setState(() => _q = v),
                    ),
                  ),
                // ---- List ----
                Expanded(
                  child: !listEnabled
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Text(
                              _t(
                                'در این حالت همه‌ی برنامه‌ها از تونل رد می‌شوند.\nبرای انتخاب برنامه‌ها یکی از دو حالت دیگر را انتخاب کن.',
                                'In this mode all apps go through the tunnel.\nPick one of the other modes to select apps.',
                              ),
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                  color: AppColors.muted(context),
                                  height: 1.7),
                            ),
                          ),
                        )
                      : ListView.builder(
                          itemCount: filtered.length,
                          itemBuilder: (ctx, i) {
                            final a = filtered[i];
                            final pkg = a['package']?.toString() ?? '';
                            final label = a['label']?.toString() ?? pkg;
                            final on = _selected.contains(pkg);
                            return SwitchListTile(
                              title: Text(label,
                                  style: TextStyle(color: AppColors.fg(context))),
                              subtitle: Text(pkg,
                                  style: TextStyle(
                                      color: AppColors.muted2(context),
                                      fontSize: 11)),
                              value: on,
                              onChanged: (v) => _toggle(pkg, v),
                            );
                          },
                        ),
                ),
              ],
            ),
    );
  }

  Widget _modeCard(
    BuildContext context, {
    required String key,
    required String titleFa,
    required String titleEn,
    required String subFa,
    required String subEn,
  }) {
    final active = _mode == key;
    return InkWell(
      onTap: () => _setMode(key),
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: active
              ? AppColors.accent.withOpacity(0.15)
              : AppColors.surface(context),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: active ? AppColors.accent : AppColors.border(context),
            width: active ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            Icon(
              active ? Icons.radio_button_checked : Icons.radio_button_off,
              color: active ? AppColors.accent : AppColors.muted(context),
              size: 20,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _t(titleFa, titleEn),
                    style: TextStyle(
                      color: AppColors.fg(context),
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _t(subFa, subEn),
                    style: TextStyle(
                      color: AppColors.muted2(context),
                      fontSize: 11,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
