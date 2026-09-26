import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/app_colors.dart';
import '../services/xray_settings.dart';

/// Full PattNG/v2rayNG-style Xray / VPN settings surface (Tasks A1–A5).
class XraySettingsScreen extends StatefulWidget {
  final String language;

  const XraySettingsScreen({super.key, required this.language});

  @override
  State<XraySettingsScreen> createState() => _XraySettingsScreenState();
}

class _XraySettingsScreenState extends State<XraySettingsScreen> {
  Map<String, dynamic> _s = Map<String, dynamic>.from(XraySettings.defaults);
  bool _loading = true;

  bool get _isFa => widget.language.startsWith('fa');
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

  Widget _section(String title, {IconData? icon}) => Container(
        margin: const EdgeInsets.fromLTRB(12, 18, 12, 6),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              AppColors.accent.withOpacity(0.20),
              AppColors.accent.withOpacity(0.05),
            ],
          ),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.accent.withOpacity(0.35)),
        ),
        child: Row(
          children: [
            if (icon != null) ...[
              Icon(icon, color: AppColors.accent, size: 18),
              const SizedBox(width: 8),
            ],
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  color: AppColors.accent,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      );

  Widget _sw(String key, String fa, String en, {String? subFa, String? subEn}) {
    return SwitchListTile(
      title: Text(_t(fa, en), style: const TextStyle(fontSize: 14)),
      subtitle: (subFa != null)
          ? Text(_t(subFa, subEn ?? subFa),
              style: TextStyle(color: AppColors.muted(context), fontSize: 11))
          : null,
      value: _s[key] == true,
      activeColor: AppColors.accent,
      onChanged: (v) => _set(key, v),
    );
  }

  Widget _numField(String key, String fa, String en,
      {int min = 0, int max = 99999}) {
    final ctrl = TextEditingController(text: '${_s[key] ?? ''}');
    return ListTile(
      title: Text(_t(fa, en), style: const TextStyle(fontSize: 14)),
      trailing: SizedBox(
        width: 90,
        child: TextField(
          controller: ctrl,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          textAlign: TextAlign.center,
          style: TextStyle(color: AppColors.fg(context), fontSize: 13),
          decoration: InputDecoration(
            isDense: true,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            border: OutlineInputBorder(
                borderSide: BorderSide(color: AppColors.border(context))),
          ),
          onSubmitted: (v) {
            final n = int.tryParse(v);
            if (n != null && n >= min && n <= max) _set(key, n);
          },
          onEditingComplete: () {
            final n = int.tryParse(ctrl.text);
            if (n != null && n >= min && n <= max) _set(key, n);
          },
        ),
      ),
    );
  }

  Widget _textField(String key, String fa, String en, {String? hint}) {
    final ctrl = TextEditingController(text: '${_s[key] ?? ''}');
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(_t(fa, en), style: const TextStyle(fontSize: 13)),
          const SizedBox(height: 4),
          TextField(
            controller: ctrl,
            style: TextStyle(color: AppColors.fg(context), fontSize: 13),
            decoration: InputDecoration(
              hintText: hint,
              isDense: true,
              border: OutlineInputBorder(
                  borderSide: BorderSide(color: AppColors.border(context))),
            ),
            onSubmitted: (v) => _set(key, v.trim()),
            onEditingComplete: () => _set(key, ctrl.text.trim()),
          ),
        ],
      ),
    );
  }

  Widget _dropdown(String key, String fa, String en, List<String> options) {
    final cur = _s[key]?.toString() ?? options.first;
    return ListTile(
      title: Text(_t(fa, en), style: const TextStyle(fontSize: 14)),
      trailing: DropdownButton<String>(
        value: options.contains(cur) ? cur : options.first,
        dropdownColor: AppColors.surface(context),
        items: options
            .map((o) => DropdownMenuItem(value: o, child: Text(o)))
            .toList(),
        onChanged: (v) {
          if (v != null) _set(key, v);
        },
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
        scrolledUnderElevation: 0,
        title: Text(
          _t('تنظیمات هسته / VPN', 'Core / VPN Settings'),
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
        actions: [
          IconButton(
            tooltip: _t('بازنشانی به پیش‌فرض', 'Reset to defaults'),
            icon: const Icon(Icons.restart_alt, size: 20),
            onPressed: () async {
              final ok = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  backgroundColor: AppColors.surface(ctx),
                  title: Text(_t('بازنشانی؟', 'Reset?'),
                      style: TextStyle(color: AppColors.fg(ctx))),
                  content: Text(
                    _t('همهٔ تنظیمات هسته به حالت پیش‌فرض برمی‌گردد.',
                        'All core settings will reset to defaults.'),
                    style: TextStyle(color: AppColors.fg(ctx), fontSize: 13),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: Text(_t('انصراف', 'Cancel')),
                    ),
                    TextButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      child: Text(_t('بازنشانی', 'Reset'),
                          style: const TextStyle(color: Colors.redAccent)),
                    ),
                  ],
                ),
              );
              if (ok != true || !mounted) return;
              final fresh = Map<String, dynamic>.from(XraySettings.defaults);
              for (final entry in fresh.entries) {
                await XraySettings.set(entry.key, entry.value);
              }
              if (!mounted) return;
              setState(() => _s = fresh);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(_t('بازنشانی شد', 'Reset done'))),
              );
            },
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.only(bottom: 40, top: 4),
              children: [
                // ---- A1 VPN ----
                _section(_t('تنظیمات VPN', 'VPN Settings'), icon: Icons.vpn_lock),
                _sw('enableIpv6', 'فعال‌سازی IPv6', 'Enable IPv6',
                    subFa: 'افزودن مسیر IPv6 به تونل',
                    subEn: 'Add IPv6 route to VPN'),
                _sw('preferIpv6', 'ترجیح IPv6', 'Prefer IPv6',
                    subFa: 'اولویت حل دامنه به IPv6',
                    subEn: 'Prefer IPv6 for domain resolution'),
                _sw('localDns', 'DNS محلی', 'Local DNS'),
                _sw('fakeDns', 'FakeDNS', 'FakeDNS',
                    subFa:
                        'هشدار: FakeDNS ممکن است با برخی اپ‌ها ناسازگار باشد',
                    subEn:
                        'Warning: FakeDNS may break some apps (same as PattNG)'),
                _textField('vpnDns', 'DNS VPN (IPv4)', 'VPN DNS (IPv4)',
                    hint: '1.1.1.1,8.8.8.8'),
                _textField('vpnDns6', 'DNS VPN (IPv6)', 'VPN DNS (IPv6)',
                    hint: '2606:4700:4700::1111'),

                // ---- A2 Advanced ----
                _section(_t('پیشرفته', 'Advanced'), icon: Icons.tune),
                _numField('mtu', 'MTU', 'VPN MTU', min: 1280, max: 9000),
                _sw('useHevTun', 'استفاده از Hev TUN', 'Use Hev TUN',
                    subFa: 'hev-socks5-tunnel به‌جای xray TUN',
                    subEn: 'hev-socks5-tunnel instead of xray TUN'),
                _dropdown('hevLogLevel', 'سطح لاگ Hev', 'Hev log level',
                    ['debug', 'info', 'warn', 'error', 'none']),
                _numField('hevTcpRwTimeout', 'تایم‌اوت TCP Hev (ثانیه)',
                    'Hev TCP R/W timeout (s)',
                    min: 1, max: 600),
                _numField('hevUdpRwTimeout', 'تایم‌اوت UDP Hev (ثانیه)',
                    'Hev UDP R/W timeout (s)',
                    min: 1, max: 600),
                _sw('sniffing', 'Sniffing', 'Sniffing'),
                _sw('sniffRouteOnly', 'routeOnly', 'routeOnly',
                    subFa: 'دامنه فقط برای routing، IP اصلی ارسال شود',
                    subEn:
                        'Keep sniffed domain for routing only; still send resolved IP'),
                _sw('localProxyEnable', 'پروکسی محلی', 'Local proxy'),
                _numField('localProxyPort', 'پورت پروکسی محلی',
                    'Local proxy port',
                    min: 1024, max: 65535),
                _textField('localProxyUser', 'کاربر پروکسی', 'Proxy user'),
                _textField('localProxyPass', 'رمز پروکسی', 'Proxy password'),
                _sw('shareProxyLan', 'اشتراک روی LAN', 'Share proxy on LAN'),
                _sw('randomPort', 'پورت تصادفی هر بار', 'Random port each toggle'),
                _dropdown('dnsProtocol', 'پروتکل DNS', 'DNS protocol',
                    ['udp', 'tcp', 'https', 'quic']),
                _textField('dohUrl', 'آدرس DoH', 'DoH URL',
                    hint: 'https://cloudflare-dns.com/dns-query'),
                _textField('directDns', 'DNS مستقیم', 'Direct DNS'),
                _textField('dnsHosts', 'نگاشت دامنه (domain:ip,...)',
                    'DNS hosts (domain:ip,...)'),

                // ---- A3 Mux ----
                _section(_t('Mux', 'Mux'), icon: Icons.layers),
                _sw('muxEnable', 'فعال‌سازی Mux', 'Enable Mux'),
                _numField('muxConcurrency', 'هم‌زمانی TCP', 'TCP concurrency',
                    min: 1, max: 1024),
                _numField('muxXudpConcurrency', 'هم‌زمانی XUDP',
                    'XUDP concurrency',
                    min: 1, max: 1024),
                _dropdown('muxXudpQuic', 'QUIC در Mux', 'QUIC in Mux',
                    ['reject', 'allow', 'skip']),

                // ---- A4 Fragment ----
                _section(_t('Fragment', 'Fragment'), icon: Icons.call_split),
                _sw('fragmentEnable', 'فعال‌سازی Fragment', 'Enable Fragment'),
                _textField('fragmentPackets', 'محدوده پکت', 'Packet ranges',
                    hint: 'tlshello یا 1-3'),
                _textField('fragmentLength', 'طول پکت (min-max)',
                    'Packet length (min-max)',
                    hint: '100-200'),
                _textField('fragmentInterval', 'فاصله پکت (min-max)',
                    'Packet interval (min-max)',
                    hint: '10-20'),
                _numField('fragmentMaxSplit', 'حداکثر split', 'Max split count',
                    min: 0, max: 256),

                // ---- A5 Observatory ----
                _section(_t('Observatory / پیش‌بررسی اتصال',
                    'Observatory / Connection pre-check')),
                _sw('observatoryEnable', 'فعال‌سازی Observatory',
                    'Enable Observatory'),
                _numField('leastPingInterval', 'بازه leastPing (ثانیه)',
                    'leastPing interval (s)',
                    min: 30, max: 3600),
                _numField('leastLoadInterval', 'بازه leastLoad (ثانیه)',
                    'leastLoad interval (s)',
                    min: 30, max: 3600),
                _dropdown('leastLoadMethod', 'متد HTTP leastLoad',
                    'leastLoad HTTP method', ['HEAD', 'GET']),
                _numField('leastLoadSample', 'تعداد نمونه leastLoad',
                    'leastLoad sample count',
                    min: 1, max: 20),
                _numField('leastLoadTimeout', 'تایم‌اوت leastLoad (ثانیه)',
                    'leastLoad timeout (s)',
                    min: 1, max: 60),
                _numField('maxFailedAttempts', 'حداکثر تلاش ناموفق',
                    'Max failed attempts',
                    min: 1, max: 20),

                _section(_t('VPN اضافه', 'VPN extras'), icon: Icons.shield_outlined),
                _sw('bypassLan', 'عبور از شبکه محلی (LAN)',
                    'Bypass local network (LAN)',
                    subFa: 'ترافیک LAN مستقیم برود، نه از VPN',
                    subEn: 'LAN traffic goes direct'),
                _sw('addHttpProxyToVpn', 'افزودن پروکسی HTTP به VPN',
                    'Add HTTP proxy to VPN',
                    subFa: 'برای اپ‌هایی که پروکسی نمی‌گیرند',
                    subEn: 'For apps that ignore proxy'),
                _sw('alwaysOnVpn', 'VPN همیشه‌روشن',
                    'Always-on VPN',
                    subFa: 'اتصال هنگام راه‌اندازی مجدد',
                    subEn: 'Reconnect on boot'),
                _sw('autoConnectBoot', 'اتصال پس از راه‌اندازی',
                    'Auto-connect on boot',
                    subFa: 'خودکار به سرور اصلی وصل شو',
                    subEn: 'Auto-connect to primary server'),
                _textField('vpnInterface', 'آدرس واسط VPN (اختیاری)',
                    'VPN interface address (optional)',
                    hint: 'x.x.x.x/32'),

                _section(_t('رابط کاربری', 'User interface'), icon: Icons.palette_outlined),
                _sw('showSpeedNotif', 'نمایش سرعت در اعلان',
                    'Show speed in notification'),
                _sw('confirmDelete', 'تأیید حذف کانفیگ',
                    'Confirm config deletion'),
                _sw('twoColumnGrid', 'نمایش دو ستون',
                    'Two-column grid',
                    subFa: 'فهرست پروفایل‌ها دو ستونی',
                    subEn: 'Two-column profile list'),
                _sw('showAllTab', 'نمایش زبانه «همه»',
                    'Show "All" tab',
                    subFa: 'همهٔ پروفایل‌ها در یک زبان',
                    subEn: 'All profiles in one tab'),

                _section(_t('سایر', 'Other'), icon: Icons.more_horiz),
                _dropdown('domainStrategy', 'استراتژی دامنه', 'Domain strategy',
                    ['AsIs', 'IPIfNonMatch', 'IPOnDemand']),
                _dropdown('logLevel', 'سطح لاگ', 'Log level',
                    ['debug', 'info', 'warning', 'error', 'none']),
              ],
            ),
    );
  }
}
