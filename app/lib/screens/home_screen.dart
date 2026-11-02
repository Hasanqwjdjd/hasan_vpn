import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/server.dart';
import '../models/subscription.dart';
import '../models/aether_profile.dart';
import '../services/aether_service.dart';
import '../services/announcement_service.dart';
import '../services/app_colors.dart';
import '../services/server_tester.dart';
import '../services/settings_service.dart';
import '../services/exit_ip_service.dart';
import '../services/link_parser.dart';
import '../services/psiphon_service.dart';
import '../services/v2ray_engine.dart';
import '../services/widget_connect_handler.dart';
import '../widgets/server_tile.dart';
import 'add_config_screen.dart';
import 'announcements_screen.dart';
import 'tor_screen.dart';
import 'qr_share_screen.dart';

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
  static const String _deletedKeysKey = 'deleted_server_keys_v1';
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

  /// اثر انگشت (هش) لینک سرورهای حذف‌شده. شناسهٔ سرورهای اشتراک بین «کش» و
  /// «دانلود تازه» ممکن است فرق کند؛ هش لینک همیشه یکی است.
  Set<String> _deletedLinkKeys = <String>{};

  String _linkKey(VpnServer s) => LinkParser.stableId('del', s.shareLink);

  bool _isDeleted(VpnServer s) =>
      _deletedIds.contains(s.id) || _deletedLinkKeys.contains(_linkKey(s));
  Set<String> _pinnedIds = <String>{};
  List<String> _manualOrder = <String>[];

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
  bool _sortAscending = true;
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
    _ui(() => _pendingWidgetId = widgetId);
    // Scaffold ممکن است هنوز کامل mount نشده باشد (به‌خصوص در cold start)؛
    // نمایش SnackBar را به بعد از فریم جاری موکول می‌کنیم.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_t(
            'سرور این ویجت را انتخاب کنید',
            'Choose the server for this widget',
          )),
          duration: const Duration(seconds: 5),
        ),
      );
    });
  }

  // ---- انتخاب چندتایی ----
  bool _selectMode = false;
  final Set<String> _checked = <String>{};

  // ---- throttle بازسازی UI (همهٔ تغییرات پس‌زمینه از این مسیر می‌گذرند) ----
  Timer? _uiTimer;
  bool _uiDirty = false;
  bool _uiNeedsSort = false;

  void _requestRebuild({bool sort = false}) {
    if (!mounted) return;
    if (sort) _uiNeedsSort = true;
    _uiDirty = true;
    if (_uiTimer != null) return;
    _flushRebuild();
    _uiTimer = Timer.periodic(const Duration(milliseconds: 150), (t) {
      if (!mounted || !_uiDirty) {
        t.cancel();
        _uiTimer = null;
        return;
      }
      _flushRebuild();
    });
  }

  void _flushRebuild() {
    if (!mounted) return;
    _uiDirty = false;
    if (_uiNeedsSort) {
      _uiNeedsSort = false;
      _sortCurrentServers();
      _servers = List<VpnServer>.from(_servers);
    }
    setState(() {});
  }

  /// تغییر state بدون بازسازی فوری؛ بازسازی‌ها حداکثر هر ۱۵۰ms یک بار.
  void _ui(VoidCallback change) {
    if (!mounted) return;
    change();
    _requestRebuild();
  }

  Future<void> _safe(Future<void> Function() step) async {
    try {
      await step();
    } catch (e) {
      debugPrint('home bootstrap step failed: $e');
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    await _safe(_loadDeletedAndPinned);
    await _safe(_loadCustomServers);
    await _safe(_loadCustomSubTags);
    await _safe(_loadServerNameOverrides);
    await _safe(_loadManualOrder);
    if (!mounted) return;
    _rebuildServerList();
    await _safe(_loadPings);
    await _safe(_loadLastServer);
    await _safe(V2RayEngine.init);
    await _safe(V2RayEngine.loadDelayUrl);
    if (!mounted) return;
    _pollTimer = Timer.periodic(const Duration(seconds: 4), (_) => _poll());
    // ویجت صفحهٔ اصلی: درخواست معلق اتصال
    WidgetConnectHandler.listen(
      (req) {
        // ignore: unawaited_futures
        _handleWidgetRequest(req);
      },
      onNeedsServer: (widgetId) => _activateWidgetSelection(widgetId),
    );
    try {
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
    } catch (e) {
      debugPrint('widget bootstrap failed: $e');
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
        'سرور ویجت پیدا نشد؛ دوباره آن را پین کنید',
        'Widget server not found — pin again from the app',
      ));
      return;
    }
    final server = _servers[idx];
    _ui(() => _selected = server);
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
      if (mounted) _ui(() {});
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
        server.nameOverride = ov;
      }
    }
  }

  Future<void> _editServerName(VpnServer server) async {
    // Aether / Oblivion: فرم کامل تنظیمات
    if (server.isAether) {
      await _editAetherServer(server);
      return;
    }
    final ctrl = TextEditingController(text: server.displayName);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.elevated(ctx),
        title: Text(_t('ویرایش نام سرور', 'Edit server name'),
            style: TextStyle(color: AppColors.fg(ctx))),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          style: TextStyle(color: AppColors.fg(ctx)),
          decoration: InputDecoration(
            labelText: _t('نام جدید', 'New name'),
            labelStyle: TextStyle(color: AppColors.muted(ctx)),
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
            child: Text(_t('ذخیره', 'Save'),
                style: const TextStyle(color: AppColors.accent)),
          ),
        ],
      ),
    );
    if (ok != true) return;

    final newName = ctrl.text.trim();
    if (newName.isEmpty) return;

    await SettingsService.setServerNameOverride(server.id, newName);
    if (!mounted) return;
    _ui(() {
      server.nameOverride = newName;
    });
  }

  Future<void> _editAetherServer(VpnServer server) async {
    final profile = AetherProfile.fromLink(server.shareLink);
    var protocol = profile.protocol;
    var scan = profile.scan;
    var noize = profile.noize;
    var ip = profile.ip;
    final nameCtrl = TextEditingController(text: server.displayName);
    final peerCtrl = TextEditingController(text: profile.peer);
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
                        labelText: _t('نام / توضیح', 'Remark / name'),
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
      nameOverride: newName.isNotEmpty ? newName : null,
    );
    final idx = _customServers.indexWhere((s) => s.id == server.id);
    if (idx >= 0) {
      _customServers[idx] = next;
      await _saveCustomServers();
    } else if (newName.isNotEmpty) {
      await SettingsService.setServerNameOverride(server.id, newName);
    }
    if (!mounted) return;
    _ui(() {
      final si = _servers.indexWhere((s) => s.id == server.id);
      if (si >= 0) _servers[si] = next;
      if (_selected?.id == server.id) _selected = next;
      if (_active?.id == server.id) _active = next;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(_t('تنظیمات Aether ذخیره شد', 'Aether saved'))),
    );
  }

  // ----------------------------------------------------- last server

  Future<void> _loadLastServer() async {
    final id = await SettingsService.getLastServer();
    if (id == null) return;
    final idx = _servers.indexWhere((s) => s.id == id);
    if (idx >= 0 && mounted) {
      _ui(() => _selected = _servers[idx]);
    }
  }

  Future<void> _jumpToSelected() async {
    final selected = _selected;
    if (selected == null) {
      _showMsg(_t('هیچ سروری انتخاب نشده', 'No server selected'));
      return;
    }
    final idx = _servers.indexWhere((s) => s.id == selected.id);
    if (idx == -1) {
      _showMsg(_t('سرور انتخاب‌شده در لیست نیست', 'Selected server is not in list'));
      return;
    }

    _ui(() => _selected = selected);

    final key = _tileKeys.putIfAbsent(selected.id, () => GlobalKey());
    final ctx = key.currentContext;
    if (ctx != null) {
      await Scrollable.ensureVisible(
        ctx,
        duration: const Duration(milliseconds: 420),
        curve: Curves.easeOutCubic,
        alignment: 0.15,
      );
      if (mounted) _ui(() => _selected = selected);
      return;
    }

    if (!_listScrollController.hasClients) return;
    final approx = ((idx + 1) * 78.0)
        .clamp(0.0, _listScrollController.position.maxScrollExtent);
    await _listScrollController.animateTo(
      approx,
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOut,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx2 = key.currentContext;
      if (ctx2 != null && mounted) {
        Scrollable.ensureVisible(
          ctx2,
          duration: const Duration(milliseconds: 280),
          curve: Curves.easeOutCubic,
          alignment: 0.15,
        );
        Future.delayed(const Duration(milliseconds: 400), () {
          if (mounted) _ui(() => _selected = selected);
        });
      }
    });
  }

  // ------------------------------------------------------------- loading

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
    _deletedLinkKeys =
        (prefs.getStringList(_deletedKeysKey) ?? <String>[]).toSet();
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
  }

  Future<void> _saveDeleted() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_deletedKey, jsonEncode(_deletedIds.toList()));
    await prefs.setStringList(_deletedKeysKey, _deletedLinkKeys.toList());
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

  Future<void> _loadManualOrder() async {
    final prefs = await SharedPreferences.getInstance();
    _manualOrder = List<String>.of(prefs.getStringList(_orderKey) ?? <String>[]);
  }

  Future<void> _saveManualOrder() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_orderKey, _manualOrder);
  }

  Future<void> _onReorder(int oldIndex, int newIndex) async {
    if (newIndex > oldIndex) newIndex -= 1;
    _ui(() {
      final item = _servers.removeAt(oldIndex);
      _servers.insert(newIndex, item);
      _manualOrder = _servers.map((s) => s.id).toList();
    });
    await _saveManualOrder();
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
      var alive = V2RayEngine.isConnected;
      if (alive && _active?.isAether == true) {
        alive = await AetherService.syncStatus();
      }
      if (!mounted) return;
      if (alive && !_connected) {
        _ui(() {
          _connected = true;
          if (_active == null && _selected != null) _active = _selected;
          _status = _t('متصل', 'Connected');
        });
      } else if (!alive && _connected) {
        _markDisconnected(_t('اتصال قطع شد', 'Connection lost'));
      }
    } catch (_) {}
  }

  // ------------------------------------------------------------- list

  void _rebuildServerList() {
    if (!mounted) return;

    final allServers = <VpnServer>[
      ..._customServers.where((server) => !_isDeleted(server)),
      ...widget.extraServers.where((server) => !_isDeleted(server)),
    ];

    for (final server in allServers) {
      server.isPinned = _pinnedIds.contains(server.id);
    }

    var list = allServers;
    if (_selectedSubId != null) {
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
        final ai = pos[a.id] ?? 9999999;
        final bi = pos[b.id] ?? 9999999;
        if (ai != bi) return ai.compareTo(bi);
        return 0;
      });
    } else {
      _sortCurrentServers();
    }
    _requestRebuild();
  }

  void _selectSubscription(String? subId) {
    _ui(() => _selectedSubId = subId);
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
    _ui(() {
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
          'ویجت به "${server.displayName}" وصل شد — از این پس بدون باز کردن برنامه وصل می‌شود',
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

  void _sortCurrentServers() {
    ServerTester.sortServers(_servers, descending: !_sortAscending);
  }

  void _cancelTesting() {
    if (!mounted) return;
    _session?.cancel();
    _ui(() {
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

  Future<void> _testAll() async {
    if (_testing || _servers.isEmpty) return;
    final targets =
        _servers.where((s) => !s.isAether && !s.isPsiphon).toList();
    if (targets.isEmpty) {
      _showMsg(_t('سروری برای تست نیست', 'Nothing to test'));
      return;
    }
    if (_connected && _active?.isAether != true && _active?.isPsiphon != true) {
      _showMsg(_t(
        'اتصال برقرار است؛ پینگ از داخل همین تونل سنجیده می‌شود.',
        'You are connected; pings are measured through the current tunnel.',
      ));
    }

    final session = TestSession();
    _session = session;

    _ui(() {
      _testing = true;
      _tested = 0;
      _total = targets.length;
      _status = _t('در حال تست...', 'Real testing...');
      for (final server in targets) {
        server.resetPing();
      }
    });

    final summary = await ServerTester.testAll(
      targets,
      session: session,
      onServerDone: (_) {
        if (!mounted || session.cancelled) return;
        _tested++;
        _requestRebuild();
      },
      onChanged: () {
        if (!mounted || session.cancelled) return;
        _requestRebuild(sort: true);
      },
    );

    if (!mounted || session.cancelled) return;
    _sortCurrentServers();
    await _savePings();

    _ui(() {
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
          ' · پینگ واقعی پشتیبانی نمی‌شود',
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

  Future<void> _persistServerState() async {
    try {
      await _saveDeleted();
      await _saveCustomServers();
      await _saveCustomSubTags();
      await _savePinned();
      await _saveManualOrder();
      await _savePings();
    } catch (e) {
      debugPrint('persist failed: $e');
    }
  }

  /// حذف دائمی: شناسه‌ها در لیست حذف‌شده‌ها ذخیره می‌شوند تا بعد از
  /// بستن برنامه یا به‌روزرسانی اشتراک برنگردند.
  Future<void> _removeServers(Iterable<VpnServer> servers) async {
    final list = servers.toList();
    if (list.isEmpty) return;
    final ids = list.map((s) => s.id).toSet();
    for (final s in list) {
      _deletedIds.add(s.id);
      _deletedLinkKeys.add(_linkKey(s));
    }
    _customServers.removeWhere((item) => ids.contains(item.id));
    for (final id in ids) {
      _customSubTags.remove(id);
      _pinnedIds.remove(id);
      _manualOrder.remove(id);
      _tileKeys.remove(id);
    }
    if (_selected != null && ids.contains(_selected!.id)) _selected = null;
    _rebuildServerList();
    await _persistServerState();
  }

  void _deleteServer(VpnServer server) => unawaited(_removeServers([server]));

  void _enterSelectMode() {
    _ui(() {
      _selectMode = true;
      _checked.clear();
    });
  }

  void _exitSelectMode() {
    _ui(() {
      _selectMode = false;
      _checked.clear();
    });
  }

  void _toggleChecked(VpnServer server) {
    if (!server.isDeletable) return;
    _ui(() {
      if (!_checked.add(server.id)) _checked.remove(server.id);
    });
  }

  void _checkAll() {
    _ui(() {
      final all = _servers.where((s) => s.isDeletable).map((s) => s.id);
      if (_checked.length == all.length) {
        _checked.clear();
      } else {
        _checked
          ..clear()
          ..addAll(all);
      }
    });
  }

  void _deleteChecked() {
    final targets = _servers.where((s) => _checked.contains(s.id)).toList();
    _selectMode = false;
    _checked.clear();
    if (targets.isEmpty) {
      _ui(() {});
      return;
    }
    unawaited(_removeServers(targets));
    _showMsg(_t('${targets.length} سرور حذف شد', '${targets.length} servers deleted'));
  }

  void _deleteDuplicates() {
    final seen = <String>{};
    final toDelete = <VpnServer>[];
    for (final s in _servers) {
      final key = s.shareLink.trim();
      if (!seen.add(key)) toDelete.add(s);
    }
    if (toDelete.isEmpty) {
      _showMsg(_t('سرور تکراری نیست', 'No duplicates'));
      return;
    }
    unawaited(_removeServers(toDelete));
    _showMsg(_t('${toDelete.length} سرور تکراری حذف شد',
        '${toDelete.length} duplicates deleted'));
  }

  void _deleteInvalid() {
    final toDelete = _servers
        .where((s) =>
            !s.isAether &&
            !s.isPsiphon &&
            s.ping == null &&
            s.status == ServerStatus.offline)
        .toList();
    if (toDelete.isEmpty) {
      _showMsg(_t('سرور آفلاین نیست', 'No offline servers'));
      return;
    }
    unawaited(_removeServers(toDelete));
    _showMsg(
        _t('${toDelete.length} سرور حذف شد', '${toDelete.length} servers deleted'));
  }

  Future<void> _disconnectAll() async {
    await AetherService.disconnect();
    await PsiphonService.stop();
    await V2RayEngine.disconnect();
  }

  void _markDisconnected(String status) {
    final wasConnected = _connected;
    _active = null;
    _livePing = null;
    _deadStrikes = 0;
    _pollTick = 0;
    _ui(() {
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
      var alive = V2RayEngine.isConnected;
      if (alive && active?.isAether == true) {
        alive = await AetherService.syncStatus();
      }
      if (!alive) {
        _deadStrikes++;
        if (_deadStrikes >= 2) {
          try {
            await _disconnectAll();
          } catch (_) {}
          _markDisconnected(_t('اتصال قطع شد', 'Connection lost'));
        }
        return;
      }
      _deadStrikes = 0;
      _pollTick++;
      if (_pollTick % 3 == 1) await _measureLive();
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
      if (info != null && force) {
        _showMsg(_t(
          'IP خروجی: ${info.ip}',
          'Exit IP: ${info.ip}',
        ));
      }
    } catch (e) {
      debugPrint('refreshExitIp: $e');
    }
  }

  /// پینگ زنده فقط برای سرورهای عادی؛ Psiphon و Aether هرگز خودکار تست نمی‌شوند.
  Future<void> _measureLive() async {
    if (!_connected || _connecting) return;
    final active = _active;
    if (active == null || active.isAether || active.isPsiphon) {
      if (_livePing != null) _ui(() => _livePing = null);
      return;
    }
    final result = await V2RayEngine.probeConnected();
    if (!mounted || !_connected) return;
    _ui(() {
      _livePing = result.ms;
      if (result.ok) {
        active.ping = result.ms;
        active.jitter = result.jitter;
        active.pingKind = PingKind.real;
        active.status = ServerStatus.online;
      }
    });
    await _savePings();
  }

  Future<void> _toggleConnection() async {
    if (_connecting) {
      _cancelConnect = true;
      _ui(() => _status = _t('در حال لغو...', 'Cancelling...'));
      return;
    }
    if (_connected) {
      _ui(() {
        _connecting = true;
        _status = _t('در حال قطع...', 'Disconnecting...');
      });
      try {
        await _disconnectAll();
      } catch (_) {}
      _markDisconnected(_t('آماده', 'Ready'));
      return;
    }
    final selected = _selected;
    if (selected == null) {
      _showMsg(_t('ابتدا یک سرور انتخاب کنید', 'Select a server first'));
      return;
    }
    _cancelConnect = false;
    _ui(() {
      _connecting = true;
      _livePing = null;
      _status = _t('در حال اتصال...', 'Connecting...');
    });

    try {
      final bool connected;
      final String? error;
      if (selected.isAether) {
        connected = await AetherService.connect(
          selected,
          isCancelled: () => _cancelConnect,
          onProgress: (message) {
            if (!mounted || _cancelConnect) return;
            _ui(() => _status = message.replaceAll('\n', ' · '));
          },
        );
        error = AetherService.lastError;
      } else if (selected.isPsiphon) {
        connected = await PsiphonService.connect(
          selected,
          isCancelled: () => _cancelConnect,
          onProgress: (message) {
            if (!mounted || _cancelConnect) return;
            _ui(() => _status = message.replaceAll('\n', ' · '));
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
      _ui(() {
        _connected = connected;
        _connecting = false;
        _active = connected ? selected : null;
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
        await Future<void>.delayed(const Duration(milliseconds: 800));
        await _measureLive();
        // نمایش IP خروجی از داخل تونل (الهام از ZedSecure)
        // ignore: unawaited_futures
        _refreshExitIp();
      }
    } catch (error) {
      if (!mounted) return;
      _ui(() {
        _connected = false;
        _connecting = false;
        _active = null;
        _status = _t('خطا در اتصال', 'Connection error');
      });
      debugPrint('Connection error: $error');
    }
  }

  Future<void> _copyAll() async {
    // فقط سرورهای خود کاربر (دستی یا از اشتراک خودش)؛ لینک سرورهای اشتراک
    // پیش‌فرض (رایگان برنامه) هرگز کپی نمی‌شود.
    final links = _servers
        .where((server) => server.isDeletable)
        .map((server) => server.shareLink)
        .where((link) => link.trim().isNotEmpty)
        .join('\n');
    if (links.isEmpty) {
      _showMsg(_t('لینکی برای کپی نیست', 'No links'));
      return;
    }
    await Clipboard.setData(ClipboardData(text: links));
    _showMsg(_t('همهٔ لینک‌ها کپی شد', 'All links copied'));
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
    _sortAscending = true;
    _manualOrder = [];
    // ignore: unawaited_futures
    _saveManualOrder();
    _sortCurrentServers();
    _ui(() => _servers = List<VpnServer>.from(_servers));
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
          onServerAdded: (server) {
            _customServers.insert(0, server);
            final revived = _deletedIds.remove(server.id) |
                _deletedLinkKeys.remove(_linkKey(server));
            if (revived) unawaited(_saveDeleted());
            // اگر سابسکریپشن خاصی انتخاب شده، سرور را به آن tag بزن
            if (_selectedSubId != null) {
              _customSubTags[server.id] = _selectedSubId!;
              _saveCustomSubTags();
            }
            _rebuildServerList();
            _saveCustomServers();
          },
        ),
      ),
    );
  }

  void _openSearch() => _ui(() => _showSearch = true);

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
                leading: const Icon(Icons.security, color: AppColors.accent),
                title: Text(_t('اتصال Tor', 'Tor Connection'),
                    style: TextStyle(color: AppColors.fg(context))),
                subtitle: Text(
                  _t('اتصال از طریق شبکه Tor', 'Connect via Tor network'),
                  style: TextStyle(color: AppColors.muted2(context), fontSize: 11),
                ),
                onTap: () {
                  Navigator.pop(sheetContext);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => TorScreen(language: widget.language),
                    ),
                  );
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
                leading: Icon(Icons.checklist, color: AppColors.muted(context)),
                title: Text(_t('انتخاب چندتایی', 'Select multiple'),
                    style: TextStyle(color: AppColors.fg(context))),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _enterSelectMode();
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
                title: Text(_t('کپی همهٔ لینک‌ها', 'Copy All Links'),
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

  Widget _buildSubTabs() {
    if (widget.subscriptions.isEmpty) return const SizedBox.shrink();

    final tabs = <Widget>[
      _subTab(null, _t('همه', 'All')),
      for (final sub in widget.subscriptions)
        _subTab(sub.id, sub.name, sub.serverCount),
    ];

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
          child: Text(
            count > 0 ? '$short ($count)' : short,
            style: TextStyle(
              color: active ? AppColors.accent : AppColors.fg(context),
              fontSize: 12.5,
              fontWeight: active ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(4, 6, 4, 4),
      child: Column(
        children: [
          Row(
            children: [
              IconButton(
                icon: Icon(Icons.menu,
                    color: AppColors.muted(context), size: 24),
                onPressed: _showMainMenu,
                tooltip: _t('منو', 'Menu'),
              ),
              Expanded(
                child: Column(
                  children: [
                    Text(
                      _isFa ? 'حسن' : 'Hasan',
                      style: TextStyle(
                        color: AppColors.fg(context),
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _status,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          color: AppColors.muted(context), fontSize: 11),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: Icon(Icons.my_location,
                    color: AppColors.accent, size: 22),
                onPressed: _jumpToSelected,
                tooltip: _t('یافتن انتخاب‌شده', 'Find selected'),
              ),
              IconButton(
                icon: Icon(
                  _sortAscending ? Icons.sort : Icons.sort_by_alpha,
                  color: AppColors.accent,
                  size: 22,
                ),
                onPressed: _toggleSort,
                tooltip: _t('مرتب‌سازی', 'Sort'),
              ),
              IconButton(
                icon: _testing
                    ? const Icon(Icons.stop_circle_outlined,
                        color: AppColors.danger, size: 22)
                    : const Icon(Icons.speed,
                        color: AppColors.accent, size: 22),
                onPressed: _testing ? _cancelTesting : _testAll,
                tooltip: _t('تست همه', 'Test All'),
              ),
              IconButton(
                icon: Icon(Icons.notifications_none,
                    color: AppColors.muted(context), size: 22),
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) =>
                          AnnouncementsScreen(language: widget.language),
                    ),
                  );
                },
                tooltip: _t('اعلان‌ها', 'Announcements'),
              ),
              IconButton(
                icon: Icon(Icons.settings,
                    color: AppColors.muted(context), size: 22),
                onPressed: widget.onOpenSettings,
                tooltip: _t('تنظیمات', 'Settings'),
              ),
            ],
          ),
          if (_showSearch)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _searchController,
                      autofocus: true,
                      style: TextStyle(
                          color: AppColors.fg(context), fontSize: 14),
                      decoration: InputDecoration(
                        hintText: _t('جستجو...', 'Search...'),
                        hintStyle:
                            TextStyle(color: AppColors.muted2(context)),
                        prefixIcon: Icon(Icons.search,
                            color: AppColors.muted(context), size: 20),
                        filled: true,
                        fillColor: AppColors.surface(context),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                      ),
                      onChanged: (value) {
                        _searchQuery = value;
                        _rebuildServerList();
                      },
                    ),
                  ),
                  IconButton(
                    icon:
                        Icon(Icons.close, color: AppColors.muted(context)),
                    onPressed: _closeSearch,
                  ),
                ],
              ),
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
                        child: Text(
                          '$_livePing ms',
                          style: const TextStyle(
                            color: AppColors.accent,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
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

  Widget _buildSelectBar() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: AppColors.surface(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border(context)),
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: _exitSelectMode,
            tooltip: _t('لغو', 'Cancel'),
            icon: Icon(Icons.close, color: AppColors.muted(context)),
          ),
          Expanded(
            child: Text(
              _t('${_checked.length} انتخاب‌شده', '${_checked.length} selected'),
              style: TextStyle(color: AppColors.fg(context), fontSize: 13),
            ),
          ),
          TextButton(
            onPressed: _checkAll,
            child: Text(_t('همه', 'All')),
          ),
          IconButton(
            onPressed: _checked.isEmpty ? null : _deleteChecked,
            tooltip: _t('حذف', 'Delete'),
            icon: Icon(
              Icons.delete_outline,
              color: _checked.isEmpty ? AppColors.muted2(context) : AppColors.danger,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildServerList() {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_selectMode) _buildSelectBar(),
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
            child: ReorderableListView.builder(
              scrollController: _listScrollController,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: _servers.length,
              onReorder: _onReorder,
              buildDefaultDragHandles: false,
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
                final tileKey =
                    _tileKeys.putIfAbsent(server.id, () => GlobalKey());
                return ReorderableDelayedDragStartListener(
                  key: ValueKey('reorder_${server.id}'),
                  index: index,
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: SizedBox(
                      height: 74,
                      child: RepaintBoundary(
                        child: ServerTile(
                        key: tileKey,
                        server: server,
                        selected: _selected?.id == server.id,
                        active: _connected && _active?.id == server.id,
                        onTap: () async {
                          if (_selectMode) {
                            _toggleChecked(server);
                            return;
                          }
                          // اگر در حالت انتخاب سرور برای ویجت هستیم، bind کن
                          if (_pendingWidgetId != null) {
                            await _handleWidgetServerSelection(server);
                            return;
                          }
                          _ui(() => _selected = server);
                          await SettingsService.setLastServer(server.id);
                        },
                        onDelete: server.isDeletable
                            ? () => _deleteServer(server)
                            : null,
                        onPin: () => _togglePin(server),
                        onShare: server.isDeletable
                            ? () => _shareServer(server)
                            : null,
                        onEdit: () => _editServerName(server),
                        selectMode: _selectMode,
                        checked: _checked.contains(server.id),
                        selectable: server.isDeletable,
                        ),
                      ),
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg(context),
      body: SafeArea(
        child: Column(
          children: [
            _buildTopBar(),
            const SizedBox(height: 4),
            _buildSubTabs(),
            const SizedBox(height: 8),
            _buildConnectButton(),
            const SizedBox(height: 12),
            _buildServerList(),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _openAddConfig,
        backgroundColor: AppColors.accent,
        child: const Icon(Icons.add, color: Colors.black),
      ),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pollTimer?.cancel();
    _uiTimer?.cancel();
    _session?.cancel();
    _searchController.dispose();
    _listScrollController.dispose();
    super.dispose();
  }
}
