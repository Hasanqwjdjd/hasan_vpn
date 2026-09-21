import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/server.dart';
import '../services/app_colors.dart';
import '../services/tor_service.dart';
import '../services/v2ray_engine.dart';

class TorScreen extends StatefulWidget {
  final String language;
  const TorScreen({super.key, this.language = 'fa'});

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
    super.dispose();
  }

  Future<void> _loadPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final bt = prefs.getString('tor_bridge_type') ?? 'obfs4';
    final cb = prefs.getStringList('tor_custom_bridges') ?? <String>[];
    if (!mounted) return;
    setState(() {
      _bridgeType = bt;
      _customBridges = cb;
    });
  }

  Future<void> _savePrefs() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('tor_bridge_type', _bridgeType);
    await prefs.setStringList('tor_custom_bridges', _customBridges);
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
        ),
      ),
    );
  }
}
