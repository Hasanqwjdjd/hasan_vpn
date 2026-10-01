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
      {int min = 0, int max = 99999, String? subFa, String? subEn}) {
    final ctrl = TextEditingController(text: '${_s[key] ?? ''}');
    return ListTile(
      title: Text(_t(fa, en), style: const TextStyle(fontSize: 14)),
      subtitle: (subFa != null)
          ? Text(_t(subFa, subEn ?? subFa),
              style: TextStyle(color: AppColors.muted(context), fontSize: 11))
          : null,
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

  Widget _textField(String key, String fa, String en,
      {String? hint, String? subFa, String? subEn}) {
    final ctrl = TextEditingController(text: '${_s[key] ?? ''}');
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(_t(fa, en), style: const TextStyle(fontSize: 13)),
          if (subFa != null)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(_t(subFa, subEn ?? subFa),
                  style: TextStyle(
                      color: AppColors.muted(context),
                      fontSize: 11,
                      height: 1.4)),
            ),
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

  Widget _dropdown(String key, String fa, String en, List<String> options,
      {String? subFa, String? subEn}) {
    final cur = _s[key]?.toString() ?? options.first;
    return ListTile(
      title: Text(_t(fa, en), style: const TextStyle(fontSize: 14)),
      subtitle: (subFa != null)
          ? Text(_t(subFa, subEn ?? subFa),
              style: TextStyle(color: AppColors.muted(context), fontSize: 11))
          : null,
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

  /// ردیف preset های Fragment — با یک تپ همهٔ فیلدها را ست می‌کند.
  Widget _fragmentPresets() {
    final presets = <({String label, String packets, String length, String interval})>[
      (label: 'پیش‌فرض', packets: 'tlshello', length: '100-200', interval: '10-20'),
      (label: 'ایران', packets: 'tlshello', length: '1-3', interval: '1-2'),
      (label: 'تهاجمی', packets: 'tlshello', length: '1-1', interval: '1-1'),
      (label: 'محافظه‌کار', packets: 'tlshello', length: '5-10', interval: '5-10'),
    ];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _t('پروفایل آماده', 'Preset'),
            style: TextStyle(
              color: AppColors.muted(context),
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: presets.map((p) {
              final active = _s['fragmentPackets'] == p.packets &&
                  _s['fragmentLength'] == p.length &&
                  _s['fragmentInterval'] == p.interval;
              return ChoiceChip(
                label: Text(p.label),
                selected: active,
                onSelected: (_) async {
                  await _set('fragmentPackets', p.packets);
                  await _set('fragmentLength', p.length);
                  await _set('fragmentInterval', p.interval);
                  await _set('fragmentMaxSplit', 0);
                },
                selectedColor: AppColors.accent.withOpacity(0.25),
                backgroundColor: AppColors.surface(context),
                labelStyle: TextStyle(
                  color: active ? AppColors.accent : AppColors.fg(context),
                  fontSize: 12.5,
                ),
                side: BorderSide(
                  color: active ? AppColors.accent : AppColors.border(context),
                ),
              );
            }).toList(),
          ),
        ],
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
                _numField('mtu', 'MTU', 'VPN MTU', min: 1280, max: 9000,
                    subFa:
                        'اندازهٔ بستهٔ شبکه. ۱۴۰۰–۱۵۰۰ معمولاً پایدار؛ کمتر برای نت‌های PPTP یا همراه‌های محدودکننده.',
                    subEn:
                        'Packet size. 1400–1500 usually stable; lower for PPTP/restricted mobile nets.'),
                _sw('mssClampEnable', 'محدودسازی MSS (TCP)',
                    'TCP MSS clamp',
                    subFa:
                        'برای مسیرهایی که پکت بزرگ را بی‌صدا دور می‌ریزند: handshake رد می‌شود ولی هر دانلود واقعی روی اولین سگمنت کامل گیر می‌کند. مقدار باید روی هر دو طرف یکی باشد.',
                    subEn:
                        'For paths that silently drop large packets: handshake passes, every real transfer stalls on the first full segment. Set the same value on both ends.'),
                _numField('mssClampValue', 'مقدار MSS (۰=خودکار)',
                    'MSS value (0=auto)',
                    min: 0, max: 1460,
                    subFa:
                        '۰ یعنی auto: MTU منهای ۴۰. محدودهٔ معتبر ۵۲۴ تا ۱۴۶۰.',
                    subEn:
                        '0 means auto: MTU minus 40. Valid range is 524 to 1460.'),
                _sw('useHevTun', 'استفاده از Hev TUN', 'Use Hev TUN',
                    subFa: 'hev-socks5-tunnel به‌جای xray TUN',
                    subEn: 'hev-socks5-tunnel instead of xray TUN'),
                _dropdown('hevLogLevel', 'سطح لاگ Hev', 'Hev log level',
                    ['debug', 'info', 'warn', 'error', 'none']),
                _numField('hevTcpRwTimeout', 'تایم‌اوت TCP Hev (ثانیه)',
                    'Hev TCP R/W timeout (s)',
                    min: 1, max: 600,
                    subFa:
                        'هر چند ثانیه TCP idle رو ببنده. بیشتر → اتصال پایدارتر روی نت ضعیف؛ کمتر → مصرف کمتر.',
                    subEn:
                        'Idle TCP close timer. Higher = stabler on weak nets; lower = less battery.'),
                _numField('hevUdpRwTimeout', 'تایم‌اوت UDP Hev (ثانیه)',
                    'Hev UDP R/W timeout (s)',
                    min: 1, max: 600,
                    subFa:
                        'همون تایم‌اوت برای UDP. برای بازی و ویدیو بیشتر بذار.',
                    subEn:
                        'Same timer for UDP. Increase for gaming/video.'),
                _sw('sniffing', 'Sniffing', 'Sniffing',
                    subFa:
                        'خواندن دامنهٔ مقصد از ترافیک برای routing دقیق‌تر. برای تفکیک سایت‌های ایرانی لازمه.',
                    subEn:
                        'Read destination domain for accurate routing. Needed for IR-site split-tunnel.'),
                _sw('sniffRouteOnly', 'routeOnly', 'routeOnly',
                    subFa: 'دامنه فقط برای routing، IP اصلی ارسال شود',
                    subEn:
                        'Keep sniffed domain for routing only; still send resolved IP'),
                _sw('localProxyEnable', 'پروکسی محلی', 'Local proxy',
                    subFa:
                        'یه inbound HTTP اضافه می‌کنه که سایر اپ‌ها یا مرورگرها بتونن از پروکسی استفاده کنن.',
                    subEn:
                        'Adds an HTTP inbound so other apps/browsers can use the proxy.'),
                _numField('localProxyPort', 'پورت پروکسی محلی',
                    'Local proxy port',
                    min: 1024, max: 65535,
                    subFa:
                        'پورت HTTP proxy روی 127.0.0.1. مثلاً 10809.',
                    subEn: 'HTTP proxy port on 127.0.0.1, e.g. 10809.'),
                _textField('localProxyUser', 'کاربر پروکسی', 'Proxy user'),
                _textField('localProxyPass', 'رمز پروکسی', 'Proxy password'),
                _sw('shareProxyLan', 'اشتراک روی LAN', 'Share proxy on LAN',
                    subFa:
                        'پروکسی روی همهٔ اینترفیس‌ها listen کنه تا گوشی‌های دیگهٔ شبکه هم بتونن استفاده کنن.',
                    subEn:
                        'Listen on all interfaces so other devices on your LAN can use the proxy.'),
                _sw('randomPort', 'پورت تصادفی هر بار', 'Random port each toggle',
                    subFa:
                        'SOCKS محلی هر بار پورت جدید انتخاب کنه (بهبود امنیت، سازگاری با بعضی فایروال‌ها).',
                    subEn:
                        'Pick a fresh local SOCKS port every connect (better security, some firewalls).'),
                _dropdown('dnsProtocol', 'پروتکل DNS', 'DNS protocol',
                    ['udp', 'tcp', 'https', 'quic']),
                // ---- A3 Mux ----
                _section(_t('Mux', 'Mux'), icon: Icons.layers),
                _sw('muxEnable', 'فعال‌سازی Mux', 'Enable Mux',
                    subFa:
                        'چند کانکشن روی یک کانال TCP — تأخیر کمتر و مصرف باتری کمتر. حتماً باید سرور پشتیبانی کنه.',
                    subEn:
                        'Multiplex streams over one TCP — lower latency & battery. Server must support it.'),
                _numField('muxConcurrency', 'هم‌زمانی TCP', 'TCP concurrency',
                    min: 1, max: 1024,
                    subFa:
                        'حداکثر تعداد کانکشن همزمان در Mux. ۸ معمولاً کافیه؛ بالاتر روی سرور ضعیف افت می‌ده.',
                    subEn:
                        'Max concurrent Mux connections. 8 usually enough; higher can hurt weak servers.'),
                _numField('muxXudpConcurrency', 'هم‌زمانی XUDP',
                    'XUDP concurrency',
                    min: 1, max: 1024,
                    subFa:
                        'حداکثر جریان UDP همزمان در Mux. ۰ = غیرفعال (توصیه‌شده برای HTTP/3).',
                    subEn:
                        'Max concurrent XUDP streams. 0 = disabled (recommended for HTTP/3).'),
                _dropdown('muxXudpQuic', 'QUIC در Mux', 'QUIC in Mux',
                    ['reject', 'allow', 'skip']),

                // ---- Reality overrides ----
                _section(_t('Reality (override)', 'Reality (override)'),
                    icon: Icons.security),
                _textField('realityPublicKey', 'Public key', 'Public key'),
                _textField('realityShortId', 'Short ID', 'Short ID'),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Text(
                    _t('Fingerprint', 'Fingerprint'),
                    style: TextStyle(
                        color: AppColors.muted(context),
                        fontSize: 13,
                        fontWeight: FontWeight.w600),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final fp in const [
                        'chrome', 'firefox', 'safari',
                        'ios', 'android', 'edge', 'random', 'randomized',
                      ])
                        ChoiceChip(
                          label: Text(fp),
                          selected: _s['realityFingerprint'] == fp,
                          onSelected: (_) => _set('realityFingerprint', fp),
                          selectedColor:
                              AppColors.accent.withOpacity(0.25),
                          backgroundColor: AppColors.surface(context),
                          labelStyle: TextStyle(
                            color: _s['realityFingerprint'] == fp
                                ? AppColors.accent
                                : AppColors.fg(context),
                            fontSize: 11,
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 6),
                _textField('realityFingerprint', 'Fingerprint دستی',
                    'Fingerprint (manual)'),
                _textField('realityServerName', 'Server name (SNI)',
                    'Server name'),
                _textField('realitySpiderX', 'Spider X path', 'Spider X'),

                // ---- A4 Fragment ----
                _section(_t('Fragment', 'Fragment'), icon: Icons.call_split),
                _sw('skipCertVerify', 'نادیده‌گرفتن اعتبار گواهی TLS',
                    'Skip TLS cert verification',
                    subFa: 'برای سرورهای self-signed یا CDN شخصی',
                    subEn: 'For self-signed or custom CDN servers'),
                _sw('fragmentEnable', 'فعال‌سازی Fragment', 'Enable Fragment',
                    subFa:
                        'شکستن TLS handshake به قطعات کوچک برای عبور از DPI. لازم برای خیلی از سرورهای ایران.',
                    subEn:
                        'Splits the TLS handshake for DPI bypass. Required for many IR-facing servers.'),
                _fragmentPresets(),
                _textField('fragmentPackets', 'محدوده پکت', 'Packet ranges',
                    hint: 'tlshello یا 1-3'),
                _textField('fragmentLength', 'طول پکت (min-max)',
                    'Packet length (min-max)',
                    hint: '100-200'),
                _textField('fragmentInterval', 'فاصله پکت (min-max)',
                    'Packet interval (min-max)',
                    hint: '10-20'),
                _numField('fragmentMaxSplit', 'حداکثر split', 'Max split count',
                    min: 0, max: 256,
                    subFa:
                        'بیشترین تعداد تکه‌ای که هر پکت به آن شکسته می‌شه. ۰ = بدون محدودیت.',
                    subEn:
                        'Max pieces per packet. 0 = unlimited.'),

                // ---- A5 Observatory ----
                _section(_t('Observatory / پیش‌بررسی اتصال',
                    'Observatory / Connection pre-check')),
                _sw('observatoryEnable', 'فعال‌سازی Observatory',
                    'Enable Observatory',
                    subFa:
                        'انتخاب خودکار بهترین outbound بر اساس پینگ/بار. برای multi-chain کاربردیه.',
                    subEn:
                        'Auto-pick best outbound by ping/load. Useful for multi-chain setups.'),
                _numField('leastPingInterval', 'بازه leastPing (ثانیه)',
                    'leastPing interval (s)',
                    min: 30, max: 3600,
                    subFa:
                        'هر چند ثانیه پینگ همهٔ outboundها اندازه‌گیری شه تا کم‌پینگ‌ترین انتخاب شه.',
                    subEn:
                        'How often to re-ping all outbounds for the least-ping strategy.'),
                _numField('leastLoadInterval', 'بازه leastLoad (ثانیه)',
                    'leastLoad interval (s)',
                    min: 30, max: 3600,
                    subFa:
                        'هر چند ثانیه بار سرورها سنجیده شه (تعداد درخواست موفق).',
                    subEn:
                        'How often to sample server load (successful requests).'),
                _dropdown('leastLoadMethod', 'متد HTTP leastLoad',
                    'leastLoad HTTP method', ['HEAD', 'GET']),
                _numField('leastLoadSample', 'تعداد نمونه leastLoad',
                    'leastLoad sample count',
                    min: 1, max: 20,
                    subFa:
                        'چند نمونه برای محاسبه میانه بگیره. بالاتر = دقیق‌تر ولی کندتر.',
                    subEn:
                        'Samples per cycle for median. Higher = accurate but slower.'),
                _numField('leastLoadTimeout', 'تایم‌اوت leastLoad (ثانیه)',
                    'leastLoad timeout (s)',
                    min: 1, max: 60,
                    subFa:
                        'چند ثانیه برای پاسخ HTTP صبر کنه قبل از رد کردن سرور.',
                    subEn:
                        'HTTP probe timeout before rejecting a server.'),
                _numField('maxFailedAttempts', 'حداکثر تلاش ناموفق',
                    'Max failed attempts',
                    min: 1, max: 20,
                    subFa:
                        'بعد از این تعداد fail، سرور از چرخهٔ انتخاب خودکار حذف می‌شه.',
                    subEn:
                        'Remove a server from auto-selection after N failures.'),

                _section(_t('رابط کاربری', 'User interface'), icon: Icons.palette_outlined),
                _sw('confirmDelete', 'تأیید حذف کانفیگ',
                    'Confirm config deletion',
                    subFa: 'قبل از حذف سرور، تأیید بگیر',
                    subEn: 'Ask before deleting a server'),
                _sw('twoColumnGrid', 'نمایش دو ستون',
                    'Two-column grid',
                    subFa: 'فهرست سرورها به‌صورت دو ستونی',
                    subEn: 'Show server list in two columns'),
                _sw('showAllTab', 'نمایش زبانه «همه»',
                    'Show "All" tab',
                    subFa: 'همهٔ سرورها در یک زبانه',
                    subEn: 'Show all servers in one tab'),

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
