import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/server.dart';
import '../models/subscription.dart';
import '../services/aether_service.dart';
import '../services/announcement_service.dart';
import '../services/app_colors.dart';
import '../services/server_tester.dart';
import '../services/settings_service.dart';
import '../services/exit_ip_service.dart';
import '../services/psiphon_service.dart';
import '../services/v2ray_engine.dart';
import '../widgets/server_tile.dart';
import 'add_config_screen.dart';
import 'announcements_screen.dart';
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

class _HomeScreenState extends State<HomeScreen> {
  static const String _deletedKey = 'deleted_server_ids_v1';
  static const String _pinnedKey = 'pinned_server_ids_v1';
  static const String _customKey = 'custom_servers_v1';
  static const String _pingsKey = 'server_pings_v1';

  final TextEditingController _searchController = TextEditingController();
  final ScrollController _listScrollController = ScrollController();
  final Map<String, GlobalKey> _tileKeys = <String, GlobalKey>{};

  List<VpnServer> _servers = [];
  List<VpnServer> _customServers = [];
  Set<String> _deletedIds = <String>{};
  Set<String> _pinnedIds = <String>{};

  String? _selectedSubId;
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

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    await _loadDeletedAndPinned();
    await _loadCustomServers();
    await _loadServerNameOverrides();
    if (!mounted) return;
    _rebuildServerList();
    await _loadPings();
    await _loadLastServer();
    await V2RayEngine.init();
    await V2RayEngine.loadDelayUrl();
    if (!mounted) return;
    _pollTimer = Timer.periodic(const Duration(seconds: 4), (_) => _poll());
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
      ...kServers,
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
    setState(() {
      server.nameOverride = newName;
    });
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

    setState(() => _selected = selected);

    final key = _tileKeys.putIfAbsent(selected.id, () => GlobalKey());
    final ctx = key.currentContext;
    if (ctx != null) {
      await Scrollable.ensureVisible(
        ctx,
        duration: const Duration(milliseconds: 420),
        curve: Curves.easeOutCubic,
        alignment: 0.15,
      );
      if (mounted) setState(() => _selected = selected);
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
          if (mounted) setState(() => _selected = selected);
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
  }

  Future<void> _savePinned() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_pinnedKey, jsonEncode(_pinnedIds.toList()));
  }

  // ------------------------------------------------------------- list

  void _rebuildServerList() {
    if (!mounted) return;

    final allServers = <VpnServer>[
      ...kServers.where((server) => !_deletedIds.contains(server.id)),
      ..._customServers.where((server) => !_deletedIds.contains(server.id)),
      ...widget.extraServers.where((server) => !_deletedIds.contains(server.id)),
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
        list = list.where((s) =>
          links.contains(s.shareLink) || customIds.contains(s.id)
        ).toList();
      }
    }

    final query = _searchQuery.trim().toLowerCase();
    if (query.isNotEmpty) {
      list = list.where((server) {
        return server.displayName.toLowerCase().contains(query) ||
            server.host.toLowerCase().contains(query) ||
            server.protocol.name.toLowerCase().contains(query);
      }).toList();
    }

    _servers = list;
    _sortCurrentServers();
    setState(() {});
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

  void _deleteServer(VpnServer server) {
    _deletedIds.add(server.id);
    _customServers.removeWhere((item) => item.id == server.id);
    if (_selected?.id == server.id) _selected = null;
    _rebuildServerList();
    _saveDeleted();
    _saveCustomServers();
    _savePings();
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
    _rebuildServerList();
    _saveDeleted();
    _saveCustomServers();
    _savePings();
    _showMsg(_t('\${toDelete.length} تکراری حذف شد',
        '\${toDelete.length} duplicates deleted'));
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
    _rebuildServerList();
    _saveDeleted();
    _saveCustomServers();
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
    await _savePings();
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
      try {
        await _disconnectAll();
      } catch (_) {}
      _markDisconnected(_t('آماده', 'Ready'));
      return;
    }
    final selected = _selected;
    if (selected == null) {
      _showMsg(_t('اول یک سرور انتخاب کن', 'Select a server first'));
      return;
    }
    _cancelConnect = false;
    setState(() {
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
            setState(() => _status = message.replaceAll('\n', ' · '));
          },
        );
        error = AetherService.lastError;
      } else if (selected.isPsiphon) {
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
      setState(() {
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
    final links = _servers
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
          onServerAdded: (server) {
            _customServers.insert(0, server);
            _rebuildServerList();
            _saveCustomServers();
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

  Widget _buildServerList() {
    return Expanded(
      child: ListView.builder(
        controller: _listScrollController,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemExtent: 78.0,
        itemCount: _servers.length + 1,
        itemBuilder: (context, index) {
          if (index == 0) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
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
            );
          }

          final server = _servers[index - 1];
          final tileKey =
              _tileKeys.putIfAbsent(server.id, () => GlobalKey());
          return ServerTile(
            key: tileKey,
            server: server,
            selected: _selected?.id == server.id,
            active: _connected && _active?.id == server.id,
            onTap: () async {
              setState(() => _selected = server);
              await SettingsService.setLastServer(server.id);
            },
            onDelete: server.isDeletable
                ? () => _deleteServer(server)
                : null,
            onPin: () => _togglePin(server),
            onShare: server.isDeletable ? () => _shareServer(server) : null,
            onEdit: () => _editServerName(server),
            onTest: () => _testOne(server),
          );
        },
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
    _pollTimer?.cancel();
    _session?.cancel();
    _searchController.dispose();
    _listScrollController.dispose();
    super.dispose();
  }
}
