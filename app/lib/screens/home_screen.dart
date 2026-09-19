import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import '../models/server.dart';
import '../services/server_tester.dart';
import '../services/v2ray_engine.dart';
import '../services/app_colors.dart';
import '../widgets/server_tile.dart';
import 'add_config_screen.dart';

class HomeScreen extends StatefulWidget {
  final List<VpnServer> extraServers;
  final VoidCallback? onOpenSettings;
  final String language;
  final VoidCallback? onRefreshSubscriptions;

  const HomeScreen({
    super.key,
    this.extraServers = const [],
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

  List<VpnServer> _servers = [];
  List<VpnServer> _customServers = [];
  Set<String> _deletedIds = {};
  Set<String> _pinnedIds = {};
  VpnServer? _selected;
  bool _testing = false;
  bool _autoMode = true;
  bool _connecting = false;
  bool _connected = false;
  bool _sortAscending = true;
  String _status = 'آماده';
  int _tested = 0;
  int _total = 0;
  bool _cancelTest = false;
  String _searchQuery = '';
  bool _showSearch = false;
  final TextEditingController _searchController = TextEditingController();

  bool get _isFa => widget.language == 'fa';
  String _t(String fa, String en) => _isFa ? fa : en;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    await _loadDeleted();
    await _loadCustomServers();
    _rebuildServerList();
    await V2RayEngine.init();
  }

  @override
  void didUpdateWidget(covariant HomeScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.extraServers.length != widget.extraServers.length) {
      _rebuildServerList();
    }
  }

