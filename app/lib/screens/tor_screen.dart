import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/server.dart';
import '../services/app_colors.dart';
import '../services/home_widget_service.dart';
import '../services/network_prober.dart';
import '../services/tor_bridges.dart';
import '../services/tor_service.dart';
import '../services/tor_sni_presets.dart';
import '../services/v2ray_engine.dart';

class TorScreen extends StatefulWidget {
  final String language;
  final String? initialBridgeLine;
  final bool autoConnect;

  const TorScreen({
    super.key,
    this.language = 'fa',
    this.initialBridgeLine,
    this.autoConnect = false,
  });

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
  String _selectedSni = TorSniPresets.defaultSni;
  bool _sniEnabled = false;
  bool _sniAutoPicking = false;
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

  /// پینگ TCP هر خط پل (کلید = خود خط پل)
  final Map<String, int?> _bridgePings = {};
  bool _pingingBridges = false;
  /// پل‌های رایگان اضافه از دکمه «جدید»
  final List<String> _extraFreeBridges = [];

  bool get _isFa => widget.language == 'fa';
  String _t(String fa, String en) => _isFa ? fa : en;

  @override
  void initState() {
    super.initState();
    _loadPrefs().then((_) async {
      final line = widget.initialBridgeLine?.trim();
      if (line != null && line.isNotEmpty) {
        final type = line.split(RegExp(r'\s+')).first.toLowerCase();
        if (!mounted) return;
        setState(() {
          if (_bridgeTypes.any((e) => e['id'] == type)) {
            _bridgeType = type;
          }
          if (!_customBridges.contains(line)) {
            _customBridges.insert(0, line);
          }
        });
        await _savePrefs();
      }
      if (widget.autoConnect && mounted && !_running && !_connecting) {
        await _toggle();
      }
    });
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
    final sni = prefs.getString('tor_sni') ?? TorSniPresets.defaultSni;
    final sniOn = prefs.getBool('tor_sni_enabled') ?? false;
    if (!mounted) return;
    setState(() {
      _bridgeType = bt;
      _customBridges = cb;
      _selectedSni = sni;
      _sniEnabled = sniOn;
    });
  }

