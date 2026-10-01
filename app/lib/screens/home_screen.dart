import 'dart:async';
import 'dart:io';
import 'package:flutter/gestures.dart';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:reorderable_grid_view/reorderable_grid_view.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/server.dart';
import '../models/subscription.dart';
import '../models/aether_profile.dart';
import '../services/aether_service.dart';
import '../services/announcement_service.dart';
import '../services/app_colors.dart';
import '../services/server_tester.dart';
import '../services/tor_session_service.dart';
import '../services/connectivity_watcher.dart';
import '../services/connection_log_service.dart';
import '../services/tunnel_session_service.dart';
import '../models/tunnel_profile.dart';
import '../models/ssh_profile.dart';
import '../services/ssh_session_service.dart';
import '../services/master_dns_session_service.dart';
import '../services/desync_service.dart';
import '../services/warp_masque_session_service.dart';
import '../services/warp_masque_service.dart';
import '../services/warp_service.dart';
import '../services/warp_endpoint_health_monitor.dart';
import '../services/connection_quality.dart';
import '../services/quality_history_service.dart';
import '../services/telemetry_service.dart';
import '../services/quality_alert.dart';
import 'quality_history_screen.dart';
import '../services/warp_batch_tester.dart';
import '../services/warp_scout_scheduler.dart';
import '../widgets/quality_badge.dart';
import '../services/warp_cache_codec.dart';
import '../services/geo_assets_service.dart';
import '../services/xray_settings.dart';
import '../services/settings_service.dart';
import '../services/quick_connect.dart';
import '../services/exit_ip_service.dart';
import '../services/geo_flag.dart';
import '../services/server_batch_export.dart';
import '../services/psiphon_service.dart';
import '../services/link_parser.dart';
import '../services/xray_json.dart';
import '../services/v2ray_engine.dart';
import '../services/home_widget_service.dart';
import '../services/widget_connect_handler.dart';
import '../widgets/server_tile.dart';
import 'add_config_screen.dart';

import 'tor_screen.dart';
import 'qr_share_screen.dart';
import '../widgets/traffic_sparkline.dart';

class _TwoSecondDragStartListener extends ReorderableDragStartListener {
  const _TwoSecondDragStartListener({
    super.key,
    required super.index,
    required super.child,
    super.enabled = true,
  });

  @override
  MultiDragGestureRecognizer createRecognizer() {
    return DelayedMultiDragGestureRecognizer(
      delay: const Duration(milliseconds: 1500),
      debugOwner: this,
    );
  }
}

class HomeScreen extends StatefulWidget {
  final List<VpnServer> extraServers;
  final List<Subscription> subscriptions;
  final VoidCallback? onOpenSettings;
  final String language;
  final VoidCallback? onRefreshSubscriptions;