  Future<void> _loadDeleted() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_deletedKey);
    if (raw != null) {
      try {
        _deletedIds = (jsonDecode(raw) as List).cast<String>().toSet();
      } catch (_) {}
    }
    final rawPin = prefs.getString(_pinnedKey);
    if (rawPin != null) {
      try {
        _pinnedIds = (jsonDecode(rawPin) as List).cast<String>().toSet();
      } catch (_) {}
    }
  }

  Future<void> _loadCustomServers() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_customKey);
    if (raw != null) {
      try {
        final list = jsonDecode(raw) as List;
        _customServers = list.map((e) {
          final m = e as Map<String, dynamic>;
          return VpnServer(
            id: m['id'] as String,
            name: m['name'] as String,
            flag: m['flag'] as String? ?? '🔧',
            shareLink: m['shareLink'] as String,
            protocol: VpnProtocol.values.firstWhere(
              (p) => p.name == (m['protocol'] as String? ?? 'custom'),
              orElse: () => VpnProtocol.custom,
            ),
            host: m['host'] as String? ?? '',
            port: m['port'] as int? ?? 443,
            isDeletable: true,
          );
        }).toList();
      } catch (_) {}
    }
  }

  Future<void> _saveCustomServers() async {
    final prefs = await SharedPreferences.getInstance();
    final list = _customServers
        .map((s) => {
              'id': s.id,
              'name': s.name,
              'flag': s.flag,
              'shareLink': s.shareLink,
              'protocol': s.protocol.name,
              'host': s.host,
              'port': s.port,
            })
        .toList();
    await prefs.setString(_customKey, jsonEncode(list));
  }

  Future<void> _saveDeleted() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_deletedKey, jsonEncode(_deletedIds.toList()));
  }

  Future<void> _savePinned() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_pinnedKey, jsonEncode(_pinnedIds.toList()));
  }

  void _togglePin(VpnServer s) {
    setState(() {
      if (_pinnedIds.contains(s.id)) {
        _pinnedIds.remove(s.id);
        s.isPinned = false;
      } else {
        _pinnedIds.add(s.id);
        s.isPinned = true;
      }
      _rebuildServerList();
    });
    _savePinned();
  }

  void _rebuildServerList() {
    if (!mounted) return;
    setState(() {
      _servers = [
        ...kServers.where((s) => !_deletedIds.contains(s.id)),
        ..._customServers.where((s) => !_deletedIds.contains(s.id)),
        ...widget.extraServers.where((s) => !_deletedIds.contains(s.id)),
      ];
      for (final s in _servers) {
        s.isPinned = _pinnedIds.contains(s.id);
      }
      if (_searchQuery.isNotEmpty) {
        final q = _searchQuery.toLowerCase();
        _servers = _servers
            .where((s) =>
                s.name.toLowerCase().contains(q) ||
                s.host.toLowerCase().contains(q) ||
                s.protocol.name.toLowerCase().contains(q))
            .toList();
      }
      ServerTester.sortServers(_servers, descending: !_sortAscending);
      _servers.sort((a, b) {
        if (a.isPinned && !b.isPinned) return -1;
        if (!a.isPinned && b.isPinned) return 1;
        return 0;
      });
    });
  }

  void _cancelTesting() {
    setState(() {
      _cancelTest = true;
      _testing = false;
      _status = _t('تست لغو شد', 'Test cancelled');
    });
  }

  Future<void> _testAll() async {
    if (_testing) return;

    setState(() {
      _testing = true;
      _cancelTest = false;
      _tested = 0;
      _total = _servers.length;
      _status = _t('در حال تست...', 'Testing...');
      for (final s in _servers) {
        s.ping = null;
        s.status = ServerStatus.idle;
      }
    });

    await ServerTester.testAllStreaming(
      _servers,
      isCancelled: () => _cancelTest,
      onServerTested: (server) {
        if (mounted) setState(() => _tested++);
      },
      onListUpdated: () {
        if (!mounted) return;
        setState(() {
          ServerTester.sortServers(_servers, descending: !_sortAscending);
          _servers.sort((a, b) {
            if (a.isPinned && !b.isPinned) return -1;
            if (!a.isPinned && b.isPinned) return 1;
            return 0;
          });
          _servers = List.from(_servers);
        });
      },
    );

    if (!mounted) return;

    setState(() {
      ServerTester.sortServers(_servers, descending: !_sortAscending);
      _servers.sort((a, b) {
        if (a.isPinned && !b.isPinned) return -1;
        if (!a.isPinned && b.isPinned) return 1;
        return 0;
      });
      _servers = List.from(_servers);
      _testing = false;
      if (!_cancelTest) {
        final best = ServerTester.fastest(_servers);
        if (best != null && _autoMode) {
          _selected = best;
          _status = _t('بهترین سرور انتخاب شد', 'Best server selected');
        } else {
          _status = _t('تست تمام شد', 'Test finished');
        }
      }
    });
  }

  Future<void> _testOne(VpnServer s) async {
    if (s.status == ServerStatus.testing) return;
    setState(() {
      s.status = ServerStatus.testing;
      s.ping = null;
    });
    final ping = await ServerTester.testPing(s);
    if (!mounted) return;
    setState(() {
      s.ping = ping;
      s.status = ping != null ? ServerStatus.online : ServerStatus.offline;
    });
  }

  void _deleteServer(VpnServer s) {
    setState(() {
      _deletedIds.add(s.id);
      _customServers.removeWhere((c) => c.id == s.id);
      if (_selected?.id == s.id) _selected = null;
      _rebuildServerList();
    });
    _saveDeleted();
    _saveCustomServers();
  }

  void _deleteInvalid() {
    final toDelete = _servers
        .where((s) => s.ping == null && s.status == ServerStatus.offline)
        .toList();
    if (toDelete.isEmpty) {
      _showMsg(_t('سرور آفلاینی برای حذف نیست', 'No offline servers to delete'));
      return;
    }
    setState(() {
      for (final s in toDelete) {
        _deletedIds.add(s.id);
        _customServers.removeWhere((c) => c.id == s.id);
      }
      if (_selected != null && _deletedIds.contains(_selected!.id)) {
        _selected = null;
      }
      _rebuildServerList();
    });
    _saveDeleted();
    _saveCustomServers();
    _showMsg(
        _t('${toDelete.length} سرور حذف شد', '${toDelete.length} servers deleted'));
  }

  Future<void> _toggleConnection() async {
    if (_connecting) return;

    if (_connected) {
      setState(() {
        _connecting = true;
        _status = _t('در حال قطع...', 'Disconnecting...');
      });
      try {
        await V2RayEngine.disconnect();
      } catch (_) {}
      if (mounted) {
        setState(() {
          _connected = false;
          _connecting = false;
          _status = _t('آماده', 'Ready');
        });
      }
      return;
    }

    if (_selected == null) {
      _showMsg(_t('اول یک سرور انتخاب کن', 'Select a server first'));
      return;
    }

    setState(() {
      _connecting = true;
      _status = _t('در حال اتصال...', 'Connecting...');
    });

    try {
      final ok = await V2RayEngine.connect(_selected!);
      if (mounted) {
        setState(() {
          _connected = ok;
          _connecting = false;
          _status = ok
              ? _t('متصل شد', 'Connected')
              : _t('اتصال ناموفق', 'Connection failed');
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _connected = false;
          _connecting = false;
          _status = _t('خطا در اتصال', 'Connection error');
        });
      }
    }
  }

  Future<void> _copyAll() async {
    final links =
        _servers.map((s) => s.shareLink).where((l) => l.isNotEmpty).join('\n');
    await Clipboard.setData(ClipboardData(text: links));
    _showMsg(_t('همه لینک‌ها کپی شد', 'All links copied'));
  }

  void _shareServer(VpnServer s) {
    Clipboard.setData(ClipboardData(text: s.shareLink));
    _showMsg(_t('لینک سرور کپی شد (می‌توانید ارسال کنید)',
        'Server link copied (you can share it)'));
  }

  void _toggleSort() {
    setState(() {
      _sortAscending = !_sortAscending;
      ServerTester.sortServers(_servers, descending: !_sortAscending);
      _servers.sort((a, b) {
        if (a.isPinned && !b.isPinned) return -1;
        if (!a.isPinned && b.isPinned) return 1;
        return 0;
      });
    });
  }

  void _showMsg(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), duration: const Duration(seconds: 2)),
    );
  }

  void _openAddConfig() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AddConfigScreen(
          language: widget.language,
          onServerAdded: (server) {
            setState(() {
              _customServers.add(server);
              _rebuildServerList();
            });
            _saveCustomServers();
          },
        ),
      ),
    );
  }

  void _showMainMenu() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.elevated(context),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
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
                  Navigator.pop(ctx);
                  _openAddConfig();
                },
              ),
              ListTile(
                leading: Icon(Icons.search, color: AppColors.muted(context)),
                title: Text(_t('جستجو در سرورها', 'Search Servers'),
                    style: TextStyle(color: AppColors.fg(context))),
                onTap: () {
                  Navigator.pop(ctx);
                  setState(() => _showSearch = true);
                },
              ),
              ListTile(
                leading: Icon(Icons.sort, color: AppColors.muted(context)),
                title: Text(_t('مرتب‌سازی', 'Sort'),
                    style: TextStyle(color: AppColors.fg(context))),
                onTap: () {
                  Navigator.pop(ctx);
                  _toggleSort();
                },
              ),
              ListTile(
                leading:
                    const Icon(Icons.delete_sweep, color: AppColors.danger),
                title: Text(_t('حذف سرورهای آفلاین', 'Delete Offline'),
                    style: TextStyle(color: AppColors.fg(context))),
                onTap: () {
                  Navigator.pop(ctx);
                  _deleteInvalid();
                },
              ),
              ListTile(
                leading: Icon(Icons.copy_all, color: AppColors.muted(context)),
                title: Text(_t('کپی همه لینک‌ها', 'Copy All Links'),
                    style: TextStyle(color: AppColors.fg(context))),
                onTap: () {
                  Navigator.pop(ctx);
                  _copyAll();
                },
              ),
              ListTile(
                leading: Icon(
                  _autoMode ? Icons.auto_mode : Icons.auto_mode_outlined,
                  color: _autoMode ? AppColors.accent : AppColors.muted(context),
                ),
                title: Text(
                    _t('حالت خودکار', 'Auto Mode'),
                    style: TextStyle(color: AppColors.fg(context))),
                trailing: Switch(
                  value: _autoMode,
                  activeColor: AppColors.accent,
                  onChanged: (v) {
                    setState(() => _autoMode = v);
                    Navigator.pop(ctx);
                  },
                ),
              ),
              const SizedBox(height: 12),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg(context),
      body: SafeArea(
        child: Column(
          children: [
            // ========== TOP BAR ==========
            Container(
              padding: const EdgeInsets.fromLTRB(4, 6, 4, 4),
              child: Column(
                children: [
                  Row(
                    children: [
                      // Hamburger Menu (≡)
                      IconButton(
                        icon: Icon(Icons.menu,
                            color: AppColors.muted(context), size: 24),
                        onPressed: _showMainMenu,
                        tooltip: _t('منو', 'Menu'),
                      ),

                      // Title
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
                              style: TextStyle(
                                  color: AppColors.muted(context),
                                  fontSize: 11),
                              textAlign: TextAlign.center,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),

                      // Speed Test
                      IconButton(
                        icon: _testing
                            ? const Icon(Icons.stop_circle_outlined,
                                color: AppColors.danger, size: 22)
                            : Icon(Icons.speed,
                                color: AppColors.accent, size: 22),
                        onPressed: _testing ? _cancelTesting : _testAll,
                        tooltip: _t('تست همه', 'Test All'),
                      ),

                      // Settings (gear)
                      IconButton(
                        icon: Icon(Icons.settings,
                            color: AppColors.muted(context), size: 22),
                        onPressed: widget.onOpenSettings,
                        tooltip: _t('تنظیمات', 'Settings'),
                      ),
                    ],
                  ),

                  // Search bar (when active)
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
                                hintStyle: TextStyle(
                                    color: AppColors.muted2(context)),
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
                              onChanged: (v) {
                                setState(() {
                                  _searchQuery = v;
                                  _rebuildServerList();
                                });
                              },
                            ),
                          ),
                          IconButton(
                            icon: Icon(Icons.close,
                                color: AppColors.muted(context)),
                            onPressed: () {
                              setState(() {
                                _showSearch = false;
                                _searchQuery = '';
                                _searchController.clear();
                                _rebuildServerList();
                              });
                            },
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),

            const SizedBox(height: 4),

            // ========== CONNECT BUTTON ==========
            GestureDetector(
              onTap: _connecting ? null : _toggleConnection,
              child: Container(
                width: 130,
                height: 130,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: _connected
                        ? AppColors.accent
                        : (_selected != null
                            ? AppColors.accent
                            : AppColors.border(context)),
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
                          )
                        ]
                      : null,
                ),
                child: Center(
                  child: _connecting
                      ? const SizedBox(
                          width: 36,
                          height: 36,
                          child: CircularProgressIndicator(
                            strokeWidth: 3,
                            color: AppColors.accent,
                          ),
                        )
                      : Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              _connected
                                  ? Icons.shield
                                  : Icons.power_settings_new,
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
            ),

            const SizedBox(height: 12),

            // ========== SERVER LIST ==========
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: _servers.length + 1,
                itemBuilder: (_, i) {
                  if (i == 0) {
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
                                  color: AppColors.muted2(context),
                                  fontSize: 10),
                            ),
                        ],
                      ),
                    );
                  }
                  final s = _servers[i - 1];
                  return ServerTile(
                    server: s,
                    selected: _selected?.id == s.id,
                    onTap: () => setState(() => _selected = s),
                    onDelete: () => _deleteServer(s),
                    onPin: () => _togglePin(s),
                    onShare: () => _shareServer(s),
                    onTest: () => _testOne(s), // صاعقه نگه داشته شد
                  );
                },
              ),
            ),
          ],
        ),
      ),

      // Floating + button
      floatingActionButton: FloatingActionButton(
        onPressed: _openAddConfig,
        backgroundColor: AppColors.accent,
        child: const Icon(Icons.add, color: Colors.black),
      ),
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }
}
