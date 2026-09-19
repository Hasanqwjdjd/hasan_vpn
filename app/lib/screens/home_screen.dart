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

  List<VpnServer> _servers = [];
  Set<String> _deletedIds = {};
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
  }

  Future<void> _saveDeleted() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_deletedKey, jsonEncode(_deletedIds.toList()));
  }

  void _rebuildServerList() {
    if (!mounted) return;
    setState(() {
      _servers = [
        ...kServers.where((s) => !_deletedIds.contains(s.id)),
        ...widget.extraServers.where((s) => !_deletedIds.contains(s.id)),
      ];
      ServerTester.sortServers(_servers, descending: !_sortAscending);
    });
  }

  Future<void> _testAll() async {
    if (_testing) {
      _cancelTest = true;
      await Future.delayed(const Duration(milliseconds: 300));
    }

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
      onServerTested: (server) => _tested++,
      onListUpdated: () {
        if (!mounted) return;
        setState(() {
          ServerTester.sortServers(_servers, descending: !_sortAscending);
          _servers = List.from(_servers);
        });
      },
    );

    if (!mounted) return;

    setState(() {
      ServerTester.sortServers(_servers, descending: !_sortAscending);
      _servers = List.from(_servers);
      _testing = false;
      final best = ServerTester.fastest(_servers);
      if (best != null && _autoMode) {
        _selected = best;
        _status = '${_t('سریع‌ترین', 'Fastest')}: ${best.name}';
      } else {
        _status = _t('آماده', 'Ready');
      }
    });
  }

  Future<void> _testOne(VpnServer server) async {
    setState(() {
      server.status = ServerStatus.testing;
      server.ping = null;
    });
    final ping = await ServerTester.testPing(server);
    if (!mounted) return;
    setState(() {
      server.ping = ping;
      server.status = ping != null ? ServerStatus.online : ServerStatus.offline;
      ServerTester.sortServers(_servers, descending: !_sortAscending);
      _servers = List.from(_servers);
    });
  }

  void _deleteServer(VpnServer server) {
    setState(() {
      _deletedIds.add(server.id);
      _servers.removeWhere((s) => s.id == server.id);
      if (_selected?.id == server.id) _selected = null;
    });
    _saveDeleted();
  }

  void _deleteInvalid() {
    final toDelete = _servers
        .where((s) =>
            s.isDeletable &&
            s.status == ServerStatus.offline &&
            s.ping == null)
        .toList();

    if (toDelete.isEmpty) {
      _showMsg(_t('سرور نامعتبری نیست', 'No invalid servers'));
      return;
    }

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.elevated(ctx),
        title: Text(_t('حذف سرورهای نامعتبر', 'Delete invalid servers'),
            style: TextStyle(color: AppColors.fg(ctx))),
        content: Text(
          '${toDelete.length} ${_t('سرور حذف بشه؟', 'servers will be deleted?')}',
          style: TextStyle(color: AppColors.muted(ctx)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(_t('لغو', 'Cancel'),
                style: TextStyle(color: AppColors.muted(ctx))),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              setState(() {
                for (final s in toDelete) {
                  _deletedIds.add(s.id);
                }
                _servers.removeWhere((s) => toDelete.contains(s));
                if (toDelete.any((s) => s.id == _selected?.id)) {
                  _selected = null;
                }
              });
              _saveDeleted();
              _showMsg('${toDelete.length} ${_t('سرور حذف شد', 'servers deleted')}');
            },
            child: Text(_t('حذف', 'Delete'),
                style: const TextStyle(color: AppColors.danger)),
          ),
        ],
      ),
    );
  }

  Future<void> _toggleConnection() async {
    if (_connecting) return;

    if (_connected) {
      setState(() {
        _connecting = true;
        _status = _t('در حال قطع...', 'Disconnecting...');
      });
      await V2RayEngine.disconnect();
      setState(() {
        _connected = false;
        _connecting = false;
        _status = _t('قطع شد', 'Disconnected');
      });
      return;
    }

    if (_selected == null) {
      _showMsg(_t('اول یه سرور انتخاب کن', 'Select a server first'));
      return;
    }

    setState(() {
      _connecting = true;
      _status = _t('در حال اتصال...', 'Connecting...');
    });

    final ok = await V2RayEngine.connect(_selected!);

    if (!mounted) return;

    setState(() {
      _connecting = false;
      _connected = ok;
      _status = ok
          ? '${_t('متصل به', 'Connected to')} ${_selected!.name}'
          : _t('اتصال ناموفق', 'Connection failed');
    });
  }

  Future<void> _copyAll() async {
    final text = _servers.map((s) => s.shareLink).join('\n');
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    _showMsg('${_servers.length} ${_t('سرور کپی شد', 'servers copied')}');
  }

  void _toggleSort() {
    setState(() {
      _sortAscending = !_sortAscending;
      ServerTester.sortServers(_servers, descending: !_sortAscending);
      _servers = List.from(_servers);
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
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: AppColors.accent))
                            : Icon(Icons.speed,
                                color: AppColors.accent, size: 22),
                        onPressed: _testing ? null : _testAll,
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
                              blurRadius: 30,
                              spreadRadius: 5)
                        ]
                      : null,
                ),
                child: Center(
                  child: _connecting
                      ? const CircularProgressIndicator(
                          color: AppColors.accent)
                      : Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              _connected
                                  ? Icons.shield
                                  : Icons.power_settings_new,
                              color: _connected
                                  ? AppColors.accent
                                  : (_selected != null
                                      ? AppColors.accent
                                      : AppColors.muted2(context)),
                              size: 36,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _connected
                                  ? _t('قطع', 'Disconnect')
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
                            '${_t('سرورها', 'Servers')} (${_servers.length})',
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
