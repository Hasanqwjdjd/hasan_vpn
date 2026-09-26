import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/aether_profile.dart';
import '../models/server.dart';
import '../services/aether_service.dart';
import '../services/app_colors.dart';
import '../services/link_parser.dart';
import '../services/psiphon_auto.dart';
import '../services/psiphon_service.dart';
import '../services/tor_sni_presets.dart';
import '../services/xray_json.dart';
import 'qr_scan_screen.dart';
import 'tor_screen.dart';

class AddConfigScreen extends StatefulWidget {
  final String language;
  final Function(VpnServer) onServerAdded;

  const AddConfigScreen({
    super.key,
    required this.language,
    required this.onServerAdded,
  });

  @override
  State<AddConfigScreen> createState() => _AddConfigScreenState();
}

class _AddConfigScreenState extends State<AddConfigScreen> {
  final TextEditingController _linkController = TextEditingController();
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _sniController = TextEditingController();
  bool _sniEnabled = false;
  bool _isFa = true;
  String _selectedType = 'manual'; // aether|psiphon|tor|manual|sub 
  // تنظیمات Aether (مقدارهای پیش‌فرض همان پیش‌فرض AetherProfile هستند)
  String _aetherProtocol = 'auto';
  String _aetherScan = 'smart';
  String _aetherNoize = 'auto';
  String _aetherIp = 'v4';
  String _aetherPerf = 'auto';
  bool _aetherQuickReconnect = true;
  bool _aetherBlockQuic = true;
  bool _aetherAdvanced = false;

  // پنل اسکن / کلید WARP جدید / لاگ (فرم Aether)
  bool _aetherWorking = false;
  String? _aetherLiveLog;

  // Aether UI جدید
  final TextEditingController _aetherOuterController = TextEditingController();
  final TextEditingController _aetherInnerController = TextEditingController();
  final TextEditingController _aetherListenPortController =
      TextEditingController(text: '10819');
  String _aetherTargetStrategy = 'AsIs';
  bool _aetherAdvancedMore = false;

  // Zero Trust (Cloudflare Teams) — فقط وقتی تیم اسم دارد فعال می‌شود
  final TextEditingController _aetherTeamController = TextEditingController();
  final TextEditingController _aetherAccessEmailController =
      TextEditingController();
  final TextEditingController _aetherAccessIdController =
      TextEditingController();
  final TextEditingController _aetherAccessSecretController =
      TextEditingController();
  final TextEditingController _aetherAccessTokenController =
      TextEditingController();
  bool _aetherGateway = false;
  String _aetherZtAuthMode = 'email'; // email | service | token

  // Aether-native Psiphon chain (جدا از PsiphonService.kt)
  String _aetherPsiphonMode = 'off'; // off | inside | reverse | only
  final TextEditingController _aetherPsiphonRegionController =
      TextEditingController();
  String _aetherPsiphonFront = ''; // '' | cdn | direct

  // Aether-native Tor chain (جدا از TorService.kt)
  String _aetherTorMode = 'off'; // off | inside | reverse | only
  final TextEditingController _aetherTorBridgeController =
      TextEditingController();
  bool _aetherTorRelays = false;

  // Routing
  final TextEditingController _aetherRouteDirectController =
      TextEditingController();
  final TextEditingController _aetherRouteBlockController =
      TextEditingController();
  bool _aetherAdvancedChain = false;

  final TextEditingController _aetherDnsController = TextEditingController();
  final TextEditingController _aetherPeerController = TextEditingController();
  final TextEditingController _psiphonSponsorController = TextEditingController();
  final TextEditingController _psiphonChannelController = TextEditingController();
  final TextEditingController _psiphonConfigController = TextEditingController();

  /// سایفون: true = برنامه خودش SponsorId/Channel/پروتکل را انتخاب می‌کند.
  bool _psiphonAuto = true;

  /// کشور خروجی سایفون؛ '' = خودکار (سریع‌ترین).
  String _psiphonRegion = '';
  List<String> _psiphonRegions = PsiphonAuto.fallbackRegions;
  final TextEditingController _aetherUpstreamController =
      TextEditingController();

  @override
  void initState() {
    super.initState();
    _isFa = widget.language == 'fa';
    PsiphonAuto.loadRegions().then((list) {
      if (!mounted) return;
      setState(() => _psiphonRegions = list);
    });
  }

  String _t(String fa, String en) => _isFa ? fa : en;

