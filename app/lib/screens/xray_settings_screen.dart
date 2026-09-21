import 'package:flutter/material.dart';

import '../services/app_colors.dart';
import '../services/xray_settings.dart';

class XraySettingsScreen extends StatefulWidget {
  final String language;

  const XraySettingsScreen({super.key, required this.language});

  @override
  State<XraySettingsScreen> createState() => _XraySettingsScreenState();
}

class _XraySettingsScreenState extends State<XraySettingsScreen> {
  Map<String, dynamic> _s = Map<String, dynamic>.from(XraySettings.defaults);
  bool _loading = true;

  bool get _isFa => widget.language == 'fa';
  String _t(String fa, String en) => _isFa ? fa : en;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final s = await XraySettings.load();
    if (!mounted) return;
    setState(() {
      _s = s;
      _loading = false;
    });
  }

  Future<void> _set(String key, dynamic value) async {
    setState(() => _s[key] = value);
    await XraySettings.set(key, value);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg(context),
      appBar: AppBar(
        backgroundColor: AppColors.bg(context),
        elevation: 0,
        title: Text(_t('تنظیمات هسته Xray', 'Xray Core Settings')),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _section(_t('بازرسی ترافیک', 'Traffic sniffing')),
                SwitchListTile(
                  title: Text(_t('Sniffing', 'Sniffing')),
                  subtitle: Text(
                    _t(
                      'تشخیص دامنه از ترافیک TLS/HTTP',
                      'Detect domain from TLS/HTTP traffic',
                    ),
                    style: TextStyle(
                        color: AppColors.muted(context), fontSize: 12),
                  ),
                  value: _s['sniffing'] != false,
                  activeColor: AppColors.accent,
                  onChanged: (v) => _set('sniffing', v),
                ),
                SwitchListTile(
                  title: Text(_t('فقط مسیر (routeOnly)', 'Route only')),
                  subtitle: Text(
                    _t(
                      'فقط برای routing استفاده شود، مقصد عوض نشود',
                      'Use for routing only, do not override destination',
                    ),
                    style: TextStyle(
                        color: AppColors.muted(context), fontSize: 12),
                  ),
                  value: _s['sniffRouteOnly'] == true,
                  activeColor: AppColors.accent,
                  onChanged: _s['sniffing'] == false
                      ? null
                      : (v) => _set('sniffRouteOnly', v),
                ),
                const SizedBox(height: 12),
                _section(_t('لاگ', 'Logging')),
                ListTile(
                  title: Text(_t('سطح لاگ', 'Log level')),
                  subtitle: Text(
                    (_s['logLevel'] ?? 'warning').toString(),
                    style: TextStyle(color: AppColors.muted(context)),
                  ),
                  trailing: DropdownButton<String>(
                    value: (_s['logLevel'] ?? 'warning').toString(),
                    dropdownColor: AppColors.elevated(context),
                    items: const [
                      DropdownMenuItem(value: 'debug', child: Text('debug')),
                      DropdownMenuItem(value: 'info', child: Text('info')),
                      DropdownMenuItem(
                          value: 'warning', child: Text('warning')),
                      DropdownMenuItem(value: 'error', child: Text('error')),
                      DropdownMenuItem(value: 'none', child: Text('none')),
                    ],
                    onChanged: (v) {
                      if (v != null) _set('logLevel', v);
                    },
                  ),
                ),
                const SizedBox(height: 12),
                _section(_t('ورودی‌های محلی', 'Local inbounds')),
                SwitchListTile(
                  title: Text(_t('اجازه LAN', 'Allow LAN')),
                  subtitle: Text(
                    _t(
                      'دستگاه‌های دیگر در شبکه بتوانند از پروکسی استفاده کنند',
                      'Other devices on LAN can use this proxy',
                    ),
                    style: TextStyle(
                        color: AppColors.muted(context), fontSize: 12),
                  ),
                  value: _s['allowLan'] == true,
                  activeColor: AppColors.accent,
                  onChanged: (v) => _set('allowLan', v),
                ),
                SwitchListTile(
                  title: Text(_t('ورودی HTTP', 'HTTP inbound')),
                  subtitle: Text(
                    _t(
                      'پورت HTTP جدا برای برنامه‌هایی که SOCKS نمی‌فهمند',
                      'Extra HTTP port for apps without SOCKS support',
                    ),
                    style: TextStyle(
                        color: AppColors.muted(context), fontSize: 12),
                  ),
                  value: _s['httpInbound'] == true,
                  activeColor: AppColors.accent,
                  onChanged: (v) => _set('httpInbound', v),
                ),
                ListTile(
                  title: Text(_t('پورت SOCKS', 'SOCKS port')),
                  trailing: SizedBox(
                    width: 90,
                    child: TextFormField(
                      initialValue: '${_s['socksPort'] ?? 10808}',
                      keyboardType: TextInputType.number,
                      textAlign: TextAlign.center,
                      decoration: const InputDecoration(
                        isDense: true,
                        border: OutlineInputBorder(),
                      ),
                      onFieldSubmitted: (v) {
                        final n = int.tryParse(v);
                        if (n != null && n > 1024 && n < 65535) {
                          _set('socksPort', n);
                        }
                      },
                    ),
                  ),
                ),
                if (_s['httpInbound'] == true)
                  ListTile(
                    title: Text(_t('پورت HTTP', 'HTTP port')),
                    trailing: SizedBox(
                      width: 90,
                      child: TextFormField(
                        initialValue: '${_s['httpPort'] ?? 10809}',
                        keyboardType: TextInputType.number,
                        textAlign: TextAlign.center,
                        decoration: const InputDecoration(
                          isDense: true,
                          border: OutlineInputBorder(),
                        ),
                        onFieldSubmitted: (v) {
                          final n = int.tryParse(v);
                          if (n != null && n > 1024 && n < 65535) {
                            _set('httpPort', n);
                          }
                        },
                      ),
                    ),
                  ),
                const SizedBox(height: 24),
                Text(
                  _t(
                    'تغییرات از اتصال بعدی اعمال می‌شوند.',
                    'Changes apply on the next connection.',
                  ),
                  style: TextStyle(
                    color: AppColors.muted2(context),
                    fontSize: 12,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
    );
  }

  Widget _section(String title) => Padding(
        padding: const EdgeInsets.only(bottom: 4, top: 4),
        child: Text(
          title,
          style: TextStyle(
            color: AppColors.accent,
            fontWeight: FontWeight.w700,
            fontSize: 13,
          ),
        ),
      );
}
