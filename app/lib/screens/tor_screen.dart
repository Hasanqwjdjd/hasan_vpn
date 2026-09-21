import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/server.dart';
import '../models/aether_profile.dart';
import '../models/server.dart';
import '../services/app_colors.dart';
import '../services/tor_service.dart';
import '../services/tor_sni_presets.dart';
import '../services/v2ray_engine.dart';

class TorScreen extends StatefulWidget {
  final String language;
  final Function(VpnServer)? onServerAdded;
  const TorScreen({super.key, this.language = 'fa', this.onServerAdded});

  @override
  State<TorScreen> createState() => _TorScreenState();
}

class _TorScreenState extends State<TorScreen> {
  static const List<Map<String, String>> _bridgeTypes = [
    {'id': 'vanilla', 'fa': 'Tor ساده (بدون پل)', 'en': 'Vanilla (no bridge)'},
    {'id': 'obfs4', 'fa': 'Obfs4 (پیشنهادی)', 'en': 'Obfs4 (recommended)'},
    {'id': 'snowflake', 'fa': 'Snowflake', 'en': 'Snowflake'},
    {'id': 'meek_lite', 'fa': 'Meek Lite', 'en': 'Meek Lite'},
    {'id': 'conjure', 'fa': 'Conjure', 'en': 'Conjure'},
    {'id': 'dnstt', 'fa': 'DNSTT', 'en': 'DNSTT'},
  ];

  String _bridgeType = 'obfs4';
  String _mode = 'real'; // 'real' | 'stealth'

  // ---- State برای Tor Stealth (از AddConfig منتقل شده)
  String _aetherProtocol = 'masque';
  String _aetherIp = 'v4';
  final TextEditingController _stealthPeerCtrl = TextEditingController();
  final TextEditingController _stealthNameCtrl = TextEditingController();
  static final RegExp _peerRegex =
      RegExp(r'^(\[[0-9a-fA-F:.]+\]|[0-9.]+):\d{1,5}$');
  String _selectedSni = TorSniPresets.defaultSni;
  List<String> _customBridges = [];
  bool _running = false;
  bool _connecting = false;
  int _bootstrap = 0;
  String _bootstrapMsg = '';
  int _socksPort = 0;
  String? _error;
  Timer? _pollTimer;
  bool _routingThroughVpn = false;
  bool _routing = false;

  bool get _isFa => widget.language == 'fa';
  String _t(String fa, String en) => _isFa ? fa : en;

  @override
  void initState() {
    super.initState();
    _loadPrefs();
    _pollTimer = Timer.periodic(const Duration(seconds: 1), (_) => _poll());
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _stealthPeerCtrl.dispose();
    _stealthNameCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final bt = prefs.getString('tor_bridge_type') ?? 'obfs4';
    final cb = prefs.getStringList('tor_custom_bridges') ?? <String>[];
    final sni = prefs.getString('tor_sni') ?? TorSniPresets.defaultSni;
    if (!mounted) return;
    setState(() {
      _bridgeType = bt;
      _customBridges = cb;
      _selectedSni = sni;
    });
  }