  Future<void> _savePrefs() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('tor_bridge_type', _bridgeType);
    await prefs.setStringList('tor_custom_bridges', _customBridges);
    await prefs.setString('tor_sni', _selectedSni);
    await prefs.setBool('tor_sni_enabled', _sniEnabled);
  }

  /// انتخاب خودکار SNI: DNS resolve چند دامنه و اولین پاسخ‌دهنده
  Future<void> _autoPickSni() async {
    if (_sniAutoPicking) return;
    setState(() => _sniAutoPicking = true);
    // لیست InviZible-style + presetهای محلی
    final candidates = <String>{
      'play.googleapis.com',
      'drive.google.com',
      'cdn.ampproject.org',
      'api.github.com',
      'ajax.aspnetcdn.com',
      'verizon.com',
      'eset.com',
      ...TorSniPresets.all.take(20),
    }.toList();
    String? best;
    for (final host in candidates) {
      try {
        final r = await NetworkProber.probeTcp(
          host,
          port: 443,
          samples: 1,
          timeout: const Duration(milliseconds: 900),
        );
        if (r.avgMs != null) {
          best = host;
          break;
        }
      } catch (_) {}
    }
    if (!mounted) return;
    setState(() {
      _selectedSni = best ?? TorSniPresets.defaultSni;
      _sniAutoPicking = false;
    });
    await _savePrefs();
    if (best != null) {
      _snack(_t('SNI خودکار: $best', 'Auto SNI: $best'));
    }
  }

  Future<void> _showSniListDialog() async {
    final ctrl = TextEditingController(
      text: [
        'play.googleapis.com',
        'drive.google.com',
        'cdn.ampproject.org',
        'api.github.com',
        'ajax.aspnetcdn.com',
        'verizon.com',
        'eset.com',
        if (!TorSniPresets.all.contains(_selectedSni)) _selectedSni,
      ].join(', '),
    );
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.elevated(ctx),
        title: Text(
          _t('جعل نشانگر نام سرور', 'Server name indication'),
          style: TextStyle(color: AppColors.fg(ctx)),
        ),
        content: SingleChildScrollView(
          child: TextField(
            controller: ctrl,
            maxLines: 8,
            style: TextStyle(color: AppColors.fg(ctx), fontSize: 13),
            decoration: InputDecoration(
              hintText: 'domain1.com, domain2.com, ...',
              hintStyle: TextStyle(color: AppColors.muted2(ctx)),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
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
            child: const Text('OK', style: TextStyle(color: AppColors.accent)),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final parts = ctrl.text
        .split(RegExp(r'[,;\s]+'))
        .map((e) => e.trim())
        .where((e) => e.contains('.'))
        .toList();
    if (parts.isNotEmpty) {
      setState(() => _selectedSni = parts.first);
      await _savePrefs();
    }
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
      final prevBootstrap = _bootstrap;
      if (running != _running ||
          bp != _bootstrap ||
          msg != _bootstrapMsg ||
          port != _socksPort ||
          err != _error) {
        setState(() {
          _running = running;
          _bootstrap = bp;
          _bootstrapMsg = _friendlyBootstrap(msg);
          _socksPort = port;
          _error = (err == null || err.isEmpty)
              ? null
              : _localizeError(err);
          // بعد از بالا آمدن Tor، حالت «در حال اتصال» را تمام کن
          if (running && bp > 0) {
            _connecting = false;
          }
          if (!running) {
            _connecting = false;
            if (_routingThroughVpn) {
              _routingThroughVpn = false;
              unawaited(V2RayEngine.disconnect());
            }
          }
        });
        // روتینگ VPN فقط بعد از Bootstrap کامل (نه بلافاصله بعد از start)
        if (running &&
            bp >= 100 &&
            prevBootstrap < 100 &&
            !_routingThroughVpn &&
            !_routing) {
          unawaited(_startVpnRouting());
        }
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
          _error = _localizeError(
              'VPN routing failed: ${V2RayEngine.lastError ?? "unknown"}');
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _routing = false;
        _error = _localizeError('VPN routing error: $e');
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

  bool get _settingsLocked => _running || _connecting;

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), duration: const Duration(seconds: 2)),
    );
  }

  Future<void> _toggle() async {
    if (_connecting) return;
    if (_running) {
      setState(() {
        _connecting = true;
        _error = null;
      });
      await _stopVpnRouting();
      await TorService.stop();
      if (!mounted) return;
      setState(() {
        _running = false;
        _connecting = false;
        _bootstrap = 0;
        _bootstrapMsg = '';
        _socksPort = 0;
        _routingThroughVpn = false;
        _routing = false;
        _error = null;
      });
      _snack(_t('اتصال Tor قطع شد', 'Tor disconnected'));
      return;
    }
    setState(() {
      _connecting = true;
      _bootstrap = 0;
      _bootstrapMsg = _t('شروع...', 'Starting...');
      _error = null;
    });
    // کم‌پینگ‌ترین پل‌ها (حداکثر ۴) برای سرعت بهتر
    final bridgesToUse = _bridgesForConnect();
    final r = await TorService.start(
      bridgeType: _bridgeType,
      customBridges: bridgesToUse.isEmpty ? null : bridgesToUse,
      sni: _sniEnabled ? _selectedSni : null,
    );
    if (!mounted) return;
    if (r['ok'] != true) {
      setState(() {
        _connecting = false;
        _running = false;
        _error = _localizeError(r['error']?.toString() ?? 'unknown error');
      });
    } else {
      setState(() {
        _running = true;
        _connecting = false;
        _socksPort = (r['socksPort'] as num?)?.toInt() ?? 9050;
        _bootstrapMsg = _t('در حال Bootstrap…', 'Bootstrapping…');
      });
    }
  }

  String _localizeError(String raw) {
    final lower = raw.toLowerCase();
    if (lower.contains('already') || lower.contains('running')) {
      return _t('Tor از قبل در حال اجراست', 'Tor is already running');
    }
    if (lower.contains('permission') || lower.contains('denied')) {
      return _t('دسترسی کافی نیست', 'Permission denied');
    }
    if (lower.contains('binary') ||
        lower.contains('libtor') ||
        lower.contains('not found')) {
      return _t('باینری Tor پیدا نشد', 'Tor binary not found');
    }
    if (lower.contains('timeout')) {
      return _t('زمان اتصال تمام شد', 'Connection timed out');
    }
    if (lower.contains('vpn routing') || lower.contains('routing')) {
      return _t(
        'روتینگ VPN ناموفق بود — دوباره وصل شوید',
        'VPN routing failed — try connecting again',
      );
    }
    if (lower.contains('bridge')) {
      return _t(
        'مشکل در پل‌ها — نوع دیگری امتحان کنید یا پل شخصی بگذارید',
        'Bridge problem — try another type or add a custom bridge',
      );
    }
    if (lower.contains('dnstt')) {
      return _t(
        'DNSTT قطع شد — دامنه+pubkey واقعی (سبک Slipnet) لازم است یا از obfs4 استفاده کنید',
        'DNSTT failed — need real domain+pubkey (Slipnet-style), or use obfs4',
      );
    }
    if (lower.contains('conjure') ||
        lower.contains('registration fail') ||
        lower.contains('libconjure')) {
      return _t(
        'Conjure ثبت‌نام نشد — پل ساختگی یا شبکه refraction در دسترس نیست. obfs4 یا snowflake را امتحان کنید.',
        'Conjure registration failed — dummy bridge or refraction unreachable. Try obfs4 or snowflake.',
      );
    }
    if (lower.contains('exited') || lower.contains('exit')) {
      return _t(
        'پروسه Tor فوری بسته شد — نوع پل یا پلاگین را عوض کنید',
        'Tor exited immediately — change bridge type or plugin',
      );
    }
    return raw;
  }

  String _friendlyBootstrap(String msg) {
    if (msg.isEmpty) return msg;
    final lower = msg.toLowerCase();
    if (lower.contains('bootstrapped 100') || lower.contains('done')) {
      return _t('Bootstrap کامل شد', 'Bootstrap complete');
    }
    if (lower.contains('connecting') || lower.contains('handshake')) {
      return _t('در حال برقراری ارتباط…', 'Handshaking…');
    }
    if (lower.contains('loading') || lower.contains('consensus')) {
      return _t('در حال بارگذاری شبکه Tor…', 'Loading Tor network…');
    }
    if (lower.contains('starting')) {
      return _t('در حال راه‌اندازی…', 'Starting…');
    }
    return msg;
  }

  Future<void> _addBridge() async {
    if (_settingsLocked) {
      _snack(_t(
        'اول اتصال را قطع کنید، بعد تنظیمات را عوض کنید',
        'Disconnect first, then change settings',
      ));
      return;
    }
    final ctrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.elevated(ctx),
        title: Text(_t('افزودن پل شخصی', 'Add custom bridge'),
            style: TextStyle(color: AppColors.fg(ctx))),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: ctrl,
              maxLines: 4,
              style: TextStyle(color: AppColors.fg(ctx), fontSize: 12),
              decoration: InputDecoration(
                hintText:
                    'obfs4 1.2.3.4:1234 FINGERPRINT cert=... iat-mode=0',
                hintStyle:
                    TextStyle(color: AppColors.muted2(ctx), fontSize: 11),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () async {
                  final data = await Clipboard.getData(Clipboard.kTextPlain);
                  final t = data?.text?.trim() ?? '';
                  if (t.isNotEmpty) ctrl.text = t;
                },
                icon: const Icon(Icons.paste, size: 16),
                label: Text(_t('از کلیپ‌بورد', 'From clipboard')),
              ),
            ),
          ],
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
    // چند خط پل را هم پشتیبانی کن
    final lines = line
        .split(RegExp(r'[\r\n]+'))
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    setState(() {
      for (final l in lines) {
        if (!_customBridges.contains(l)) _customBridges.add(l);
      }
    });
    await _savePrefs();
    _snack(_t(
      '${lines.length} پل اضافه شد',
      '${lines.length} bridge(s) added',
    ));
  }

  Future<void> _removeBridge(int i) async {
    if (_settingsLocked) {
      _snack(_t(
        'اول اتصال را قطع کنید',
        'Disconnect first',
      ));
      return;
    }
    setState(() => _customBridges.removeAt(i));
    await _savePrefs();
  }

  Future<void> _clearCustomBridges() async {
    if (_settingsLocked) {
      _snack(_t('اول اتصال را قطع کنید', 'Disconnect first'));
      return;
    }
    if (_customBridges.isEmpty) return;
    setState(() => _customBridges.clear());
    await _savePrefs();
    _snack(_t('پل‌های شخصی پاک شدند', 'Custom bridges cleared'));
  }

  /// پینگ TCP همهٔ پل‌های رایگان (+ شخصی) نوع فعلی
  Future<void> _pingAllBridges() async {
    if (_pingingBridges) return;
    final list = <String>{
      ...TorBridges.forType(_bridgeType, sni: _selectedSni),
      ..._customBridges,
    }.toList();
    if (list.isEmpty) {
      _snack(_t(
        'برای این نوع پل، endpoint قابل پینگ نیست',
        'No pingable endpoints for this bridge type',
      ));
      return;
    }
    setState(() {
      _pingingBridges = true;
      _bridgePings.clear();
    });
    await NetworkProber.runBatched<String>(
      list,
      6,
      (line) async {
        final ep = TorBridges.parseEndpoint(line);
        if (ep == null) {
          if (mounted) setState(() => _bridgePings[line] = null);
          return;
        }
        final r = await NetworkProber.probeTcp(
          ep.host,
          port: ep.port,
          samples: 2,
          timeout: const Duration(seconds: 2),
        );
        if (!mounted) return;
        setState(() => _bridgePings[line] = r.avgMs);
      },
    );
    if (!mounted) return;
    setState(() => _pingingBridges = false);
    final ok = _bridgePings.values.where((v) => v != null && v > 0).length;
    _snack(_t(
      'پینگ $ok پل انجام شد',
      'Pinged $ok bridges',
    ));
  }

  /// پل‌هایی که برای اتصال استفاده می‌شوند: ترجیح کم‌پینگ‌ترین‌ها
  List<String> _bridgesForConnect() {
    if (_customBridges.isNotEmpty) {
      final withPing = List<String>.from(_customBridges);
      withPing.sort((a, b) {
        final pa = _bridgePings[a] ?? 99999;
        final pb = _bridgePings[b] ?? 99999;
        return pa.compareTo(pb);
      });
      return withPing.take(4).toList();
    }
    final free = TorBridges.forType(_bridgeType, sni: _selectedSni);
    final sorted = List<String>.from(free);
    sorted.sort((a, b) {
      final pa = _bridgePings[a] ?? 99999;
      final pb = _bridgePings[b] ?? 99999;
      return pa.compareTo(pb);
    });
    return sorted.take(4).toList();
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
          style: TextStyle(
            color: _settingsLocked
                ? AppColors.muted2(context)
                : AppColors.fg(context),
            fontSize: 14,
          ),
          icon: Icon(Icons.expand_more,
              color: _settingsLocked
                  ? AppColors.muted2(context)
                  : AppColors.accent),
          items: [
            for (final bt in _bridgeTypes)
              DropdownMenuItem<String>(
                value: bt['id'],
                child: Text(_isFa ? bt['fa']! : bt['en']!),
              ),
          ],
          onChanged: _settingsLocked
              ? null
              : (v) async {
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
            if (_bridgeType == 'snowflake' ||
                _bridgeType == 'meek_lite' ||
                _bridgeType == 'conjure')
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  _t(
                    'این نوع پل برای دور زدن فیلتر طراحی شده و معمولاً کندتر از obfs4 است. برای سرعت بیشتر obfs4 + پینگ پل‌ها را امتحان کنید.',
                    'This bridge type is for censorship resistance and is usually slower than obfs4. For speed, try obfs4 + bridge ping.',
                  ),
                  style: TextStyle(
                      color: AppColors.muted2(context), fontSize: 11, height: 1.4),
                ),
              ),
            if (_bridgeType == 'dnstt')
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  _t(
                    'DNSTT نیاز به پل معتبر (دامنه + resolver) دارد. بدون پل شخصی ممکن است فوری قطع شود. از اپراتور DNSTT خط پل بگیرید.',
                    'DNSTT needs a valid bridge (domain + resolver). Without a custom bridge it may disconnect immediately.',
                  ),
                  style: TextStyle(
                      color: AppColors.danger.withOpacity(0.85),
                      fontSize: 11,
                      height: 1.4),
                ),
              ),
            const SizedBox(height: 16),

            // ---- پل‌های رایگان هر نوع (قابل مشاهده برای کاربر) ----
            if (TorBridges.hasFree(_bridgeType)) ...[
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    _t(
                      'پل‌های رایگان (${TorBridges.forType(_bridgeType, sni: _selectedSni).length})',
                      'Free bridges (${TorBridges.forType(_bridgeType, sni: _selectedSni).length})',
                    ),
                    style: TextStyle(
                      color: AppColors.muted(context),
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (_pingingBridges)
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 8),
                      child: SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  else
                    IconButton(
                      tooltip: _t('پینگ پل‌ها', 'Ping bridges'),
                      onPressed: _pingAllBridges,
                      icon: const Icon(Icons.speed,
                          color: AppColors.accent, size: 20),
                    ),
                  TextButton(
                    onPressed: () {
                      final pool = TorBridges.extraPool(_bridgeType);
                      if (pool.isEmpty) {
                        _snack(_t(
                          'استخر جدیدی برای این نوع نیست',
                          'No extra pool for this type',
                        ));
                        return;
                      }
                      var n = 0;
                      setState(() {
                        for (final b in pool) {
                          if (!_extraFreeBridges.contains(b) &&
                              !TorBridges.forType(_bridgeType,
                                      sni: _selectedSni)
                                  .contains(b)) {
                            _extraFreeBridges.add(b);
                            n++;
                          }
                        }
                      });
                      _snack(n > 0
                          ? _t('$n پل رایگان جدید', '$n new free bridges')
                          : _t('پل جدیدی نبود', 'No new bridges'));
                    },
                    child: Text(
                      _t('جدید', 'New'),
                      style: const TextStyle(color: AppColors.accent, fontSize: 12),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: _settingsLocked
                        ? () => _snack(_t(
                              'اول اتصال را قطع کنید',
                              'Disconnect first',
                            ))
                        : () {
                            final free = [
                              ...TorBridges.forType(
                                  _bridgeType, sni: _selectedSni),
                              ..._extraFreeBridges.where((b) =>
                                  b.startsWith(_bridgeType) ||
                                  _bridgeType == 'meek_lite'),
                            ];
                            var added = 0;
                            setState(() {
                              for (final b in free) {
                                if (!_customBridges.contains(b)) {
                                  _customBridges.add(b);
                                  added++;
                                }
                              }
                            });
                            _savePrefs();
                            _snack(added > 0
                                ? _t('$added پل رایگان اضافه شد',
                                    '$added free bridge(s) added')
                                : _t('همه از قبل اضافه بودند',
                                    'All already added'));
                          },
                    icon: const Icon(Icons.download_outlined,
                        color: AppColors.accent, size: 18),
                    label: Text(
                      _t('افزودن همه', 'Add all'),
                      style: const TextStyle(color: AppColors.accent),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                _t(
                  'این پل‌ها رایگان‌اند و به‌صورت خودکار استفاده می‌شوند اگر پل شخصی نگذارید.',
                  'These free bridges are used automatically if you add no custom ones.',
                ),
                style: TextStyle(
                    color: AppColors.muted2(context), fontSize: 11),
              ),
              const SizedBox(height: 8),
              for (final b in [
                ...TorBridges.forType(_bridgeType, sni: _selectedSni),
                ..._extraFreeBridges,
              ])
                Container(
                  margin: const EdgeInsets.only(bottom: 6),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: AppColors.surface(context),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppColors.border(context)),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.lock_open,
                          color: AppColors.accent, size: 16),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Directionality(
                          textDirection: TextDirection.ltr,
                          child: Text(
                            TorBridges.shortLabel(b),
                            style: TextStyle(
                              color: AppColors.fg(context),
                              fontSize: 12,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                      if (_bridgePings.containsKey(b))
                        Padding(
                          padding: const EdgeInsets.only(right: 4),
                          child: Text(
                            _bridgePings[b] == null
                                ? '—'
                                : '${_bridgePings[b]}ms',
                            style: TextStyle(
                              color: (_bridgePings[b] ?? 999) < 200
                                  ? Colors.green
                                  : ((_bridgePings[b] ?? 999) < 500
                                      ? Colors.orange
                                      : AppColors.danger),
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      IconButton(
                        icon: const Icon(Icons.speed,
                            color: AppColors.warn, size: 18),
                        tooltip: _t('پینگ این پل', 'Ping this bridge'),
                        onPressed: () async {
                          final ep = TorBridges.parseEndpoint(b);
                          if (ep == null) {
                            _snack(_t(
                              'این پل endpoint قابل پینگ ندارد',
                              'No pingable endpoint',
                            ));
                            return;
                          }
                          final r = await NetworkProber.probeTcp(
                            ep.host,
                            port: ep.port,
                            samples: 2,
                          );
                          if (!mounted) return;
                          setState(() => _bridgePings[b] = r.avgMs);
                          _snack(r.avgMs == null
                              ? _t('بدون پاسخ', 'No response')
                              : _t('پینگ: ${r.avgMs}ms', 'Ping: ${r.avgMs}ms'));
                        },
                      ),
                      IconButton(
                        icon: Icon(Icons.share_outlined,
                            color: AppColors.muted2(context), size: 18),
                        tooltip: _t('اشتراک‌گذاری', 'Share'),
                        onPressed: () {
                          Clipboard.setData(ClipboardData(text: b));
                          _snack(_t(
                            'خط پل کپی شد',
                            'Bridge line copied',
                          ));
                        },
                      ),
                      IconButton(
                        icon: const Icon(Icons.widgets_outlined,
                            color: AppColors.accent, size: 18),
                        tooltip: _t('ویجت صفحهٔ اصلی', 'Home widget'),
                        onPressed: () async {
                          await HomeWidgetService.pin(
                            type: 'tor',
                            title: TorBridges.shortLabel(b),
                            subtitle: _bridgeType,
                            payload: b,
                          );
                          _snack(_t(
                            'به ویجت اضافه شد',
                            'Added to home widget',
                          ));
                        },
                      ),
                      IconButton(
                        icon: Icon(
                          _customBridges.contains(b)
                              ? Icons.check_circle
                              : Icons.add_circle_outline,
                          color: _customBridges.contains(b)
                              ? Colors.green
                              : AppColors.accent,
                          size: 20,
                        ),
                        onPressed: () {
                          if (_settingsLocked) {
                            _snack(_t(
                              'اول اتصال را قطع کنید',
                              'Disconnect first',
                            ));
                            return;
                          }
                          setState(() {
                            if (_customBridges.contains(b)) {
                              _customBridges.remove(b);
                            } else {
                              _customBridges.add(b);
                            }
                          });
                          _savePrefs();
                        },
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 16),
            ],

            // ---- پل‌های شخصی ----
            if (_bridgeType == 'obfs4' ||
                _bridgeType == 'meek_lite' ||
                _bridgeType == 'conjure' ||
                _bridgeType == 'dnstt' ||
                _bridgeType == 'snowflake') ...[
              Row(
                children: [
                  Expanded(
                    child: Text(
                      _t('پل‌های شخصی (${_customBridges.length})',
                          'Custom bridges (${_customBridges.length})'),
                      style: TextStyle(
                        color: AppColors.muted(context),
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  if (_customBridges.isNotEmpty)
                    TextButton(
                      onPressed: _clearCustomBridges,
                      child: Text(
                        _t('پاک‌کردن', 'Clear'),
                        style: TextStyle(
                            color: AppColors.danger, fontSize: 12),
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
                      'بدون پل شخصی، از پل‌های رایگان بالا استفاده می‌شود.',
                      'Without custom bridges, free bridges above are used.',
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

            // جعل نشانگر نام سرور — UI شبیه InviZible (سوییچ + لیست یکجا)
            if (_bridgeType == 'meek_lite' ||
                _bridgeType == 'snowflake' ||
                _bridgeType == 'obfs4') ...[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.surface(context),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.border(context)),
                ),
                child: SwitchListTile(
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
                  title: Text(
                    _t('جعل نشانگر نام سرور', 'Server name indication spoof'),
                    style: TextStyle(
                      color: AppColors.fg(context),
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  subtitle: Text(
                    _sniEnabled
                        ? (_sniAutoPicking
                            ? _t('در حال انتخاب خودکار…', 'Auto-picking…')
                            : _selectedSni)
                        : _t(
                            'خاموش — بدون جعل SNI',
                            'Off — no SNI spoof',
                          ),
                    style: TextStyle(
                        color: AppColors.muted2(context), fontSize: 11),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                  value: _sniEnabled,
                  activeColor: AppColors.accent,
                  onChanged: _settingsLocked
                      ? null
                      : (v) async {
                          setState(() => _sniEnabled = v);
                          if (v) {
                            await _autoPickSni();
                          }
                          await _savePrefs();
                        },
                ),
              ),
              if (_sniEnabled)
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(
                    onPressed:
                        _settingsLocked ? null : _showSniListDialog,
                    child: Text(
                      _t('مشاهده / ویرایش لیست SNI', 'View / edit SNI list'),
                      style: const TextStyle(color: AppColors.accent),
                    ),
                  ),
                ),
              const SizedBox(height: 12),
            ],

            Center(child: _connectButton()),
            const SizedBox(height: 20),

            // پیشرفت Bootstrap — هم هنگام connecting و هم تا رسیدن به ۱۰۰٪
            if ((_connecting || _running) && _bootstrap < 100)
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
                    if (_bootstrapMsg.isNotEmpty) ...[
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
                        style: const TextStyle(
                            color: AppColors.danger, fontSize: 12),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close,
                          color: AppColors.danger, size: 18),
                      onPressed: () => setState(() => _error = null),
                      tooltip: _t('بستن', 'Dismiss'),
                    ),
                  ],
                ),
              ),

            // وضعیت نهایی اتصال
            if (_running && _bootstrap >= 100)
              Container(
                margin: const EdgeInsets.only(top: 12),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.accent.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.accent),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
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
                    const SizedBox(height: 6),
                    Text(
                      _routingThroughVpn
                          ? _t(
                              'ترافیک دستگاه از طریق Tor رد می‌شود (آیکون VPN فعال)',
                              'Device traffic is routed via Tor (VPN icon on)',
                            )
                          : _routing
                              ? _t('در حال راه‌اندازی روتینگ VPN…',
                                  'Starting VPN routing…')
                              : _t(
                                  'روتینگ VPN هنوز فعال نشده — چند لحظه صبر کنید',
                                  'VPN routing not active yet — wait a moment',
                                ),
                      style: TextStyle(
                          color: AppColors.muted2(context), fontSize: 11),
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