  const HomeScreen({
    super.key,
    this.extraServers = const [],
    this.subscriptions = const [],
    this.onOpenSettings,
    this.language = 'fa',
    this.onRefreshSubscriptions,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  static const String _deletedKey = 'deleted_server_ids_v1';
  static const String _pinnedKey = 'pinned_server_ids_v1';
  static const String _customKey = 'custom_servers_v1';
  static const String _pingsKey = 'server_pings_v1';
  static const String _orderKey = 'server_order_v1';
  static const String _customSubTagsKey = 'custom_server_sub_tags_v1';

  final TextEditingController _searchController = TextEditingController();
  final ScrollController _listScrollController = ScrollController();
  final Map<String, GlobalKey> _tileKeys = <String, GlobalKey>{};

  List<VpnServer> _servers = [];
  List<VpnServer> _customServers = [];
  // tag سرورهای custom به سابسکریپشن‌ها: serverId → subscriptionId
  Map<String, String> _customSubTags = <String, String>{};
  Set<String> _deletedIds = <String>{};
  Set<String> _pinnedIds = <String>{};
  bool _showAllTab = true;
  bool _twoColumnGrid = false;

  // ─── گروه «سرور رایگان» (تلگرام) ───

  // ─── auto fastest interval + reconnect ───
  Timer? _autoFastestTimer;
  Timer? _autoTestTimer;
  bool _autoReconnectRunning = false;
  bool _autoFailoverRunning = false;
  bool _autoFailoverEnabled = false;
  final QualityMonitor _qualityMonitor = QualityMonitor();
  final WarpBatchTester _batchTester = WarpBatchTester();
  bool _batchRunning = false;
  DateTime? _lastConnectTime;
  // Smart Resume: true = کاربر خودش دستی قطع کرد (auto-reconnect نشه)
  bool _manualDisconnect = false;
  Timer? _widgetTimerRefresh;
  bool _smartResumeEnabled = true;
  List<String> _manualOrder = <String>[];
  static const String _sortKey = 'settings_sort_ascending_v1';
  bool _sortAscending = true;

  // ─── گروه‌های کاربر ───
  Map<String, List<String>> _userGroups = <String, List<String>>{};
  List<String> _userGroupsOrder = <String>[];
  static const String _userGroupsKey = 'server_groups_v1';
  static const String _userGroupsOrderKey = 'server_groups_order_v1';
  final TextEditingController _groupConfigCtrl = TextEditingController();

  String? _selectedSubId;
  // اگر از ویجت با widget_needs_server اومده باشیم، این مقدار پر می‌شه
  int? _pendingWidgetId;
  VpnServer? _selected;
  VpnServer? _active;

  TestSession? _session;
  Timer? _pollTimer;

  bool _testing = false;
  bool _connecting = false;
  bool _connected = false;
  bool _selectionMode = false;
  final Set<String> _selectedIds = <String>{};
  bool _showSearch = false;
  bool _cancelConnect = false;
  bool _polling = false;

  int _pollTick = 0;
  int _deadStrikes = 0;
  int? _livePing;

  String _searchQuery = '';
  String _status = 'آماده';

  int _tested = 0;
  int _total = 0;

  bool get _isFa => widget.language == 'fa';
  String _t(String fa, String en) => _isFa ? fa : en;

  @override
  /// بررسی می‌کند که آیا از intent جاری (cold start)، درخواست انتخاب سرور
  /// برای ویجت آمده است.
  Future<void> _readWidgetSelectionIntent() async {
    try {
      const ch = MethodChannel('com.hasan.hasan_vpn/widget');
      final map = await ch.invokeMethod<Map>('getLaunchExtras');
      if (map != null && map['widget_needs_server'] == true) {
        final wid = (map['widget_id'] as num?)?.toInt();
        if (wid != null && wid > 0) _activateWidgetSelection(wid);
      }
    } catch (_) {}
  }

  /// حالت انتخاب سرور برای یک ویجت خاص را فعال می‌کند و SnackBar نشان
  /// می‌دهد. هم از cold-start (_readWidgetSelectionIntent) و هم از
  /// warm-start — وقتی اپ از قبل در پس‌زمینه زنده بوده و MainActivity از
  /// طریق onNewIntent پیام widget_needs_server را پوش می‌کند
  /// (WidgetConnectHandler.listen → onNeedsServer) — صدا زده می‌شود.
  void _activateWidgetSelection(int widgetId) {
    if (!mounted) return;
    setState(() => _pendingWidgetId = widgetId);
    // Scaffold ممکن است هنوز کامل mount نشده باشد (به‌خصوص در cold start)؛
    // نمایش SnackBar را به بعد از فریم جاری موکول می‌کنیم.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_t(
            'سرور مورد نظر برای این ویجت را انتخاب کنید',
            'Choose the server for this widget',
          )),
          duration: const Duration(seconds: 5),
        ),
      );
    });
  }

  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _bootstrap();
    // رصد تغییرات شبکه — اتصال مجدد خودکار
    ConnectivityWatcher.instance.start(_onNetworkReconnected);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // ignore: unawaited_futures
      _readWidgetSelectionIntent();
    });
  }

  Future<void> _bootstrap() async {
    // ─── مجوز اعلان + VPN در اولین اجرا ───
    // ignore: unawaited_futures
    _requestFirstLaunchPermissions();
    // ─── دانلود خودکار Geo ایران در اولین اجرا ───
    // ignore: unawaited_futures
    _autoDownloadGeoIran();
    // ─── listener برای قطع خودکار سرور وقتی Tor روت می‌کنه ───
    TorSessionService.instance.routingCount.addListener(_onTorRoutingChanged);
    TunnelSessionService.instance.routingCount
        .addListener(_onTunnelRoutingChanged);
    SshSessionService.instance.routingCount
        .addListener(_onSshRoutingChanged);
    MasterDnsSessionService.instance.routingCount
        .addListener(_onMasterDnsRoutingChanged);
    WarpMasqueSessionService.instance.routingCount
        .addListener(_onWarpMasqueRoutingChanged);
    WarpMasqueService.scanProgress.addListener(_onMasqueScanProgress);
    WarpEndpointHealthMonitor.instance.onDegraded = _onWarpEndpointDegraded;
    WarpEndpointHealthMonitor.instance.onRecovered = _onWarpEndpointRecovered;
    // WARP Scout Scheduler — restore تنظیمات ذخیره‌شده
    WarpScoutScheduler.instance.serversProvider = () => _servers;
    WarpScoutScheduler.instance.onRescanNeeded = _onSchedulerRescan;
    // ignore: unawaited_futures
    WarpScoutScheduler.instance.restore();
    // Quality alert
    QualityAlert.instance.onLowQuality = _onLowQuality;
    QualityAlert.instance.onRecovered = _onQualityRecovered;
    // ignore: unawaited_futures
    QualityAlert.instance.restore();
    // Batch test auto-run
    _maybeAutoBatchOnStart();
    // آماده‌سازی export cache
    // ignore: unawaited_futures
    Future<void>.delayed(const Duration(seconds: 2), () {
      if (mounted) _refreshExportCache();
    });
    // Smart Resume pref
    // ignore: unawaited_futures
    _loadSmartResumePref();

    await _loadDeletedAndPinned();
    await _loadUiSettings();
    await _loadCustomServers();
    await _loadCustomSubTags();
    await _loadServerNameOverrides();
    await _loadManualOrder();
    await _loadUserGroups();
    if (!mounted) return;
    _rebuildServerList();
    await _loadPings();
    // FIX: بعد از بارگذاری ping‌ها، ترتیب sort رو اعمال کن — وگرنه
    // سرورها بدون ping مرتب می‌شن و ترتیب گم می‌شه.
    await _loadSortPreference();
    _rebuildServerList();
    await _loadLastServer();
    await V2RayEngine.init();
    await V2RayEngine.loadDelayUrl();
    if (!mounted) return;
    // 12 s, not 4 s. The 4 s tick was building and probing the tunnel
    // every 4 seconds of every session, which is most of the heat.
    // A tunnel that dies takes longer to notice but the user sees a
    // "lost" state within one poll cycle either way.
    _pollTimer = Timer.periodic(const Duration(seconds: 12), (_) => _poll());
    _startAutoFastestInterval();
    _startAutoTestTimer();
    // ویجت صفحهٔ اصلی: درخواست معلق اتصال
    WidgetConnectHandler.listen(
      (req) {
        // ignore: unawaited_futures
        _handleWidgetRequest(req);
      },
      onNeedsServer: (widgetId) => _activateWidgetSelection(widgetId),
      onChooseTorBridge: (widgetId) => _openTorBridgePickerForWidget(widgetId),
    );
    // ★ ابتدا بررسی انتخاب سرور برای ویجت (اگر pending server selection هست، اپ رو نبند)
    await _readWidgetSelectionIntent();
    if (_pendingWidgetId == null) {
      final pending = await WidgetConnectHandler.consumePending();
      if (pending != null && mounted) {
        await _handleWidgetRequest(pending);
      }
    } else {
      // pending server selection داریم → consumePending رو پاک کن بدون اجرا
      await WidgetConnectHandler.consumePending();
    }
  }

  /// اتصال از ویجت ۲×۱ / ۱×۱
  Future<void> _handleWidgetRequest(WidgetConnectRequest req) async {
    if (!mounted || req.payload.isEmpty) return;

    // ویجت ۱×۱: فوراً به پس‌زمینه برو تا UI دیده نشود
    if (req.bgConnect) {
      // ignore: unawaited_futures
      _maybeMoveTaskToBack();
    }

    // به ریشه برگرد تا صفحهٔ قبلی (مثلاً Tor) باز نماند
    try {
      Navigator.of(context).popUntil((r) => r.isFirst);
    } catch (_) {}

    final payload = req.payload.trim();
    final looksLikeBridge = RegExp(
      r'^(obfs4|snowflake|meek|conjure|dnstt)\b',
      caseSensitive: false,
    ).hasMatch(payload);
    final type = looksLikeBridge ? 'tor' : req.type;

    if (type == 'dns') {
      final parts = payload.split('|');
      final primary = parts.isNotEmpty ? parts[0].trim() : '';
      final secondary = parts.length > 1 ? parts[1].trim() : '';
      if (primary.isEmpty) return;
      await SettingsService.setGameDns(primary, secondary);
      if (!mounted) return;
      _showMsg(_t(
        'DNS بازی از ویجت: $primary',
        'Game DNS from widget: $primary',
      ));
      if (req.bgConnect) await _maybeMoveTaskToBack();
      return;
    }

    if (type == 'tor') {
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => TorScreen(
            language: widget.language,
            initialBridgeLine: payload,
            autoConnect: req.autoConnect,
          ),
        ),
      );
      return;
    }

    // server — فقط صفحهٔ اصلی + اتصال همان سرور
    final idx = _servers.indexWhere(
      (s) =>
          s.id == payload ||
          s.shareLink == payload ||
          s.displayName == req.title,
    );
    if (idx < 0) {
      _showMsg(_t(
        'سرور ویجت پیدا نشد — دوباره از داخل اپ پین کنید',
        'Widget server not found — pin again from the app',
      ));
      return;
    }
    final server = _servers[idx];
    setState(() => _selected = server);
    await SettingsService.setLastServer(server.id);

    if (!req.autoConnect) return;
    if (_connected && _active?.id == server.id) {
      if (req.bgConnect) await _maybeMoveTaskToBack();
      return;
    }
    if (_connected) {
      try {
        await _disconnectAll();
      } catch (_) {}
      _markDisconnected(_t('آماده', 'Ready'));
    }
    if (!mounted) return;
    await _toggleConnection();
    if (req.bgConnect) await _maybeMoveTaskToBack();
  }

  /// ویجت ۱×۱: بعد از شروع اتصال، اپ را به پس‌زمینه بفرست
  Future<void> _maybeMoveTaskToBack() async {
    try {
      const ch = MethodChannel('com.hasan.hasan_vpn/widget');
      await ch.invokeMethod('moveTaskToBack');
    } catch (_) {}
  }

  @override
  void didUpdateWidget(covariant HomeScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.extraServers != widget.extraServers ||
        oldWidget.subscriptions != widget.subscriptions ||
        oldWidget.language != widget.language) {
      _rebuildServerList();
    }
  }

  // ------------------------------------------------------------------ Pings

  Future<void> _loadPings() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_pingsKey);
    if (raw == null) return;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return;
      final pings = Map<String, dynamic>.from(decoded);
      for (final server in _servers) {
        final entry = pings[server.id];
        if (entry is Map) {
          final ping = entry['ping'];
          final kind = entry['kind']?.toString();
          if (ping is int && ping > 0) {
            server.ping = ping;
            // از الان همه‌ی پینگ‌ها real هستن؛ اما اگه کش قدیمی از نسخه‌ی
            // قبل با tcp ذخیره شده باشه، اون رو نادیده می‌گیریم.
            if (kind == 'real') {
              server.pingKind = PingKind.real;
              server.status = ServerStatus.online;
            } else {
              // کش قدیمی TCP رو نادیده بگیر.
              server.ping = null;
              server.pingKind = PingKind.none;
              server.status = ServerStatus.idle;
            }
          }
        }
      }
      if (mounted) setState(() {});
    } catch (_) {}
  }

  Future<void> _savePings() async {
    final prefs = await SharedPreferences.getInstance();
    final map = <String, dynamic>{};
    for (final server in _servers) {
      if (server.ping != null &&
          server.ping! > 0 &&
          server.pingKind == PingKind.real) {
        map[server.id] = {
          'ping': server.ping,
          'kind': 'real',
        };
      }
    }
    await prefs.setString(_pingsKey, jsonEncode(map));
  }

  // ----------------------------------------------------- server names

  Future<void> _loadServerNameOverrides() async {
    final overrides = await SettingsService.getServerNameOverrides();
    final allServers = <VpnServer>[
      ..._customServers,
      ...widget.extraServers,
    ];
    for (final server in allServers) {
      final ov = overrides[server.id];
      if (ov != null && ov.isNotEmpty) {
        server.nameOverride = VpnServer.sanitizeServerName(ov);
      }
    }
  }

  Future<void> _editServerName(VpnServer server) async {
    // Aether / Oblivion: فرم کامل تنظیمات
    if (server.isAether) {
      await _editAetherServer(server);
      return;
    }
    await _editServerFull(server);
  }

  Future<void> _editServerFull(VpnServer server) async {
    final nameCtrl = TextEditingController(text: server.displayName);
    final sniCtrl = TextEditingController(text: server.sniOrHost ?? '');
    final alpnCtrl = TextEditingController(text: server.tls.alpn ?? '');
    final cipherCtrl =
        TextEditingController(text: server.tls.cipherSuites ?? '');
    final echCtrl = TextEditingController(text: server.tls.echConfigList ?? '');
    final verifyPeerCtrl =
        TextEditingController(text: server.tls.verifyPeerCertByName ?? '');
    final pinCtrl =
        TextEditingController(text: server.tls.pinnedPeerCertSha256 ?? '');
    final finalMaskCtrl =
        TextEditingController(text: server.tls.finalMask ?? '');
    final dialModeCtrl =
        TextEditingController(text: server.tls.dialMode ?? '');
    final targetStratCtrl =
        TextEditingController(text: server.tls.targetStrategy ?? '');
    final dnsCtrl = TextEditingController(text: server.dns ?? '');
    final sniPoolCtrl =
        TextEditingController(text: server.tls.sniPool.join(', '));
    final backupCtrl =
        TextEditingController(text: server.backupAddresses.join(', '));


    String fp = server.tls.fingerprint ?? 'none';
    bool insecure = server.tls.allowInsecure;
    bool browserDialer = server.tls.browserDialer;

    try {
      final result = await showDialog<Map<String, dynamic>>(
        context: context,
        builder: (ctx) => StatefulBuilder(builder: (ctx, setLocal) {
          Widget field(String label, TextEditingController c,
              {int maxLines = 1, String? hint}) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: TextField(
                controller: c,
                maxLines: maxLines,
                style: TextStyle(color: AppColors.fg(ctx), fontSize: 13),
                decoration: InputDecoration(
                  labelText: label,
                  hintText: hint,
                  hintStyle:
                      TextStyle(color: AppColors.muted2(ctx), fontSize: 11),
                  labelStyle:
                      TextStyle(color: AppColors.muted(ctx), fontSize: 12),
                  isDense: true,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            );
          }

          return AlertDialog(
            backgroundColor: AppColors.elevated(ctx),
            title: Text(_t('ویرایش سرور', 'Edit server'),
                style: TextStyle(color: AppColors.fg(ctx), fontSize: 16)),
            content: SizedBox(
              width: double.maxFinite,
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(_t('عمومی', 'General'),
                        style: TextStyle(
                            color: AppColors.accent,
                            fontSize: 12,
                            fontWeight: FontWeight.w700)),
                    const SizedBox(height: 6),
                    field(_t('نام', 'Name'), nameCtrl),
                    field(_t('SNI', 'SNI'), sniCtrl),
                    field(
                        _t('SNI Pool (چند دامنه، جدا با کاما)',
                            'SNI Pool (multiple, comma-separated)'),
                        sniPoolCtrl,
                        hint:
                            'cloudflare.com, google.com, github.com'),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(
                        _t(
                          'اگه پر باشه، هر اتصال یه دامنه تصادفی از این لیست انتخاب می‌کنه (دور زدن DPI بر اساس SNI). خالی = فقط SNI بالا.',
                          'If set, each connection picks a random domain from this list (SNI-based DPI bypass). Empty = only the SNI above.',
                        ),
                        style: TextStyle(
                            color: AppColors.muted2(ctx),
                            fontSize: 10,
                            height: 1.4),
                      ),
                    ),
                    field(
                        _t('آدرس‌های پشتیبان (Multi-address failover)',
                            'Backup addresses (failover)'),
                        backupCtrl,
                        hint: '1.2.3.4:443, 5.6.7.8:8443'),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(
                        _t(
                          'اگه پر باشه، قبل از هر اتصال همهٔ آدرس‌ها probe می‌شن و بهترین انتخاب می‌شه (score = mean_rtt + 2×jitter + 20×loss). فرمت: host:port با کاما.',
                          'If set, all addresses are probed before each connect and the best is chosen (score = mean_rtt + 2*jitter + 20*loss). Format: host:port, comma-separated.',
                        ),
                        style: TextStyle(
                            color: AppColors.muted2(ctx),
                            fontSize: 10,
                            height: 1.4),
                      ),
                    ),
                    field(
                        _t('DNS سفارشی (اختیاری)', 'Custom DNS (optional)'),
                        dnsCtrl,
                        hint: '9.9.9.9 یا 9.9.9.9,1.1.1.1'),

                    const SizedBox(height: 8),
                    Text(_t('TLS / Fingerprint', 'TLS / Fingerprint'),
                        style: TextStyle(
                            color: AppColors.accent,
                            fontSize: 12,
                            fontWeight: FontWeight.w700)),
                    const SizedBox(height: 6),
                    DropdownButtonFormField<String>(
                      value: fp,
                      dropdownColor: AppColors.elevated(ctx),
                      style: TextStyle(color: AppColors.fg(ctx), fontSize: 13),
                      decoration: InputDecoration(
                        labelText: _t('اثرانگشت (fingerprint)', 'Fingerprint'),
                        labelStyle:
                            TextStyle(color: AppColors.muted(ctx), fontSize: 12),
                        isDense: true,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      items: const [
                        DropdownMenuItem(value: 'none', child: Text('none')),
                        DropdownMenuItem(value: 'chrome', child: Text('chrome')),
                        DropdownMenuItem(value: 'firefox', child: Text('firefox')),
                        DropdownMenuItem(value: 'safari', child: Text('safari')),
                        DropdownMenuItem(value: 'ios', child: Text('ios')),
                        DropdownMenuItem(value: 'android', child: Text('android')),
                        DropdownMenuItem(value: 'edge', child: Text('edge')),
                        DropdownMenuItem(value: 'random', child: Text('random')),
                        DropdownMenuItem(value: 'randomized', child: Text('randomized')),
                        DropdownMenuItem(value: 'unsafe', child: Text('unsafe')),
                      ],
                      onChanged: (v) => setLocal(() => fp = v ?? 'none'),
                    ),
                    const SizedBox(height: 8),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      activeColor: AppColors.accent,
                      title: Text(
                          _t('نادیده گرفتن تأیید گواهی (allowInsecure)',
                              'Skip cert verify (allowInsecure)'),
                          style:
                              TextStyle(color: AppColors.fg(ctx), fontSize: 12)),
                      value: insecure,
                      onChanged: (v) => setLocal(() => insecure = v),
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      activeColor: AppColors.accent,
                      title: Text(_t('Browser Dialer', 'Browser Dialer'),
                          style:
                              TextStyle(color: AppColors.fg(ctx), fontSize: 12)),
                      value: browserDialer,
                      onChanged: (v) => setLocal(() => browserDialer = v),
                    ),
                    field('ALPN', alpnCtrl, hint: 'h2,http/1.1'),
                    field(_t('مجموعه رمزنگاری (Cipher Suites)', 'Cipher Suites'),
                        cipherCtrl, maxLines: 3),
                    field('echConfigList', echCtrl),
                    field(
                        _t('تأیید گواهی بر اساس نام', 'Verify peer cert by name'),
                        verifyPeerCtrl,
                        hint: 'example.com'),
                    field(_t('اثر انگشت گواهی (SHA-256)',
                            'Pinned peer cert SHA-256'),
                        pinCtrl, maxLines: 3),

                    const SizedBox(height: 8),
                    Text(_t('پیشرفته', 'Advanced'),
                        style: TextStyle(
                            color: AppColors.accent,
                            fontSize: 12,
                            fontWeight: FontWeight.w700)),
                    const SizedBox(height: 6),
                    // Preset Cloudflare: fragment+fingerprint بر اساس
                    // پروتکل Patterniha برای دور زدن محدودیت آپلود CF.
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: () {
                          setLocal(() {
                            fp = 'unsafe';
                            finalMaskCtrl.text =
                                '{"tcp": [{"type": "fragment", "settings": {"packets": "tlshello", "lengths": ["0", "104", "1"], "delays": ["0"], "maxSplit": "0"}},{"type": "fragment", "settings": {"packets": "1-1", "lengths": ["114", "1"], "delays": ["1"], "maxSplit": "11"}}]}';
                            cipherCtrl.text =
                                'TLS_AES_256_GCM_SHA384:TLS_CHACHA20_POLY1305_SHA256:TLS_AES_128_GCM_SHA256:TLS_ECDHE_ECDSA_WITH_AES_256_GCM_SHA384:TLS_ECDHE_RSA_WITH_AES_256_GCM_SHA384:TLS_ECDHE_ECDSA_WITH_AES_128_GCM_SHA256:TLS_ECDHE_RSA_WITH_AES_128_GCM_SHA256:TLS_ECDHE_ECDSA_WITH_CHACHA20_POLY1305_SHA256:TLS_ECDHE_RSA_WITH_CHACHA20_POLY1305_SHA256:TLS_ECDHE_ECDSA_WITH_AES_256_CBC_SHA:TLS_ECDHE_RSA_WITH_AES_256_CBC_SHA:TLS_ECDHE_ECDSA_WITH_AES_128_CBC_SHA256:TLS_ECDHE_RSA_WITH_AES_128_CBC_SHA256';
                          });
                        },
                        icon: const Icon(Icons.cloud_outlined, size: 16),
                        label: Text(
                          _t('Preset کلودفلر (Fragment + Fingerprint)',
                              'Cloudflare preset (Fragment + Fingerprint)'),
                          style: const TextStyle(fontSize: 12),
                        ),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.accent,
                          side: const BorderSide(color: AppColors.accent),
                          padding: const EdgeInsets.symmetric(vertical: 8),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    field('dialMode', dialModeCtrl),
                    field('targetStrategy', targetStratCtrl, hint: 'AsIs'),


                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text(_t('انصراف', 'Cancel'),
                    style: TextStyle(color: AppColors.muted(ctx))),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, {
                  'name': nameCtrl.text.trim(),
                  'sni': sniCtrl.text.trim(),
                  'fingerprint': fp == 'none' ? null : fp,
                  'allowInsecure': insecure,
                  'alpn': alpnCtrl.text.trim(),
                  'cipherSuites': cipherCtrl.text.trim(),
                  'echConfigList': echCtrl.text.trim(),
                  'verifyPeerCertByName': verifyPeerCtrl.text.trim(),
                  'pinnedPeerCertSha256': pinCtrl.text.trim(),
                  'finalMask': finalMaskCtrl.text.trim(),
                  'dialMode': dialModeCtrl.text.trim(),
                  'browserDialer': browserDialer,
                  'targetStrategy': targetStratCtrl.text.trim(),
                  'backupAddresses': backupCtrl.text.trim(),
                  'dns': dnsCtrl.text.trim(),
                }),
                child: Text(_t('ذخیره', 'Save'),
                    style: const TextStyle(color: AppColors.accent)),
              ),
            ],
          );
        }),
      );

      if (result == null || !mounted) return;

      final newName = (result['name'] as String).trim();
      final newSni = (result['sni'] as String).trim();

      String? nz(dynamic v) {
        final s = v?.toString() ?? '';
        return s.isEmpty ? null : s;
      }

      final sniPoolStr = (sniPoolCtrl.text).trim();
      final sniPoolList = sniPoolStr
          .split(RegExp(r'[,\n]+'))
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList();

      final newTls = TlsOptions(
        fingerprint: nz(result['fingerprint']),
        allowInsecure: result['allowInsecure'] == true,
        alpn: nz(result['alpn']),
        cipherSuites: nz(result['cipherSuites']),
        echConfigList: nz(result['echConfigList']),
        verifyPeerCertByName: nz(result['verifyPeerCertByName']),
        pinnedPeerCertSha256: nz(result['pinnedPeerCertSha256']),
        finalMask: nz(result['finalMask']),
        dialMode: nz(result['dialMode']),
        browserDialer: result['browserDialer'] == true,
        targetStrategy: nz(result['targetStrategy']),
        sniPool: sniPoolList,
      );

      final newDns = (result['dns'] as String?)?.trim() ?? '';

      // Multi-address failover (BackPack-derived).
      final newBackups = ((result['backupAddresses'] as String?) ?? '')
          .split(',')
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toList();

      final updated = server.copyWith(
        name: newName.isNotEmpty ? newName : null,
        nameOverride: newName.isNotEmpty ? newName : null,
        tls: newTls,
        dns: newDns.isEmpty ? null : newDns,
        backupAddresses: newBackups,
      );

      // آپدیت sniOrHost (nullable final است؛ مستقیم ست می‌کنیم)
      updated.sniOrHost = newSni.isEmpty ? null : newSni;

      // ذخیره در custom servers یا name override
      final idx = _customServers.indexWhere((s) => s.id == server.id);
      if (idx >= 0) {
        _customServers[idx] = updated;
        await _saveCustomServers();
      } else if (newName.isNotEmpty) {
        await SettingsService.setServerNameOverride(server.id, newName);
      }

      if (!mounted) return;
      setState(() {
        final si = _servers.indexWhere((s) => s.id == server.id);
        if (si >= 0) _servers[si] = updated;
        if (_selected?.id == server.id) _selected = updated;
        if (_active?.id == server.id) _active = updated;
      });

      _showMsg(_t('سرور ویرایش شد', 'Server updated'));
    } finally {
      nameCtrl.dispose();
      sniCtrl.dispose();
      alpnCtrl.dispose();
      cipherCtrl.dispose();
      echCtrl.dispose();
      verifyPeerCtrl.dispose();
      pinCtrl.dispose();
      finalMaskCtrl.dispose();
      dialModeCtrl.dispose();
      targetStratCtrl.dispose();
      dnsCtrl.dispose();
      sniPoolCtrl.dispose();
    }
  }

  Future<void> _editAetherServer(VpnServer server) async {
    final profile = AetherProfile.fromLink(server.shareLink);
    var protocol = profile.protocol;
    var scan = profile.scan;
    var noize = profile.noize;
    var ip = profile.ip;
    final nameCtrl = TextEditingController(text: server.displayName);
    final peerCtrl = TextEditingController(text: profile.peer);
    try {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setLocal) {
            return AlertDialog(
              backgroundColor: AppColors.elevated(ctx),
              title: Text('AETHER',
                  style: TextStyle(color: AppColors.fg(ctx))),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: nameCtrl,
                      style: TextStyle(color: AppColors.fg(ctx)),
                      decoration: InputDecoration(
                        labelText: _t('ملاحظات / نام', 'Remark / name'),
                        labelStyle: TextStyle(color: AppColors.muted(ctx)),
                      ),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      value: protocol,
                      dropdownColor: AppColors.elevated(ctx),
                      decoration: InputDecoration(
                        labelText: _t('پروتکل', 'Protocol'),
                        labelStyle: TextStyle(color: AppColors.muted(ctx)),
                      ),
                      items: AetherProfile.protocols
                          .map((p) => DropdownMenuItem(
                                value: p,
                                child: Text(p,
                                    style: TextStyle(
                                        color: AppColors.fg(ctx))),
                              ))
                          .toList(),
                      onChanged: (v) {
                        if (v != null) setLocal(() => protocol = v);
                      },
                    ),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<String>(
                      value: scan,
                      dropdownColor: AppColors.elevated(ctx),
                      decoration: InputDecoration(
                        labelText: _t('حالت اسکن', 'Scan mode'),
                        labelStyle: TextStyle(color: AppColors.muted(ctx)),
                      ),
                      items: AetherProfile.scans
                          .map((p) => DropdownMenuItem(
                                value: p,
                                child: Text(p,
                                    style: TextStyle(
                                        color: AppColors.fg(ctx))),
                              ))
                          .toList(),
                      onChanged: (v) {
                        if (v != null) setLocal(() => scan = v);
                      },
                    ),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<String>(
                      value: noize,
                      dropdownColor: AppColors.elevated(ctx),
                      decoration: InputDecoration(
                        labelText: _t('مبهم‌سازی', 'Noize'),
                        labelStyle: TextStyle(color: AppColors.muted(ctx)),
                      ),
                      items: AetherProfile.noizes
                          .map((p) => DropdownMenuItem(
                                value: p,
                                child: Text(p,
                                    style: TextStyle(
                                        color: AppColors.fg(ctx))),
                              ))
                          .toList(),
                      onChanged: (v) {
                        if (v != null) setLocal(() => noize = v);
                      },
                    ),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<String>(
                      value: ip,
                      dropdownColor: AppColors.elevated(ctx),
                      decoration: InputDecoration(
                        labelText: _t('نسخه IP', 'IP version'),
                        labelStyle: TextStyle(color: AppColors.muted(ctx)),
                      ),
                      items: AetherProfile.ips
                          .map((p) => DropdownMenuItem(
                                value: p,
                                child: Text(p,
                                    style: TextStyle(
                                        color: AppColors.fg(ctx))),
                              ))
                          .toList(),
                      onChanged: (v) {
                        if (v != null) setLocal(() => ip = v);
                      },
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: peerCtrl,
                      style: TextStyle(color: AppColors.fg(ctx)),
                      decoration: InputDecoration(
                        labelText:
                            _t('نشانی (اختیاری ip:port)', 'Peer (optional)'),
                        labelStyle: TextStyle(color: AppColors.muted(ctx)),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () async {
                    final r = await AetherService.testBinary();
                    if (!ctx.mounted) return;
                    final buf = StringBuffer();
                    buf.writeln(r['ok'] == true ? 'OK' : 'FAIL');
                    if (r['path'] != null) buf.writeln('path: ${r['path']}');
                    if (r['cmd'] != null) buf.writeln('cmd: ${r['cmd']}');
                    if (r['exitCode'] != null) {
                      buf.writeln('exit: ${r['exitCode']}');
                    }
                    if (r['elf'] != null) buf.writeln('elf: ${r['elf']}');
                    if (r['stdout'] != null &&
                        r['stdout'].toString().isNotEmpty) {
                      buf.writeln('--- stdout ---');
                      buf.writeln(r['stdout']);
                    }
                    if (r['stderr'] != null &&
                        r['stderr'].toString().isNotEmpty) {
                      buf.writeln('--- stderr ---');
                      buf.writeln(r['stderr']);
                    }
                    if (r['error'] != null) buf.writeln('error: ${r['error']}');
                    await showDialog<void>(
                      context: ctx,
                      builder: (c2) => AlertDialog(
                        backgroundColor: AppColors.elevated(c2),
                        title: Text(
                          _t('تست باینری Aether', 'Aether binary test'),
                          style: TextStyle(color: AppColors.fg(c2)),
                        ),
                        content: SingleChildScrollView(
                          child: SelectableText(
                            buf.toString(),
                            style: TextStyle(
                              color: AppColors.fg(c2),
                              fontFamily: 'monospace',
                              fontSize: 12,
                            ),
                          ),
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(c2),
                            child: Text('OK',
                                style: const TextStyle(
                                    color: AppColors.accent)),
                          ),
                        ],
                      ),
                    );
                  },
                  child: Text(_t('تست باینری', 'Test binary'),
                      style: TextStyle(color: AppColors.muted(ctx))),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: Text(_t('لغو', 'Cancel'),
                      style: TextStyle(color: AppColors.muted(ctx))),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: Text(_t('ذخیره', 'Save'),
                      style: const TextStyle(color: AppColors.accent)),
                ),
              ],
            );
          },
        );
      },
    );
    if (ok != true || !mounted) return;
    final updated = AetherProfile(
      protocol: protocol,
      scan: scan,
      noize: noize,
      ip: ip,
      dns: profile.dns,
      peer: peerCtrl.text.trim(),
      upstream: profile.upstream,
      quickReconnect: profile.quickReconnect,
      blockQuic: profile.blockQuic,
      perf: profile.perf,
    );
    final newLink = updated.toLink();
    final newName = nameCtrl.text.trim();
    final peerHost = updated.peer.isNotEmpty
        ? updated.peer.split(':').first
        : server.host;
    final next = server.copyWith(
      name: newName.isNotEmpty ? newName : null,
      shareLink: newLink,
      host: peerHost,
      nameOverride: newName.isNotEmpty
          ? VpnServer.sanitizeServerName(newName)
          : null,
    );
    final idx = _customServers.indexWhere((s) => s.id == server.id);
    if (idx >= 0) {
      _customServers[idx] = next;
      await _saveCustomServers();
    } else if (newName.isNotEmpty) {
      await SettingsService.setServerNameOverride(server.id, newName);
    }
    if (!mounted) return;
    setState(() {
      final si = _servers.indexWhere((s) => s.id == server.id);
      if (si >= 0) _servers[si] = next;
      if (_selected?.id == server.id) _selected = next;
      if (_active?.id == server.id) _active = next;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(_t('تنظیمات Aether ذخیره شد', 'Aether saved'))),
    );
    } finally {
      nameCtrl.dispose();
      peerCtrl.dispose();
    }
  }

  // ----------------------------------------------------- last server

  Future<void> _loadLastServer() async {
    final id = await SettingsService.getLastServer();
    if (id == null) return;
    final idx = _servers.indexWhere((s) => s.id == id);
    if (idx >= 0 && mounted) {
      setState(() => _selected = _servers[idx]);
    }
  }

  Future<void> _jumpToSelected() async {
    // Index-only. The old code used Scrollable.ensureVisible with a
    // GlobalKey; with thousands of servers that forces Flutter to lay out
    // and search the whole list before it can even start, which is why
    // the app froze. The list rows are a fixed 78 px (SizedBox 74 +
    // bottom 4), so a plain jumpTo is exact and instant.
    final selected = _selected;
    if (selected == null) {
      _showMsg(_t('هیچ سروری انتخاب نشده', 'No server selected'));
      return;
    }
    final idx = _servers.indexWhere((s) => s.id == selected.id);
    if (idx == -1) {
      _showMsg(
          _t('سرور انتخاب‌شده در لیست نیست', 'Selected server is not in list'));
      return;
    }
    if (!_listScrollController.hasClients) return;

    // Row height: see _buildServerList — SizedBox(height: 74) + 4 padding,
    // or mainAxisExtent 62 + 6 spacing in grid mode.
    final rowHeight = _twoColumnGrid ? 62.0 : 78.0;
    final gridRow = _twoColumnGrid ? (idx ~/ 2) : idx;
    final target = (gridRow * rowHeight)
        .clamp(0.0, _listScrollController.position.maxScrollExtent);
    _listScrollController.jumpTo(target);
  }

  // ------------------------------------------------------------- loading

  Future<void> _loadUiSettings() async {
    try {
      final xs = await XraySettings.load();
      final showAll = xs['showAllTab'] != false;
      final twoCol = xs['twoColumnGrid'] == true;
      if (mounted) {
        setState(() {
          _showAllTab = showAll;
          _twoColumnGrid = twoCol;
        });
      }
    } catch (_) {}
  }

  Future<void> _loadDeletedAndPinned() async {
    final prefs = await SharedPreferences.getInstance();
    final deletedRaw = prefs.getString(_deletedKey);
    if (deletedRaw != null) {
      try {
        final decoded = jsonDecode(deletedRaw);
        if (decoded is List) {
          _deletedIds = decoded.map((e) => e.toString()).toSet();
        }
      } catch (_) {}
    }
    final pinnedRaw = prefs.getString(_pinnedKey);
    if (pinnedRaw != null) {
      try {
        final decoded = jsonDecode(pinnedRaw);
        if (decoded is List) {
          _pinnedIds = decoded.map((e) => e.toString()).toSet();
        }
      } catch (_) {}
    }
  }

  Future<void> _loadCustomServers() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_customKey);
    if (raw == null) return;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return;
      final loaded = <VpnServer>[];
      for (final item in decoded) {
        if (item is! Map) continue;
        final map = Map<String, dynamic>.from(item);
        final id = map['id']?.toString();
        final name = map['name']?.toString();
        final shareLink = map['shareLink']?.toString();
        if (id == null || name == null || shareLink == null) continue;
        final protocolName = map['protocol']?.toString() ?? 'custom';
        final protocol = VpnProtocol.values.firstWhere(
          (value) => value.name == protocolName,
          orElse: () => VpnProtocol.custom,
        );
        loaded.add(VpnServer(
          id: id,
          name: name,
          flag: map['flag']?.toString() ?? '🔧',
          shareLink: shareLink,
          protocol: protocol,
          host: map['host']?.toString() ?? '',
          port: _safePort(map['port']),
          isDeletable: true,
        ));
      }
      _customServers = loaded;
    } catch (_) {
      _customServers = <VpnServer>[];
    }
  }

  int _safePort(dynamic value) {
    if (value is int && value > 0 && value <= 65535) return value;
    final parsed = int.tryParse(value?.toString() ?? '');
    if (parsed != null && parsed > 0 && parsed <= 65535) return parsed;
    return 443;
  }

  /// آماده‌سازی داده export برای settings screen.
  Future<void> _refreshExportCache() async {
    try {
      final json = ServerBatchExport.export(_servers);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('quick_export_servers_v1', json);
    } catch (e) {
      debugPrint('refreshExportCache: $e');
    }
  }

  Future<void> _saveCustomServers() async {
    final prefs = await SharedPreferences.getInstance();
    final data = _customServers
        .map((server) => <String, dynamic>{
              'id': server.id,
              'name': server.name,
              'flag': server.flag,
              'shareLink': server.shareLink,
              'protocol': server.protocol.name,
              'host': server.host,
              'port': server.port,
            })
        .toList();
    await prefs.setString(_customKey, jsonEncode(data));
    // Keep the export cache in step. Quality history and server health
    // screens read `quick_export_servers_v1`; the cache was only built in
    // initState, so after adding or editing a server those screens kept
    // looking at a snapshot from app launch.
    unawaited(_refreshExportCache());
  }

  Future<void> _saveDeleted() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_deletedKey, jsonEncode(_deletedIds.toList()));
  }

  Future<void> _saveCustomSubTags() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_customSubTagsKey, jsonEncode(_customSubTags));
  }

  Future<void> _loadCustomSubTags() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_customSubTagsKey);
      if (raw == null) return;
      final m = jsonDecode(raw) as Map;
      _customSubTags = m.map((k, v) => MapEntry(k.toString(), v.toString()));
    } catch (_) {
      _customSubTags = <String, String>{};
    }
  }

  Future<void> _savePinned() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_pinnedKey, jsonEncode(_pinnedIds.toList()));
  }

  Future<void> _loadSortPreference() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final v = prefs.getBool(_sortKey);
      if (v != null) _sortAscending = v;
    } catch (_) {}
  }

  Future<void> _saveSortPreference() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_sortKey, _sortAscending);
    } catch (_) {}
  }

  Future<void> _loadManualOrder() async {
    final prefs = await SharedPreferences.getInstance();
    _manualOrder = prefs.getStringList(_orderKey) ?? <String>[];
  }

  Future<void> _loadUserGroups() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_userGroupsKey) ?? '{}';
      final dec = jsonDecode(raw);
      final m = <String, List<String>>{};
      if (dec is Map) {
        dec.forEach((k, v) {
          if (v is List) {
            m[k.toString()] = v.map((e) => e.toString()).toList();
          }
        });
      }
      final ord = prefs.getStringList(_userGroupsOrderKey) ?? <String>[];
      for (final k in m.keys) {
        if (!ord.contains(k)) ord.add(k);
      }
      if (mounted) {
        setState(() {
          _userGroups = m;
          _userGroupsOrder = ord;
        });
      } else {
        _userGroups = m;
        _userGroupsOrder = ord;
      }
    } catch (_) {}
  }

  Future<void> _cleanupOrphanGroupIds() async {
    // FIX2: strip deleted-server ids out of every user group
    if (_userGroups.isEmpty) return;
    var changed = false;
    final cleaned = <String, List<String>>{};
    _userGroups.forEach((k, v) {
      final filtered = v.where((id) => !_deletedIds.contains(id)).toList();
      if (filtered.length != v.length) changed = true;
      cleaned[k] = filtered;
    });
    if (!changed) return;
    _userGroups = cleaned;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_userGroupsKey, jsonEncode(_userGroups));
    if (mounted) setState(() {});
  }

  Future<void> _saveManualOrder() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_orderKey, _manualOrder);
  }

  Future<void> _onReorder(int oldIndex, int newIndex) async {
    // FIX: جلوگیری از wrap-around و out-of-bounds. ReorderableGridView
    // گاهی وقتی به انتها می‌رسه newIndex رو خارج از محدوده می‌ده.
    if (_servers.isEmpty) return;
    if (oldIndex < 0 || oldIndex >= _servers.length) return;
    if (newIndex > oldIndex) newIndex -= 1;
    newIndex = newIndex.clamp(0, _servers.length - 1);
    if (newIndex == oldIndex) return;

    setState(() {
      final item = _servers.removeAt(oldIndex);
      _servers.insert(newIndex, item);
      _manualOrder = _servers.map((s) => s.id).toList();
    });
    await _saveManualOrder();
  }

  Widget _compactIconButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback onPressed,
    Color? color,
  }) {
    return IconButton(
      icon: Icon(icon, size: 18, color: color),
      tooltip: tooltip,
      onPressed: onPressed,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
      visualDensity: VisualDensity.compact,
    );
  }

  Future<void> _openReorderSelectedSheet() async {
    final selected = _servers
        .where((s) => _selectedIds.contains(s.id))
        .toList();
    if (selected.length < 2) {
      _showMsg(_t('حداقل ۲ سرور انتخاب کنید', 'Select at least 2'));
      return;
    }

    final result = await showModalBottomSheet<List<VpnServer>>(
      context: context,
      backgroundColor: AppColors.elevated(context),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        var items = List<VpnServer>.from(selected);
        return StatefulBuilder(
          builder: (ctx, setModalState) => SafeArea(
            child: SizedBox(
              height: MediaQuery.of(ctx).size.height * 0.6,
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      children: [
                        const Icon(Icons.swap_vert, color: AppColors.accent),
                        const SizedBox(width: 8),
                        Text(
                          _t('جابه‌جایی سرورها', 'Reorder servers'),
                          style: TextStyle(
                            color: AppColors.fg(ctx),
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: ReorderableListView.builder(
                      buildDefaultDragHandles: false,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      itemCount: items.length,
                      onReorder: (o, n) {
                        setModalState(() {
                          if (n > o) n -= 1;
                          final moved = items.removeAt(o);
                          items.insert(n, moved);
                        });
                      },
                      itemBuilder: (ctx, i) => ReorderableDragStartListener(
                        key: ValueKey('reorder_sel_${items[i].id}'),
                        index: i,
                        child: Card(
                          margin: const EdgeInsets.symmetric(vertical: 3),
                          color: AppColors.surface(ctx),
                          child: ListTile(
                            dense: true,
                            title: Text(
                              items[i].displayName,
                              style: TextStyle(
                                color: AppColors.fg(ctx),
                                fontSize: 13,
                              ),
                            ),
                            trailing: Icon(
                              Icons.drag_handle,
                              color: AppColors.muted2(ctx),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(10),
                    child: Row(
                      children: [
                        Expanded(
                          child: TextButton(
                            onPressed: () => Navigator.pop(ctx),
                            child: Text(_t('انصراف', 'Cancel')),
                          ),
                        ),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: () => Navigator.pop(ctx, items),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.accent,
                            ),
                            child: Text(
                              _t('ذخیره', 'Save'),
                              style: const TextStyle(color: Colors.black),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );

    if (result == null || result.isEmpty || !mounted) return;

    final reorderedIds = result.map((s) => s.id).toList();
    final rest = _servers
        .where((s) => !_selectedIds.contains(s.id))
        .map((s) => s.id)
        .toList();

    setState(() {
      _manualOrder = <String>[...reorderedIds, ...rest];
      _selectionMode = false;
      _selectedIds.clear();
    });
    await _saveManualOrder();
    _rebuildServerList();
    if (mounted) setState(() {});
  }


  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed) {
      _syncRealConnectionState();
      // ویجت ممکن است وقتی اپ در پس‌زمینه بوده extras نوشته باشد
      // ignore: unawaited_futures
      WidgetConnectHandler.consumePending().then((req) {
        if (req != null && mounted) _handleWidgetRequest(req);
      });
      // باگ #1: اگر اپ از قبل زنده بوده و کاربر روی ویجتِ بدون binding
      // زده، onNewIntent باید widget_needs_server را از طریق
      // onNeedsServer پوش کرده باشد؛ این فراخوانی صرفاً یک fallback است
      // برای مواردی که آن پیام به هر دلیلی از دست رفته باشد.
      if (_pendingWidgetId == null) {
        // ignore: unawaited_futures
        _readWidgetSelectionIntent();
      }
    }
  }

  Future<void> _syncRealConnectionState() async {
    if (!mounted || _connecting) return;
    try {
      // Utility sessions (Tor / Aether / Psiphon / SSH / Tunnel) have
      // their own liveness signals, and V2Ray's flag alone says nothing
      // about them. Leave the state alone when one of them is routing.
      if (TorSessionService.instance.anyRouting ||
          TunnelSessionService.instance.anyRouting ||
          SshSessionService.instance.anyRouting ||
          V2RayEngine.isUtilitySession) {
        return;
      }
      final alive = V2RayEngine.isConnected;
      if (!mounted) return;
      if (!alive && _connected) {
        _markDisconnected(_t('اتصال قطع شد', 'Connection lost'));
      }
    } catch (_) {}
  }

  // ------------------------------------------------------------- list

  List<VpnServer> _torPresets() => [
        VpnServer(
          id: TorSessionService.presetVanillaId,
          name: 'Tor \u0633\u0627\u062F\u0647',
          flag: '\u{1F9C5}',
          shareLink: 'tor://vanilla',
          protocol: VpnProtocol.custom,
          host: 'tor',
          port: 9050,
          isDeletable: false,
          isPinned: true,
        ),
        VpnServer(
          id: TorSessionService.presetWebtunnelId,
          name: 'WebTunnel',
          flag: '\u{1F9C5}',
          shareLink: 'tor://webtunnel',
          protocol: VpnProtocol.custom,
          host: 'tor',
          port: 9050,
          isDeletable: false,
          isPinned: true,
        ),
      ];

  Widget _buildTorTile(VpnServer server) {
    final isWebtunnel = server.id == TorSessionService.presetWebtunnelId;
    final bridgeType = isWebtunnel ? 'webtunnel' : 'vanilla';
    final notifier = TorSessionService.instance.notifierFor(server.id);
    return ValueListenableBuilder<TorSessionState>(
      valueListenable: notifier,
      builder: (context, st, _) {
        final connected = st.routingThroughVpn;
        final busy = st.connecting ||
            (st.running && st.bootstrap < 100 && st.bootstrap > 0);
        return Container(
          margin: const EdgeInsets.only(bottom: 6),
          decoration: BoxDecoration(
            color: AppColors.surface(context),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: connected ? AppColors.accent : AppColors.border(context),
              width: connected ? 1.5 : 1,
            ),
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () async {
                if (_selectionMode) return;
                final already = st.routingThroughVpn || st.running;
                final wid = _pendingWidgetId;
                if (wid != null && wid > 0 && !already) {
                  try {
                    final prefs = await SharedPreferences.getInstance();
                    await prefs.setString(
                        'widget_server_$wid', 'tor|$bridgeType|Tor');
                  } catch (_) {}
                  await TorSessionService.instance.connect(server.id);
                  if (!mounted) return;
                  setState(() => _pendingWidgetId = null);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(_t(
                        'این تور برای ویجت انتخاب شد',
                        'Tor selected for widget',
                      )),
                      duration: const Duration(seconds: 2),
                    ),
                  );
                  return;
                }
                if (already) {
                  await TorSessionService.instance.disconnect();
                  return;
                }
                // اگه VPN سرور وصله، اول قطعش کن تا Tor تنها بمونه
                if (_connected) {
                  try {
                    await _disconnectAll();
                  } catch (_) {}
                  _markDisconnected(_t('آماده', 'Ready'));
                }
                await TorSessionService.instance.connect(server.id);
              },
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(server.flag,
                            style: const TextStyle(fontSize: 20)),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                server.name,
                                style: TextStyle(
                                  color: connected
                                      ? AppColors.accent
                                      : AppColors.fg(context),
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                connected
                                    ? 'SOCKS: ${st.socksPort}'
                                    : (busy
                                        ? '${st.bootstrap}% \u00B7 ${st.bootstrapMsg}'
                                        : (st.error ??
                                            _t('\u0622\u0645\u0627\u062F\u0647',
                                                'Ready'))),
                                style: TextStyle(
                                  color: st.error != null
                                      ? AppColors.danger
                                      : AppColors.muted2(context),
                                  fontSize: 10,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                        const Icon(Icons.push_pin,
                            size: 16, color: AppColors.accent),
                        const SizedBox(width: 4),
                        IconButton(
                          onPressed: () async {
                            final wid = _pendingWidgetId;
                            if (wid != null &&
                                wid > 0 &&
                                !connected &&
                                !st.running) {
                              try {
                                final prefs =
                                    await SharedPreferences.getInstance();
                                await prefs.setString(
                                    'widget_server_$wid',
                                    'tor|$bridgeType|Tor');
                              } catch (_) {}
                              await TorSessionService.instance
                                  .connect(server.id);
                              if (!mounted) return;
                              setState(() => _pendingWidgetId = null);
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(_t(
                                    'این تور برای ویجت انتخاب شد',
                                    'Tor selected for widget',
                                  )),
                                  duration: const Duration(seconds: 2),
                                ),
                              );
                              return;
                            }
                            if (connected || st.running) {
                              await TorSessionService.instance.disconnect();
                            } else {
                              if (_connected) {
                                try {
                                  await _disconnectAll();
                                } catch (_) {}
                                _markDisconnected(_t('آماده', 'Ready'));
                              }
                              await TorSessionService.instance
                                  .connect(server.id);
                            }
                          },
                          tooltip: connected
                              ? _t('\u0642\u0637\u0639', 'Disconnect')
                              : _t('\u0627\u062A\u0635\u0627\u0644',
                                  'Connect'),
                          icon: Icon(
                            connected
                                ? Icons.toggle_on
                                : (busy ? Icons.sync : Icons.toggle_off),
                            color: connected
                                ? AppColors.accent
                                : AppColors.muted(context),
                            size: 32,
                          ),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(
                              minWidth: 40, minHeight: 40),
                        ),
                      ],
                    ),
                    if (busy)
                      Padding(
                        padding: const EdgeInsets.only(
                            top: 6, left: 28, right: 8),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(2),
                          child: LinearProgressIndicator(
                            value: st.bootstrap > 0
                                ? st.bootstrap / 100
                                : null,
                            color: AppColors.accent,
                            backgroundColor: AppColors.border(context),
                            minHeight: 3,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  void _rebuildServerList() {
    if (!mounted) return;

    final allServers = <VpnServer>[
      ..._customServers.where((server) => !_deletedIds.contains(server.id)),
      ...widget.extraServers.where((server) => !_deletedIds.contains(server.id)),
    ];

    for (final server in allServers) {
      server.isPinned = _pinnedIds.contains(server.id);
    }

    var list = allServers;
    if (_selectedSubId != null && _selectedSubId!.startsWith('ugroup:')) {
      final gname = _selectedSubId!.substring('ugroup:'.length);
      final ids = (_userGroups[gname] ?? const <String>[]).toSet();
      list = list.where((s) => ids.contains(s.id)).toList();
    } else if (_selectedSubId != null) {
      final sub = widget.subscriptions.firstWhere(
        (s) => s.id == _selectedSubId,
        orElse: () => Subscription(id: '', name: '', url: ''),
      );
      if (sub.id.isNotEmpty) {
        final links = sub.cachedLinks.toSet();
        final customIds = _customServers.map((s) => s.id).toSet();
        list = list.where((s) {
          // سرورهای اشتراک → با shareLink
          if (links.contains(s.shareLink)) return true;
          // سرورهای custom → با tag به همین سابسکریپشن
          if (customIds.contains(s.id) && _customSubTags[s.id] == _selectedSubId) {
            return true;
          }
          return false;
        }).toList();
      }
    }

    final query = _searchQuery.trim().toLowerCase();
    if (query.isNotEmpty) {
      list = list.where((server) {
        return server.displayName.toLowerCase().contains(query) ||
            (server.isDeletable && server.host.toLowerCase().contains(query)) ||
            server.protocol.name.toLowerCase().contains(query);
      }).toList();
    }

    _servers = list;
    if (_manualOrder.isNotEmpty) {
      final pos = <String, int>{};
      for (var i = 0; i < _manualOrder.length; i++) {
        pos[_manualOrder[i]] = i;
      }
      _servers.sort((a, b) {
        if (a.isPinned != b.isPinned) return a.isPinned ? -1 : 1;
        final ai = pos[a.id] ?? 9999999;
        final bi = pos[b.id] ?? 9999999;
        return ai.compareTo(bi);
      });
    } else {
      _sortCurrentServers();
      final pinned = _servers.where((s) => s.isPinned).toList();
      final unpinned = _servers.where((s) => !s.isPinned).toList();
      _servers = <VpnServer>[...pinned, ...unpinned];
    }
    setState(() {});
  
    // The export cache feeds the quality / health screens — refresh
    // it whenever the list actually changes.
    unawaited(_refreshExportCache());
  }

  Future<void> _loadSmartResumePref() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!mounted) return;
      setState(() {
        _smartResumeEnabled = prefs.getBool('smart_resume_v1') ?? true;
      });
    } catch (_) {}
  }

  void _onNetworkReconnected() {
    if (!mounted) return;
    // Smart Resume: اگه کاربر قبلاً خودش دستی قطع کرده، وصل نشو
    if (_manualDisconnect) {
      debugPrint('NetworkReconnected ignored: user manually disconnected');
      return;
    }
    if (!_smartResumeEnabled) {
      debugPrint('NetworkReconnected ignored: Smart Resume disabled');
      return;
    }
    // اگه کاربر اتصال نداشت، auto-reconnect نکن
    if (!_connected && !_connecting) {
      debugPrint('NetworkReconnected ignored: was not connected');
      return;
    }
    if (_autoReconnectRunning) return;
    // FIX: اگر ۶۰ ثانیه از زمان اتصال نگذشته، احتمالاً این تغییر شبکه
    // خودِ VPN interface ماست، نه شبکه‌ی واقعی. auto-reconnect نزن.
    if (_lastConnectTime != null &&
        DateTime.now().difference(_lastConnectTime!).inSeconds < 60) {
      debugPrint('NetworkReconnected ignored: within 60s of last connect');
      return;
    }
    _autoReconnectRunning = true;
    // ignore: unawaited_futures
    _autoReconnect().whenComplete(() => _autoReconnectRunning = false);
  }

  Future<void> _autoReconnect() async {
    try {
      // اول قطع کامل
      await _disconnectAll();
    } catch (_) {}
    if (!mounted) return;
    await Future.delayed(const Duration(milliseconds: 600));
    if (!mounted) return;
    try {
      await _toggleConnection();
    } catch (_) {}
  }

  Future<void> _startAutoTestTimer() async {
    // Manual-only by design. The periodic auto test has been removed
    // because it was the single biggest contributor to heat and battery
    // drain and because the user asked for manual runs only.
    _autoTestTimer?.cancel();
    _autoTestTimer = null;
  }

  Future<void> _runAutoTestAll() async {
    if (!mounted) return;
    if (_testing) return;
    try {
      await _testAll();
    } catch (_) {}
  }

  void _startAutoFastestInterval() {
    _autoFastestTimer?.cancel();
    _autoFastestTimer = Timer.periodic(
      const Duration(minutes: 30),
      (_) => _autoFastestTick(),
    );
  }

  Future<void> _autoFastestTick() async {
    try {
      final enabled = await SettingsService.getConnectFastest();
      if (!enabled) return;
      if (!mounted) return;
      // FIX: اگه Tor/Tunnel/SSH دارن ترافیک رو روت می‌کنن، سرور خودکار
      // وصل نکن — وگرنه Tor و سرور همزمان فعال می‌شن.
      if (TorSessionService.instance.anyRouting ||
          TunnelSessionService.instance.anyRouting ||
          SshSessionService.instance.anyRouting) {
        return;
      }
      final fastest = ServerTester.fastest(_servers);
      if (fastest == null) return;
      final same = _active?.id == fastest.id || _selected?.id == fastest.id;
      if (same) return;
      if (mounted) {
        setState(() {
          _selected = fastest;
        });
      }
      // اگه متصل بودیم، با سرور جدید دوباره وصل شو
      if (_connected && !_connecting) {
        await _autoReconnect();
      }
    } catch (_) {}
  }

  /// callback زنده‌ی اسکن MASQUE — status رو از داخل دیالوگ آپدیت می‌کنه.
  void _onMasqueScanProgress() {
    if (!mounted) return;
    // فقط وقتی در حال اتصال هستیم
    if (!_connecting) return;
    final s = WarpMasqueService.scanProgress.value;
    if (s.phase.isEmpty) return;
    final detail = s.endpoint.isNotEmpty
        ? '${s.phase} · ${s.endpoint}${s.ms > 0 ? " · ${s.ms}ms" : ""}'
        : s.phase;
    if (detail == _status) return;
    setState(() => _status = detail);
  }

  /// شروع مانیتور برای سرور متصل فعلی.
  Future<void> _startHealthMonitorFor(VpnServer server) async {
    try {
      String? pkB64;
      String? peerB64;
      // استخراج کلید از shareLink برای WARP/WARP+
      if (server.protocol == VpnProtocol.amneziaWg) {
        final fields = _extractWgKeysFromVpn(server.shareLink);
        pkB64 = fields?.privateKey;
        peerB64 = fields?.publicKey;
      } else if (server.protocol == VpnProtocol.chain) {
        final uri = Uri.parse(server.shareLink);
        final inner = uri.queryParameters['second'] ?? '';
        if (inner.isNotEmpty) {
          final fields = _extractWgKeysFromVpn(inner);
          pkB64 = fields?.privateKey;
          peerB64 = fields?.publicKey;
        }
      }
      // endpoint فعلی از host:port
      final endpoint = '${server.host}:${server.port}';
      WarpEndpointHealthMonitor.instance.start(
        serverId: server.id,
        endpoint: endpoint,
        privateKeyB64: pkB64,
        peerPublicKeyB64: peerB64,
      );
    } catch (_) {}
  }

  /// استخراج کلیدها از یه vpn:// link.
  ({String privateKey, String publicKey})? _extractWgKeysFromVpn(
      String link) {
    try {
      if (!link.startsWith('vpn://')) return null;
      final b64 = link.substring('vpn://'.length).trim();
      final raw = utf8.decode(
        base64.decode(base64.normalize(b64)),
        allowMalformed: true,
      );
      final outer = jsonDecode(raw);
      if (outer is! Map) return null;
      Map? awg;
      final containers = outer['containers'];
      if (containers is List) {
        for (final c in containers) {
          if (c is Map && c['awg'] is Map) {
            awg = Map<String, dynamic>.from(c['awg'] as Map);
            break;
          }
        }
      }
      if (awg == null) return null;
      final lastCfg = (awg['last_config'] ?? '').toString();
      if (lastCfg.isEmpty) return null;
      final inner = jsonDecode(lastCfg);
      if (inner is! Map) return null;
      final iface = inner['interface'];
      final peer = inner['peer'];
      if (iface is! Map || peer is! Map) return null;
      final priv =
          (iface['private_key'] ?? iface['privateKey'] ?? '').toString();
      final pub =
          (peer['public_key'] ?? peer['publicKey'] ?? '').toString();
      if (priv.isEmpty || pub.isEmpty) return null;
      return (privateKey: priv, publicKey: pub);
    } catch (_) {
      return null;
    }
  }

  /// شروع refresh دوره‌ای ویجت (هر ۳۰ ثانیه).
  void _startWidgetTimerRefresh() {
    _widgetTimerRefresh?.cancel();
    _widgetTimerRefresh = Timer.periodic(
      const Duration(seconds: 30),
      (_) {
        if (!mounted || !_connected) return;
        // ignore: unawaited_futures
        HomeWidgetService.setConnectedStart(
          _lastConnectTime ?? DateTime.now(),
        );
      },
    );
  }

  void _stopWidgetTimerRefresh() {
    _widgetTimerRefresh?.cancel();
    _widgetTimerRefresh = null;
  }

  /// callback کیفیت پایین — هشدار + لرزش کوتاه.
  void _onLowQuality(int score) {
    if (!mounted) return;
    // لرزش کوتاه (فقط اگه اپ در foreground باشه)
    try {
      HapticFeedback.mediumImpact();
      // الگوی دو-ضربه‌ای برای هشدار واضح‌تر
      Future.delayed(const Duration(milliseconds: 180), () {
        try {
          HapticFeedback.lightImpact();
        } catch (_) {}
      });
    } catch (_) {}
    _showMsg(_t(
      'کیفیت اتصال افت کرد (امتیاز ' + score.toString() + ') — endpoint رو تغییر بده',
      'Connection quality dropped (score ' + score.toString() + ') — change endpoint',
    ));
  }

  void _onQualityRecovered() {
    if (!mounted) return;
    // لرزش کوتاه برای بازیابی
    try {
      HapticFeedback.lightImpact();
    } catch (_) {}
    _showMsg(_t('کیفیت اتصال برگشت', 'Quality recovered'));
  }

  /// callback از WARP Scout Scheduler — rescan سرور هدف.
  Future<void> _onSchedulerRescan(VpnServer server, {bool force = false}) async {
    try {
      debugPrint('scheduler: rescan ' + server.name + ' force=' + force.toString());
      if (server.protocol == VpnProtocol.warpMasque) {
        if (!force) {
          final alive = await WarpEndpointHealthMonitor.quickCheck(
            server.host + ':' + server.port.toString(),
          );
          if (alive) return;
        }
        await _rescanMasqueServer(server);
      } else {
        if (!force) {
          final alive = await WarpEndpointHealthMonitor.quickCheck(
            server.host + ':' + server.port.toString(),
          );
          if (alive) return;
        }
        await _rescanWarpServer(server);
      }
    } catch (e) {
      debugPrint('scheduler rescan error: ' + e.toString());
    }
  }

  /// health monitor: endpoint فعلی خراب شد → failover به یه endpoint دیگه.
  void _onWarpEndpointDegraded(String serverId) {
    if (!mounted) return;
    if (!_autoFailoverEnabled) return;
    if (_autoFailoverRunning) return;
    if (!_connected) return;
    final active = _active;
    if (active == null || active.id != serverId) return;
    _autoFailoverRunning = true;
    _showMsg(_t(
      'endpoint فعلی ضعیف شده — تلاش برای پیدا کردن جایگزین...',
      'Current endpoint degraded — searching for a replacement...',
    ));
    // ignore: unawaited_futures
    _performAutoFailover(active).whenComplete(
      () => _autoFailoverRunning = false,
    );
  }

  void _onWarpEndpointRecovered(String serverId) {
    if (!mounted) return;
    final active = _active;
    if (active == null || active.id != serverId) return;
    _showMsg(_t('endpoint دوباره سالم شد', 'Endpoint recovered'));
  }

  /// پیدا کردن endpoint جدید برای سرور فعلی و جایگزینی.
  Future<void> _performAutoFailover(VpnServer server) async {
    try {
      // برای MASQUE از _rescanMasqueServer، برای WARP/WARP+ از _rescanWarpServer
      final isMasque = server.protocol == VpnProtocol.warpMasque;
      if (isMasque) {
        await _rescanMasqueServer(server);
      } else {
        await _rescanWarpServer(server);
      }
    } catch (_) {}
  }

  void _onWarpMasqueRoutingChanged() {
    if (!mounted) return;
    if (WarpMasqueSessionService.instance.anyRouting && _connected) {
      setState(() {
        _connected = false;
        _active = null;
        _status = _t('اتصال از طریق WARP MASQUE', 'Routing via WARP MASQUE');
      });
    }
  }

  void _onMasterDnsRoutingChanged() {
    if (!mounted) return;
    if (MasterDnsSessionService.instance.anyRouting && _connected) {
      setState(() {
        _connected = false;
        _active = null;
        _status = _t('اتصال از طریق MasterDNS', 'Routing via MasterDNS');
      });
    }
  }

  void _onSshRoutingChanged() {
    if (!mounted) return;
    if (SshSessionService.instance.anyRouting && _connected) {
      setState(() {
        _connected = false;
        _active = null;
        _status = _t('اتصال از طریق SSH', 'Routing via SSH');
      });
    }
  }

  void _onTunnelRoutingChanged() {
    if (!mounted) return;
    if (TunnelSessionService.instance.anyRouting && _connected) {
      setState(() {
        _connected = false;
        _active = null;
        _status = _t('اتصال از طریق تونل DNS', 'Routing via DNS tunnel');
      });
    }
  }

  void _onTorRoutingChanged() {
    if (!mounted) return;
    if (TorSessionService.instance.anyRouting && _connected) {
      // Tor داره روت می‌کنه → سرور باید کاملاً قطع نمایش داده بشه
      setState(() {
        _connected = false;
        _active = null;
        _status = _t('اتصال از طریق Tor', 'Routing via Tor');
      });
    }
  }

  Future<void> _requestFirstLaunchPermissions() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final asked = prefs.getBool('first_launch_perm_v1') ?? false;
      if (asked) return;

      // 1) مجوز اعلان
      try {
        const ch = MethodChannel('com.hasan.hasan_vpn/device');
        await ch.invokeMethod('notifPermission');
      } catch (_) {}

      // 2) مجوز VPN — با یه warm-up کوتاه که دیالوگ سیستم رو باز می‌کنه
      try {
        await V2RayEngine.init();
        // اتصال کوتاه به یه freedom config فقط برای باز شدن دیالوگ
        final warmup = VpnServer(
          id: 'perm_warmup',
          name: 'Warmup',
          flag: '⚡',
          shareLink: 'xrayjson://warmup',
          protocol: VpnProtocol.xrayJson,
          host: '127.0.0.1',
          port: 1,
          isDeletable: false,
        );
        const cfg =
            '{"inbounds":[{"tag":"s","port":10810,"listen":"127.0.0.1",'
            '"protocol":"socks","settings":{"auth":"noauth"}}],'
            '"outbounds":[{"tag":"direct","protocol":"freedom"}]}';
        // ignore: unawaited_futures
        V2RayEngine.startConfig(
          remark: 'Warmup',
          config: cfg,
          server: warmup,
        ).then((_) async {
          // بلافاصله قطع کن
          try {
            await Future.delayed(const Duration(milliseconds: 800));
            await V2RayEngine.disconnect();
          } catch (_) {}
        });
      } catch (_) {}

      await prefs.setBool('first_launch_perm_v1', true);
    } catch (_) {}
  }

  Future<void> _autoDownloadGeoIran() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final done = prefs.getBool('geo_iran_downloaded_v1') ?? false;
      if (done) return;
      // 1. geoip + geosite از chocolate4u-iran
      try {
        await GeoAssetsService.downloadFromSource('chocolate4u-iran');
      } catch (_) {}
      // 2. FIX: geoip-only-cn-private.dat (قبلاً فقط دستی دانلود می‌شد)
      try {
        final cnEntry = GeoAssetsService.catalog.firstWhere(
          (e) => e['id'] == 'geoip-cn-private',
          orElse: () => const <String, String>{},
        );
        final cnUrl = cnEntry['url'];
        if (cnUrl != null && cnUrl.isNotEmpty) {
          await GeoAssetsService.download(
              'geoip-only-cn-private.dat', cnUrl);
        }
      } catch (_) {}
      await prefs.setBool('geo_iran_downloaded_v1', true);
    } catch (_) {}
  }


  void _selectSubscription(String? subId) {
    setState(() => _selectedSubId = subId);
    _rebuildServerList();
  }

  void _togglePin(VpnServer server) {
    if (_pinnedIds.contains(server.id)) {
      _pinnedIds.remove(server.id);
    } else {
      _pinnedIds.add(server.id);
    }
    _rebuildServerList();
    _savePinned();
  }

  /// ذخیره binding برای ویجت مشخص
  Future<void> _bindServerToWidget(int widgetId, VpnServer server) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = 'server|${server.shareLink}|${server.displayName}';
      await prefs.setString('widget_server_$widgetId', raw);
    } catch (_) {}
  }

  /// وقتی از ویجت با widget_needs_server اومده‌ایم: روی اولین سرور که کلیک شه bind کن
  Future<void> _handleWidgetServerSelection(VpnServer server) async {
    final wid = _pendingWidgetId;
    if (wid == null) return;
    await _bindServerToWidget(wid, server);
    if (!mounted) return;
    setState(() {
      _selected = server;
      _pendingWidgetId = null;
    });
    await SettingsService.setLastServer(server.id);
    // برچسب ویجت را فوراً به‌روز کن تا منتظر onUpdate بعدی سیستم نمانیم
    try {
      const ch = MethodChannel('com.hasan.hasan_vpn/widget');
      await ch.invokeMethod('updateWidgets');
    } catch (_) {}
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(_t(
          'ویجت به "${server.displayName}" وصل شد — از این به بعد بدون باز کردن اپ وصل می‌شه',
          'Widget bound to "${server.displayName}" — future taps connect silently',
        )),
        duration: const Duration(seconds: 3),
      ),
    );
    // اتصال خودکار
    try {
      await _toggleConnection();
    } catch (_) {}
    // به پس‌زمینه برو
    try {
      const ch = MethodChannel('com.hasan.hasan_vpn/widget');
      await ch.invokeMethod('moveTaskToBack');
    } catch (_) {}
  }

  Future<void> _pinServerToHome(VpnServer server) async {
    await HomeWidgetService.pin(
      type: 'server',
      title: server.displayName,
      subtitle: server.host.isNotEmpty ? server.host : server.protocol.name,
      payload: server.id,
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(_t(
          'به ویجت صفحهٔ اصلی اضافه شد — ویجت Hasan را از صفحهٔ اصلی اضافه کنید',
          'Pinned to home widget — add Hasan widget from home screen',
        )),
      ),
    );
  }

  void _sortCurrentServers() {
    ServerTester.sortServers(_servers, descending: !_sortAscending);
  }

  void _cancelTesting() {
    if (!mounted) return;
    _session?.cancel();
    setState(() {
      _testing = false;
      _status = _t('تست لغو شد', 'Test cancelled');
      for (final server in _servers) {
        if (server.status == ServerStatus.testing) {
          server.status =
              server.ping != null ? ServerStatus.online : ServerStatus.idle;
        }
      }
    });
    _savePings();
  }

  /// اگه کاربر auto-batch رو فعال کرده، بعد از ۵ ثانیه اجرا کن.
  Future<void> _maybeAutoBatchOnStart() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final enabled = prefs.getBool('batch_auto_v1') ?? false;
      if (!enabled) return;
      // تأخیر تا UI کامپایل بشه
      await Future<void>.delayed(const Duration(seconds: 5));
      if (!mounted) return;
      if (_batchRunning) return;
      // ignore: unawaited_futures
      _runWarpBatchTest();
    } catch (_) {}
  }

  /// تست دسته‌ای چند سرور WARP/WARP+/MASQUE به‌صورت موازی.
  ///
  /// هر سرور رو با یه endpoint rescan تست می‌کنه. بهترین endpoint
  /// برای هر سرور ذخیره می‌شه.
  Future<void> _runWarpBatchTest() async {
    if (_batchRunning) {
      _showMsg(_t('تست دسته‌ای در حال اجراست', 'Batch test already running'));
      return;
    }

    final warpServers = _servers
        .where((s) =>
            (s.protocol == VpnProtocol.amneziaWg ||
                s.protocol == VpnProtocol.chain ||
                s.protocol == VpnProtocol.warpMasque) &&
            s.isDeletable)
        .toList();

    if (warpServers.isEmpty) {
      _showMsg(_t('هیچ سرور WARP/WARP+/MASQUE قابل تست نیست',
          'No testable WARP/WARP+/MASQUE server'));
      return;
    }

    if (_connected) {
      try { await _disconnectAll(); } catch (_) {}
      _markDisconnected(_t('آماده', 'Ready'));
    }

    _batchRunning = true;

    // نمایش دیالوگ زنده
    // ignore: unawaited_futures
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface(ctx),
        title: Text(
          _t('تست دسته‌ای WARP', 'WARP batch test'),
          style: TextStyle(color: AppColors.fg(ctx), fontSize: 15),
        ),
        content: SizedBox(
          width: double.maxFinite,
          height: 350,
          child: ValueListenableBuilder<WarpBatchState>(
            valueListenable: _batchTester.state,
            builder: (_, state, __) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  LinearProgressIndicator(
                    value: state.total > 0 ? state.progress : null,
                    color: AppColors.accent,
                    backgroundColor: AppColors.border(ctx),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${state.tested} / ${state.total}',
                    style: TextStyle(
                        color: AppColors.muted(ctx), fontSize: 12),
                  ),
                  if (state.currentServer.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        state.currentServer,
                        style: TextStyle(
                            color: AppColors.fg(ctx), fontSize: 11),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  const SizedBox(height: 10),
                  Expanded(
                    child: state.results.isEmpty
                        ? Center(
                            child: Text(
                              _t('شروع...', 'Starting...'),
                              style: TextStyle(
                                  color: AppColors.muted2(ctx),
                                  fontSize: 11),
                            ),
                          )
                        : ListView.builder(
                            itemCount: state.results.length,
                            itemBuilder: (_, i) {
                              final r = state.results[i];
                              return ListTile(
                                dense: true,
                                title: Text(
                                  r.server.displayName,
                                  style: TextStyle(
                                      color: AppColors.fg(ctx),
                                      fontSize: 11),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                subtitle: Text(
                                  r.ok
                                      ? r.bestEndpoint!
                                      : (r.error ?? 'unknown'),
                                  style: TextStyle(
                                    color: r.ok
                                        ? AppColors.muted2(ctx)
                                        : AppColors.danger,
                                    fontSize: 9.5,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                trailing: Text(
                                  r.ok ? '${r.latencyMs}ms' : '✕',
                                  style: TextStyle(
                                    color: r.ok
                                        ? AppColors.accent
                                        : AppColors.danger,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              );
                            },
                          ),
                  ),
                ],
              );
            },
          ),
        ),
        actions: [
          ValueListenableBuilder<WarpBatchState>(
            valueListenable: _batchTester.state,
            builder: (_, state, __) => TextButton(
              onPressed: state.running
                  ? () {
                      _batchTester.cancel();
                      Navigator.pop(ctx);
                    }
                  : () => Navigator.pop(ctx),
              child: Text(
                state.running
                    ? _t('لغو', 'Cancel')
                    : _t('بستن', 'Close'),
                style: TextStyle(
                    color: state.running
                        ? AppColors.danger
                        : AppColors.accent),
              ),
            ),
          ),
        ],
      ),
    );

    try {
      final results = await _batchTester.run(
        servers: warpServers,
        rescan: (server) async {
          if (server.protocol == VpnProtocol.warpMasque) {
            return await WarpMasqueService.rescanEndpoints(
              endpoint: server.host + ':' + server.port.toString(),
              endpointCandidates: server.warpMasqueEndpointCandidates,
              timeoutSec: 90,
            );
          }
          return await WarpService.rescanEndpoints(server);
        },
      );

      if (!mounted) return;
      if (Navigator.of(context, rootNavigator: true).canPop()) {
        Navigator.of(context, rootNavigator: true).pop();
      }

      // آپدیت endpoint برنده روی هر سرور
      var updated = 0;
      for (final r in results) {
        if (!r.ok) continue;
        final ep = r.bestEndpoint!;
        final parts = ep.split(':');
        if (parts.length < 2) continue;
        final newHost = parts[0];
        final newPort = int.tryParse(parts[1]) ?? r.server.port;
        final upd = r.server.copyWith(host: newHost, port: newPort);
        setState(() {
          final idx = _customServers.indexWhere((s) => s.id == r.server.id);
          if (idx >= 0) _customServers[idx] = upd;
          final si = _servers.indexWhere((s) => s.id == r.server.id);
          if (si >= 0) _servers[si] = upd;
        });
        updated++;
      }
      // ignore: unawaited_futures
      _saveCustomServers();

      _showMsg(_t(
        'تست دسته‌ای تمام شد — $updated endpoint ذخیره شد',
        'Batch test done — $updated endpoints saved',
      ));
    } catch (e) {
      if (!mounted) return;
      if (Navigator.of(context, rootNavigator: true).canPop()) {
        Navigator.of(context, rootNavigator: true).pop();
      }
      _showMsg(_t('خطا: $e', 'Error: $e'));
    } finally {
      _batchRunning = false;
    }
  }

  Future<void> _testAll() async {
    if (_testing || _servers.isEmpty) return;
    final targets = _servers.where((s) => !s.isAether).toList();
    if (targets.isEmpty) {
      _showMsg(_t('سروری برای تست نیست', 'Nothing to test'));
      return;
    }
    if (_connected && _active?.isAether != true) {
      _showMsg(_t(
        'الان وصل هستی؛ پینگ‌ها از داخل تونل فعلی اندازه‌گیری می‌شوند.',
        'You are connected; pings are measured through the current tunnel.',
      ));
    }

    final session = TestSession();
    _session = session;

    setState(() {
      _testing = true;
      _tested = 0;
      _total = targets.length;
      _status = _t('در حال تست واقعی...', 'Real testing...');
      for (final server in targets) {
        server.resetPing();
      }
    });

    final summary = await ServerTester.testAll(
      targets,
      session: session,
      onServerDone: (_) {
        if (!mounted || session.cancelled) return;
        setState(() => _tested++);
      },
      onChanged: () {
        if (!mounted || session.cancelled) return;
        _sortCurrentServers();
        setState(() => _servers = List<VpnServer>.from(_servers));
      },
    );

    if (!mounted || session.cancelled) return;
    _sortCurrentServers();
    await _savePings();
    // FIX: sort state رو هم ذخیره کن که بعد از ریستارت بمونه
    await _saveSortPreference();
    // FIX: ترتیب جدید رو به‌عنوان manualOrder هم ذخیره کن — تا اگه
    // لیست از نو ساخته شد، همون ترتیب برگرده.
    _manualOrder = _servers.map((s) => s.id).toList();
    await _saveManualOrder();

    setState(() {
      _servers = List<VpnServer>.from(_servers);
      _testing = false;
      final fastest = ServerTester.fastest(_servers);
      final counts = '${summary.online}/${summary.total}';
      if (fastest != null && !_connected) {
        _selected = fastest;
        _status = _t('بهترین سرور انتخاب شد ($counts آنلاین)',
            'Best server ($counts online)');
      } else {
        _status = _t(
            'تست تمام شد ($counts آنلاین)', 'Test finished ($counts online)');
      }

      if (summary.realUnavailable) {
        _status += _t(
          ' · پینگ واقعی پشتیبانی نشد',
          ' · real ping unsupported',
        );
      }
    });
    // ignore: unawaited_futures
    AnnouncementService.onTestFinished(
      online: summary.online,
      total: summary.total,
    );
  }

  Future<void> _testOne(VpnServer server) async {
    if (server.status == ServerStatus.testing) return;
    if (server.isAether) {
      if (_connected && _active?.id == server.id) {
        await _measureLive(force: true);
        _showMsg(_livePing != null
            ? _t('پینگ زنده: $_livePing ms', 'Live ping: $_livePing ms')
            : _t('پاسخی نیامد', 'No response'));
      } else {
        _showMsg(_t('Aether آدرس ثابت ندارد؛ اول وصل شو',
            'Aether has no fixed address; connect first'));
      }
      return;
    }

    setState(() => server.status = ServerStatus.testing);
    final session = TestSession();
    await ServerTester.testOne(
      server,
      session: session,
      onChanged: () {
        if (mounted) setState(() {});
      },
    );
    if (!mounted) return;
    await _savePings();
    setState(() {});
  }

  Future<void> _deleteServer(VpnServer server) async {
    final s = await XraySettings.load();
    if (s['confirmDelete'] != false) {
      if (!mounted) return;
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: AppColors.surface(ctx),
          title: Text(_t('حذف سرور؟', 'Delete server?'),
              style: TextStyle(color: AppColors.fg(ctx))),
          content: Text(server.displayName,
              style: TextStyle(color: AppColors.fg(ctx), fontSize: 13)),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(_t('انصراف', 'Cancel')),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(_t('حذف', 'Delete'),
                  style: const TextStyle(color: Colors.redAccent)),
            ),
          ],
        ),
      );
      if (ok != true) return;
    }
    // ذخیره snapshot برای undo
    final removedServer = server;
    final originalIndex =
        _customServers.indexWhere((item) => item.id == server.id);
    final originalTag = _customSubTags[server.id];

    _deletedIds.add(server.id);
    _customServers.removeWhere((item) => item.id == server.id);
    _customSubTags.remove(server.id);
    _saveCustomSubTags();
    if (_selected?.id == server.id) _selected = null;
    // ignore: unawaited_futures
    _cleanupOrphanGroupIds();
    _rebuildServerList();
    _saveDeleted();
    _saveCustomServers();
    _savePings();

    // Snackbar با دکمه Undo
    if (!mounted) return;
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(_t(
          'سرور حذف شد: ${server.displayName}',
          'Deleted: ${server.displayName}',
        )),
        duration: const Duration(seconds: 5),
        action: SnackBarAction(
          label: _t('بازگردانی', 'Undo'),
          textColor: AppColors.accent,
          onPressed: () async {
            if (!mounted) return;
            _deletedIds.remove(server.id);
            // بازگردانی در جای اصلی
            if (originalIndex >= 0 &&
                originalIndex <= _customServers.length) {
              _customServers.insert(originalIndex, removedServer);
            } else {
              _customServers.insert(0, removedServer);
            }
            if (originalTag != null) {
              _customSubTags[server.id] = originalTag;
            }
            _saveCustomSubTags();
            _rebuildServerList();
            _saveDeleted();
            _saveCustomServers();
            // ignore: unawaited_futures
            _savePings();
            if (!mounted) return;
            setState(() {});
            _showMsg(_t('سرور بازگردانی شد', 'Server restored'));
          },
        ),
      ),
    );
  }
  void _deleteDuplicates() {
    final seen = <String>{};
    final toDelete = <VpnServer>[];
    for (final s in _servers) {
      final key = s.shareLink.trim();
      if (seen.contains(key)) {
        toDelete.add(s);
      } else {
        seen.add(key);
      }
    }
    if (toDelete.isEmpty) {
      _showMsg(_t('تکراری‌ای نیست', 'No duplicates'));
      return;
    }
    for (final s in toDelete) {
      _deletedIds.add(s.id);
      _customServers.removeWhere((item) => item.id == s.id);
    }
    if (_selected != null && _deletedIds.contains(_selected!.id)) {
      _selected = null;
    }
    // ignore: unawaited_futures
    _cleanupOrphanGroupIds();
    _rebuildServerList();
    _saveDeleted();
    _saveCustomServers();
    _savePings();
    _showMsg(_t('${toDelete.length} تکراری حذف شد',
        '${toDelete.length} duplicates deleted'));
  }

  void _deleteInvalid() {
    final toDelete = _servers
        .where((s) =>
            !s.isAether && s.ping == null && s.status == ServerStatus.offline)
        .toList();
    if (toDelete.isEmpty) {
      _showMsg(_t('سرور آفلاینی نیست', 'No offline servers'));
      return;
    }
    for (final server in toDelete) {
      _deletedIds.add(server.id);
      _customServers.removeWhere((item) => item.id == server.id);
    }
    if (_selected != null && _deletedIds.contains(_selected!.id)) {
      _selected = null;
    }
    // ignore: unawaited_futures
    _cleanupOrphanGroupIds();
    _rebuildServerList();
    _saveDeleted();
    _saveCustomServers();
    _showMsg(
        _t('${toDelete.length} سرور حذف شد', '${toDelete.length} servers deleted'));
  }

  /// FIX: قبل از هر اتصال جدید، همه‌ی session های فعلی رو ببند.
  /// این تضمین می‌کنه که هیچ‌وقت دو تونل همزمان فعال نباشن —
  /// مثلاً کاربر وسط Tor هست، روی یه vless می‌زنه: Tor باید بمیره.
  /// Tear down every other session before starting a new one so no two
  /// tunnels are ever active at once (Tor -> VLESS -> Aether, etc.).
  ///
  /// No timeout wrapper here. `Future.timeout()` does NOT cancel the
  /// underlying future in Dart — it only makes the caller stop waiting.
  /// The original teardown keeps running in the background and fires its
  /// native cleanup several seconds later, exactly when the new tunnel is
  /// coming up. That closes sockets or destroys the fresh TUN while the
  /// status bar still shows a VPN icon, which is why every server looked
  /// "connected" but carried nothing.
  ///
  /// The strict sequencing is worth the occasional longer wait: a tunnel
  /// that actually works beats a tunnel that returns fast but is dead.
  Future<void> _disconnectAllSessionsForNewConnect() async {
    try {
      if (TorSessionService.instance.anyRouting) {
        await TorSessionService.instance.disconnect();
      }
    } catch (_) {}
    try {
      if (TunnelSessionService.instance.anyRouting) {
        await TunnelSessionService.instance.disconnect();
      }
    } catch (_) {}
    try {
      if (SshSessionService.instance.anyRouting) {
        await SshSessionService.instance.disconnect();
      }
    } catch (_) {}
    try {
      if (MasterDnsSessionService.instance.anyRouting) {
        await MasterDnsSessionService.instance.disconnect();
      }
    } catch (_) {}
    try {
      if (WarpMasqueSessionService.instance.anyRouting) {
        await WarpMasqueSessionService.instance.disconnect();
      }
    } catch (_) {}
    try {
      if (DesyncService.isRunning) {
        await DesyncService.stop();
      }
    } catch (_) {}
    try {
      await AetherService.disconnect();
    } catch (_) {}
    try {
      await PsiphonService.stop();
    } catch (_) {}
    try {
      if (V2RayEngine.isConnected) {
        await V2RayEngine.disconnect();
      }
    } catch (_) {}
    if (mounted) {
      setState(() {
        _connected = false;
        _active = null;
        _livePing = null;
      });
    }
  }

  Future<void> _disconnectAll() async {
    try {
      await AetherService.disconnect();
    } catch (_) {}
    try {
      await PsiphonService.stop();
    } catch (_) {}
    try {
      await V2RayEngine.disconnect();
    } catch (_) {}
  }

  void _markDisconnected(String status) {
    // The persisted id only matters while a tunnel is up. Clearing it
    // stops the resume hook from resurrecting a session the user ended.
    // ignore: unawaited_futures
    SharedPreferences.getInstance()
        .then((p) => p.remove('last_active_server_id_v1'))
        .catchError((_) {});
    // ignore: unawaited_futures
    ConnectionLogService.logError('TRACE',
        'UI._markDisconnected status="$status" active=\${_active?.id} connected=\$_connected');
    if (_active != null) {
      // ignore: unawaited_futures
      ConnectionLogService.logDisconnect(_active!.displayName);
    }
    final wasConnected = _connected;
    _active = null;
    _livePing = null;
    _deadStrikes = 0;
    _pollTick = 0;
    // توقف health monitor
    try {
      WarpEndpointHealthMonitor.instance.stop();
    } catch (_) {}
    // پاک کردن quality widget + timer + flag
    _stopWidgetTimerRefresh();
    // ignore: unawaited_futures
    HomeWidgetService.clearQuality();
    // ignore: unawaited_futures
    HomeWidgetService.clearConnectedStart();
    // ignore: unawaited_futures
    HomeWidgetService.setCountryFlag('');
    _autoFailoverEnabled = false;
    if (!mounted) return;
    setState(() {
      _connected = false;
      _connecting = false;
      _status = status;
    });
    if (wasConnected) {
      // ignore: unawaited_futures
      AnnouncementService.onDisconnected();
    }
  }

  Future<void> _poll() async {
    if (!mounted || _connecting || _polling || !_connected) return;
    _polling = true;
    try {
      final active = _active;
      // Utility sessions (Aether / Psiphon / Tor / SSH / Tunnel) do not
      // have the same V2Ray "is alive" semantics, so skip the dead-strike
      // logic — but still take a quality sample so the history screen and
      // the notification badge are not empty while they run.
      if (TorSessionService.instance.anyRouting ||
          TunnelSessionService.instance.anyRouting ||
          SshSessionService.instance.anyRouting ||
          V2RayEngine.isUtilitySession) {
        _pollTick++;
        if (_pollTick % 3 == 1) {
          try {
            await _measureLive();
          } catch (_) {}
        }
        return;
      }
      var alive = V2RayEngine.isConnected;
      if (alive && active?.isAether == true) {
        alive = await AetherService.syncStatus();
      }
      // FIX2: before declaring the tunnel dead, verify with a real probe.
      // flutter_vless can transiently report 'idle'/'disconnecting' while
      // the tunnel is actually working. A real SOCKS probe avoids
      // disconnecting a healthy connection.
      if (!alive) {
        try {
          final probe = await V2RayEngine.probeConnected();
          if (probe.ok) {
            alive = true;
          }
        } catch (_) {}
      }
      if (!alive) {
        _deadStrikes++;
        // FIX2: raised from 2 (8s) to 5 (20s) so transient flutters
        // don't kill a working tunnel.
        if (_deadStrikes >= 5) {
          // ignore: unawaited_futures
          ConnectionLogService.logError('TRACE',
              'UI._poll dead-strikes hit threshold (5) — killing tunnel');
          try {
            await _disconnectAll();
          } catch (_) {}
          _markDisconnected(_t('اتصال قطع شد', 'Connection lost'));
        }
        return;
      }
      _deadStrikes = 0;
      _pollTick++;
      // Every 6th poll = ~72 s between live probes. Every 3rd was 36 s
      // and dominated battery use; the notification only needs to feel
      // alive, not be truthful to the second.
      if (_pollTick % 6 == 1) await _measureLive();
    } finally {
      _polling = false;
    }
  }

  Future<void> _refreshExitIp({bool force = false}) async {
    if (!_connected) return;
    try {
      final info = await ExitIpService.fetch(
        socksPort: V2RayEngine.localSocksPort,
      );
      if (!mounted || !_connected) return;
      if (info == null) return;

      // آپدیت flag + نام سرور بر اساس کشور خروجی
      final active = _active;
      if (active != null && info.country != null &&
          info.country!.isNotEmpty) {
        final newFlag = GeoFlag.fromName(info.country);
        final farsi = GeoFlag.farsiName(info.country);
        // ست کردن flag در ویجت
        if (newFlag != '🌐') {
          // ignore: unawaited_futures
          HomeWidgetService.setCountryFlag(newFlag);
        }
        // flag فقط اگه تغییر کرده
        if (newFlag != '🌐' && active.flag != newFlag) {
          final updated = active.copyWith(flag: newFlag);
          setState(() {
            if (_active?.id == active.id) _active = updated;
            final si = _servers.indexWhere((s) => s.id == active.id);
            if (si >= 0) _servers[si] = updated;
            final ci = _customServers.indexWhere((s) => s.id == active.id);
            if (ci >= 0) _customServers[ci] = updated;
            if (_selected?.id == active.id) _selected = updated;
          });
          // ignore: unawaited_futures
          _saveCustomServers();
        }
        // ذخیره country در prefs برای نمایش بعدی
        try {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('server_geo_${active.id}', farsi);
          await prefs.setString('server_flag_${active.id}', newFlag);
        } catch (_) {}
      }

      if (force) {
        final geoLabel = info.country != null
            ? ' · ${GeoFlag.farsiName(info.country)}'
            : '';
        _showMsg(_t(
          'IP خروجی: ${info.ip}$geoLabel',
          'Exit IP: ${info.ip}$geoLabel',
        ));
      }
    } catch (e) {
      debugPrint('refreshExitIp: $e');
    }
  }

  Future<void> _measureLive({bool force = false}) async {
    if (!_connected) return;
    if (!force && _connecting) return;
    final result = await V2RayEngine.probeConnected();
    if (!mounted || !_connected) return;
    setState(() {
      _livePing = result.ms;
      final active = _active;
      if (active != null && result.ok) {
        active.ping = result.ms;
        active.jitter = result.jitter;
        active.pingKind = PingKind.real;
        active.status = ServerStatus.online;
      }
    });
    // افزودن نمونه به مانیتور کیفیت
    if (result.ok && result.ms != null) {
      _qualityMonitor.addSample(
        pingMs: result.ms!,
        jitterMs: result.jitter ?? 0,
      );
      // ذخیره در تاریخچه
      final latest = _qualityMonitor.latest.value;
      // ارسال کیفیت به notification
      if (latest != null) {
        // ignore: unawaited_futures
        Future<void>.microtask(() {
          TelemetryService.setQuality(
            latest.score,
            latest.grade.emoji,
          );
          HomeWidgetService.setQuality(
            latest.score,
            latest.grade.emoji,
          );
        });
      }
      // هشدار کیفیت
      if (latest != null) {
        QualityAlert.instance.evaluate(latest.score);
      }
      if (latest != null) {
        // ignore: unawaited_futures
        QualityHistoryService.add(QualitySample(
          at: DateTime.now(),
          score: latest.score,
          pingMs: latest.pingMs,
          jitterMs: latest.jitterMs,
          lossPct: latest.lossPct,
          serverId: _active?.id ?? _selected?.id ?? '',
        ));
      }
    }
    await _savePings();
  }

  /// قبل از اتصال به WARP/WARP+/MASQUE، endpoint فعلی رو verify کن.
  /// اگه سالم نبود، rescan خودکار انجام بده.
  ///
  /// برمی‌گردونه: سرور آپدیت‌شده (یا همون سرور اگه چیزی نیاز نبود).
  Future<VpnServer> _verifyWarpEndpointBeforeConnect(
      VpnServer server) async {
    // MASQUE has its own scan/verify pipeline and does not speak the
    // WARP endpoint protocol this helper was written for. Calling it here
    // made the app parse the warpmasque:// link as a VLESS URL, which
    // threw "subscription is invalid or unsupported" on every connect.
    if (server.protocol == VpnProtocol.warpMasque) return server;
    final isWarp = server.protocol == VpnProtocol.amneziaWg ||
        server.protocol == VpnProtocol.chain;
    if (!isWarp) return server;
    if (!server.isDeletable) return server; // built-in

    final endpoint = '${server.host}:${server.port}';
    try {
      setState(() => _status = _t(
          'بررسی endpoint $endpoint ...', 'Verifying endpoint $endpoint ...'));
      final alive = await WarpEndpointHealthMonitor.quickCheck(
        endpoint,
        timeoutMs: 2500,
      );
      if (alive) {
        debugPrint('preconnect: $endpoint is alive');
        return server;
      }
      // خرابه — rescan
      debugPrint('preconnect: $endpoint dead — rescanning');
      setState(() => _status = _t(
          'endpoint خراب — پیدا کردن جایگزین...',
          'Endpoint dead — finding replacement...'));
      final rescan = server.protocol == VpnProtocol.warpMasque
          ? await WarpMasqueService.rescanEndpoints(
              endpoint: endpoint,
              endpointCandidates: server.warpMasqueEndpointCandidates,
              timeoutSec: 60,
            )
          : await WarpService.rescanEndpoints(server);
      if (rescan.endpoint == null) {
        debugPrint('preconnect: rescan failed — using original');
        return server;
      }
      final parts = rescan.endpoint!.split(':');
      if (parts.length < 2) return server;
      final newHost = parts[0];
      final newPort = int.tryParse(parts[1]) ?? server.port;
      final updated = server.copyWith(host: newHost, port: newPort);
      // آپدیت لیست
      setState(() {
        final si = _servers.indexWhere((s) => s.id == server.id);
        if (si >= 0) _servers[si] = updated;
        final ci = _customServers.indexWhere((s) => s.id == server.id);
        if (ci >= 0) _customServers[ci] = updated;
        if (_selected?.id == server.id) _selected = updated;
      });
      // ignore: unawaited_futures
      _saveCustomServers();
      _showMsg(_t(
        'endpoint جدید: ${rescan.endpoint} (${rescan.ms}ms)',
        'New endpoint: ${rescan.endpoint} (${rescan.ms}ms)',
      ));
      return updated;
    } catch (e) {
      debugPrint('preconnect verify failed: $e');
      return server;
    }
  }

  /// Quick Connect: probe every directly-dialable server, pick the best by
  /// rtt + 2*jitter + 20*loss, select it and hand it to the unchanged
  /// connect flow (_toggleConnection).
  Future<void> _quickConnect() async {
    if (_connecting || _connected) {
      _showMsg(_t('اول اتصال فعلی را قطع کنید', 'Disconnect first'));
      return;
    }
    final cands = _servers.where((s) =>
        s.host.isNotEmpty &&
        s.port > 0 &&
        s.protocol != VpnProtocol.ssh &&
        s.protocol != VpnProtocol.tunnel &&
        s.protocol != VpnProtocol.aether &&
        s.protocol != VpnProtocol.psiphon);
    final list = cands
        .map((s) => <String, dynamic>{
              'id': s.id,
              'host': s.host,
              'port': s.port,
              'protocol':
                  s.protocol == VpnProtocol.hysteria2 ? 'udp' : 'tcp',
            })
        .toList();
    if (list.isEmpty) {
      _showMsg(_t('سروری برای تست نیست', 'No servers to test'));
      return;
    }
    _showMsg(_t('در حال یافتن بهترین سرور...', 'Finding the best server...'));
    final best = await QuickConnect.pickBest(list);
    if (!mounted) return;
    if (best == null) {
      _showMsg(_t('سرور سالمی پیدا نشد', 'No reachable server found'));
      return;
    }
    final idx = _servers.indexWhere((s) => s.id == best['id']);
    if (idx < 0) return;
    setState(() => _selected = _servers[idx]);
    await SettingsService.setLastServer(_servers[idx].id);
    await _toggleConnection();
  }

  Future<void> _toggleConnection() async {
    if (_connecting) {
      _cancelConnect = true;
      setState(() => _status = _t('در حال لغو...', 'Cancelling...'));
      return;
    }
    if (_connected) {
      setState(() {
        _connecting = true;
        _status = _t('در حال قطع...', 'Disconnecting...');
      });
      // Smart Resume: کاربر خودش قطع کرد — auto-reconnect نکن
      _manualDisconnect = true;
      try {
        await _disconnectAll();
      } catch (_) {}
      _markDisconnected(_t('آماده', 'Ready'));
      return;
    }
    var selected = _selected;
    // Auto-select fastest: if the user enabled it in settings, replace
    // the manual selection with the highest-scoring online server.
    try {
      final autoFastest = await SettingsService.getConnectFastest();
      if (autoFastest) {
        final best = ServerTester.fastest(_servers);
        if (best != null &&
            best.status == ServerStatus.online &&
            best.ping != null) {
          selected = best;
          if (mounted) {
            setState(() {
              _selected = best;
              _status = _t(
                  'اتصال به سریع‌ترین: ${best.displayName}',
                  'Fastest: ${best.displayName}');
            });
          }
        }
      }
    } catch (_) {}

    if (selected == null) {
      _showMsg(_t('اول یک سرور انتخاب کن', 'Select a server first'));
      return;
    }
    // FIX(R2): ssh/tunnel از سرویس اختصاصی خودشون روت می‌شن، نه V2RayEngine.
    if (selected.protocol == VpnProtocol.ssh ||
        selected.protocol == VpnProtocol.tunnel) {
      _showMsg(_t(
          'برای این نوع سرور، روی خود سرور در لیست ضربه بزن',
          'For this server type, tap the server in the list instead'));
      return;
    }
    _cancelConnect = false;

    // Show immediate feedback BEFORE tearing down the previous session —
    // the teardown can take seconds (Tor/Aether/Psiphon), and until now
    // that delay landed before this setState, so a press looked like
    // nothing had happened and users tapped again.
    if (mounted) {
      setState(() {
        _connecting = true;
        _livePing = null;
        _status = _t('آماده‌سازی...', 'Preparing...');
      });
    }

    // FIX: قبل از اتصال جدید، *همه‌ی* session های در حال اجرا رو
    // disconnect کن (Tor، Tunnel، SSH، Aether، Psiphon، Xray).
    // هرگز نباید دو تونل همزمان فعال باشن.
    if (mounted) {
      setState(() => _status =
          _t('قطع اتصال قبلی...', 'Disconnecting previous...'));
    }
    await _disconnectAllSessionsForNewConnect();
    if (!mounted) return;

    setState(() {
      _status = _t('در حال اتصال...', 'Connecting...');
    });

    try {
      // Pre-connect verify برای WARP/WARP+/MASQUE
      selected = await _verifyWarpEndpointBeforeConnect(selected!);
      if (!mounted) return;
      if (_cancelConnect) return;

      final bool connected;
      final String? error;
      if (selected.isAether) {
        connected = await AetherService.connect(
          selected,
          isCancelled: () => _cancelConnect,
          onProgress: (message) {
            if (!mounted || _cancelConnect) return;
            setState(() => _status = message.replaceAll('\n', ' · '));
          },
        );
        error = AetherService.lastError;
      } else if (selected.isPsiphon) {
        if (mounted) {
          setState(() => _status =
              _t('Psiphon · آماده‌سازی...', 'Psiphon · preparing...'));
        }
        connected = await PsiphonService.connect(
          selected,
          isCancelled: () => _cancelConnect,
          onProgress: (message) {
            if (!mounted || _cancelConnect) return;
            setState(() => _status = message.replaceAll('\n', ' · '));
          },
        );
        error = PsiphonService.lastError;
      } else {
        connected = await V2RayEngine.connect(selected);
        error = V2RayEngine.lastError;
      }

      if (!mounted) return;
      if (connected && _cancelConnect) {
        try {
          await _disconnectAll();
        } catch (_) {}
        _markDisconnected(_t('لغو شد', 'Cancelled'));
        return;
      }
      _deadStrikes = 0;
      _pollTick = 0;
      if (connected) _lastConnectTime = DateTime.now();
      if (connected) _manualDisconnect = false;
      if (connected && selected != null) {
        try {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('last_active_server_id_v1', selected.id);
        } catch (_) {}
      }
      if (connected) {
        // widget timer start + refresh دوره‌ای
        // ignore: unawaited_futures
        HomeWidgetService.setConnectedStart(DateTime.now());
        _startWidgetTimerRefresh();
      }
      setState(() {
        _connected = connected;
        _connecting = false;
        _active = connected ? selected : null;
        // log
        if (connected) {
          // ignore: unawaited_futures
          ConnectionLogService.logConnect(selected!.displayName);
        } else if (error != null && error.isNotEmpty) {
          // ignore: unawaited_futures
          ConnectionLogService.logError(selected!.displayName, error);
        }
        
        if (connected) {
          _status = _t('متصل شد', 'Connected');
        } else if (_cancelConnect) {
          _status = _t('لغو شد', 'Cancelled');
        } else if (error != null && error.isNotEmpty) {
          _status = _t('اتصال ناموفق: $error', 'Failed: $error');
        } else {
          _status = _t('اتصال ناموفق', 'Failed');
        }
      });
      if (connected) {
        await SettingsService.setLastServer(selected.id);
        // ignore: unawaited_futures
        AnnouncementService.onConnected(selected.displayName);
        // health monitor — فقط برای WARP/WARP+/MASQUE
        if (selected.protocol == VpnProtocol.amneziaWg ||
            selected.protocol == VpnProtocol.chain ||
            selected.protocol == VpnProtocol.warpMasque) {
          _autoFailoverEnabled = true;
          // ignore: unawaited_futures
          _startHealthMonitorFor(selected);
        } else {
          _autoFailoverEnabled = false;
        }
        await Future<void>.delayed(const Duration(milliseconds: 800));
        await _measureLive();
        // نمایش IP خروجی از داخل تونل (الهام از ZedSecure)
        // ignore: unawaited_futures
        _refreshExitIp();
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _connected = false;
        _connecting = false;
        _active = null;
        _status = _t('خطا در اتصال', 'Connection error');
      });
      debugPrint('Connection error: $error');
    }
  }

  Future<void> _copyAll() async {
    // فقط سرورهایی که خود کاربر اضافه کرده؛ لینک سرورهای اشتراک‌های پیش‌فرض
    // (رایگان برنامه) هرگز کپی نمی‌شود.
    final customIds = _customServers.map((s) => s.id).toSet();
    final links = _servers
        .where((server) => customIds.contains(server.id))
        .map((server) => server.shareLink)
        .where((link) => link.trim().isNotEmpty)
        .join('\n');
    if (links.isEmpty) {
      _showMsg(_t('لینکی وجود ندارد', 'No links'));
      return;
    }
    await Clipboard.setData(ClipboardData(text: links));
    _showMsg(_t('همه لینک‌ها کپی شد', 'All links copied'));
  }

  void _copyServerLink(VpnServer server) {
    // فقط سرورهای خود کاربر — نه built-in و نه subscription.
    if (!server.isDeletable) {
      _showMsg(_t('سرورهای اشتراک قابل کپی نیستند',
          'Subscription servers cannot be copied'));
      return;
    }
    Clipboard.setData(ClipboardData(text: server.shareLink));
    _showMsg(_t('لینک کپی شد', 'Link copied'));
  }

  /// Rescan endpoint برای WARP MASQUE — با Kotlin parallel scanner.
  /// دیالوگ زنده + ذخیره endpoint برنده.
  Future<void> _rescanMasqueServer(VpnServer server) async {
    if (WarpMasqueService.scanProgress.value.active) {
      _showMsg(_t('اسکن قبلی هنوز در حال اجراست',
          'Previous scan still running'));
      return;
    }

    // استخراج پارامترها از shareLink
    final uri = Uri.parse(server.shareLink);
    final q = uri.queryParameters;
    final primaryEndpoint = (q['endpoint'] ?? q['ep'] ?? '').trim();
    final sni = (q['sni'] ?? WarpMasqueService.defaultSni).trim();
    final dns = (q['dns'] ?? WarpMasqueService.defaultDns).trim();
    final h2 = (q['h2'] ?? '1') == '1';
    final candidates =
        (q['candidates'] ?? q['cn'] ?? '').trim();

    if (primaryEndpoint.isEmpty) {
      _showMsg(_t('MASQUE: endpoint ناقص است',
          'MASQUE: endpoint missing'));
      return;
    }

    final rescanFuture = WarpMasqueService.rescanEndpoints(
      endpoint: primaryEndpoint,
      endpointCandidates:
          candidates.isNotEmpty ? candidates : null,
      sni: sni,
      dns: dns,
      http2: h2,
      timeoutSec: 90,
    );

    bool masqueDialogPopped = false;
    // ignore: unawaited_futures
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface(ctx),
        title: Text(
          _t('اسکن MASQUE', 'Scanning MASQUE'),
          style: TextStyle(color: AppColors.fg(ctx), fontSize: 15),
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: ValueListenableBuilder<WarpMasqueScanState>(
            valueListenable: WarpMasqueService.scanProgress,
            builder: (_, state, __) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  LinearProgressIndicator(
                    value: state.total > 0 ? state.progress : null,
                    color: AppColors.accent,
                    backgroundColor: AppColors.border(ctx),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    state.phase.isNotEmpty ? state.phase : '…',
                    style: TextStyle(
                        color: AppColors.fg(ctx), fontSize: 12),
                  ),
                  if (state.total > 0)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        '${state.tested}/${state.total}',
                        style: TextStyle(
                            color: AppColors.muted2(ctx),
                            fontSize: 11),
                      ),
                    ),
                  if (state.endpoint.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        '${state.endpoint}'
                        '${state.ms > 0 ? " · ${state.ms}ms" : ""}',
                        style: TextStyle(
                            color: state.ms > 0
                                ? AppColors.accent
                                : AppColors.muted(ctx),
                            fontSize: 11),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  if (state.error.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        state.error,
                        style: TextStyle(
                            color: AppColors.danger, fontSize: 11),
                      ),
                    ),
                ],
              );
            },
          ),
        ),
        actions: [
          ValueListenableBuilder<WarpMasqueScanState>(
            valueListenable: WarpMasqueService.scanProgress,
            builder: (_, state, __) => TextButton(
              // Always enabled: during a scan the user must be able to
              // dismiss the dialog. The scan continues in the background
              // and its result is still consumed by the await below.
              onPressed: () {
                masqueDialogPopped = true;
                Navigator.pop(ctx);
              },
              child: Text(
                _t(state.done ? 'بستن' : 'لغو',
                    state.done ? 'Close' : 'Cancel'),
                style: const TextStyle(color: AppColors.accent),
              ),
            ),
          ),
        ],
      ),
    );

    final result = await rescanFuture;

    if (!mounted) return;
    if (!masqueDialogPopped &&
        Navigator.of(context, rootNavigator: true).canPop()) {
      Navigator.of(context, rootNavigator: true).pop();
    }

    if (result.endpoint == null) {
      _showMsg(_t(
        'اسکن MASQUE ناموفق: ${result.error ?? "unknown"}',
        'MASQUE rescan failed: ${result.error ?? "unknown"}',
      ));
      return;
    }

    final parts = result.endpoint!.split(':');
    if (parts.length < 2) {
      _showMsg(_t('endpoint نامعتبر', 'Invalid endpoint'));
      return;
    }
    final newHost = parts[0];
    final newPort = int.tryParse(parts[1]) ?? server.port;

    final newQ = Map<String, String>.from(q);
    newQ['endpoint'] = result.endpoint!;
    final newLink = Uri(
      scheme: 'warpmasque',
      host: 'config',
      queryParameters: newQ,
    ).toString();

    final updated = server.copyWith(
      host: newHost,
      port: newPort,
      shareLink: newLink,
    );
    setState(() {
      final idx = _customServers.indexWhere((s) => s.id == server.id);
      if (idx >= 0) _customServers[idx] = updated;
      final si = _servers.indexWhere((s) => s.id == server.id);
      if (si >= 0) _servers[si] = updated;
      if (_selected?.id == server.id) _selected = updated;
    });
    // ignore: unawaited_futures
    _saveCustomServers();

    _showMsg(_t(
      'بهترین MASQUE: ${result.endpoint} (${result.ms}ms)',
      'Best MASQUE endpoint: ${result.endpoint} (${result.ms}ms)',
    ));
  }

  /// Rescan endpoint برای WARP/WARP+ — یه دیالوگ زنده که وضعیت
  /// scan/verify رو نشون می‌ده، بعد endpoint رو ذخیره می‌کنه.
  Future<void> _rescanWarpServer(VpnServer server) async {
    if (WarpService.scanProgress.value.active) {
      _showMsg(_t('اسکن قبلی هنوز در حال اجراست',
          'Previous scan still running'));
      return;
    }

    // شروع اسکن در پس‌زمینه + دیالوگ زنده
    final rescanFuture = WarpService.rescanEndpoints(server);

    // نمایش دیالوگ در پس‌زمینه بدون await
    // ignore: unawaited_futures
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface(ctx),
        title: Text(
          _t('اسکن endpoint ها', 'Rescanning endpoints'),
          style: TextStyle(color: AppColors.fg(ctx), fontSize: 15),
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: ValueListenableBuilder<WarpScanState>(
            valueListenable: WarpService.scanProgress,
            builder: (_, state, __) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  LinearProgressIndicator(
                    value: state.total > 0 ? state.progress : null,
                    color: AppColors.accent,
                    backgroundColor: AppColors.border(ctx),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    state.phase.isNotEmpty ? state.phase : '…',
                    style: TextStyle(color: AppColors.fg(ctx), fontSize: 12),
                  ),
                  if (state.total > 0)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        '${state.tested}/${state.total}',
                        style: TextStyle(
                            color: AppColors.muted2(ctx), fontSize: 11),
                      ),
                    ),
                  if (state.lastEndpoint != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        '${state.lastEndpoint}'
                        '${state.lastMs != null ? " · ${state.lastMs}ms" : ""}',
                        style: TextStyle(
                            color: state.lastMs != null
                                ? AppColors.accent
                                : AppColors.muted(ctx),
                            fontSize: 11),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  if (state.error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        state.error!,
                        style: TextStyle(
                            color: AppColors.danger, fontSize: 11),
                      ),
                    ),
                ],
              );
            },
          ),
        ),
        actions: [
          // Export cache — کاربر می‌تونه endpoint برنده رو با دوستش به اشتراک بذاره
          TextButton.icon(
            icon: Icon(Icons.ios_share, size: 16,
                color: AppColors.muted(ctx)),
            onPressed: () async {
              final uri = await WarpCacheCodec.exportCurrent();
              if (uri == null) {
                if (mounted) {
                  _showMsg(_t(
                    'کش خالی است — اول یک اسکن موفق انجام بده',
                    'Cache empty — run a successful scan first',
                  ));
                }
                return;
              }
              await Clipboard.setData(ClipboardData(text: uri));
              if (mounted) {
                _showMsg(_t(
                  'لینک کش کپی شد',
                  'Cache link copied',
                ));
              }
            },
            label: Text(
              _t('خروجی', 'Export'),
              style: TextStyle(
                  color: AppColors.muted(ctx), fontSize: 12),
            ),
          ),
          // Import cache — کاربر paste کنه
          TextButton.icon(
            icon: Icon(Icons.download, size: 16,
                color: AppColors.muted(ctx)),
            onPressed: () async {
              final clipboardData =
                  await Clipboard.getData(Clipboard.kTextPlain);
              final text = clipboardData?.text?.trim() ?? '';
              if (text.isEmpty ||
                  !WarpCacheCodec.looksLikeCache(text)) {
                if (mounted) {
                  _showMsg(_t(
                    'کلیپ‌بورد لینک کش معتبر ندارد',
                    'Clipboard has no valid cache link',
                  ));
                }
                return;
              }
              final n = await WarpCacheCodec.importFrom(text);
              if (mounted) {
                _showMsg(n > 0
                    ? _t('$n endpoint وارد شد',
                        '$n endpoints imported')
                    : _t('import ناموفق', 'Import failed'));
              }
            },
            label: Text(
              _t('ورودی', 'Import'),
              style: TextStyle(
                  color: AppColors.muted(ctx), fontSize: 12),
            ),
          ),
          ValueListenableBuilder<WarpScanState>(
            valueListenable: WarpService.scanProgress,
            builder: (_, state, __) => TextButton(
              onPressed:
                  state.done ? () => Navigator.pop(ctx) : null,
              child: Text(
                _t('بستن', 'Close'),
                style: TextStyle(
                    color: state.done
                        ? AppColors.accent
                        : AppColors.muted2(ctx)),
              ),
            ),
          ),
        ],
      ),
    );

    final rescanResult = await rescanFuture;

    if (!mounted) return;
    if (Navigator.of(context, rootNavigator: true).canPop()) {
      Navigator.of(context, rootNavigator: true).pop();
    }

    if (rescanResult.endpoint == null) {
      _showMsg(_t(
        'اسکن ناموفق: ${rescanResult.error ?? "unknown"}',
        'Rescan failed: ${rescanResult.error ?? "unknown"}',
      ));
      return;
    }

    final hostPort = rescanResult.endpoint!.split(':');
    final newHost = hostPort.first;
    final newPort = int.tryParse(
            hostPort.length > 1 ? hostPort[1] : '') ??
        server.port;

    final updated = server.copyWith(host: newHost, port: newPort);
    setState(() {
      final idx = _customServers.indexWhere((s) => s.id == server.id);
      if (idx >= 0) _customServers[idx] = updated;
      final si = _servers.indexWhere((s) => s.id == server.id);
      if (si >= 0) _servers[si] = updated;
      if (_selected?.id == server.id) _selected = updated;
    });
    // ignore: unawaited_futures
    _saveCustomServers();

    _showMsg(_t(
      'بهترین endpoint: ${rescanResult.endpoint} (${rescanResult.ms}ms)',
      'Best endpoint: ${rescanResult.endpoint} (${rescanResult.ms}ms)',
    ));
  }

  void _shareServer(VpnServer server) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            QrShareScreen(server: server, language: widget.language),
      ),
    );
  }

  void _toggleSort() {
    // FIX: واقعاً toggle کن (قبلاً همیشه true می‌شد و فقط صعودی می‌موند).
    // manualOrder رو هم پاک نکن — فقط ترتیب sort رو عوض کن.
    _sortAscending = !_sortAscending;
    // ignore: unawaited_futures
    _saveSortPreference();
    _sortCurrentServers();
    // ترتیب جدید رو ذخیره کن تا بعد از ریستارت بمونه
    _manualOrder = _servers.map((s) => s.id).toList();
    // ignore: unawaited_futures
    _saveManualOrder();
    if (mounted) {
      setState(() {});
      _showMsg(_sortAscending
          ? _t('مرتب‌سازی صعودی', 'Sort ascending')
          : _t('مرتب‌سازی نزولی', 'Sort descending'));
    }
  }

  void _sortCurrentServersLegacy() {
    _sortAscending = true;
    _manualOrder = [];
    // ignore: unawaited_futures
    _saveManualOrder();
    _sortCurrentServers();
    setState(() => _servers = List<VpnServer>.from(_servers));
    _showMsg(_t('سرورها مرتب شدند', 'Servers sorted'));
  }

  void _showMsg(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 2)),
    );
  }

  void _openAddConfig() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AddConfigScreen(
          language: widget.language,
          onServerAdded: (server) async {
            _customServers.insert(0, server);
            _manualOrder.insert(0, server.id);
            final subId = _selectedSubId;
            if (subId != null && subId.startsWith('ugroup:')) {
              // FIX4: adding a server while a user group tab is active must
              // put it in that group too, or the group filter hides it and
              // the auto-ping below updates a server the UI never shows.
              final gname = subId.substring('ugroup:'.length);
              final gList =
                  List<String>.from(_userGroups[gname] ?? const <String>[]);
              if (!gList.contains(server.id)) {
                gList.add(server.id);
                _userGroups = {..._userGroups, gname: gList};
                // ignore: unawaited_futures
                SharedPreferences.getInstance().then(
                  (p) => p.setString(_userGroupsKey, jsonEncode(_userGroups)),
                );
              }
            } else if (subId != null) {
              // اگر سابسکریپشن خاصی انتخاب شده، سرور را به آن tag بزن
              _customSubTags[server.id] = subId;
              _saveCustomSubTags();
            }
            _rebuildServerList();
            _saveCustomServers();
            _saveManualOrder();
            // auto-ping: سرور جدید رو خودکار تست کن
            // ignore: unawaited_futures
            Future.delayed(const Duration(milliseconds: 400), () {
              _testOne(server);
            });
          },
        ),
      ),
    );
  }

  void _openSearch() => setState(() => _showSearch = true);

  void _closeSearch() {
    _searchController.clear();
    _searchQuery = '';
    _showSearch = false;
    _rebuildServerList();
  }

  void _showMainMenu() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.elevated(context),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 8),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.muted2(context),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 12),
              ListTile(
                leading: const Icon(Icons.add_circle_outline,
                    color: AppColors.accent),
                title: Text(_t('افزودن کانفیگ', 'Add Config'),
                    style: TextStyle(color: AppColors.fg(context))),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _openAddConfig();
                },
              ),
              ListTile(
                leading:
                    Icon(Icons.search, color: AppColors.muted(context)),
                title: Text(_t('جستجو در سرورها', 'Search Servers'),
                    style: TextStyle(color: AppColors.fg(context))),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _openSearch();
                },
              ),
              ListTile(
                leading: Icon(Icons.content_copy, color: AppColors.muted(context)),
                title: Text(_t('حذف تکراری‌ها', 'Delete duplicates'),
                    style: TextStyle(color: AppColors.fg(context))),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _deleteDuplicates();
                },
              ),
              ListTile(
                leading:
                    const Icon(Icons.delete_sweep, color: AppColors.danger),
                title: Text(_t('حذف سرورهای آفلاین', 'Delete Offline'),
                    style: TextStyle(color: AppColors.fg(context))),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _deleteInvalid();
                },
              ),
              ListTile(
                leading:
                    Icon(Icons.copy_all, color: AppColors.muted(context)),
                title: Text(_t('کپی همه لینک‌ها', 'Copy All Links'),
                    style: TextStyle(color: AppColors.fg(context))),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _copyAll();
                },
              ),
              const SizedBox(height: 12),
            ],
          ),
        );
      },
    );
  }

  /// میانگین امتیاز کیفیت سرورهای یه گروه.
  ///
  /// برمی‌گردونه: null اگه نمونه‌ای نباشه، وگرنه int (0-100).
  int? _avgQualityForServers(Iterable<VpnServer> servers) {
    final ids = servers.map((s) => s.id).toSet();
    if (ids.isEmpty) return null;
    final samples = QualityHistoryService.cached;
    var sum = 0;
    var count = 0;
    // آخرین نمونه هر سرور
    final latestByServer = <String, int>{};
    for (final sample in samples) {
      if (!ids.contains(sample.serverId)) continue;
      final prev = latestByServer[sample.serverId];
      if (prev == null) {
        latestByServer[sample.serverId] = sample.score;
      } else {
        // آخرین رو نگه دار (چون samples از قدیم به جدید sort شدن)
        latestByServer[sample.serverId] = sample.score;
      }
    }
    for (final score in latestByServer.values) {
      sum += score;
      count++;
    }
    if (count == 0) return null;
    return (sum / count).round();
  }

  /// سرورهای یه subscription با id داده‌شده.
  Iterable<VpnServer> _serversForSubscription(String subId) {
    if (subId.startsWith('ugroup:')) {
      final gname = subId.substring('ugroup:'.length);
      final ids = _userGroups[gname] ?? const <String>[];
      return _servers.where((s) => ids.contains(s.id));
    }
    // از لینک‌های subscription — serverها id دارن
    return _servers.where((s) => s.id.startsWith(subId));
  }

  /// رنگ نقطه‌ی کیفیت.
  Color _qualityDotColor(int? avgScore) {
    if (avgScore == null) return AppColors.muted2(context);
    if (avgScore >= 85) return AppColors.accent;
    if (avgScore >= 70) return const Color(0xFF8BC34A);
    if (avgScore >= 50) return AppColors.warn;
    if (avgScore >= 30) return const Color(0xFFFF7043);
    return AppColors.danger;
  }

  Widget _buildSubTabs() {
    if (widget.subscriptions.isEmpty && _userGroups.isEmpty) {
      return const SizedBox.shrink();
    }

    final tabs = <Widget>[];
    final showAll = _showAllTab;
    if (showAll) tabs.add(_subTab(null, _t('همه', 'All')));
    for (final sub in widget.subscriptions) {
      tabs.add(_subTab(sub.id, sub.name, sub.serverCount));
    }
    for (final gname in _userGroupsOrder) {
      if (!_userGroups.containsKey(gname)) continue;
      final cnt = (_userGroups[gname] ?? const <String>[]).length;
      tabs.add(_userGroupTab(gname, cnt));
    }
    if (_userGroups.isNotEmpty) {
      tabs.add(
        GestureDetector(
          onTap: () => _openGroupManager(),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: AppColors.surface(context),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.border(context)),
            ),
            child: Center(
              child: Icon(Icons.folder_open,
                  size: 16, color: AppColors.muted2(context)),
            ),
          ),
        ),
      );
    }

    return SizedBox(
      height: 40,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        itemCount: tabs.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) => tabs[i],
      ),
    );
  }

  Widget _subTab(String? subId, String label, [int count = 0]) {
    final active = _selectedSubId == subId;
    final short = label.length > 14 ? '${label.substring(0, 13)}…' : label;
    // quality dot (اگه نمونه داشتیم)
    int? avgQ;
    if (subId != null) {
      avgQ = _avgQualityForServers(_serversForSubscription(subId));
    }
    return GestureDetector(
      onTap: () => _selectSubscription(subId),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: active
              ? AppColors.accent.withOpacity(0.15)
              : AppColors.surface(context),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: active ? AppColors.accent : AppColors.border(context),
          ),
        ),
        child: Center(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (avgQ != null && !active) ...[
                Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: _qualityDotColor(avgQ),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 6),
              ],
              Text(
                count > 0 ? '$short ($count)' : short,
                style: TextStyle(
                  color: active ? AppColors.accent : AppColors.fg(context),
                  fontSize: 12.5,
                  fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _userGroupTab(String name, int count) {
    final active = _selectedSubId == 'ugroup:$name';
    final short = name.length > 14 ? '${name.substring(0, 13)}…' : name;
    return GestureDetector(
      onTap: () => _selectSubscription('ugroup:$name'),
      onLongPress: () => _openGroupManager(),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: active
              ? AppColors.accent.withOpacity(0.15)
              : AppColors.surface(context),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: active ? AppColors.accent : AppColors.border(context),
          ),
        ),
        child: Center(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.folder_outlined,
                  size: 14,
                  color: active ? AppColors.accent : AppColors.muted2(context)),
              const SizedBox(width: 6),
              Text(
                count > 0 ? '$short ($count)' : short,
                style: TextStyle(
                  color: active ? AppColors.accent : AppColors.fg(context),
                  fontSize: 12.5,
                  fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openGroupManager() async {
    if (_userGroups.isEmpty) {
      _showMsg(_t('هنوز گروهی نساخته‌اید', 'No groups yet'));
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    final workingGroups = <String, List<String>>{};
    _userGroups.forEach((k, v) => workingGroups[k] = List<String>.from(v));
    final workingOrder = List<String>.from(_userGroupsOrder);
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surface(context),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (bsCtx) {
        return StatefulBuilder(
          builder: (sCtx, setLocal) {
            Future<void> persist() async {
              final g = <String, dynamic>{};
              for (final k in workingOrder) {
                if (workingGroups[k] != null) g[k] = workingGroups[k];
              }
              await prefs.setString(_userGroupsKey, jsonEncode(g));
              await prefs.setStringList(_userGroupsOrderKey, workingOrder);
            }

            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 8),
                      child: Row(
                        children: [
                          const Icon(Icons.folder_outlined,
                              color: AppColors.accent),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _t('مدیریت گروه‌ها', 'Manage groups'),
                              style: TextStyle(
                                  color: AppColors.fg(sCtx),
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700),
                            ),
                          ),
                          IconButton(
                            icon: Icon(Icons.close,
                                color: AppColors.muted2(sCtx)),
                            onPressed: () => Navigator.pop(bsCtx),
                          ),
                        ],
                      ),
                    ),
                    Flexible(
                      child: ReorderableListView.builder(
                        shrinkWrap: true,
                        itemCount: workingOrder.length,
                        onReorder: (a, b) {
                          if (b > a) b -= 1;
                          final item = workingOrder.removeAt(a);
                          workingOrder.insert(b, item);
                          setLocal(() {});
                          persist();
                        },
                        itemBuilder: (_, i) {
                          final name = workingOrder[i];
                          final cnt =
                              (workingGroups[name] ?? const <String>[]).length;
                          return ListTile(
                            key: ValueKey('grp_$name'),
                            leading: const Icon(Icons.drag_handle),
                            title: Text(name,
                                style: TextStyle(color: AppColors.fg(sCtx))),
                            subtitle: Text(
                              '$cnt ${_t('سرور', 'servers')}',
                              style: TextStyle(
                                  color: AppColors.muted2(sCtx), fontSize: 11),
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: Icon(Icons.edit,
                                      size: 18, color: AppColors.muted2(sCtx)),
                                  onPressed: () async {
                                    final nameCtrl =
                                        TextEditingController(text: name);
                                    final linkCtrl = TextEditingController();
                                    final curIds = List<String>.from(
                                        workingGroups[name] ??
                                            const <String>[]);
                                    try {
                                      final res = await showDialog<Map<String, dynamic>>(
                                        context: sCtx,
                                        builder: (d) {
                                          return StatefulBuilder(builder: (dCtx, setLocalEdit) {
                                            return AlertDialog(
                                              backgroundColor: AppColors.surface(d),
                                              title: Text(
                                                  _t('ویرایش گروه', 'Edit group'),
                                                  style: TextStyle(color: AppColors.fg(d), fontSize: 16)),
                                              content: SizedBox(
                                                width: double.maxFinite,
                                                child: SingleChildScrollView(
                                                  child: Column(
                                                    crossAxisAlignment: CrossAxisAlignment.start,
                                                    mainAxisSize: MainAxisSize.min,
                                                    children: [
                                                      Text(_t('نام گروه', 'Group name'),
                                                          style: TextStyle(color: AppColors.muted(d), fontSize: 12)),
                                                      const SizedBox(height: 6),
                                                      TextField(
                                                        controller: nameCtrl,
                                                        style: TextStyle(color: AppColors.fg(d), fontSize: 13),
                                                        decoration: InputDecoration(
                                                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                                        ),
                                                      ),
                                                      const SizedBox(height: 10),
                                                      Text(_t('سرورهای داخل گروه (${curIds.length})',
                                                          'Servers in group (${curIds.length})'),
                                                          style: TextStyle(color: AppColors.muted(d), fontSize: 12)),
                                                      const SizedBox(height: 6),
                                                      Container(
                                                        constraints: const BoxConstraints(maxHeight: 220),
                                                        decoration: BoxDecoration(
                                                          color: AppColors.bg(dCtx),
                                                          borderRadius: BorderRadius.circular(8),
                                                          border: Border.all(color: AppColors.border(dCtx)),
                                                        ),
                                                        child: curIds.isEmpty
                                                            ? Padding(
                                                                padding: const EdgeInsets.all(12),
                                                                child: Text(_t('خالی', 'Empty'),
                                                                    style: TextStyle(color: AppColors.muted2(dCtx), fontSize: 12)),
                                                              )
                                                            : ListView.builder(
                                                                shrinkWrap: true,
                                                                itemCount: curIds.length,
                                                                itemBuilder: (_, i) {
                                                                  final sid = curIds[i];
                                                                  final srv = _customServers.firstWhere(
                                                                    (s) => s.id == sid,
                                                                    orElse: () => VpnServer(
                                                                      id: sid,
                                                                      name: sid,
                                                                      flag: '?',
                                                                      shareLink: '',
                                                                      protocol: VpnProtocol.custom,
                                                                      host: '',
                                                                      port: 0,
                                                                    ),
                                                                  );
                                                                  return ListTile(
                                                                    dense: true,
                                                                    title: Text(srv.displayName,
                                                                        style: TextStyle(color: AppColors.fg(dCtx), fontSize: 12),
                                                                        maxLines: 1, overflow: TextOverflow.ellipsis),
                                                                    trailing: IconButton(
                                                                      icon: const Icon(Icons.close, size: 16, color: Colors.redAccent),
                                                                      onPressed: () {
                                                                        setLocalEdit(() => curIds.remove(sid));
                                                                      },
                                                                    ),
                                                                  );
                                                                },
                                                              ),
                                                      ),
                                                      const SizedBox(height: 10),
                                                      Text(_t('افزودن کانفیگ جدید (هر خط یکی: vless/vmess/trojan/ss/hysteria2 یا JSON)',
                                                          'Add new config (vless/vmess/trojan/ss/hysteria2 or JSON)'),
                                                          style: TextStyle(color: AppColors.muted(d), fontSize: 11)),
                                                      const SizedBox(height: 6),
                                                      TextField(
                                                        controller: linkCtrl,
                                                        maxLines: 3,
                                                        style: TextStyle(color: AppColors.fg(d), fontSize: 12),
                                                        decoration: InputDecoration(
                                                          hintText: 'vless://...',
                                                          hintStyle: TextStyle(color: AppColors.muted2(d), fontSize: 11),
                                                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                              ),
                                              actions: [
                                                TextButton(
                                                  onPressed: () => Navigator.pop(d),
                                                  child: Text(_t('انصراف', 'Cancel')),
                                                ),
                                                TextButton(
                                                  onPressed: () => Navigator.pop(d, {
                                                    'name': nameCtrl.text.trim(),
                                                    'ids': curIds,
                                                    'newLinks': linkCtrl.text.trim(),
                                                  }),
                                                  child: Text(_t('ذخیره', 'Save'),
                                                      style: const TextStyle(color: AppColors.accent)),
                                                ),
                                              ],
                                            );
                                          });
                                        },
                                      );
                                      if (res == null) return;
                                      final newName = res['name'] as String;
                                      if (newName.isEmpty) return;
                                      final finalIds = (res['ids'] as List).cast<String>().toList();
                                      // افزودن کانفیگ‌های جدید
                                      final newLinks = res['newLinks'] as String;
                                      if (newLinks.isNotEmpty) {
                                        final links = LinkParser.extractLinks(newLinks);
                                        final stamp = DateTime.now().millisecondsSinceEpoch;
                                        if (XrayJson.looksLike(newLinks)) {
                                          final srv = XrayJson.parse(newLinks, id: 'custom_${stamp}_ge');
                                          if (srv != null) {
                                            _customServers.insert(0, srv);
                                            finalIds.add(srv.id);
                                          }
                                        } else {
                                          for (var i = 0; i < links.length; i++) {
                                            final srv = LinkParser.parse(links[i], id: 'custom_${stamp}_ge$i');
                                            if (srv == null) continue;
                                            _customServers.insert(0, srv);
                                            finalIds.add(srv.id);
                                          }
                                        }
                                        await _saveCustomServers();
                                      }
                                      workingGroups.remove(name);
                                      workingGroups[newName] = finalIds;
                                      final idx = workingOrder.indexOf(name);
                                      if (idx >= 0) workingOrder[idx] = newName;
                                      setLocal(() {});
                                      await persist();
                                    } finally {
                                      nameCtrl.dispose();
                                      linkCtrl.dispose();
                                    }
                                  },
                                ),
                                IconButton(
                                  icon: const Icon(Icons.delete_outline,
                                      size: 18, color: Colors.redAccent),
                                  onPressed: () async {
                                    final ok = await showDialog<bool>(
                                      context: sCtx,
                                      builder: (d) => AlertDialog(
                                        backgroundColor: AppColors.surface(d),
                                        title: Text(_t('حذف گروه', 'Delete group'),
                                            style: TextStyle(
                                                color: AppColors.fg(d))),
                                        content: Text(
                                          _t('گروه «$name» حذف شود؟',
                                              'Delete group "$name"?'),
                                          style: TextStyle(
                                              color: AppColors.fg(d)),
                                        ),
                                        actions: [
                                          TextButton(
                                            onPressed: () =>
                                                Navigator.pop(d, false),
                                            child: Text(
                                                _t('انصراف', 'Cancel')),
                                          ),
                                          TextButton(
                                            onPressed: () =>
                                                Navigator.pop(d, true),
                                            child: Text(_t('حذف', 'Delete')),
                                          ),
                                        ],
                                      ),
                                    );
                                    if (ok != true) return;
                                    workingGroups.remove(name);
                                    workingOrder.remove(name);
                                    setLocal(() {});
                                    await persist();
                                  },
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
    if (!mounted) return;
    setState(() {
      _userGroups = workingGroups;
      _userGroupsOrder = workingOrder;
      if (_selectedSubId != null && _selectedSubId!.startsWith('ugroup:')) {
        final gname = _selectedSubId!.substring('ugroup:'.length);
        if (!_userGroups.containsKey(gname)) _selectedSubId = null;
      }
    });
    _rebuildServerList();
  }

  /// Jump, not animate. With thousands of servers an animated scroll makes
  /// the framework build every intermediate frame, which is what made the
  /// app stutter and heat up. jumpTo lands in one frame.
  void _scrollToTop() {
    if (!_listScrollController.hasClients) return;
    _listScrollController.jumpTo(0);
  }

  void _scrollToBottom() {
    if (!_listScrollController.hasClients) return;
    _listScrollController.jumpTo(
      _listScrollController.position.maxScrollExtent,
    );
  }

  Widget _buildTopBar() {
    // Compact bar: one menu button, the title, the connection status, then
    // only the two buttons you press constantly (test-all, batch). The
    // rest (find, top, bottom, sort, selection) live in an overflow menu
    // so the header stops eating a third of the screen.
    return Container(
      padding: const EdgeInsets.fromLTRB(0, 2, 0, 2),
      child: Row(
        children: [
          IconButton(
            icon: Icon(Icons.menu,
                color: AppColors.muted(context), size: 22),
            onPressed: _showMainMenu,
            tooltip: _t('منو', 'Menu'),
            padding: const EdgeInsets.symmetric(horizontal: 4),
            constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
          ),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Hasan VPN',
                  style: TextStyle(
                    color: AppColors.fg(context),
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  _status,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      color: AppColors.muted(context), fontSize: 11),
                ),
              ],
            ),
          ),
          // Find selected — always visible, one of the most-used buttons.
          IconButton(
            icon: Icon(Icons.my_location,
                color: AppColors.accent, size: 20),
            onPressed: _jumpToSelected,
            tooltip: _t('یافتن انتخاب‌شده', 'Find selected'),
            padding: const EdgeInsets.symmetric(horizontal: 4),
            constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
          ),
          // Test All — kept visible, used constantly.
          IconButton(
            icon: _testing
                ? const Icon(Icons.stop_circle_outlined,
                    color: AppColors.danger, size: 20)
                : const Icon(Icons.speed,
                    color: AppColors.accent, size: 20),
            onPressed: _testing ? _cancelTesting : _testAll,
            tooltip: _t('تست همه', 'Test All'),
            padding: const EdgeInsets.symmetric(horizontal: 4),
            constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
          ),
          // Settings — was removed by mistake; users had no way to reach it.
          IconButton(
            icon: Icon(Icons.settings,
                color: AppColors.muted(context), size: 20),
            onPressed: widget.onOpenSettings,
            tooltip: _t('تنظیمات', 'Settings'),
            padding: const EdgeInsets.symmetric(horizontal: 4),
            constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
          ),
          // Overflow menu — top / bottom / sort / selection.
          PopupMenuButton<String>(
            icon: Icon(Icons.more_vert,
                color: AppColors.accent, size: 20),
            padding: const EdgeInsets.symmetric(horizontal: 4),
            tooltip: _t('بیشتر', 'More'),
            onSelected: (v) {
              switch (v) {
                case 'top':
                  _scrollToTop();
                  break;
                case 'bottom':
                  _scrollToBottom();
                  break;
                case 'sort':
                  _toggleSort();
                  break;
                case 'quick':
                  _quickConnect();
                  break;
                case 'select':
                  setState(() {
                    _selectionMode = !_selectionMode;
                    if (!_selectionMode) _selectedIds.clear();
                  });
                  break;
              }
            },
            itemBuilder: (c) => [
              PopupMenuItem(
                value: 'top',
                child: Row(children: [
                  const Icon(Icons.vertical_align_top,
                      color: AppColors.accent, size: 18),
                  const SizedBox(width: 10),
                  Text(_t('برو به اول', 'Top')),
                ]),
              ),
              PopupMenuItem(
                value: 'bottom',
                child: Row(children: [
                  const Icon(Icons.vertical_align_bottom,
                      color: AppColors.accent, size: 18),
                  const SizedBox(width: 10),
                  Text(_t('برو به آخر', 'Bottom')),
                ]),
              ),
              PopupMenuItem(
                value: 'quick',
                child: Text(_t('اتصال سریع', 'Quick Connect')),
              ),
              PopupMenuItem(
                value: 'sort',
                child: Row(children: [
                  Icon(_sortAscending ? Icons.sort : Icons.sort_by_alpha,
                      color: AppColors.accent, size: 18),
                  const SizedBox(width: 10),
                  Text(_t('مرتب‌سازی', 'Sort')),
                ]),
              ),
              PopupMenuItem(
                value: 'select',
                child: Row(children: [
                  Icon(_selectionMode
                          ? Icons.check_box
                          : Icons.check_box_outline_blank,
                      color: AppColors.accent, size: 18),
                  const SizedBox(width: 10),
                  Text(_t('انتخاب چندتایی', 'Multi-select')),
                ]),
              ),
            ],
          ),
        ],
      ),
    );
  }



  Widget _buildConnectButton() {
    final selectedColor =
        _selected == null ? AppColors.border(context) : AppColors.accent;
    return GestureDetector(
      onTap: _toggleConnection,
      child: Container(
        width: 130,
        height: 130,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
            color: _connected ? AppColors.accent : selectedColor,
            width: 3,
          ),
          color: _connected
              ? AppColors.accent.withOpacity(0.15)
              : (_selected != null
                  ? AppColors.accent.withOpacity(0.05)
                  : Colors.transparent),
          boxShadow: _connected
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
          child: _connecting
              ? Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const SizedBox(
                      width: 32,
                      height: 32,
                      child: CircularProgressIndicator(
                        strokeWidth: 3,
                        color: AppColors.accent,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(_t('لغو', 'Cancel'),
                        style: TextStyle(
                            color: AppColors.muted(context), fontSize: 11)),
                  ],
                )
              : Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (_connected && _livePing != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 2),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              '$_livePing ms',
                              style: const TextStyle(
                                color: AppColors.accent,
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(width: 4),
                            ValueListenableBuilder<QualityScore?>(
                              valueListenable: _qualityMonitor.latest,
                              builder: (_, score, __) => QualityBadge(
                                score: score,
                                compact: true,
                                language: widget.language,
                              ),
                            ),
                          ],
                        ),
                      ),
                    Icon(
                      _connected ? Icons.shield : Icons.power_settings_new,
                      size: 42,
                      color: _connected
                          ? AppColors.accent
                          : (_selected != null
                              ? AppColors.accent
                              : AppColors.muted2(context)),
                    ),
                    if (_connected) ...[
                      const SizedBox(height: 4),
                      const SizedBox(
                        height: 36,
                        width: 120,
                        child: TrafficSparkline(height: 32),
                      ),
                    ],
                    const SizedBox(height: 6),
                    Text(
                      _connected
                          ? _t('قطع اتصال', 'Disconnect')
                          : (_selected != null
                              ? _t('اتصال', 'Connect')
                              : _t('انتخاب سرور', 'Pick server')),
                      style: TextStyle(
                        color: _connected
                            ? AppColors.accent
                            : (_selected != null
                                ? AppColors.accent
                                : AppColors.muted2(context)),
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }

  Widget _buildServerList() {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '${_t("سرورها", "Servers")} (${_servers.length})',
                  style: TextStyle(
                    color: AppColors.muted(context),
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (_testing)
                  Text(
                    '$_tested / $_total',
                    style: TextStyle(
                        color: AppColors.muted2(context), fontSize: 10),
                  ),
              ],
            ),
          ),
          Expanded(
            child: _twoColumnGrid
                ? ReorderableGridView.builder(
                    controller: _listScrollController,
                    padding: const EdgeInsets.only(
                        left: 8, right: 8, bottom: 110),
                    cacheExtent: 120.0,
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      mainAxisSpacing: 6,
                      crossAxisSpacing: 6,
                      mainAxisExtent: 62,
                    ),
                    itemCount: _servers.length,
                    onReorder: _onReorder,
                    itemBuilder: (context, index) {
                      final server = _servers[index];
                      return _TwoSecondDragStartListener(
                        key: ValueKey('grid_reorder_${server.id}'),
                        index: index,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          child: _buildServerTile(server, compact: true),
                        ),
                      );
                    },
                  )
                : ReorderableListView.builder(
              scrollController: _listScrollController,
              padding: const EdgeInsets.only(
                  left: 16, right: 16, bottom: 90),
              itemCount: _servers.length,
              onReorder: _onReorder,
              buildDefaultDragHandles: false,
              // Only build a small window of rows around the viewport
              // instead of the default 250-pixel margin; with thousands of
              // servers that margin was building dozens of tiles per frame.
              cacheExtent: 120.0,
              proxyDecorator: (child, index, animation) {
                return Material(
                  color: Colors.transparent,
                  elevation: 8,
                  borderRadius: BorderRadius.circular(14),
                  child: child,
                );
              },
              itemBuilder: (context, index) {
                final server = _servers[index];
                return _TwoSecondDragStartListener(
                  key: ValueKey('reorder_${server.id}'),
                  index: index,
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: SizedBox(
                      height: 74,
                      child: _buildServerTile(server),
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

  /// آخرین امتیاز کیفیت این سرور (از history).
  int? _lastQualityFor(String serverId) {
    if (serverId.isEmpty) return null;
    final samples = QualityHistoryService.cached;
    for (var i = samples.length - 1; i >= 0; i--) {
      if (samples[i].serverId == serverId) {
        return samples[i].score;
      }
    }
    return null;
  }

  Widget _buildServerTile(VpnServer server, {bool compact = false}) {
    final tileKey = _tileKeys.putIfAbsent(server.id, () => GlobalKey());
    // Live badge — از batch tester یا WARP scan progress
    return ValueListenableBuilder<WarpBatchState>(
      valueListenable: _batchTester.state,
      builder: (_, batchState, __) {
        String? live;
        if (batchState.running &&
            batchState.currentServer == server.displayName) {
          live = 'SCAN ${batchState.tested}/${batchState.total}';
        } else if (batchState.running) {
          // در حال تست batch هست ولی این سرور فعلی نیست
          final done = batchState.results
              .any((r) => r.server.id == server.id);
          if (done) {
            final r = batchState.results
                .firstWhere((r) => r.server.id == server.id);
            live = r.ok ? '✓ ${r.latencyMs}ms' : '✕';
          }
        }
        final quality = _lastQualityFor(server.id);
        return _buildServerTileInner(
            server, compact, tileKey, live, quality);
      },
    );
  }

  Widget _buildServerTileInner(
    VpnServer server,
    bool compact,
    GlobalKey tileKey,
    String? liveBadge,
    int? qualityScore,
  ) {
    return ServerTile(
      key: tileKey,
      server: server,
      compact: compact,
      liveBadge: liveBadge,
      qualityScore: qualityScore,
      selected: _selected?.id == server.id,
      active: _connected && _active?.id == server.id,
      onTap: () async {
        if (_selectionMode) {
          setState(() {
            if (_selectedIds.contains(server.id)) {
              _selectedIds.remove(server.id);
              if (_selectedIds.isEmpty) _selectionMode = false;
            } else {
              _selectedIds.add(server.id);
            }
          });
          return;
        }
        if (_pendingWidgetId != null) {
          await _handleWidgetServerSelection(server);
          return;
        }
        // SSH: routing از SshSessionService انجام می‌شود
        if (server.protocol == VpnProtocol.ssh) {
          final n = SshSessionService.instance.notifierFor(server.id);
          final isOn = n.value.routingThroughVpn || n.value.running;
          if (isOn) {
            await SshSessionService.instance.disconnect();
            return;
          }
          if (_connected) {
            try {
              await _disconnectAll();
            } catch (_) {}
            _markDisconnected(_t('آماده', 'Ready'));
          }
          if (TorSessionService.instance.anyRouting) {
            try {
              await TorSessionService.instance.disconnect();
            } catch (_) {}
          }
          if (TunnelSessionService.instance.anyRouting) {
            try {
              await TunnelSessionService.instance.disconnect();
            } catch (_) {}
          }
          final prof = SshProfile.fromLink(server.shareLink);
          setState(() {
            _selected = server;
            _status = _t('اتصال SSH...', 'Connecting SSH...');
          });
          await SshSessionService.instance.connect(server.id, prof);
          return;
        }
        // WARP MASQUE: routing از WarpMasqueSessionService انجام می‌شود
        if (server.protocol == VpnProtocol.warpMasque) {
          final n = WarpMasqueSessionService.instance.notifierFor(server.id);
          final isOn = n.value.routingThroughVpn || n.value.running;
          if (isOn) {
            await WarpMasqueSessionService.instance.disconnect();
            return;
          }
          if (_connected) {
            try {
              await _disconnectAll();
            } catch (_) {}
            _markDisconnected(_t('آماده', 'Ready'));
          }
          if (TorSessionService.instance.anyRouting) {
            try { await TorSessionService.instance.disconnect(); } catch (_) {}
          }
          if (TunnelSessionService.instance.anyRouting) {
            try { await TunnelSessionService.instance.disconnect(); } catch (_) {}
          }
          if (MasterDnsSessionService.instance.anyRouting) {
            try { await MasterDnsSessionService.instance.disconnect(); } catch (_) {}
          }

          final uri = Uri.parse(server.shareLink);
          final q = uri.queryParameters;
          final endpoint = (q['endpoint'] ?? '').trim();
          final sni = (q['sni'] ?? 'soft98.ir').trim();
          final dns = (q['dns'] ?? '1.1.1.1,1.0.0.1').trim();
          final h2 = (q['h2'] ?? '1') == '1';
          final candidates = (q['candidates'] ?? q['cn'] ?? '').trim();
          final deviceName = (q['device'] ?? q['dn'] ?? 'Hasan-VPN').trim();
          if (endpoint.isEmpty) {
            _showMsg(_t('WARP MASQUE: endpoint ناقصه',
                'WARP MASQUE: endpoint missing'));
            return;
          }

          setState(() {
            _selected = server;
            _status = _t('اتصال WARP MASQUE...', 'Connecting WARP MASQUE...');
          });
          // ignore: unawaited_futures
          ConnectionLogService.logConnect(server.displayName);

          await WarpMasqueSessionService.instance.connect(
            server.id,
            endpoint: endpoint,
            endpointCandidates:
                candidates.isNotEmpty ? candidates : null,
            sni: sni,
            dns: dns,
            http2: h2,
            deviceName: deviceName.isEmpty ? 'Hasan-VPN' : deviceName,
          );
          return;
        }
        // MasterDNS: routing از MasterDnsSessionService انجام می‌شود
        if (server.protocol == VpnProtocol.masterdns) {
          final n = MasterDnsSessionService.instance
              .notifierFor(server.id);
          final isOn = n.value.routingThroughVpn || n.value.running;
          if (isOn) {
            await MasterDnsSessionService.instance.disconnect();
            return;
          }
          if (_connected) {
            try {
              await _disconnectAll();
            } catch (_) {}
            _markDisconnected(_t('آماده', 'Ready'));
          }
          if (TorSessionService.instance.anyRouting) {
            try {
              await TorSessionService.instance.disconnect();
            } catch (_) {}
          }
          if (TunnelSessionService.instance.anyRouting) {
            try {
              await TunnelSessionService.instance.disconnect();
            } catch (_) {}
          }

          // parse masterdns:// link
          final uri = Uri.parse(server.shareLink);
          final q = uri.queryParameters;
          final domain = (q['domain'] ?? server.host).trim();
          final key = (q['key'] ?? '').trim();
          final method = int.tryParse(q['method'] ?? '1') ?? 1;
          final resolvers = (q['resolvers'] ?? '').trim();
          if (domain.isEmpty || key.isEmpty) {
            _showMsg(_t('MasterDNS: domain/key ناقصه',
                'MasterDNS: domain/key missing'));
            return;
          }

          setState(() {
            _selected = server;
            _status = _t('اتصال MasterDNS...', 'Connecting MasterDNS...');
          });
          // ignore: unawaited_futures
          ConnectionLogService.logConnect(server.displayName);
          // advanced TOML از shareLink (اگه کاربر تنظیم کرده باشه)
          final advancedToml =
              (uri.queryParameters['advanced'] ?? '').trim();
          await MasterDnsSessionService.instance.connect(
            server.id, domain, key,
            method: method,
            resolvers: resolvers,
            advancedToml: advancedToml.isEmpty ? null : advancedToml,
          );
          return;
        }
        // تونل DNS: routing از TunnelSessionService انجام می‌شود
        if (server.protocol == VpnProtocol.tunnel) {
          final n = TunnelSessionService.instance.notifierFor(server.id);
          final isOn = n.value.routingThroughVpn || n.value.running;
          if (isOn) {
            await TunnelSessionService.instance.disconnect();
            return;
          }
          if (_connected) {
            try {
              await _disconnectAll();
            } catch (_) {}
            _markDisconnected(_t('آماده', 'Ready'));
          }
          if (TorSessionService.instance.anyRouting) {
            try {
              await TorSessionService.instance.disconnect();
            } catch (_) {}
          }
          final prof = TunnelProfile.fromLink(server.shareLink);
          setState(() {
            _selected = server;
            _status = _t('اتصال تونل DNS...', 'Connecting tunnel...');
          });
          // ignore: unawaited_futures
          ConnectionLogService.logConnect(server.displayName);
          await TunnelSessionService.instance.connect(server.id, prof);
          return;
        }
        setState(() => _selected = server);
        await SettingsService.setLastServer(server.id);
      },
      onDelete: _customServers.any((s) => s.id == server.id)
          ? () => _deleteServer(server)
          : null,
      onPin: () => _togglePin(server),
      // کپی/اشتراک فقط برای سرورهای خود کاربر (isDeletable=true):
      // built-in و subscription این گزینه‌ها رو ندارن.
      onCopy: server.isDeletable ? () => _copyServerLink(server) : null,
      onShare: server.isDeletable ? () => _shareServer(server) : null,
      onEdit: () => _editServerName(server),
      onTest: () => _testOne(server),
      onHomeWidget: () => _pinServerToHome(server),
      onRescanWarp: (server.protocol == VpnProtocol.amneziaWg ||
              server.protocol == VpnProtocol.chain ||
              server.protocol == VpnProtocol.warpMasque)
          ? () => server.protocol == VpnProtocol.warpMasque
              ? _rescanMasqueServer(server)
              : _rescanWarpServer(server)
          : null,
    );
  }

  @override
  bool _isPatternihaActive() {
    if (_selectedSubId == null) return false;
    try {
      final sub = widget.subscriptions.firstWhere((s) => s.id == _selectedSubId);
      final key = '${sub.id} ${sub.name}'.toLowerCase();
      return key.contains('patterniha');
    } catch (_) {
      return false;
    }
  }

  /// بنر انتخاب Tor برای ویجتِ در انتظار
  Widget _buildWidgetPickerBanner() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.accent.withOpacity(0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.accent),
      ),
      child: Row(
        children: [
          Icon(Icons.widgets, color: AppColors.accent, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _t(
                'یک سرور از لیست انتخاب کنید، یا Tor را برای این ویجت فعال کنید',
                'Pick a server from the list, or use Tor for this widget',
              ),
              style: TextStyle(color: AppColors.fg(context), fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  /// کپی دسته‌ای انتخاب‌شده‌ها.
  Future<void> _bulkCopy(String mode) async {
    final selected = _servers
        .where((s) => _selectedIds.contains(s.id))
        .toList();
    if (selected.isEmpty) {
      _showMsg(_t('چیزی انتخاب نشده', 'Nothing selected'));
      return;
    }

    final copyable = <VpnServer>[];
    var blockedCount = 0;
    for (final s in selected) {
      final isCustom = _customServers.any((c) => c.id == s.id);
      if (isCustom || s.isAether || s.isPsiphon) {
        copyable.add(s);
      } else {
        blockedCount++;
      }
    }

    if (copyable.isEmpty) {
      _showMsg(_t('سرور های داخل برنامه قابل کپی برداری نمی باشد',
          'Built-in servers cannot be copied'));
      setState(() {
        _selectionMode = false;
        _selectedIds.clear();
      });
      return;
    }

    String payload;
    switch (mode) {
      case 'names':
        payload = copyable.map((s) => s.displayName).join('\n');
        break;
      case 'json':
        final list = copyable.map((s) => <String, dynamic>{
              'name': s.displayName,
              'protocol': s.protocol.name,
              'flag': s.flag,
              'host': s.host,
              'port': s.port,
              'shareLink': s.shareLink,
            }).toList();
        payload = const JsonEncoder.withIndent('  ').convert(list);
        break;
      case 'links':
      default:
        payload = copyable.map((s) => s.shareLink).join('\n');
        break;
    }

    await Clipboard.setData(ClipboardData(text: payload));
    if (!mounted) return;
    _showMsg(_t(
      '${copyable.length} مورد کپی شد${blockedCount > 0 ? " ($blockedCount نامعتبر رد شد)" : ""}',
      '${copyable.length} copied${blockedCount > 0 ? " ($blockedCount skipped)" : ""}',
    ));
    setState(() {
      _selectionMode = false;
      _selectedIds.clear();
    });
  }

  Future<void> _addSelectedToGroup() async {
    await _openGroupMembersEditor();
  }

  Future<void> _openGroupMembersEditor() async {
    final allServers = <VpnServer>[
      ..._customServers,
      ...widget.extraServers,
    ];
    if (allServers.isEmpty) {
      _showMsg(_t('سروری برای گروه‌بندی نیست', 'No servers to group'));
      return;
    }

    // انتخاب اولیه: اگه کاربر قبلاً چند سرور رو انتخاب کرده بود،
    // به‌عنوان پیش‌فرض tick بزن. وگرنه اگه گروهی وجود داره، اولین
    // گروه رو باز کن.
    final preselected = Set<String>.from(_selectedIds);
    String? selectedGroup = (preselected.isEmpty && _userGroupsOrder.isNotEmpty)
        ? _userGroupsOrder.first
        : null;
    String newGroupName = '';
    final editingIds = <String>{...preselected};
    if (selectedGroup != null) {
      editingIds.clear();
      editingIds.addAll(_userGroups[selectedGroup] ?? const <String>[]);
    }

    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface(context),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (bsCtx) {
        return StatefulBuilder(builder: (sCtx, setLocal) {
          Future<void> save() async {
            final name = selectedGroup ?? newGroupName.trim();
            if (name.isEmpty) {
              _showMsg(_t('اسم گروه رو وارد کن', 'Enter group name'));
              return;
            }
            final updated = <String, List<String>>{};
            _userGroups.forEach((k, v) => updated[k] = List<String>.from(v));
            updated[name] = editingIds.toList();
            final order = List<String>.from(_userGroupsOrder);
            if (!order.contains(name)) order.add(name);
            await prefs.setString(_userGroupsKey, jsonEncode(updated));
            await prefs.setStringList(_userGroupsOrderKey, order);
            if (!mounted) return;
            setState(() {
              _userGroups = updated;
              _userGroupsOrder = order;
              _selectionMode = false;
              _selectedIds.clear();
            });
            _rebuildServerList();
            if (sCtx.mounted) Navigator.pop(sCtx);
            _showMsg(_t('$name: ${editingIds.length} سرور',
                '$name: ${editingIds.length} servers'));
          }

          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.folder_outlined,
                          color: AppColors.accent),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _t('مدیریت اعضای گروه', 'Edit group members'),
                          style: TextStyle(
                              color: AppColors.fg(sCtx),
                              fontSize: 16,
                              fontWeight: FontWeight.w700),
                        ),
                      ),
                      IconButton(
                        icon: Icon(Icons.close,
                            color: AppColors.muted2(sCtx)),
                        onPressed: () => Navigator.pop(sCtx),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _t('گروه رو انتخاب کن یا جدید بساز',
                        'Pick a group or create new'),
                    style: TextStyle(
                        color: AppColors.muted2(sCtx), fontSize: 11),
                  ),
                  const SizedBox(height: 8),
                  // ---- chip ها ----
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: <Widget>[
                      ..._userGroupsOrder
                          .where((g) => _userGroups.containsKey(g))
                          .map((g) => ChoiceChip(
                                label: Text(g),
                                selected: selectedGroup == g,
                                selectedColor:
                                    AppColors.accent.withOpacity(0.25),
                                labelStyle: TextStyle(
                                    color: selectedGroup == g
                                        ? AppColors.accent
                                        : AppColors.fg(sCtx),
                                    fontSize: 12),
                                onSelected: (_) {
                                  setLocal(() {
                                    selectedGroup = g;
                                    editingIds.clear();
                                    editingIds.addAll(
                                        _userGroups[g] ?? const <String>[]);
                                  });
                                },
                              )),
                      ChoiceChip(
                        label: Text(_t('+ گروه جدید', '+ New group')),
                        selected: selectedGroup == null,
                        selectedColor:
                            AppColors.accent.withOpacity(0.25),
                        labelStyle: TextStyle(
                            color: selectedGroup == null
                                ? AppColors.accent
                                : AppColors.fg(sCtx),
                            fontSize: 12),
                        onSelected: (_) {
                          setLocal(() {
                            selectedGroup = null;
                            editingIds.clear();
                          });
                        },
                      ),
                    ],
                  ),
                  if (selectedGroup == null) ...[
                    const SizedBox(height: 8),
                    TextField(
                      onChanged: (v) => newGroupName = v,
                      style: TextStyle(color: AppColors.fg(sCtx)),
                      decoration: InputDecoration(
                        labelText: _t('نام گروه جدید', 'New group name'),
                        labelStyle:
                            TextStyle(color: AppColors.muted2(sCtx)),
                        filled: true,
                        fillColor: AppColors.bg(sCtx),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 10),
                  // ---- انتخاب سرور ----
                  Row(
                    children: [
                      Text(
                        _t('انتخاب سرورها', 'Select servers'),
                        style: TextStyle(
                            color: AppColors.muted(sCtx),
                            fontSize: 12,
                            fontWeight: FontWeight.w600),
                      ),
                      const Spacer(),
                      Text(
                        '${editingIds.length}/${allServers.length}',
                        style: TextStyle(
                            color: AppColors.accent, fontSize: 12),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Flexible(
                    child: Container(
                      constraints: const BoxConstraints(maxHeight: 320),
                      decoration: BoxDecoration(
                        color: AppColors.bg(sCtx),
                        borderRadius: BorderRadius.circular(10),
                        border:
                            Border.all(color: AppColors.border(sCtx)),
                      ),
                      child: ListView.builder(
                        shrinkWrap: true,
                        itemCount: allServers.length,
                        itemBuilder: (_, i) {
                          final s = allServers[i];
                          return CheckboxListTile(
                            dense: true,
                            controlAffinity:
                                ListTileControlAffinity.leading,
                            activeColor: AppColors.accent,
                            value: editingIds.contains(s.id),
                            title: Text(
                              s.displayName,
                              style: TextStyle(
                                  color: AppColors.fg(sCtx),
                                  fontSize: 13),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: Text(
                              s.host,
                              style: TextStyle(
                                  color: AppColors.muted2(sCtx),
                                  fontSize: 10),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            onChanged: (v) {
                              setLocal(() {
                                if (v == true) {
                                  editingIds.add(s.id);
                                } else {
                                  editingIds.remove(s.id);
                                }
                              });
                            },
                          );
                        },
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  // FIX: بخش افزودن کانفیگ مستقیم به گروه (مثل سابسکریپشن‌ها)
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppColors.bg(sCtx),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AppColors.border(sCtx)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _t('افزودن کانفیگ مستقیم (vless/vmess/trojan/ss/hysteria2 یا JSON)',
                              'Add config (vless/vmess/trojan/ss/hysteria2 or JSON)'),
                          style: TextStyle(
                              color: AppColors.muted(sCtx), fontSize: 11),
                        ),
                        const SizedBox(height: 6),
                        TextField(
                          controller: _groupConfigCtrl,
                          maxLines: 3,
                          style: TextStyle(
                              color: AppColors.fg(sCtx), fontSize: 12),
                          decoration: InputDecoration(
                            hintText: 'vless://...\nvmess://...',
                            hintStyle: TextStyle(
                                color: AppColors.muted2(sCtx),
                                fontSize: 11),
                            filled: true,
                            fillColor: AppColors.surface(sCtx),
                            contentPadding: const EdgeInsets.all(8),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Align(
                          alignment: AlignmentDirectional.centerEnd,
                          child: TextButton.icon(
                            onPressed: () async {
                              final text = _groupConfigCtrl.text.trim();
                              if (text.isEmpty) {
                                _showMsg(_t('چیزی وارد نشده', 'Nothing pasted'));
                                return;
                              }
                              final links = LinkParser.extractLinks(text);
                              if (links.isEmpty && !XrayJson.looksLike(text)) {
                                _showMsg(_t('لینک معتبری پیدا نشد',
                                    'No valid link found'));
                                return;
                              }
                              int added = 0;
                              final stamp = DateTime.now()
                                  .millisecondsSinceEpoch;
                              if (XrayJson.looksLike(text)) {
                                final srv = XrayJson.parse(text,
                                    id: 'custom_${stamp}_grp');
                                if (srv != null) {
                                  _customServers.insert(0, srv);
                                  editingIds.add(srv.id);
                                  added++;
                                }
                              } else {
                                for (var i = 0; i < links.length; i++) {
                                  final srv = LinkParser.parse(
                                      links[i], id: 'custom_${stamp}_g$i');
                                  if (srv == null) continue;
                                  _customServers.insert(0, srv);
                                  editingIds.add(srv.id);
                                  added++;
                                }
                              }
                              if (added > 0) {
                                await _saveCustomServers();
                                _groupConfigCtrl.clear();
                              }
                              if (sCtx.mounted) {
                                setLocal(() {});
                                _showMsg(added > 0
                                    ? _t('$added کانفیگ اضافه شد',
                                        '$added config(s) added')
                                    : _t('افزودن ناموفق',
                                        'Failed to add'));
                              }
                            },
                            icon: const Icon(Icons.add,
                                color: AppColors.accent, size: 16),
                            label: Text(_t('افزودن', 'Add'),
                                style: const TextStyle(
                                    color: AppColors.accent, fontSize: 12)),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton.icon(
                      onPressed: save,
                      icon: const Icon(Icons.save_outlined),
                      label: Text(_t('ذخیره', 'Save')),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.accent,
                        foregroundColor: Colors.black,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        });
      },
    );
  }

  Future<void> _unused_oldAddToGroup() async {
    final ids = _selectedIds.toList();
    if (ids.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    final groupsRaw = prefs.getString('server_groups_v1') ?? '{}';
    Map<String, dynamic> groups;
    try {
      final decoded = jsonDecode(groupsRaw);
      groups = decoded is Map ? Map<String, dynamic>.from(decoded) : {};
    } catch (_) {
      groups = {};
    }
    if (!mounted) return;
    final ctrl = TextEditingController();
    try {
    final groupName = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface(ctx),
        title: Text(_t('افزودن به گروه', 'Add to group'),
            style: TextStyle(color: AppColors.fg(ctx))),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (groups.isNotEmpty)
              ...groups.keys.map((name) => ListTile(
                    dense: true,
                    title: Text(name,
                        style: TextStyle(color: AppColors.fg(ctx))),
                    onTap: () => Navigator.pop(ctx, name),
                  )),
            TextField(
              controller: ctrl,
              style: TextStyle(color: AppColors.fg(ctx)),
              decoration: InputDecoration(
                labelText: _t('یا گروه جدید', 'Or new group'),
                labelStyle: TextStyle(color: AppColors.muted2(ctx)),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: const Text('OK'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(_t('انصراف', 'Cancel')),
          ),
        ],
      ),
    );
    ctrl.dispose();
    if (groupName == null || groupName.isEmpty) return;
    final existing = (groups[groupName] as List?)?.cast<String>() ?? [];
    final merged = {...existing, ...ids}.toList();
    groups[groupName] = merged;
    await prefs.setString(_userGroupsKey, jsonEncode(groups));
    if (!mounted) return;
    final newGroups = <String, List<String>>{};
    groups.forEach((k, v) {
      if (v is List) {
        newGroups[k.toString()] = v.map((e) => e.toString()).toList();
      }
    });
    final newOrder = List<String>.from(_userGroupsOrder);
    if (!newOrder.contains(groupName)) newOrder.add(groupName);
    await prefs.setStringList(_userGroupsOrderKey, newOrder);
    setState(() {
      _userGroups = newGroups;
      _userGroupsOrder = newOrder;
      _selectionMode = false;
      _selectedIds.clear();
    });
    _showMsg(_t('$groupName: ${merged.length} سرور',
        '$groupName: ${merged.length} servers'));
    } finally {
      ctrl.dispose();
    }
  }

  Future<void> _openTorBridgePickerForWidget(int widgetId) async {
    String? defaultMode;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('widget_server_$widgetId') ?? '';
      final parts = raw.split('|');
      if (parts.length >= 2 && parts[0] == 'tor' && parts[1].isNotEmpty) {
        defaultMode = parts[1];
      }
    } catch (_) {}

    if (!mounted) return;
    final mode = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: AppColors.surface(context),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(14),
              child: Text(
                widget.language == 'fa'
                    ? 'نوع اتصال Tor را انتخاب کنید'
                    : 'Choose Tor mode',
                style: TextStyle(
                  color: AppColors.fg(ctx),
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            for (final m in const [
              ['vanilla', 'ساده (بدون پل)', 'Vanilla (no bridge)'],
              ['obfs4', 'obfs4', 'obfs4'],
              ['snowflake', 'Snowflake (P2P)', 'Snowflake (P2P)'],
              ['meek_lite', 'Meek / Azure', 'Meek / Azure'],
              ['webtunnel', 'WebTunnel', 'WebTunnel'],
            ])
              ListTile(
                leading: Icon(
                  m[0] == defaultMode
                      ? Icons.radio_button_checked
                      : Icons.radio_button_off,
                  color: AppColors.accent,
                ),
                title: Text(
                  widget.language == 'fa' ? m[1] : m[2],
                  style: TextStyle(color: AppColors.fg(ctx)),
                ),
                onTap: () => Navigator.pop(ctx, m[0]),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (mode == null || !mounted) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('widget_server_$widgetId', 'tor|$mode|Tor');
    } catch (_) {}
    final presetId = 'widget_tor_$widgetId';
    await TorSessionService.instance.connectWithType(presetId, mode);
    if (!mounted) return;
    setState(() => _pendingWidgetId = null);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(_t(
          'این تور برای ویجت انتخاب شد',
          'Tor selected for widget',
        )),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Widget _buildPatternihaBanner() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFF3A2A00),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF8A6A00)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline, color: Color(0xFFFFB300), size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _t(
                'سرورهای این اشتراک فقط یوتیوب، ایکس و بیشتر وب‌سایت‌های معمولی را باز می‌کنند. اینستاگرام، تیک‌تاک، تلگرام و واتساپ از طریق این سرورها کار نمی‌کنند.',
                'These servers only work for YouTube, X and most regular websites. Instagram, TikTok, Telegram and WhatsApp will NOT work.',
              ),
              style: const TextStyle(
                color: Color(0xFFFFD54F),
                fontSize: 11.5,
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget build(BuildContext context) {
    return Scaffold(
      bottomNavigationBar: _selectionMode
          ? SafeArea(
              child: Container(
                color: AppColors.elevated(context),
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                child: Row(
                  children: [
                    _compactIconButton(
                      icon: Icons.close,
                      tooltip: _t('انصراف', 'Cancel'),
                      onPressed: () => setState(() {
                        _selectionMode = false;
                        _selectedIds.clear();
                      }),
                    ),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: Text(
                          '${_selectedIds.length} ${_t('مورد', 'selected')}',
                          style: TextStyle(
                            color: AppColors.fg(context),
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                    PopupMenuButton<String>(
                      icon: Icon(Icons.copy,
                          color: AppColors.fg(context), size: 20),
                      tooltip: _t('کپی', 'Copy'),
                      color: AppColors.surface(context),
                      onSelected: (mode) => _bulkCopy(mode),
                      itemBuilder: (bCtx) => <PopupMenuEntry<String>>[
                        PopupMenuItem(
                          value: 'links',
                          child: Row(children: [
                            Icon(Icons.link,
                                size: 16, color: AppColors.fg(bCtx)),
                            const SizedBox(width: 8),
                            Text(_t('لینک‌های اشتراک', 'Share links'),
                                style: TextStyle(color: AppColors.fg(bCtx))),
                          ]),
                        ),
                        PopupMenuItem(
                          value: 'names',
                          child: Row(children: [
                            Icon(Icons.label_outline,
                                size: 16, color: AppColors.fg(bCtx)),
                            const SizedBox(width: 8),
                            Text(_t('نام سرورها', 'Server names'),
                                style: TextStyle(color: AppColors.fg(bCtx))),
                          ]),
                        ),
                        PopupMenuItem(
                          value: 'json',
                          child: Row(children: [
                            Icon(Icons.data_object,
                                size: 16, color: AppColors.fg(bCtx)),
                            const SizedBox(width: 8),
                            Text(_t('JSON کامل', 'Full JSON'),
                                style: TextStyle(color: AppColors.fg(bCtx))),
                          ]),
                        ),
                      ],
                    ),
                    _compactIconButton(
                      icon: Icons.folder_special,
                      tooltip: _t('افزودن به گروه', 'Add to group'),
                      onPressed: _addSelectedToGroup,
                    ),
                    _compactIconButton(
                      icon: Icons.push_pin,
                      tooltip: _t('پین', 'Pin'),
                      onPressed: () {
                        for (final s in _servers) {
                          if (_selectedIds.contains(s.id)) {
                            _pinnedIds.add(s.id);
                          }
                        }
                        setState(() {
                          _selectionMode = false;
                          _selectedIds.clear();
                        });
                        _rebuildServerList();
                        _savePinned();
                      },
                    ),
                    _compactIconButton(
                      icon: Icons.speed,
                      tooltip: _t('تست', 'Test'),
                      onPressed: () async {
                        final targets = _servers
                            .where((s) => _selectedIds.contains(s.id))
                            .toList();
                        setState(() {
                          _selectionMode = false;
                          _selectedIds.clear();
                        });
                        for (final s in targets) {
                          await ServerTester.testOne(s, session: TestSession());
                          if (mounted) setState(() {});
                        }
                      },
                    ),
                    _compactIconButton(
                      icon: Icons.delete_outline,
                      tooltip: _t('حذف', 'Delete'),
                      color: AppColors.danger,
                      onPressed: () {
                        final ids = _selectedIds.toSet();
                        setState(() {
                          _servers.removeWhere((s) => ids.contains(s.id) && s.isDeletable);
                          _customServers.removeWhere((s) => ids.contains(s.id));
                          _selectionMode = false;
                          _selectedIds.clear();
                        });
                      },
                    ),
                  ],
                ),
              ),
            )
          : null,

      backgroundColor: AppColors.bg(context),
      body: SafeArea(
        child: Column(
          children: [
            _buildTopBar(),
            const SizedBox(height: 4),
            _buildSubTabs(),
            if (_pendingWidgetId != null) ...[
              const SizedBox(height: 6),
              _buildWidgetPickerBanner(),
            ],
            if (_isPatternihaActive()) ...[
              const SizedBox(height: 6),
              _buildPatternihaBanner(),
            ],
            const SizedBox(height: 8),
            for (final t in _torPresets())
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: _buildTorTile(t),
              ),
            const SizedBox(height: 4),
            _buildServerList(),
          ],
        ),
      ),
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          FloatingActionButton(
            heroTag: 'connect_fab',
            onPressed: _connecting ? null : _toggleConnection,
            backgroundColor: _connected
                ? AppColors.accent
                : AppColors.elevated(context),
            child: _connecting
                ? const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      color: AppColors.accent,
                    ),
                  )
                : Icon(
                    _connected ? Icons.shield : Icons.power_settings_new,
                    color:
                        _connected ? Colors.black : AppColors.accent,
                    size: 24,
                  ),
          ),
          const SizedBox(height: 10),
          FloatingActionButton(
            heroTag: 'add_fab',
            onPressed: _openAddConfig,
            backgroundColor: AppColors.accent,
            child: const Icon(Icons.add, color: Colors.black),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _autoFastestTimer?.cancel();
    _widgetTimerRefresh?.cancel();
    try {
      WarpMasqueService.scanProgress.removeListener(_onMasqueScanProgress);
    } catch (_) {}
    try {
      WarpEndpointHealthMonitor.instance.onDegraded = null;
      WarpEndpointHealthMonitor.instance.onRecovered = null;
      WarpEndpointHealthMonitor.instance.stop();
    } catch (_) {}
    try {
      WarpScoutScheduler.instance.onRescanNeeded = null;
      WarpScoutScheduler.instance.serversProvider = null;
    } catch (_) {}
    try {
      QualityAlert.instance.onLowQuality = null;
      QualityAlert.instance.onRecovered = null;
    } catch (_) {}
    _qualityMonitor.reset();
    ConnectivityWatcher.instance.stop();
    try {
      TorSessionService.instance.routingCount
          .removeListener(_onTorRoutingChanged);
    } catch (_) {}
    try {
      TunnelSessionService.instance.routingCount
          .removeListener(_onTunnelRoutingChanged);
    } catch (_) {}
    try {
      SshSessionService.instance.routingCount
          .removeListener(_onSshRoutingChanged);
    } catch (_) {}
    try {
      MasterDnsSessionService.instance.routingCount
          .removeListener(_onMasterDnsRoutingChanged);
    } catch (_) {}
    try {
      WarpMasqueSessionService.instance.routingCount
          .removeListener(_onWarpMasqueRoutingChanged);
    } catch (_) {}
    WidgetsBinding.instance.removeObserver(this);
    _pollTimer?.cancel();
    _session?.cancel();
    _groupConfigCtrl.dispose();
    _searchController.dispose();
    _listScrollController.dispose();
    super.dispose();
  }
}