  Future<void> _savePrefs() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('tor_bridge_type', _bridgeType);
    await prefs.setStringList('tor_custom_bridges', _customBridges);
    await prefs.setString('tor_sni', _selectedSni);
  }

  Future<void> _poll() async {
    try {
      final s = await TorService.status();
      if (!mounted) return;
      final running = s['running'] == true;
      final bp = (s['bootstrapPercent'] as num?)?.toInt() ?? 0;
      final msg = s['bootstrapMessage']?.toString() ?? '';
      final port = (s['socksPort'] as num?)?.toInt() ?? 0;
      final err = s['error']?.toString();
      if (running != _running ||
          bp != _bootstrap ||
          msg != _bootstrapMsg ||
          port != _socksPort ||
          err != _error) {
        setState(() {
          _running = running;
          _bootstrap = bp;
          _bootstrapMsg = msg;
          _socksPort = port;
          _error = (err == null || err.isEmpty) ? null : err;
          if (!running) {
            if (_connecting) _connecting = false;
            if (_routingThroughVpn) {
              _routingThroughVpn = false;
              // stop Xray routing as well
              unawaited(V2RayEngine.disconnect());
            }
          }
        });
      }
    } catch (_) {}
  }

  /// کانفیگ Xray برای روت ترافیک از طریق Tor.
  /// inbound: SOCKS روی 10808 → outbound: SOCKS به 127.0.0.1:9050
  String _buildTorXrayConfig() {
    final cfg = <String, dynamic>{
      'inbounds': [
        {
          'tag': 'socks-in',
          'port': 10808,
          'listen': '127.0.0.1',
          'protocol': 'socks',
          'settings': {
            'auth': 'noauth',
            'udp': true,
            'address': '127.0.0.1',
          },
          'sniffing': {
            'enabled': true,
            'destOverride': ['http', 'tls', 'quic'],
          },
        },
      ],
      'outbounds': [
        {
          'tag': 'tor-out',
          'protocol': 'socks',
          'settings': {
            'servers': [
              {
                'address': '127.0.0.1',
                'port': _socksPort > 0 ? _socksPort : 9050,
              },
            ],
          },
        },
        {
          'tag': 'direct',
          'protocol': 'freedom',
        },
      ],
      'routing': {
        'domainStrategy': 'AsIs',
        'rules': [],
      },
    };
    return jsonEncode(cfg);
  }

  /// بعد از Bootstrap کامل، Xray را با SOCKS Tor راه می‌اندازیم تا
  /// کل ترافیک گوشی از Tor رد شود و VPN icon ظاهر شود.
  Future<void> _startVpnRouting() async {
    if (_routingThroughVpn || _routing) return;
    setState(() => _routing = true);
    try {
      // یک سرور جعلی می‌سازیم فقط برای نمایش در Telemetry
      final fakeServer = VpnServer(
        id: 'tor_${DateTime.now().millisecondsSinceEpoch}',
        name: 'Tor',
        flag: '🧅',
        shareLink: 'xrayjson://tor',
        protocol: VpnProtocol.xrayJson,
        host: '127.0.0.1',
        port: _socksPort > 0 ? _socksPort : 9050,
        isDeletable: false,
      );
      final ok = await V2RayEngine.startConfig(
        remark: 'Tor',
        config: _buildTorXrayConfig(),
        server: fakeServer,
      );
      if (!mounted) return;
      setState(() {
        _routingThroughVpn = ok;
        _routing = false;
        if (!ok) {
          _error = 'VPN routing failed: ${V2RayEngine.lastError ?? "unknown"}';
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _routing = false;
        _error = 'VPN routing error: $e';
      });
    }
  }

  Future<void> _stopVpnRouting() async {
    if (!_routingThroughVpn) return;
    try {
      await V2RayEngine.disconnect();
    } catch (_) {}
    if (!mounted) return;
    setState(() => _routingThroughVpn = false);
  }

  Future<void> _toggle() async {
    if (_connecting) return;
    if (_running) {
      setState(() => _connecting = true);
      await _stopVpnRouting();
      await TorService.stop();
      if (!mounted) return;
      setState(() {
        _running = false;
        _connecting = false;
        _bootstrap = 0;
        _bootstrapMsg = '';
      });
      return;
    }
    setState(() {
      _connecting = true;
      _bootstrap = 0;
      _bootstrapMsg = _t('شروع...', 'Starting...');
      _error = null;
    });
    final r = await TorService.start(
      bridgeType: _bridgeType,
      customBridges: _customBridges.isEmpty ? null : _customBridges,
      sni: _selectedSni,
    );
    if (!mounted) return;
    if (r['ok'] != true) {
      setState(() {
        _connecting = false;
        _error = r['error']?.toString() ?? 'unknown error';
      });
    } else {
      setState(() {
        _running = true;
        _socksPort = (r['socksPort'] as num?)?.toInt() ?? 9050;
      });
      // بعد از اینکه Tor بالا آمد، ترافیک را از آن رد کن
      unawaited(_startVpnRouting());
    }
  }

  Future<void> _addBridge() async {
    final ctrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.elevated(ctx),
        title: Text(_t('افزودن پل شخصی', 'Add custom bridge'),
            style: TextStyle(color: AppColors.fg(ctx))),
        content: TextField(
          controller: ctrl,
          maxLines: 3,
          style: TextStyle(color: AppColors.fg(ctx), fontSize: 12),
          decoration: InputDecoration(
            hintText: 'obfs4 1.2.3.4:1234 FINGERPRINT cert=... iat-mode=0',
            hintStyle: TextStyle(color: AppColors.muted2(ctx), fontSize: 11),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(_t('لغو', 'Cancel'),
                style: TextStyle(color: AppColors.muted(ctx))),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(_t('افزودن', 'Add'),
                style: const TextStyle(color: AppColors.accent)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final line = ctrl.text.trim();
    if (line.isEmpty) return;
    setState(() => _customBridges.add(line));
    await _savePrefs();
  }

  Future<void> _removeBridge(int i) async {
    setState(() => _customBridges.removeAt(i));
    await _savePrefs();
  }

  Widget _bridgeSelector() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.surface(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border(context)),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: _bridgeType,
          isExpanded: true,
          dropdownColor: AppColors.elevated(context),
          style: TextStyle(color: AppColors.fg(context), fontSize: 14),
          icon: const Icon(Icons.expand_more, color: AppColors.accent),
          items: [
            for (final bt in _bridgeTypes)
              DropdownMenuItem<String>(
                value: bt['id'],
                child: Text(_isFa ? bt['fa']! : bt['en']!),
              ),
          ],
          onChanged: (v) async {
            if (v == null) return;
            setState(() => _bridgeType = v);
            await _savePrefs();
          },
        ),
      ),
    );
  }

  Widget _connectButton() {
    final active = _running;
    final busy = _connecting;
    return GestureDetector(
      onTap: busy ? null : _toggle,
      child: Container(
        width: 150,
        height: 150,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
            color: active ? AppColors.accent : AppColors.border(context),
            width: 3,
          ),
          color: active
              ? AppColors.accent.withOpacity(0.15)
              : Colors.transparent,
          boxShadow: active
              ? [
                  BoxShadow(
                    color: AppColors.accent.withOpacity(0.3),
                    blurRadius: 20,
                    spreadRadius: 2,
                  ),
                ]
              : null,
        ),
        child: Center(
          child: busy
              ? Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    SizedBox(
                      width: 48,
                      height: 48,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          CircularProgressIndicator(
                            value: _bootstrap > 0 ? _bootstrap / 100 : null,
                            strokeWidth: 3,
                            color: AppColors.accent,
                            backgroundColor:
                                AppColors.border(context),
                          ),
                          Center(
                            child: Text(
                              '$_bootstrap%',
                              style: const TextStyle(
                                color: AppColors.accent,
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _t('اتصال...', 'Connecting...'),
                      style: TextStyle(
                          color: AppColors.muted(context), fontSize: 11),
                    ),
                  ],
                )
              : Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      active ? Icons.shield : Icons.power_settings_new,
                      size: 44,
                      color: active
                          ? AppColors.accent
                          : AppColors.muted2(context),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      active
                          ? _t('قطع اتصال', 'Disconnect')
                          : _t('اتصال', 'Connect'),
                      style: TextStyle(
                        color: active
                            ? AppColors.accent
                            : AppColors.muted2(context),
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (active && _socksPort > 0)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          'SOCKS: $_socksPort',
                          style: TextStyle(
                              color: AppColors.muted2(context),
                              fontSize: 10),
                        ),
                      ),
                  ],
                ),
        ),
      ),
    );
  }

  // -------------------------------------------------------------- Stealth

  void _addStealthServer() {
    final peer = _stealthPeerCtrl.text.trim();
    if (peer.isNotEmpty && !_peerRegex.hasMatch(peer)) {
      _showSnack(_t('آدرس Endpoint باید ip:port باشد',
          'Endpoint must be ip:port'));
      return;
    }
    final profile = AetherProfile(
      protocol: _aetherProtocol,
      scan: 'stealth',
      noize: 'aggressive',
      ip: _aetherIp,
      peer: peer,
      quickReconnect: false,
      blockQuic: true,
      perf: 'medium',
    );
    final typed = _stealthNameCtrl.text.trim();
    final name = typed.isNotEmpty ? typed : 'Tor Stealth · ${profile.summary}';
    final server = VpnServer(
      id: 'tor_stealth_${DateTime.now().millisecondsSinceEpoch}',
      name: name,
      flag: '🧅',
      shareLink: profile.toLink(),
      protocol: VpnProtocol.aether,
      host: peer.isNotEmpty ? peer.split(':').first : 'stealth-auto',
      port: 0,
      isDeletable: true,
    );
    widget.onServerAdded?.call(server);
    _showSnack(_t('سرور Tor Stealth اضافه شد', 'Tor Stealth server added'));
  }

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), duration: const Duration(seconds: 2)),
    );
  }

  Widget _modeSwitcher() {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.surface(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border(context)),
      ),
      child: Row(
        children: [
          Expanded(
            child: GestureDetector(
              onTap: () => setState(() => _mode = 'real'),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color: _mode == 'real'
                      ? AppColors.accent.withOpacity(0.18)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.security,
                        size: 16,
                        color: _mode == 'real'
                            ? AppColors.accent
                            : AppColors.muted(context)),
                    const SizedBox(width: 6),
                    Text(
                      _t('Tor واقعی', 'Real Tor'),
                      style: TextStyle(
                        color: _mode == 'real'
                            ? AppColors.accent
                            : AppColors.muted(context),
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Expanded(
            child: GestureDetector(
              onTap: () => setState(() => _mode = 'stealth'),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color: _mode == 'stealth'
                      ? const Color(0xFFEF5350).withOpacity(0.18)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.visibility_off,
                        size: 16,
                        color: _mode == 'stealth'
                            ? const Color(0xFFEF5350)
                            : AppColors.muted(context)),
                    const SizedBox(width: 6),
                    Text(
                      _t('Tor Stealth', 'Tor Stealth'),
                      style: TextStyle(
                        color: _mode == 'stealth'
                            ? const Color(0xFFEF5350)
                            : AppColors.muted(context),
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStealthForm() {
    const red = Color(0xFFEF5350);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: red.withOpacity(0.08),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: red.withOpacity(0.35)),
          ),
          child: Text(
            _t(
              'حالت Tor Stealth از مسیر stealth هسته Aether با پنهان‌کاری قوی استفاده می‌کند (نه شبکه رسمی Tor). برای فیلترینگ خیلی سخت مناسب است.',
              'Tor Stealth uses Aether stealth path with strong obfuscation (not the official Tor network). Best for heavy filtering.',
            ),
            style: TextStyle(
                color: AppColors.muted(context), fontSize: 12, height: 1.5),
          ),
        ),
        const SizedBox(height: 16),
        Text(_t('پروتکل پایه', 'Base protocol'),
            style: TextStyle(
                color: AppColors.muted(context),
                fontSize: 13,
                fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final p in const ['masque', 'masque_h2', 'wg', 'mim'])
              ChoiceChip(
                label: Text(p.toUpperCase()),
                selected: _aetherProtocol == p,
                selectedColor: red.withOpacity(0.25),
                labelStyle: TextStyle(
                  color: _aetherProtocol == p
                      ? red
                      : AppColors.muted(context),
                  fontSize: 12,
                ),
                onSelected: (_) => setState(() => _aetherProtocol = p),
              ),
          ],
        ),
        const SizedBox(height: 14),
        Text(_t('نسخه IP', 'IP version'),
            style: TextStyle(
                color: AppColors.muted(context),
                fontSize: 13,
                fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          children: [
            for (final ip in const ['v4', 'v6', 'both'])
              ChoiceChip(
                label: Text(ip == 'both' ? _t('هر دو', 'Both') : ip.toUpperCase()),
                selected: _aetherIp == ip,
                selectedColor: red.withOpacity(0.25),
                labelStyle: TextStyle(
                  color: _aetherIp == ip ? red : AppColors.muted(context),
                  fontSize: 12,
                ),
                onSelected: (_) => setState(() => _aetherIp = ip),
              ),
          ],
        ),
        const SizedBox(height: 14),
        Text(_t('Endpoint دستی (اختیاری)', 'Manual endpoint (optional)'),
            style: TextStyle(
                color: AppColors.muted(context),
                fontSize: 13,
                fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        TextField(
          controller: _stealthPeerCtrl,
          style: TextStyle(color: AppColors.fg(context), fontSize: 13),
          decoration: InputDecoration(
            hintText: '162.159.192.1:2408',
            hintStyle: TextStyle(color: AppColors.muted2(context)),
            filled: true,
            fillColor: AppColors.surface(context),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: AppColors.border(context)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: AppColors.border(context)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: red, width: 1.5),
            ),
          ),
        ),
        const SizedBox(height: 14),
        Text(_t('نام (اختیاری)', 'Name (optional)'),
            style: TextStyle(
                color: AppColors.muted(context),
                fontSize: 13,
                fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        TextField(
          controller: _stealthNameCtrl,
          style: TextStyle(color: AppColors.fg(context)),
          decoration: InputDecoration(
            hintText: _t('مثال: Tor Stealth من', 'e.g. My Tor Stealth'),
            hintStyle: TextStyle(color: AppColors.muted2(context)),
            filled: true,
            fillColor: AppColors.surface(context),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: AppColors.border(context)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: AppColors.border(context)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: red, width: 1.5),
            ),
          ),
        ),
        const SizedBox(height: 20),
        SizedBox(
          width: double.infinity,
          height: 50,
          child: ElevatedButton(
            onPressed: _addStealthServer,
            style: ElevatedButton.styleFrom(
              backgroundColor: red,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            child: Text(
              _t('افزودن سرور Tor Stealth', 'Add Tor Stealth server'),
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
            ),
          ),
        ),
      ],
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
        title: Text(_t('Tor', 'Tor'),
            style: TextStyle(color: AppColors.fg(context))),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _modeSwitcher(),
            const SizedBox(height: 16),
            if (_mode == 'real') ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.surface(context),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.border(context)),
              ),
              child: Text(
                _t(
                  'اتصال از طریق شبکه Tor با پشتیبانی از پل‌های مخفی‌سازی (obfs4, snowflake و...). اگر Tor ساده کار نکرد، obfs4 را امتحان کنید.',
                  'Connect via Tor network with support for obfuscation bridges (obfs4, snowflake, etc). If vanilla Tor fails, try obfs4.',
                ),
                style: TextStyle(
                    color: AppColors.muted(context), fontSize: 12, height: 1.6),
              ),
            ),
            const SizedBox(height: 16),

            Text(
              _t('نوع پل', 'Bridge type'),
              style: TextStyle(
                color: AppColors.muted(context),
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            _bridgeSelector(),
            const SizedBox(height: 16),

            if (_bridgeType == 'obfs4' ||
                _bridgeType == 'meek_lite' ||
                _bridgeType == 'conjure' ||
                _bridgeType == 'dnstt') ...[
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    _t('پل‌های شخصی (${_customBridges.length})',
                        'Custom bridges (${_customBridges.length})'),
                    style: TextStyle(
                      color: AppColors.muted(context),
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  TextButton.icon(
                    onPressed: _addBridge,
                    icon: const Icon(Icons.add,
                        color: AppColors.accent, size: 18),
                    label: Text(_t('افزودن', 'Add'),
                        style: const TextStyle(color: AppColors.accent)),
                  ),
                ],
              ),
              if (_customBridges.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    _t(
                      'بدون پل شخصی، از پل‌های پیش‌فرض استفاده می‌شود (ممکن است مسدود باشند).',
                      'Without custom bridges, default bridges are used (may be blocked).',
                    ),
                    style: TextStyle(
                        color: AppColors.muted2(context), fontSize: 11),
                  ),
                )
              else
                for (var i = 0; i < _customBridges.length; i++)
                  Container(
                    margin: const EdgeInsets.only(bottom: 6),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppColors.surface(context),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AppColors.border(context)),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Directionality(
                            textDirection: TextDirection.ltr,
                            child: Text(
                              _customBridges[i],
                              style: TextStyle(
                                color: AppColors.fg(context),
                                fontSize: 11,
                                fontFamily: 'monospace',
                              ),
                              maxLines: 3,
                            ),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close,
                              color: AppColors.danger, size: 18),
                          onPressed: () => _removeBridge(i),
                        ),
                      ],
                    ),
                  ),
              const SizedBox(height: 20),
            ],

            // انتخاب SNI (برای meek_lite و snowflake)
            if (_bridgeType == 'meek_lite' || _bridgeType == 'snowflake') ...[
              Text(
                _t('نام میزبان SNI (جعل نام سرور)',
                    'SNI hostname (fake server name)'),
                style: TextStyle(
                  color: AppColors.muted(context),
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.surface(context),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.border(context)),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: _selectedSni,
                    isExpanded: true,
                    dropdownColor: AppColors.elevated(context),
                    style: TextStyle(color: AppColors.fg(context), fontSize: 13),
                    icon: const Icon(Icons.expand_more, color: AppColors.accent),
                    items: [
                      for (final s in TorSniPresets.all)
                        DropdownMenuItem<String>(
                          value: s,
                          child: Text(s, overflow: TextOverflow.ellipsis),
                        ),
                    ],
                    onChanged: (v) async {
                      if (v == null) return;
                      setState(() => _selectedSni = v);
                      await _savePrefs();
                    },
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                _t(
                  'این نام در TLS handshake جعل می‌شود تا DPI فریب بخورد.',
                  'This name is spoofed in TLS handshake to evade DPI.',
                ),
                style: TextStyle(color: AppColors.muted2(context), fontSize: 11),
              ),
              const SizedBox(height: 16),
            ],

            Center(child: _connectButton()),
            const SizedBox(height: 20),

            if (_bootstrapMsg.isNotEmpty && _connecting)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.surface(context),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.border(context)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            _t('پیشرفت اتصال', 'Bootstrap progress'),
                            style: TextStyle(
                              color: AppColors.muted(context),
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        Text(
                          '$_bootstrap%',
                          style: const TextStyle(
                            color: AppColors.accent,
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    LinearProgressIndicator(
                      value: _bootstrap > 0 ? _bootstrap / 100 : null,
                      color: AppColors.accent,
                      backgroundColor: AppColors.border(context),
                    ),
                    const SizedBox(height: 8),
                    Directionality(
                      textDirection: TextDirection.ltr,
                      child: Text(
                        _bootstrapMsg,
                        style: TextStyle(
                            color: AppColors.muted2(context),
                            fontSize: 11,
                            fontFamily: 'monospace'),
                      ),
                    ),
                  ],
                ),
              ),

            if (_error != null && _error!.isNotEmpty)
              Container(
                margin: const EdgeInsets.only(top: 12),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.danger.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.danger),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.error_outline,
                        color: AppColors.danger, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _error!,
                        style:
                            const TextStyle(color: AppColors.danger, fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),

            if (_running && _bootstrap >= 100)
              Container(
                margin: const EdgeInsets.only(top: 12),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.accent.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.accent),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.check_circle,
                        color: AppColors.accent, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _t(
                          'متصل به Tor · پورت SOCKS: $_socksPort',
                          'Connected to Tor · SOCKS port: $_socksPort',
                        ),
                        style: const TextStyle(
                            color: AppColors.accent, fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            ] else ...[
              _buildStealthForm(),
            ],
          ],
        ),
      ),
    );
  }
}