  void _showMsg(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), duration: const Duration(seconds: 2)),
    );
  }

  /// دیالوگ انتخاب SNI جعلی — لیست کامل مثل عکس‌های برنامهٔ مرجع
  /// دیالوگ انتخاب SNI — وقتی فعال است حتماً یکی باید انتخاب شود.
  /// لیست کامل (همهٔ دامنه‌های قبلی برنامه + دامنه‌های عکس) بدون حذف.
  Future<void> _showSniPicker() async {
    // اگر خالی بود، پیش‌فرض را می‌گذاریم تا همیشه یک مقدار معتبر داشته باشیم
    var selected = _sniController.text.trim();
    if (selected.isEmpty) selected = TorSniPresets.defaultSni;

    final customController = TextEditingController(text: selected);
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return AlertDialog(
              backgroundColor: AppColors.surface(ctx),
              title: Text(
                _t('جعل نشانگر نام سرور', 'Spoof Server Name Indicator'),
                style: TextStyle(color: AppColors.fg(ctx), fontSize: 16),
              ),
              content: SizedBox(
                width: double.maxFinite,
                height: MediaQuery.of(ctx).size.height * 0.55,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _t(
                        'یک مورد را انتخاب کنید (الزامی)',
                        'Select one item (required)',
                      ),
                      style: TextStyle(
                          color: AppColors.muted2(ctx), fontSize: 11),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: customController,
                      style: TextStyle(color: AppColors.fg(ctx), fontSize: 13),
                      decoration: InputDecoration(
                        hintText: _t(
                            'یا دامنهٔ دلخواه بنویسید…',
                            'Or type a custom domain…'),
                        hintStyle:
                            TextStyle(color: AppColors.muted2(ctx)),
                        filled: true,
                        fillColor: AppColors.bg(ctx),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide:
                              BorderSide(color: AppColors.border(ctx)),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide:
                              BorderSide(color: AppColors.border(ctx)),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: const BorderSide(
                              color: AppColors.accent, width: 1.5),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 10),
                      ),
                      onChanged: (v) {
                        final t = v.trim();
                        if (t.isNotEmpty) {
                          setDialogState(() => selected = t);
                        }
                      },
                    ),
                    const SizedBox(height: 10),
                    Expanded(
                      child: ListView.separated(
                        itemCount: TorSniPresets.all.length,
                        separatorBuilder: (_, __) => Divider(
                          height: 1,
                          color: AppColors.border(ctx),
                        ),
                        itemBuilder: (context, i) {
                          final sni = TorSniPresets.all[i];
                          final isSelected = sni == selected;
                          return ListTile(
                            dense: true,
                            contentPadding:
                                const EdgeInsets.symmetric(horizontal: 4),
                            leading: Icon(
                              isSelected
                                  ? Icons.radio_button_checked
                                  : Icons.radio_button_off,
                              color: isSelected
                                  ? AppColors.accent
                                  : AppColors.muted2(ctx),
                              size: 20,
                            ),
                            title: Text(
                              sni,
                              style: TextStyle(
                                color: isSelected
                                    ? AppColors.accent
                                    : AppColors.fg(ctx),
                                fontSize: 13,
                                fontWeight: isSelected
                                    ? FontWeight.w600
                                    : FontWeight.normal,
                              ),
                            ),
                            onTap: () {
                              setDialogState(() {
                                selected = sni;
                                customController.text = sni;
                              });
                            },
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: Text(_t('لغو', 'Cancel'),
                      style: TextStyle(color: AppColors.muted(ctx))),
                ),
                TextButton(
                  onPressed: () {
                    // حتماً یک مقدار غیرخالی برگردان
                    final value = selected.trim().isNotEmpty
                        ? selected.trim()
                        : TorSniPresets.defaultSni;
                    Navigator.pop(ctx, value);
                  },
                  child: Text(_t('تأیید', 'OK'),
                      style: const TextStyle(color: AppColors.accent)),
                ),
              ],
            );
          },
        );
      },
    );

    if (result != null && result.isNotEmpty && mounted) {
      setState(() {
        _sniController.text = result;
        _sniEnabled = true; // اگر از دیالوگ انتخاب شد، سوئیچ هم روشن بماند
      });
    }
  }

  void _addFromLink() {
    final text = _linkController.text.trim();
    if (text.isEmpty) {
      _showMsg(_t('لینک را وارد کنید', 'Enter a link'));
      return;
    }

    final customName = _nameController.text.trim();
    final stamp = DateTime.now().millisecondsSinceEpoch;
    var added = 0;

    // SNI جعلی — فقط وقتی سوئیچ روشن باشد؛ اگر روشن باشد حتماً یک مقدار معتبر
    final sniOverride = _sniEnabled
        ? (_sniController.text.trim().isEmpty
            ? TorSniPresets.defaultSni
            : _sniController.text.trim())
        : '';

    // کانفیگ کامل JSON (Patterniha و مشابه)
    if (XrayJson.looksLike(text)) {
      final modified = sniOverride.isEmpty
          ? text
          : LinkParser.applySniOverride(text, sniOverride);
      var server = XrayJson.parse(modified, id: 'custom_$stamp');
      if (server != null) {
        if (customName.isNotEmpty) {
          server = server.copyWith(name: customName);
        }
        widget.onServerAdded(server);
        added = 1;
      }
    } else {
      // ممکن است چند لینک (هر کدام در یک خط) پیست شده باشد.
      final links = LinkParser.extractLinks(text);
      if (links.isEmpty) {
        _showMsg(
          _t(
            'لینک معتبری پیدا نشد (vless / vmess / trojan / ss / hysteria2 / aether / JSON)',
            'No valid link found (vless / vmess / trojan / ss / hysteria2 / aether / JSON)',
          ),
        );
        return;
      }

      for (var i = 0; i < links.length; i++) {
        final rawLink = sniOverride.isEmpty
            ? links[i]
            : LinkParser.applySniOverride(links[i], sniOverride);
        var server = LinkParser.parse(rawLink, id: 'custom_${stamp}_$i');
        if (server == null) continue;

        if (customName.isNotEmpty && links.length == 1) {
          server = server.copyWith(name: customName);
        }

        widget.onServerAdded(server);
        added++;
      }
    }

    if (added == 0) {
      _showMsg(_t('لینک قابل خواندن نبود', 'Could not read the link'));
      return;
    }

    Navigator.pop(context);
    _showMsg(
      added == 1
          ? _t('سرور اضافه شد', 'Server added')
          : _t('$added سرور اضافه شد', '$added servers added'),
    );
  }

  String _firstLinkName(String text) {
    if (XrayJson.looksLike(text)) {
      return XrayJson.parse(text, id: 'preview')?.name ?? '';
    }
    final links = LinkParser.extractLinks(text);
    if (links.length != 1) return '';
    final parsed = LinkParser.parse(links.first, id: 'preview');
    return parsed?.name ?? '';
  }

  Future<void> _pasteFromClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim() ?? '';
    if (text.isNotEmpty) {
      setState(() {
        _linkController.text = text;
        if (_nameController.text.isEmpty) {
          _nameController.text = _firstLinkName(text);
        }
      });
      _showMsg(_t('از کلیپ‌بورد پیست شد', 'Pasted from clipboard'));
    } else {
      _showMsg(_t('کلیپ‌بورد خالی است', 'Clipboard is empty'));
    }
  }

  Future<void> _scanQr() async {
    final result = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => QrScanScreen(language: widget.language)),
    );
    if (!mounted) return;
    if (result != null && result.trim().isNotEmpty) {
      setState(() {
        _linkController.text = result.trim();
        if (_nameController.text.isEmpty) {
          _nameController.text = _firstLinkName(result.trim());
        }
      });
      _showMsg(_t('کانفیگ از QR خوانده شد', 'Config read from QR'));
    }
  }

  static final RegExp _peerRegex = RegExp(r'^(\[[0-9a-fA-F:.]+\]|[0-9.]+):\d{1,5}$');

  void _addAetherServer() {
    final peer = _aetherPeerController.text.trim();
    final upstream = _aetherUpstreamController.text.trim();
    final dns = _aetherDnsController.text
        .split(RegExp(r'[\s,]+'))
        .where((e) => e.isNotEmpty)
        .join(',');

    if (peer.isNotEmpty && !_peerRegex.hasMatch(peer)) {
      _showMsg(_t('آدرس Peer باید به شکل ip:port باشد', 'Peer must look like ip:port'));
      return;
    }
    if (upstream.isNotEmpty && !upstream.contains('://')) {
      _showMsg(
        _t(
          'پراکسی بالادستی باید مثل socks5://127.0.0.1:1080 باشد',
          'Upstream must look like socks5://127.0.0.1:1080',
        ),
      );
      return;
    }

    final profile = AetherProfile(
      protocol: _aetherProtocol,
      scan: _aetherScan,
      noize: _aetherNoize,
      ip: _aetherIp,
      dns: dns,
      peer: peer,
      upstream: upstream,
      quickReconnect: _aetherQuickReconnect,
      blockQuic: _aetherBlockQuic,
      perf: _aetherPerf,
      outer: _aetherOuterController.text.trim(),
      inner: _aetherInnerController.text.trim(),
      listenPort: int.tryParse(_aetherListenPortController.text.trim()) ?? 0,
      targetStrategy: _aetherTargetStrategy,
      teamName: _aetherTeamController.text.trim(),
      accessEmail: _aetherZtAuthMode == 'email'
          ? _aetherAccessEmailController.text.trim()
          : '',
      accessId: _aetherZtAuthMode == 'service'
          ? _aetherAccessIdController.text.trim()
          : '',
      accessSecret: _aetherZtAuthMode == 'service'
          ? _aetherAccessSecretController.text.trim()
          : '',
      accessToken: _aetherZtAuthMode == 'token'
          ? _aetherAccessTokenController.text.trim()
          : '',
      gatewayEnabled: _aetherGateway,
      psiphonMode: _aetherPsiphonMode,
      psiphonRegion: _aetherPsiphonRegionController.text.trim(),
      psiphonFront: _aetherPsiphonFront,
      torMode: _aetherTorMode,
      torBridge: _aetherTorBridgeController.text.trim(),
      torRelays: _aetherTorRelays,
      routeDirect: _aetherRouteDirectController.text.trim(),
      routeBlock: _aetherRouteBlockController.text.trim(),
    );

    final name = _nameController.text.trim().isNotEmpty
        ? _nameController.text.trim()
        : 'Aether · ${profile.summary}';

    final server = VpnServer(
      id: 'aether_${DateTime.now().millisecondsSinceEpoch}',
      name: name,
      flag: '🟣',
      shareLink: profile.toLink(),
      protocol: VpnProtocol.aether,
      host: 'auto-discover',
      port: 0,
      isDeletable: true,
    );

    widget.onServerAdded(server);
    Navigator.pop(context);
    _showMsg(_t('سرور Aether اضافه شد', 'Aether server added'));
  }

  void _addSiphonServer() {
    final sponsor = _psiphonSponsorController.text.trim();
    final channel = _psiphonChannelController.text.trim();
    final config = _psiphonConfigController.text.trim();
    final region = _psiphonRegion.trim();

    final params = <String, String>{};
    if (_psiphonAuto) {
      params['auto'] = '1';
    } else {
      if (sponsor.isNotEmpty) params['sponsor'] = sponsor;
      if (channel.isNotEmpty) params['channel'] = channel;
      if (config.isNotEmpty) params['config'] = config;
    }
    if (region.isNotEmpty) params['region'] = region;

    final q = params.entries
        .map((e) => '${e.key}=${Uri.encodeComponent(e.value)}')
        .join('&');
    final link = q.isEmpty ? 'psiphon://auto' : 'psiphon://?$q';

    final name = _nameController.text.trim().isNotEmpty
        ? _nameController.text.trim()
        : (_psiphonAuto
            ? 'Psiphon · Auto'
            : 'Psiphon · ${sponsor.isNotEmpty ? sponsor : "custom"}');

    final server = VpnServer(
      id: 'psiphon_${DateTime.now().millisecondsSinceEpoch}',
      name: name,
      flag: '💧',
      shareLink: link,
      protocol: VpnProtocol.psiphon,
      host: 'auto-discover',
      port: 0,
      isDeletable: true,
    );

    widget.onServerAdded(server);
    Navigator.pop(context);
    _showMsg(_t('سرور Psiphon اضافه شد', 'Psiphon server added'));
  }

  AetherProfile _currentAetherProfile() {
    final peer = _aetherPeerController.text.trim();
    final upstream = _aetherUpstreamController.text.trim();
    final dns = _aetherDnsController.text
        .split(RegExp(r'[\s,]+'))
        .where((e) => e.isNotEmpty)
        .join(',');
    return AetherProfile(
      protocol: _aetherProtocol,
      scan: _aetherScan,
      noize: _aetherNoize,
      ip: _aetherIp,
      dns: dns,
      peer: peer,
      upstream: upstream,
      quickReconnect: _aetherQuickReconnect,
      blockQuic: _aetherBlockQuic,
      perf: _aetherPerf,
      outer: _aetherOuterController.text.trim(),
      inner: _aetherInnerController.text.trim(),
      listenPort: int.tryParse(_aetherListenPortController.text.trim()) ?? 0,
      targetStrategy: _aetherTargetStrategy,
      teamName: _aetherTeamController.text.trim(),
      accessEmail: _aetherZtAuthMode == 'email'
          ? _aetherAccessEmailController.text.trim()
          : '',
      accessId: _aetherZtAuthMode == 'service'
          ? _aetherAccessIdController.text.trim()
          : '',
      accessSecret: _aetherZtAuthMode == 'service'
          ? _aetherAccessSecretController.text.trim()
          : '',
      accessToken: _aetherZtAuthMode == 'token'
          ? _aetherAccessTokenController.text.trim()
          : '',
      gatewayEnabled: _aetherGateway,
      psiphonMode: _aetherPsiphonMode,
      psiphonRegion: _aetherPsiphonRegionController.text.trim(),
      psiphonFront: _aetherPsiphonFront,
      torMode: _aetherTorMode,
      torBridge: _aetherTorBridgeController.text.trim(),
      torRelays: _aetherTorRelays,
      routeDirect: _aetherRouteDirectController.text.trim(),
      routeBlock: _aetherRouteBlockController.text.trim(),
    );
  }

  /// اسکن برای یافتن سرور: با تنظیمات فعلی فرم یک مسیر سالم Aether پیدا
  /// می‌کند، بدون این‌که VPN واقعی را بالا بیاورد یا وصل‌شده نگه دارد.
  Future<void> _aetherScanNow() async {
    if (_aetherWorking) return;
    setState(() {
      _aetherWorking = true;
      _aetherLiveLog = _t('در حال اسکن برای یافتن سرور…',
          'Scanning for a working endpoint…');
    });

    final ok = await AetherService.scanOnly(
      _currentAetherProfile(),
      onProgress: (msg) {
        if (!mounted) return;
        setState(() => _aetherLiveLog = msg);
      },
    );

    if (!mounted) return;

    // استخراج outer/inner از log پردازه (فارسی یا انگلیسی)
    String outer = '';
    String inner = '';
    if (ok) {
      try {
        final log = await AetherService.nativeLog();
        // مسیر بیرونی 188.114.96.132:878 و مسیر درونی 188.114.96.1:1701 پیدا شد
        final faRe = RegExp(
            r'مسیر بیرونی\s+(\S+)\s+و مسیر درونی\s+(\S+)\s+پیدا شد');
        var m = faRe.firstMatch(log);
        if (m != null) {
          outer = m.group(1) ?? '';
          inner = m.group(2) ?? '';
        } else {
          // using cloudflare edge X:Y (outer) and Z:W (inner)
          final enRe = RegExp(
              r'cloudflare edge\s+(\S+)\s+\(outer\)\s+and\s+(\S+)\s+\(inner\)');
          m = enRe.firstMatch(log);
          if (m != null) {
            outer = m.group(1) ?? '';
            inner = m.group(2) ?? '';
          }
        }
      } catch (_) {}
    }

    setState(() {
      _aetherWorking = false;
      _aetherLiveLog = ok
          ? '${_aetherLiveLog ?? ''}\n${_t('✅ مسیر سالم پیدا شد', '✅ Found a working route')}'
              .trim()
          : '${_aetherLiveLog ?? ''}\n❌ ${AetherService.lastError ?? _t('هیچ مسیر سالمی پیدا نشد', 'No working route found')}'
              .trim();
      if (outer.isNotEmpty) {
        _aetherOuterController.text = outer;
      }
      if (inner.isNotEmpty) {
        _aetherInnerController.text = inner;
      }
    });

    if (ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: const Color(0xFF2E7D32),
          content: Text(
            outer.isNotEmpty && inner.isNotEmpty
                ? _t(
                    'مسیر بیرونی $outer و مسیر درونی $inner پیدا شد',
                    'outer $outer inner $inner',
                  )
                : _t('سرور پیدا شد', 'Endpoint found'),
          ),
          duration: const Duration(seconds: 3),
        ),
      );
    } else {
      _showMsg(_t('هیچ مسیر سالمی پیدا نشد', 'No working route found'));
    }
  }

  /// دریافت کلید WARP جدید: هویت WARP فعلی را پاک می‌کند تا اتصال بعدی یک
  /// حساب رایگان تازه بسازد. فقط وقتی Aether وصل نیست کار می‌کند.
  Future<void> _aetherGetNewKey() async {
    if (_aetherWorking) return;
    if (AetherService.isConnected) {
      _showMsg(_t('اول Aether را قطع کن', 'Disconnect Aether first'));
      return;
    }
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.elevated(ctx),
        title: Text(
          _t('دریافت کلید جدید WARP', 'Get new WARP key'),
          style: TextStyle(color: AppColors.fg(ctx), fontSize: 15),
        ),
        content: Text(
          _t(
            'کلید فعلی WARP حذف و یک کلید جدید ثبت می‌شود. اگر ثبت ناموفق باشد، کلید فعلی حفظ می‌شود.',
            'The current WARP key is removed and a new one is registered. If registration fails, the current key is kept.',
          ),
          style: TextStyle(
              color: AppColors.muted2(ctx), fontSize: 12.5, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(_t('لغو', 'Cancel'),
                style: TextStyle(color: AppColors.muted(ctx))),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              _t('دریافت کلید جدید WARP', 'Get new WARP key'),
              style: const TextStyle(color: AppColors.accent),
            ),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    setState(() {
      _aetherWorking = true;
      _aetherLiveLog =
          _t('در حال حذف کلید قبلی WARP و ثبت کلید جدید…', 'Resetting WARP key…');
    });
    final ok = await AetherService.resetIdentity();
    if (!mounted) return;
    setState(() => _aetherWorking = false);
    _showMsg(ok
        ? _t('کلید جدید WARP آماده است — از اسکن بعدی استفاده می‌شود',
            'New WARP key ready — used on next scan')
        : _t('پاک‌کردن هویت ناموفق', 'Could not reset identity'));
  }

  Future<void> _aetherDumpEnv() async {
    final env = AetherService.dumpEnvPreview(_currentAetherProfile());
    final lines = env.entries.map((e) => '${e.key}=${e.value}').toList()
      ..sort();
    final text = lines.join('\n');
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(_t('Dump env', 'Dump env')),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: SelectableText(text, style: const TextStyle(fontSize: 11)),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: text));
              if (ctx.mounted) Navigator.pop(ctx);
              _showMsg(_t('کپی شد', 'Copied'));
            },
            child: Text(_t('کپی', 'Copy')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(_t('بستن', 'Close')),
          ),
        ],
      ),
    );
  }

  Widget _buildAetherScanPanel() {
    const color = Color(0xFF7C4DFF);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _aetherField(
            controller: _aetherOuterController,
            label: _t('مسیر بیرونی', 'Outer endpoint'),
            hint: '188.114.96.132:878',
            color: color,
          ),
          const SizedBox(height: 10),
          _aetherField(
            controller: _aetherInnerController,
            label: _t('مسیر درونی', 'Inner endpoint'),
            hint: '188.114.96.1:1701',
            color: color,
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _aetherWorking ? null : _aetherScanNow,
                  icon: _aetherWorking
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: color))
                      : const Icon(Icons.wifi_find, size: 16, color: color),
                  label: Text(_t('اسکن برای یافتن سرور', 'Scan for server'),
                      style: const TextStyle(color: color, fontSize: 12)),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: color),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _aetherWorking ? null : _aetherGetNewKey,
                  icon: const Icon(Icons.vpn_key_outlined,
                      size: 16, color: color),
                  label: Text(_t('دریافت کلید جدید WARP', 'New WARP key'),
                      style: const TextStyle(color: color, fontSize: 11.5),
                      overflow: TextOverflow.ellipsis),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: color),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          InkWell(
            onTap: () =>
                setState(() => _aetherAdvancedMore = !_aetherAdvancedMore),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Icon(
                    _aetherAdvancedMore
                        ? Icons.expand_less
                        : Icons.expand_more,
                    color: color,
                    size: 18,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    _t('تنظیمات پیشرفته', 'Advanced'),
                    style: const TextStyle(
                      color: color,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (_aetherAdvancedMore) ...[
            const SizedBox(height: 10),
            Text(
              _t('targetStrategy', 'targetStrategy'),
              style: TextStyle(
                color: AppColors.muted(context),
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: AppColors.bg(context),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: color.withOpacity(0.5)),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: _aetherTargetStrategy,
                  isExpanded: true,
                  dropdownColor: AppColors.elevated(context),
                  style: TextStyle(color: AppColors.fg(context), fontSize: 13),
                  items: const [
                    DropdownMenuItem(value: 'AsIs', child: Text('AsIs')),
                    DropdownMenuItem(
                        value: 'IPIfNonMatch', child: Text('IPIfNonMatch')),
                    DropdownMenuItem(
                        value: 'IPOnDemand', child: Text('IPOnDemand')),
                  ],
                  onChanged: (v) {
                    if (v == null) return;
                    setState(() => _aetherTargetStrategy = v);
                  },
                ),
              ),
            ),
            const SizedBox(height: 10),
            _aetherField(
              controller: _aetherListenPortController,
              label: _t('پورت شنود', 'Listen port'),
              hint: '10819',
              color: color,
              keyboard: TextInputType.number,
            ),
            const SizedBox(height: 12),
            Text(
              _t('فرمان Aether', 'Aether command'),
              style: TextStyle(
                color: AppColors.muted(context),
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 6),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.bg(context),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.border(context)),
              ),
              child: Directionality(
                textDirection: TextDirection.ltr,
                child: SelectableText(
                  _aetherPreviewCommand(),
                  style: TextStyle(
                    color: AppColors.fg(context),
                    fontSize: 11,
                    fontFamily: 'monospace',
                    height: 1.5,
                  ),
                ),
              ),
            ),
          ],
          if (_aetherLiveLog != null && _aetherLiveLog!.isNotEmpty) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: Text(_t('لاگ', 'Log'),
                      style: TextStyle(
                          color: AppColors.muted(context),
                          fontSize: 11,
                          fontWeight: FontWeight.w600)),
                ),
                InkWell(
                  onTap: () {
                    Clipboard.setData(ClipboardData(text: _aetherLiveLog!));
                    _showMsg(_t('کپی شد', 'Copied'));
                  },
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.copy,
                          size: 13, color: AppColors.muted(context)),
                      const SizedBox(width: 4),
                      Text(_t('کپی', 'Copy'),
                          style: TextStyle(
                              color: AppColors.muted(context), fontSize: 11)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Container(
              width: double.infinity,
              constraints: const BoxConstraints(maxHeight: 240),
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.bg(context),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.border(context)),
              ),
              child: SingleChildScrollView(
                child: Directionality(
                  textDirection: TextDirection.ltr,
                  child: Text(
                    _aetherLiveLog!,
                    style: TextStyle(
                        color: AppColors.muted2(context),
                        fontSize: 10.5,
                        fontFamily: 'monospace'),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _aetherPreviewCommand() {
    final port = _aetherListenPortController.text.trim().isEmpty
        ? '10819'
        : _aetherListenPortController.text.trim();
    final parts = <String>['aether'];
    parts.add('--bind 127.0.0.1:$port');
    switch (_aetherProtocol) {
      case 'gool':
        parts.add('--protocol gool');
        break;
      case 'mim':
        parts.add('--protocol mim');
        break;
      case 'wg':
        parts.add('--protocol wg');
        break;
      case 'masque_h2':
        parts.add('--protocol masque --masque-http2');
        break;
      case 'masque':
        parts.add('--protocol masque');
        break;
      default:
        parts.add('--protocol masque');
    }
    if (_aetherScan != 'smart') parts.add('--scan $_aetherScan');
    if (_aetherIp == 'v6') {
      parts.add('--ip v6');
    } else if (_aetherIp == 'both') {
      parts.add('--ip both');
    } else {
      parts.add('--ip v4');
    }
    if (_aetherOuterController.text.trim().isNotEmpty &&
        _aetherInnerController.text.trim().isNotEmpty &&
        (_aetherProtocol == 'gool' || _aetherProtocol == 'mim')) {
      parts.add('--wiw-outer ${_aetherOuterController.text.trim()}');
      parts.add('--wiw-inner ${_aetherInnerController.text.trim()}');
    } else if (_aetherProtocol == 'gool' || _aetherProtocol == 'mim') {
      parts.add('--wiw-scan');
    }
    if (_aetherQuickReconnect) parts.add('--quick-reconnect');
    return parts.join(' ');
  }

  Widget _aetherField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required Color color,
    TextInputType? keyboard,
  }) {
    return TextField(
      controller: controller,
      keyboardType: keyboard,
      style: TextStyle(color: AppColors.fg(context), fontSize: 13),
      onChanged: (_) => setState(() {}),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        labelStyle: TextStyle(color: AppColors.muted(context)),
        hintStyle: TextStyle(color: AppColors.muted2(context), fontSize: 12),
        filled: true,
        fillColor: AppColors.surface(context),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: AppColors.border(context)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: AppColors.border(context)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: color, width: 1.5),
        ),
      ),
    );
  }

  void _addFreeEnginePack() {
    final stamp = DateTime.now().millisecondsSinceEpoch;
    final engines = <({String id, String name, String flag, AetherProfile profile})>[
      (
        id: 'aether_$stamp',
        name: 'Aether · Auto',
        flag: '☁️',
        profile: const AetherProfile(
          protocol: 'auto',
          scan: 'smart',
          noize: 'auto',
          quickReconnect: true,
          blockQuic: true,
        ),
      ),
      (
        id: 'siphon_$stamp',
        name: 'Siphon · Gool',
        flag: '💧',
        profile: const AetherProfile(
          protocol: 'gool',
          scan: 'smart',
          noize: 'gfw',
          quickReconnect: true,
          blockQuic: true,
        ),
      ),
];

    for (final e in engines) {
      // host معنادار تا در لیست «host = host» یا خالی دیده نشود
      final hostLabel = e.id.startsWith('tor_')
          ? 'stealth-auto'
          : e.id.startsWith('siphon_')
              ? 'gool-auto'
              : 'warp-auto';
      widget.onServerAdded(VpnServer(
        id: e.id,
        name: e.name,
        flag: e.flag,
        shareLink: e.profile.toLink(),
        protocol: VpnProtocol.aether,
        host: hostLabel,
        port: 0,
        isDeletable: true,
      ));
    }
    Navigator.pop(context);
    _showMsg(_t(
      '۲ موتور رایگان اضافه شد (Aether / Siphon)',
      '2 free engines added (Aether / Siphon)',
    ));
  }


  Widget _siphonLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text,
        style: TextStyle(
          color: AppColors.muted(context),
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  InputDecoration _siphonDecoration(String hint) {
    return InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(color: AppColors.muted2(context), fontSize: 12),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      filled: true,
      fillColor: AppColors.surface(context),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: AppColors.border(context)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: AppColors.border(context)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: Color(0xFF26A69A)),
      ),
    );
  }

  Widget _buildSiphonForm() {
    const teal = Color(0xFF26A69A);
    final regionItems = <String>['', ..._psiphonRegions];
    if (!regionItems.contains(_psiphonRegion)) {
      regionItems.add(_psiphonRegion);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: teal.withOpacity(0.08),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: teal.withOpacity(0.35)),
          ),
          child: Text(
            _psiphonAuto
                ? _t(
                    'حالت خودکار: برنامه خودش SponsorId، کانال، مجموعهٔ پروتکل '
                    'و مهلت اتصال را انتخاب می‌کند و کانفیگ را می‌سازد. اگر یک '
                    'ترکیب وصل نشد، خودکار سراغ ترکیب بعدی می‌رود و ترکیبِ '
                    'موفق را برای دفعهٔ بعد یادش می‌ماند.',
                    'Automatic mode: the app picks SponsorId, channel, protocol '
                    'set and timeouts, and builds the config itself. If one '
                    'combination fails it tries the next, and remembers the '
                    'one that worked.',
                  )
                : _t(
                    'حالت دستی: SponsorId / Channel یا JSON کامل را خودت بده. '
                    'خالی بگذاری، مقادیر پیش‌فرض استفاده می‌شود.',
                    'Manual mode: provide your own SponsorId / Channel or a '
                    'full JSON. Leave empty to use defaults.',
                  ),
            style: TextStyle(
              color: AppColors.muted(context),
              fontSize: 12,
              height: 1.5,
            ),
          ),
        ),
        const SizedBox(height: 12),
        Container(
          decoration: BoxDecoration(
            color: AppColors.surface(context),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.border(context)),
          ),
          child: SwitchListTile(
            value: _psiphonAuto,
            activeColor: teal,
            onChanged: (v) => setState(() => _psiphonAuto = v),
            title: Text(
              _t('خودکار (پیشنهادی)', 'Automatic (recommended)'),
              style: TextStyle(
                color: AppColors.fg(context),
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
            subtitle: Text(
              _t('SponsorId و بقیهٔ گزینه‌ها را برنامه انتخاب کند',
                  'Let the app choose SponsorId and the other options'),
              style: TextStyle(color: AppColors.muted(context), fontSize: 12),
            ),
          ),
        ),
        const SizedBox(height: 16),
        if (_psiphonAuto) ...[
          _siphonLabel(_t('کشور خروجی', 'Exit country')),
          DropdownButtonFormField<String>(
            value: _psiphonRegion,
            isExpanded: true,
            dropdownColor: AppColors.surface(context),
            style: TextStyle(color: AppColors.fg(context), fontSize: 14),
            decoration: _siphonDecoration(''),
            items: [
              for (final r in regionItems)
                DropdownMenuItem<String>(
                  value: r,
                  child: Text(PsiphonAuto.regionLabel(r, fa: _isFa)),
                ),
            ],
            onChanged: (v) => setState(() => _psiphonRegion = v ?? ''),
          ),
          const SizedBox(height: 6),
          Text(
            _t(
              'روی «خودکار» بگذاری، Psiphon سریع‌ترین خروجی را انتخاب می‌کند. '
              'فهرست کشورها بعد از اولین اتصال از خود Psiphon به‌روز می‌شود.',
              'On "Auto", Psiphon picks the fastest exit. The country list '
              'is refreshed from Psiphon after the first connection.',
            ),
            style: TextStyle(color: AppColors.muted2(context), fontSize: 11),
          ),
        ] else ...[
          _siphonLabel('SponsorId'),
          TextField(
            controller: _psiphonSponsorController,
            style: TextStyle(color: AppColors.fg(context), fontSize: 13),
            decoration: _siphonDecoration(
                'خالی = پیش‌فرض (FFFFFFFFFFFFFFFF)'),
          ),
          const SizedBox(height: 12),
          _siphonLabel('PropagationChannelId'),
          TextField(
            controller: _psiphonChannelController,
            style: TextStyle(color: AppColors.fg(context), fontSize: 13),
            decoration: _siphonDecoration('Channel ID'),
          ),
          const SizedBox(height: 12),
          _siphonLabel(_t('منطقه خروجی (اختیاری)', 'Egress region (optional)')),
          TextField(
            controller: _aetherPeerController,
            style: TextStyle(color: AppColors.fg(context), fontSize: 13),
            decoration: _siphonDecoration('US, DE, SG, ... یا خالی'),
          ),
          const SizedBox(height: 12),
          _siphonLabel(_t('یا کانفیگ JSON کامل', 'Or full JSON config')),
          TextField(
            controller: _psiphonConfigController,
            maxLines: 4,
            style: TextStyle(color: AppColors.fg(context), fontSize: 12),
            decoration: _siphonDecoration(
              '{ "SponsorId": "...", "PropagationChannelId": "..." }',
            ),
          ),
        ],
        const SizedBox(height: 12),
        _siphonLabel(_t('نام (اختیاری)', 'Name (optional)')),
        TextField(
          controller: _nameController,
          style: TextStyle(color: AppColors.fg(context)),
          decoration:
              _siphonDecoration(_t('مثال: سایفون من', 'e.g. My Psiphon')),
        ),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          height: 50,
          child: ElevatedButton(
            onPressed: _addSiphonServer,
            style: ElevatedButton.styleFrom(
              backgroundColor: teal,
              foregroundColor: Colors.black,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            child: Text(
              _psiphonAuto
                  ? _t('افزودن سایفون خودکار', 'Add automatic Psiphon')
                  : _t('افزودن سایفون دستی', 'Add manual Psiphon'),
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTorForm() {
    return TorScreen(
      language: widget.language,
      embedded: true,
    );
  }

  Widget _buildTypeCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required String type,
    required Color color,
  }) {
    final selected = _selectedType == type;
    return GestureDetector(
      onTap: () => setState(() => _selectedType = type),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: selected
              ? color.withOpacity(0.15)
              : AppColors.surface(context),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? color : AppColors.border(context),
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: color.withOpacity(0.2),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: color, size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: AppColors.fg(context),
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: AppColors.muted(context),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            if (selected)
              Icon(Icons.check_circle, color: color, size: 22),
          ],
        ),
      ),
    );
  }

  Widget _buildChoiceRow({
    required String label,
    required List<String> values,
    required Map<String, String> valueLabelsFa,
    required Map<String, String> valueLabelsEn,
    required String selected,
    required ValueChanged<String> onSelected,
    required Color color,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
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
          children: values.map((v) {
            final isSel = v == selected;
            final label = _isFa ? (valueLabelsFa[v] ?? v) : (valueLabelsEn[v] ?? v);
            return ChoiceChip(
              label: Text(label),
              selected: isSel,
              onSelected: (_) => onSelected(v),
              selectedColor: color.withOpacity(0.25),
              backgroundColor: AppColors.surface(context),
              labelStyle: TextStyle(
                color: isSel ? color : AppColors.muted(context),
                fontWeight: isSel ? FontWeight.w600 : FontWeight.w400,
                fontSize: 12.5,
              ),
              side: BorderSide(color: isSel ? color : AppColors.border(context)),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required Color color,
  }) {
    OutlineInputBorder border(Color c, [double w = 1]) => OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: c, width: w),
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            color: AppColors.muted(context),
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          style: TextStyle(color: AppColors.fg(context), fontSize: 13),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(color: AppColors.muted2(context)),
            filled: true,
            fillColor: AppColors.surface(context),
            border: border(AppColors.border(context)),
            enabledBorder: border(AppColors.border(context)),
            focusedBorder: border(color, 1.5),
          ),
        ),
      ],
    );
  }

  Widget _buildAetherForm() {
    const color = Color(0xFF7C4DFF);
    const gap = SizedBox(height: 18);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: color.withOpacity(0.08),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: color.withOpacity(0.3)),
          ),
          child: Row(
            children: [
              const Icon(Icons.auto_awesome, color: color, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  _t(
                    'Aether خودش مسیر آزاد را پیدا می‌کند و به شبکه‌ی WARP وصل می‌شود؛ نیازی به لینک سرور نیست. در حالت «هوشمند» ابتدا سریع‌ترین روش امتحان می‌شود و اگر نشد، خودکار به روش‌های قوی‌تر می‌رود.',
                    'Aether finds a working route and connects to WARP by itself; no server link is needed. In Smart mode it tries the fastest method first and escalates automatically.',
                  ),
                  style: TextStyle(
                    color: AppColors.muted(context),
                    fontSize: 12.5,
                    height: 1.5,
                  ),
                ),
              ),
            ],
          ),
        ),
        gap,
        _buildChoiceRow(
          label: _t('پروتکل انتقال', 'Transport protocol'),
          values: AetherProfile.protocols,
          valueLabelsFa: const {
            'auto': 'خودکار (پیشنهادی)',
            'masque': 'MASQUE (HTTP/3)',
            'masque_h2': 'MASQUE (HTTP/2)',
            'wg': 'WireGuard',
            'gool': 'Gool (WARP در WARP)',
            'mim': 'MIM (MASQUE در MASQUE)',
          },
          valueLabelsEn: const {
            'auto': 'Auto (recommended)',
            'masque': 'MASQUE (HTTP/3)',
            'masque_h2': 'MASQUE (HTTP/2)',
            'wg': 'WireGuard',
            'gool': 'Gool (WARP-in-WARP)',
            'mim': 'MIM (MASQUE-in-MASQUE)',
          },
          selected: _aetherProtocol,
          onSelected: (v) => setState(() => _aetherProtocol = v),
          color: color,
        ),
        gap,
        _buildChoiceRow(
          label: _t('حالت اسکن', 'Scan mode'),
          values: AetherProfile.scans,
          valueLabelsFa: const {
            'smart': 'هوشمند',
            'turbo': 'توربو (سریع‌ترین اتصال)',
            'balanced': 'متعادل (پینگ بهتر)',
            'thorough': 'کامل',
            'stealth': 'مخفی',
            'ironclad': 'آهنین (مطمئن‌ترین)',
          },
          valueLabelsEn: const {
            'smart': 'Smart',
            'turbo': 'Turbo (fastest connect)',
            'balanced': 'Balanced (better ping)',
            'thorough': 'Thorough',
            'stealth': 'Stealth',
            'ironclad': 'Ironclad (most reliable)',
          },
          selected: _aetherScan,
          onSelected: (v) => setState(() => _aetherScan = v),
          color: color,
        ),
        gap,
        _buildChoiceRow(
          label: _t('نسخه‌ی IP', 'IP version'),
          values: AetherProfile.ips,
          valueLabelsFa: const {'v4': 'IPv4', 'v6': 'IPv6', 'both': 'هر دو'},
          valueLabelsEn: const {'v4': 'IPv4', 'v6': 'IPv6', 'both': 'Both'},
          selected: _aetherIp,
          onSelected: (v) => setState(() => _aetherIp = v),
          color: color,
        ),
        gap,
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          activeColor: color,
          title: Text(
            _t('اتصال مجدد سریع', 'Quick reconnect'),
            style: TextStyle(color: AppColors.fg(context), fontSize: 14),
          ),
          subtitle: Text(
            _t(
              'از آخرین مسیر سالم دوباره استفاده می‌کند (بدون اسکن تازه)',
              'Reuses the last working gateway (no fresh scan)',
            ),
            style: TextStyle(color: AppColors.muted2(context), fontSize: 11.5),
          ),
          value: _aetherQuickReconnect,
          onChanged: (v) => setState(() => _aetherQuickReconnect = v),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          activeColor: color,
          title: Text(
            _t('مسدود کردن QUIC', 'Block QUIC'),
            style: TextStyle(color: AppColors.fg(context), fontSize: 14),
          ),
          subtitle: Text(
            _t(
              'مرورگر و برنامه‌ها فوراً به TCP برمی‌گردند (بارگذاری صفحات سریع‌تر)',
              'Browsers/apps fall back to TCP immediately (faster page loads)',
            ),
            style: TextStyle(color: AppColors.muted2(context), fontSize: 11.5),
          ),
          value: _aetherBlockQuic,
          onChanged: (v) => setState(() => _aetherBlockQuic = v),
        ),
        const SizedBox(height: 4),
        InkWell(
          onTap: () => setState(() => _aetherAdvanced = !_aetherAdvanced),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              children: [
                Icon(
                  _aetherAdvanced ? Icons.expand_less : Icons.expand_more,
                  color: color,
                ),
                const SizedBox(width: 6),
                Text(
                  _t('تنظیمات پیشرفته', 'Advanced'),
                  style: const TextStyle(
                    color: color,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
        if (_aetherAdvanced) ...[
          const SizedBox(height: 8),
          _buildChoiceRow(
            label: _t('پروفایل نویز (مقابله با DPI)', 'Noize profile (anti-DPI)'),
            values: AetherProfile.noizes,
            valueLabelsFa: const {
              'auto': 'خودکار',
              'off': 'خاموش',
              'light': 'سبک',
              'firewall': 'فایروال',
              'balanced': 'متعادل',
              'gfw': 'GFW',
              'aggressive': 'شدید',
            },
            valueLabelsEn: const {
              'auto': 'Auto',
              'off': 'Off',
              'light': 'Light',
              'firewall': 'Firewall',
              'balanced': 'Balanced',
              'gfw': 'GFW',
              'aggressive': 'Aggressive',
            },
            selected: _aetherNoize,
            onSelected: (v) => setState(() => _aetherNoize = v),
            color: color,
          ),
          gap,
          _buildChoiceRow(
            label: _t('مصرف منابع', 'Performance profile'),
            values: AetherProfile.perfs,
            valueLabelsFa: const {
              'auto': 'خودکار',
              'low': 'کم',
              'medium': 'متوسط',
              'high': 'بالا (سرعت بیشتر)',
            },
            valueLabelsEn: const {
              'auto': 'Auto',
              'low': 'Low',
              'medium': 'Medium',
              'high': 'High (more speed)',
            },
            selected: _aetherPerf,
            onSelected: (v) => setState(() => _aetherPerf = v),
            color: color,
          ),
          gap,
          _buildTextField(
            controller: _aetherDnsController,
            label: _t('DNS داخل تونل (اختیاری)', 'DNS inside tunnel (optional)'),
            hint: '1.1.1.1, 1.0.0.1',
            color: color,
          ),
          gap,
          _buildTextField(
            controller: _aetherPeerController,
            label: _t('Peer دستی ip:port (اختیاری)', 'Manual peer ip:port (optional)'),
            hint: '162.159.192.1:2408',
            color: color,
          ),
          gap,
          _buildTextField(
            controller: _aetherUpstreamController,
            label: _t('پراکسی بالادستی (اختیاری)', 'Upstream proxy (optional)'),
            hint: 'socks5://127.0.0.1:1080',
            color: color,
          ),
        ],
        const SizedBox(height: 4),
        InkWell(
          onTap: () => setState(() => _aetherAdvancedChain = !_aetherAdvancedChain),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              children: [
                Icon(
                  _aetherAdvancedChain ? Icons.expand_less : Icons.expand_more,
                  color: color,
                ),
                const SizedBox(width: 6),
                Text(
                  _t('زنجیره و Zero Trust (بومی Aether)',
                      'Chain & Zero Trust (native Aether)'),
                  style: const TextStyle(
                    color: color,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
        if (_aetherAdvancedChain) ...[
          const SizedBox(height: 4),
          Text(
            _t(
              'این بخش از پشتیبانی بومی Aether برای Psiphon/Tor/Zero Trust استفاده '
              'می‌کند (از طریق متغیرهای محیطی خود Aether) — کاملاً جدا از صفحه‌ی '
              'Tor یا سرورهای سایفون موجود در برنامه.',
              'Uses Aether\'s own native Psiphon/Tor/Zero Trust support (via Aether '
              'env vars) — fully separate from the app\'s Tor screen or Psiphon '
              'servers.',
            ),
            style: TextStyle(color: AppColors.muted2(context), fontSize: 11),
          ),
          gap,
          Text(_t('زنجیره‌ی Psiphon', 'Psiphon chain'),
              style: TextStyle(
                  color: AppColors.muted(context),
                  fontSize: 13,
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          _buildChoiceRow(
            label: '',
            values: AetherProfile.chainModes,
            valueLabelsFa: const {
              'off': 'خاموش',
              'inside': 'داخل تونل',
              'reverse': 'قبل از تونل',
              'only': 'فقط Psiphon',
            },
            valueLabelsEn: const {
              'off': 'Off',
              'inside': 'Inside tunnel',
              'reverse': 'Tunnel-through-Psiphon',
              'only': 'Psiphon only',
            },
            selected: _aetherPsiphonMode,
            onSelected: (v) => setState(() => _aetherPsiphonMode = v),
            color: color,
          ),
          if (_aetherPsiphonMode != 'off') ...[
            gap,
            _buildTextField(
              controller: _aetherPsiphonRegionController,
              label: _t('منطقه خروجی سایفون (اختیاری)', 'Psiphon egress region (optional)'),
              hint: 'DE, NL, US, GB, JP…',
              color: color,
            ),
            gap,
            _buildChoiceRow(
              label: _t('حالت fronting', 'Fronting mode'),
              values: const ['', 'cdn', 'direct'],
              valueLabelsFa: const {'': 'پیش‌فرض', 'cdn': 'CDN (meek)', 'direct': 'مستقیم'},
              valueLabelsEn: const {'': 'Default', 'cdn': 'CDN (meek)', 'direct': 'Direct'},
              selected: _aetherPsiphonFront,
              onSelected: (v) => setState(() => _aetherPsiphonFront = v),
              color: color,
            ),
          ],
          gap,
          Text(_t('زنجیره‌ی Tor', 'Tor chain'),
              style: TextStyle(
                  color: AppColors.muted(context),
                  fontSize: 13,
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          _buildChoiceRow(
            label: '',
            values: AetherProfile.chainModes,
            valueLabelsFa: const {
              'off': 'خاموش',
              'inside': 'داخل تونل',
              'reverse': 'قبل از تونل',
              'only': 'فقط Tor',
            },
            valueLabelsEn: const {
              'off': 'Off',
              'inside': 'Inside tunnel',
              'reverse': 'Tunnel-through-Tor',
              'only': 'Tor only',
            },
            selected: _aetherTorMode,
            onSelected: (v) => setState(() => _aetherTorMode = v),
            color: color,
          ),
          if (_aetherTorMode != 'off') ...[
            gap,
            _buildTextField(
              controller: _aetherTorBridgeController,
              label: _t('پل دستی (خالی = خودکار از bridgedb)',
                  'Manual bridge (empty = auto from bridgedb)'),
              hint: 'obfs4 1.2.3.4:443 ...',
              color: color,
            ),
            gap,
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              activeColor: color,
              title: Text(_t('استفاده از رله‌های عمومی به‌عنوان پل', 'Use public relays as bridges'),
                  style: TextStyle(color: AppColors.fg(context), fontSize: 13)),
              subtitle: Text(
                  _t('وقتی bridgedb هم بسته باشد', 'When bridgedb itself is blocked'),
                  style: TextStyle(color: AppColors.muted2(context), fontSize: 11)),
              value: _aetherTorRelays,
              onChanged: (v) => setState(() => _aetherTorRelays = v),
            ),
          ],
          gap,
          Text(_t('Cloudflare Zero Trust', 'Cloudflare Zero Trust'),
              style: TextStyle(
                  color: AppColors.muted(context),
                  fontSize: 13,
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          _buildTextField(
            controller: _aetherTeamController,
            label: _t('نام تیم (اختیاری)', 'Team name (optional)'),
            hint: 'mycompany',
            color: color,
          ),
          if (_aetherTeamController.text.trim().isNotEmpty ||
              _aetherAdvancedChain) ...[
            gap,
            _buildChoiceRow(
              label: _t('روش احراز هویت', 'Auth method'),
              values: const ['email', 'service', 'token'],
              valueLabelsFa: const {
                'email': 'ایمیل (کد یک‌بارمصرف)',
                'service': 'Service Token',
                'token': 'JWT آماده',
              },
              valueLabelsEn: const {
                'email': 'Email (one-time code)',
                'service': 'Service token',
                'token': 'Existing JWT',
              },
              selected: _aetherZtAuthMode,
              onSelected: (v) => setState(() => _aetherZtAuthMode = v),
              color: color,
            ),
            gap,
            if (_aetherZtAuthMode == 'email')
              _buildTextField(
                controller: _aetherAccessEmailController,
                label: _t('ایمیل سازمانی', 'Organization email'),
                hint: 'you@company.com',
                color: color,
              )
            else if (_aetherZtAuthMode == 'service') ...[
              _buildTextField(
                controller: _aetherAccessIdController,
                label: 'Access Client ID',
                hint: '',
                color: color,
              ),
              gap,
              _buildTextField(
                controller: _aetherAccessSecretController,
                label: 'Access Client Secret',
                hint: '',
                color: color,
              ),
            ] else
              _buildTextField(
                controller: _aetherAccessTokenController,
                label: 'Access JWT',
                hint: 'eyJhbGciOi...',
                color: color,
              ),
            gap,
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              activeColor: color,
              title: Text(_t('عبور از Gateway سازمان', 'Route via org Gateway'),
                  style: TextStyle(color: AppColors.fg(context), fontSize: 13)),
              subtitle: Text(
                  _t('ترافیک HTTP/HTTPS از پراکسی Gateway سازمان رد می‌شود',
                      'HTTP/HTTPS traffic goes through the org Gateway proxy'),
                  style: TextStyle(color: AppColors.muted2(context), fontSize: 11)),
              value: _aetherGateway,
              onChanged: (v) => setState(() => _aetherGateway = v),
            ),
          ],
          gap,
          Text(_t('مسیریابی', 'Routing'),
              style: TextStyle(
                  color: AppColors.muted(context),
                  fontSize: 13,
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          _buildTextField(
            controller: _aetherRouteDirectController,
            label: _t('مستقیم (بدون تونل) — با کاما', 'Direct (bypass tunnel) — comma-separated'),
            hint: 'bank.ir, 192.168.0.0/16',
            color: color,
          ),
          gap,
          _buildTextField(
            controller: _aetherRouteBlockController,
            label: _t('مسدود — با کاما', 'Block — comma-separated'),
            hint: 'ads.example.com',
            color: color,
          ),
        ],
        gap,
        Text(
          _t('نام (اختیاری)', 'Name (optional)'),
          style: TextStyle(
            color: AppColors.muted(context),
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _nameController,
          style: TextStyle(color: AppColors.fg(context)),
          decoration: InputDecoration(
            hintText: _t('مثال: Aether من', 'e.g. My Aether'),
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
              borderSide: const BorderSide(color: color, width: 1.5),
            ),
          ),
        ),
        const SizedBox(height: 20),
        _buildAetherScanPanel(),
        const SizedBox(height: 24),
        SizedBox(
          width: double.infinity,
          height: 50,
          child: ElevatedButton(
            onPressed: _addAetherServer,
            style: ElevatedButton.styleFrom(
              backgroundColor: color,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            child: Text(
              _t('افزودن Aether', 'Add Aether'),
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
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
        title: Text(
          _t('افزودن کانفیگ', 'Add Config'),
          style: TextStyle(color: AppColors.fg(context)),
        ),
        iconTheme: IconThemeData(color: AppColors.fg(context)),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Type selection
            Text(
              _t('نوع کانفیگ', 'Config Type'),
              style: TextStyle(
                color: AppColors.muted(context),
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 10),

            _buildTypeCard(
              title: _t('دستی / لینک', 'Manual / Link'),
              subtitle: _t('Paste یا اسکن QR لینک VLESS / Trojan / ...',
                  'Paste or scan a VLESS / Trojan / ... link'),
              icon: Icons.link,
              type: 'manual',
              color: AppColors.accent,
            ),
            _buildTypeCard(
              title: 'Aether',
              subtitle: _t(
                'WARP + اسکن مسیر + MASQUE/WireGuard (ادغام‌شده)',
                'WARP + route scan + MASQUE/WireGuard (merged)',
              ),
              icon: Icons.auto_awesome,
              type: 'aether',
              color: const Color(0xFF7C4DFF),
            ),
            _buildTypeCard(
              title: 'Siphon',
              subtitle: _t('هستهٔ واقعی Psiphon Labs',
                  'Real Psiphon Labs core'),
              icon: Icons.water_drop,
              type: 'siphon',
              color: const Color(0xFF26A69A),
            ),
            _buildTypeCard(
              title: 'Tor',
              subtitle: _t('اتصال واقعی به شبکهٔ رسمی Tor با پل‌های رایگان',
                  'Real connection to the official Tor network with free bridges'),
              icon: Icons.security,
              type: 'tor',
              color: const Color(0xFFEF5350),
            ),

            const SizedBox(height: 20),

            if (_selectedType == 'manual') ...[
              // Manual input
              Text(
                _t('لینک کانفیگ', 'Config Link'),
                style: TextStyle(
                  color: AppColors.muted(context),
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _linkController,
                maxLines: 4,
                style: TextStyle(color: AppColors.fg(context), fontSize: 13),
                decoration: InputDecoration(
                  hintText: 'vless://... یا trojan://... یا ss://...',
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
                    borderSide:
                        const BorderSide(color: AppColors.accent, width: 1.5),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _pasteFromClipboard,
                      icon: const Icon(Icons.paste, size: 18),
                      label: Text(_t('پیست از کلیپ‌بورد', 'Paste')),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.accent,
                        side: const BorderSide(color: AppColors.accent),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _scanQr,
                      icon: const Icon(Icons.qr_code_scanner, size: 18),
                      label: Text(_t('اسکن QR', 'Scan QR')),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.accent,
                        side: const BorderSide(color: AppColors.accent),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                _t('نام سرور (اختیاری)', 'Server Name (optional)'),
                style: TextStyle(
                  color: AppColors.muted(context),
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _nameController,
                style: TextStyle(color: AppColors.fg(context)),
                decoration: InputDecoration(
                  hintText: _t('مثال: سرور من', 'e.g. My Server'),
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
                    borderSide:
                        const BorderSide(color: AppColors.accent, width: 1.5),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              // ---- جعل نشانگر نام سرور (SNI Spoof) ----
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: AppColors.surface(context),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppColors.border(context)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        _t('جعل نشانگر نام سرور', 'Spoof Server Name Indicator'),
                        style: TextStyle(
                          color: AppColors.fg(context),
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      subtitle: Text(
                        _t(
                          'اگر SNI مسدود است، دامنهٔ جعلی انتخاب کنید',
                          'If SNI is blocked, pick a spoofed domain',
                        ),
                        style: TextStyle(
                            color: AppColors.muted2(context), fontSize: 11),
                      ),
                      value: _sniEnabled,
                      activeColor: AppColors.accent,
                      onChanged: (v) {
                        setState(() {
                          _sniEnabled = v;
                          if (v && _sniController.text.trim().isEmpty) {
                            _sniController.text = TorSniPresets.defaultSni;
                          }
                        });
                      },
                    ),
                    if (_sniEnabled) ...[
                      const SizedBox(height: 4),
                      InkWell(
                        borderRadius: BorderRadius.circular(10),
                        onTap: () => _showSniPicker(),
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 12),
                          decoration: BoxDecoration(
                            color: AppColors.bg(context),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                                color: AppColors.border(context)),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.security,
                                  color: AppColors.accent, size: 18),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  _sniController.text.trim().isEmpty
                                      ? TorSniPresets.defaultSni
                                      : _sniController.text.trim(),
                                  style: TextStyle(
                                    color: AppColors.fg(context),
                                    fontSize: 13,
                                  ),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              Icon(Icons.chevron_left,
                                  color: AppColors.muted2(context), size: 20),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        _t(
                          'از این مورد تنها اگر نمی‌توانید به TOR متصل شوید استفاده کنید. ممکن است باعث عدم اتصال بعضی سرورها شود.',
                          'Use only if you cannot connect. May break some servers.',
                        ),
                        style: TextStyle(
                            color: AppColors.muted2(context),
                            fontSize: 11,
                            height: 1.4),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: _addFromLink,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.accent,
                    foregroundColor: Colors.black,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: Text(
                    _t('افزودن سرور', 'Add Server'),
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ] else if (_selectedType == 'aether' ||
                false) ...[
                            _buildAetherForm(),
              const SizedBox(height: 16),
            ] else if (_selectedType == 'siphon') ...[
              _buildSiphonForm(),
            ] else if (_selectedType == 'tor') ...[
              _buildTorForm(),
            ],
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _linkController.dispose();
    _psiphonSponsorController.dispose();
    _psiphonChannelController.dispose();
    _psiphonConfigController.dispose();
    _nameController.dispose();
    _sniController.dispose();
    _aetherDnsController.dispose();
    _aetherPeerController.dispose();
    _aetherUpstreamController.dispose();
    _aetherTeamController.dispose();
    _aetherAccessEmailController.dispose();
    _aetherAccessIdController.dispose();
    _aetherAccessSecretController.dispose();
    _aetherAccessTokenController.dispose();
    _aetherPsiphonRegionController.dispose();
    _aetherTorBridgeController.dispose();
    _aetherRouteDirectController.dispose();
    _aetherRouteBlockController.dispose();
    _aetherOuterController.dispose();
    _aetherInnerController.dispose();
    _aetherListenPortController.dispose();
    super.dispose();
  }
}
