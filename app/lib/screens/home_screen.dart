import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/server.dart';
import '../services/aether_service.dart';
import '../services/app_colors.dart';
import '../services/server_tester.dart';
import '../services/v2ray_engine.dart';
import '../widgets/server_tile.dart';
import 'add_config_screen.dart';
import 'qr_share_screen.dart';

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

  final TextEditingController _searchController = TextEditingController();

  List<VpnServer> _servers = [];
  List<VpnServer> _customServers = [];
  Set<String> _deletedIds = <String>{};
  Set<String> _pinnedIds = <String>{};

  VpnServer? _selected;

  bool _testing = false;
  bool _autoMode = true;
  bool _connecting = false;
  bool _connected = false;
  bool _sortAscending = true;
  bool _cancelTest = false;
  bool _showSearch = false;

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

    if (!mounted) return;
    _rebuildServerList();

    await V2RayEngine.init();
  }

  @override
  void didUpdateWidget(covariant HomeScreen oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.extraServers != widget.extraServers ||
        oldWidget.language != widget.language) {
      _rebuildServerList();
    }
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
      } catch (_) {
        _deletedIds = <String>{};
      }
    }

    final pinnedRaw = prefs.getString(_pinnedKey);
    if (pinnedRaw != null) {
      try {
        final decoded = jsonDecode(pinnedRaw);
        if (decoded is List) {
          _pinnedIds = decoded.map((e) => e.toString()).toSet();
        }
      } catch (_) {
        _pinnedIds = <String>{};
      }
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

        if (id == null || name == null || shareLink == null) {
          continue;
        }

        final protocolName = map['protocol']?.toString() ?? 'custom';

        final protocol = VpnProtocol.values.firstWhere(
          (value) => value.name == protocolName,
          orElse: () => VpnProtocol.custom,
        );

        loaded.add(
          VpnServer(
            id: id,
            name: name,
            flag: map['flag']?.toString() ?? '🔧',
            shareLink: shareLink,
            protocol: protocol,
            host: map['host']?.toString() ?? '',
            port: _safePort(map['port']),
            isDeletable: true,
          ),
        );
      }

      _customServers = loaded;
    } catch (_) {
      _customServers = <VpnServer>[];
    }
  }

  int _safePort(dynamic value) {
    if (value is int && value > 0 && value <= 65535) {
      return value;
    }

    final parsed = int.tryParse(value?.toString() ?? '');
    if (parsed != null && parsed > 0 && parsed <= 65535) {
      return parsed;
    }

    return 443;
  }

  Future<void> _saveCustomServers() async {
    final prefs = await SharedPreferences.getInstance();

    final data = _customServers
        .map(
          (server) => <String, dynamic>{
            'id': server.id,
            'name': server.name,
            'flag': server.flag,
            'shareLink': server.shareLink,
            'protocol': server.protocol.name,
            'host': server.host,
            'port': server.port,
          },
        )
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

  void _sortCurrentServers() {
    ServerTester.sortServers(
      _servers,
      descending: !_sortAscending,
    );

    _servers.sort((a, b) {
      if (a.isPinned && !b.isPinned) return -1;
      if (!a.isPinned && b.isPinned) return 1;
      return 0;
    });
  }

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

    var visibleServers = allServers;

    final query = _searchQuery.trim().toLowerCase();

    if (query.isNotEmpty) {
      visibleServers = visibleServers.where((server) {
        return server.name.toLowerCase().contains(query) ||
            server.host.toLowerCase().contains(query) ||
            server.protocol.name.toLowerCase().contains(query);
      }).toList();
    }

    _servers = visibleServers;
    _sortCurrentServers();

    setState(() {});
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

  void _cancelTesting() {
    if (!mounted) return;

    setState(() {
      _cancelTest = true;
      _testing = false;
      _status = _t('تست لغو شد', 'Test cancelled');
    });
  }

  Future<void> _testAll() async {
    if (_testing || _servers.isEmpty) return;

    setState(() {
      _testing = true;
      _cancelTest = false;
      _tested = 0;
      _total = _servers.length;
      _status = _t('در حال تست...', 'Testing...');

      for (final server in _servers) {
        server.ping = null;
        server.status = ServerStatus.idle;
      }
    });

    await ServerTester.testAllStreaming(
      _servers,
      isCancelled: () => _cancelTest,
      onServerTested: (_) {
        if (!mounted) return;
        setState(() {
          _tested++;
        });
      },
      onListUpdated: () {
        if (!mounted) return;

        _sortCurrentServers();

        setState(() {
          _servers = List<VpnServer>.from(_servers);
        });
      },
    );

    if (!mounted) return;

    _sortCurrentServers();

    setState(() {
      _servers = List<VpnServer>.from(_servers);
      _testing = false;

      if (!_cancelTest) {
        final fastest = ServerTester.fastest(_servers);

        if (_autoMode && fastest != null) {
          _selected = fastest;
          _status = _t('بهترین سرور انتخاب شد', 'Best server selected');
        } else {
          _status = _t('تست تمام شد', 'Test finished');
        }
      }
    });
  }

  Future<void> _testOne(VpnServer server) async {
    if (server.status == ServerStatus.testing) return;

    if (server.isAether) {
      _showMsg(
        _t(
          'تست پینگ برای Aether قابل استفاده نیست',
          'Ping test is not available for Aether',
        ),
      );
      return;
    }

    setState(() {
      server.status = ServerStatus.testing;
      server.ping = null;
    });

    final ping = await ServerTester.testPing(server);

    if (!mounted) return;

    setState(() {
      server.ping = ping;
      server.status =
          ping == null ? ServerStatus.offline : ServerStatus.online;
    });
  }

  void _deleteServer(VpnServer server) {
    _deletedIds.add(server.id);
    _customServers.removeWhere((item) => item.id == server.id);

    if (_selected?.id == server.id) {
      _selected = null;
    }

    _rebuildServerList();
    _saveDeleted();
    _saveCustomServers();
  }

  void _deleteInvalid() {
    final toDelete = _servers
        .where(
          (server) =>
              !server.isAether &&
              server.ping == null &&
              server.status == ServerStatus.offline,
        )
        .toList();

    if (toDelete.isEmpty) {
      _showMsg(
        _t(
          'سرور آفلاینی برای حذف نیست',
          'No offline servers to delete',
        ),
      );
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
      _t(
        '${toDelete.length} سرور حذف شد',
        '${toDelete.length} servers deleted',
      ),
    );
  }

  Future<void> _refreshConnectionState() async {
    if (!_connected) return;

    if (_selected?.isAether == true) {
      final alive = await AetherService.syncStatus();

      if (!alive && mounted) {
        setState(() {
          _connected = false;
          _status = _t('آماده', 'Ready');
        });
      }
    }
  }

  Future<void> _disconnectAll() async {
    await AetherService.disconnect();
    await V2RayEngine.disconnect();
  }

  Future<void> _toggleConnection() async {
    if (_connecting) return;

    await _refreshConnectionState();

    if (_connected) {
      setState(() {
        _connecting = true;
        _status = _t('در حال قطع...', 'Disconnecting...');
      });

      try {
        await _disconnectAll();
      } catch (_) {}

      if (!mounted) return;

      setState(() {
        _connected = false;
        _connecting = false;
        _status = _t('آماده', 'Ready');
      });

      return;
    }

    final selected = _selected;

    if (selected == null) {
      _showMsg(
        _t(
          'اول یک سرور انتخاب کن',
          'Select a server first',
        ),
      );
      return;
    }

    setState(() {
      _connecting = true;
      _status = _t('در حال اتصال...', 'Connecting...');
    });

    try {
      final bool connected;
      final String? error;

      if (selected.isAether) {
        connected = await AetherService.connect(selected);
        error = AetherService.lastError;
      } else {
        connected = await V2RayEngine.connect(selected);
        error = V2RayEngine.lastError;
      }

      if (!mounted) return;

      setState(() {
        _connected = connected;
        _connecting = false;

        if (connected) {
          _status = _t('متصل شد', 'Connected');
        } else if (error != null && error.isNotEmpty) {
          _status = _t(
            'اتصال ناموفق: $error',
            'Connection failed: $error',
          );
        } else {
          _status = _t('اتصال ناموفق', 'Connection failed');
        }
      });
    } catch (error) {
      if (!mounted) return;

      setState(() {
        _connected = false;
        _connecting = false;
        _status = _t(
          'خطا در اتصال',
          'Connection error',
        );
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
      _showMsg(_t('لینکی وجود ندارد', 'No links available'));
      return;
    }

    await Clipboard.setData(ClipboardData(text: links));
    _showMsg(_t('همه لینک‌ها کپی شد', 'All links copied'));
  }

  void _shareServer(VpnServer server) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => QrShareScreen(
          server: server,
          language: widget.language,
        ),
      ),
    );
  }

  void _toggleSort() {
    _sortAscending = !_sortAscending;
    _sortCurrentServers();

    setState(() {
      _servers = List<VpnServer>.from(_servers);
    });
  }

  void _showMsg(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _openAddConfig() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AddConfigScreen(
          language: widget.language,
          onServerAdded: (server) {
            _customServers.add(server);
            _rebuildServerList();
            _saveCustomServers();
          },
        ),
      ),
    );
  }

  void _openSearch() {
    setState(() {
      _showSearch = true;
    });
  }

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
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(20),
        ),
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
                leading: const Icon(
                  Icons.add_circle_outline,
                  color: AppColors.accent,
                ),
                title: Text(
                  _t('افزودن کانفیگ', 'Add Config'),
                  style: TextStyle(
                    color: AppColors.fg(context),
                  ),
                ),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _openAddConfig();
                },
              ),
              ListTile(
                leading: Icon(
                  Icons.search,
                  color: AppColors.muted(context),
                ),
                title: Text(
                  _t('جستجو در سرورها', 'Search Servers'),
                  style: TextStyle(
                    color: AppColors.fg(context),
                  ),
                ),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _openSearch();
                },
              ),
              ListTile(
                leading: Icon(
                  Icons.sort,
                  color: AppColors.muted(context),
                ),
                title: Text(
                  _t('مرتب‌سازی', 'Sort'),
                  style: TextStyle(
                    color: AppColors.fg(context),
                  ),
                ),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _toggleSort();
                },
              ),
              ListTile(
                leading: const Icon(
                  Icons.delete_sweep,
                  color: AppColors.danger,
                ),
                title: Text(
                  _t('حذف سرورهای آفلاین', 'Delete Offline'),
                  style: TextStyle(
                    color: AppColors.fg(context),
                  ),
                ),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _deleteInvalid();
                },
              ),
              ListTile(
                leading: Icon(
                  Icons.copy_all,
                  color: AppColors.muted(context),
                ),
                title: Text(
                  _t('کپی همه لینک‌ها', 'Copy All Links'),
                  style: TextStyle(
                    color: AppColors.fg(context),
                  ),
                ),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _copyAll();
                },
              ),
              ListTile(
                leading: Icon(
                  _autoMode
                      ? Icons.auto_mode
                      : Icons.auto_mode_outlined,
                  color: _autoMode
                      ? AppColors.accent
                      : AppColors.muted(context),
                ),
                title: Text(
                  _t('حالت خودکار', 'Auto Mode'),
                  style: TextStyle(
                    color: AppColors.fg(context),
                  ),
                ),
                trailing: Switch(
                  value: _autoMode,
                  activeColor: AppColors.accent,
                  onChanged: (value) {
                    setState(() {
                      _autoMode = value;
                    });
                    Navigator.pop(sheetContext);
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

  Widget _buildTopBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(4, 6, 4, 4),
      child: Column(
        children: [
          Row(
            children: [
              IconButton(
                icon: Icon(
                  Icons.menu,
                  color: AppColors.muted(context),
                  size: 24,
                ),
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
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: AppColors.muted(context),
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: _testing
                    ? const Icon(
                        Icons.stop_circle_outlined,
                        color: AppColors.danger,
                        size: 22,
                      )
                    : const Icon(
                        Icons.speed,
                        color: AppColors.accent,
                        size: 22,
                      ),
                onPressed: _testing ? _cancelTesting : _testAll,
                tooltip: _t('تست همه', 'Test All'),
              ),
              IconButton(
                icon: Icon(
                  Icons.settings,
                  color: AppColors.muted(context),
                  size: 22,
                ),
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
                        color: AppColors.fg(context),
                        fontSize: 14,
                      ),
                      decoration: InputDecoration(
                        hintText: _t('جستجو...', 'Search...'),
                        hintStyle: TextStyle(
                          color: AppColors.muted2(context),
                        ),
                        prefixIcon: Icon(
                          Icons.search,
                          color: AppColors.muted(context),
                          size: 20,
                        ),
                        filled: true,
                        fillColor: AppColors.surface(context),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
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
                    icon: Icon(
                      Icons.close,
                      color: AppColors.muted(context),
                    ),
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
    final selectedColor = _selected == null
        ? AppColors.border(context)
        : AppColors.accent;

    return GestureDetector(
      onTap: _connecting ? null : _toggleConnection,
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
    );
  }

  Widget _buildServerList() {
    return Expanded(
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 16),
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
                        color: AppColors.muted2(context),
                        fontSize: 10,
                      ),
                    ),
                ],
              ),
            );
          }

          final server = _servers[index - 1];

          return ServerTile(
            server: server,
            selected: _selected?.id == server.id,
            onTap: () {
              setState(() {
                _selected = server;
              });
            },
            onDelete: () => _deleteServer(server),
            onPin: () => _togglePin(server),
            onShare: () => _shareServer(server),
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
            _buildConnectButton(),
            const SizedBox(height: 12),
            _buildServerList(),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _openAddConfig,
        backgroundColor: AppColors.accent,
        child: const Icon(
          Icons.add,
          color: Colors.black,
        ),
      ),
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }
}
