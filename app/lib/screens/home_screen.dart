import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import '../models/server.dart';
import '../services/server_tester.dart';
import '../services/v2ray_engine.dart';
import '../services/app_colors.dart';
import '../widgets/server_tile.dart';

class HomeScreen extends StatefulWidget {
  final List<VpnServer> extraServers;
  final VoidCallback? onOpenSettings;
  final String language;

  const HomeScreen({
    super.key,
    this.extraServers = const [],
    this.onOpenSettings,
    this.language = 'fa',
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  static const String _deletedKey = 'deleted_server_ids_v1';
  static const String _pinnedKey = 'pinned_server_ids_v1';

  List<VpnServer> _servers = [];
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

  bool get _isFa => widget.language == 'fa';
  String _t(String fa, String en) => _isFa ? fa : en;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    await _loadDeleted();
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
        ...widget.extraServers.where((s) => !_deletedIds.contains(s.id)),
      ];
      for (final s in _servers) {
        s.isPinned = _pinnedIds.contains(s.id);
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
      if (_selected?.id == s.id) _selected = null;
      _rebuildServerList();
    });
    _saveDeleted();
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
      }
      if (_selected != null && _deletedIds.contains(_selected!.id)) {
        _selected = null;
      }
      _rebuildServerList();
    });
    _saveDeleted();
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg(context),
      body: SafeArea(
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
              child: Column(
                children: [
                  Row(
                    children: [
                      IconButton(
                        icon: Icon(Icons.settings,
                            color: AppColors.muted(context), size: 22),
                        onPressed: widget.onOpenSettings,
                      ),
                      Expanded(
                        child: Column(
                          children: [
                            Text(
                              _isFa ? 'حسن' : 'Hasan',
                              style: TextStyle(
                                color: AppColors.fg(context),
                                fontSize: 22,
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
                      IconButton(
                        icon: _testing
                            ? const Icon(Icons.stop_circle_outlined,
                                color: AppColors.danger, size: 22)
                            : Icon(Icons.speed,
                                color: AppColors.accent, size: 22),
                        onPressed: _testing ? _cancelTesting : _testAll,
                      ),
                    ],
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      IconButton(
                        icon: Icon(Icons.sort,
                            color: AppColors.muted(context), size: 20),
                        onPressed: _toggleSort,
                      ),
                      IconButton(
                        icon: Icon(Icons.delete_sweep,
                            color: AppColors.danger, size: 20),
                        onPressed: _deleteInvalid,
                      ),
                      IconButton(
                        icon: Icon(Icons.copy_all,
                            color: AppColors.muted(context), size: 20),
                        onPressed: _copyAll,
                      ),
                      IconButton(
                        icon: Icon(
                          _autoMode
                              ? Icons.auto_mode
                              : Icons.auto_mode_outlined,
                          color: _autoMode
                              ? AppColors.accent
                              : AppColors.muted(context),
                          size: 20,
                        ),
                        onPressed: () =>
                            setState(() => _autoMode = !_autoMode),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
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
                    onTest: () => _testOne(s),
                    onDelete: () => _deleteServer(s),
                    onPin: () => _togglePin(s),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
