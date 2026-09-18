import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import '../models/server.dart';
import '../services/server_tester.dart';
import '../services/connector.dart';
import '../widgets/server_tile.dart';

class HomeScreen extends StatefulWidget {
  final List<VpnServer> extraServers;

  const HomeScreen({super.key, this.extraServers = const []});

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
  String _status = 'آماده';
  int _tested = 0;
  int _total = 0;
  bool _cancelTest = false;

  @override
  void initState() {
    super.initState();
    _loadDeleted();
    _rebuildServerList();
    WidgetsBinding.instance.addPostFrameCallback((_) => _runTest());
  }

  @override
  void didUpdateWidget(covariant HomeScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.extraServers.length != widget.extraServers.length) {
      _rebuildServerList();
      _runTest();
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
    _servers = [
      ...kServers.where((s) => !_deletedIds.contains(s.id)),
      ...widget.extraServers.where((s) => !_deletedIds.contains(s.id)),
    ];
  }

  Future<void> _runTest() async {
    if (_testing) {
      _cancelTest = true;
      await Future.delayed(const Duration(milliseconds: 300));
    }

    _servers = _servers.where((s) => !_deletedIds.contains(s.id)).toList();

    setState(() {
      _testing = true;
      _cancelTest = false;
      _tested = 0;
      _total = _servers.length;
      _status = 'در حال تست سرورها...';
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
          ServerTester.sortServers(_servers);
          _servers = List.from(_servers);
        });
      },
    );

    if (!mounted) return;

    setState(() {
      ServerTester.sortServers(_servers);
      _servers = List.from(_servers);
      _testing = false;
      final best = ServerTester.fastest(_servers);
      if (best != null && _autoMode) {
        _selected = best;
        _status = 'سریع‌ترین: ${best.name}';
      } else {
        _status = 'آماده';
      }
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('سرور نامعتبری برای حذف نیست'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1D25),
        title: const Text('حذف سرورهای نامعتبر',
            style: TextStyle(color: Colors.white)),
        content: Text(
          '${toDelete.length} سرور نامعتبر حذف بشه؟',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('لغو', style: TextStyle(color: Colors.white54)),
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
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('${toDelete.length} سرور حذف شد'),
                  duration: const Duration(seconds: 2),
                ),
              );
            },
            child: const Text('حذف',
                style: TextStyle(color: Color(0xFFE07070))),
          ),
        ],
      ),
    );
  }

  Future<void> _connect() async {
    if (_selected == null) return;
    setState(() {
      _connecting = true;
      _status = 'در حال اتصال...';
    });
    final ok = await Connector.connect(_selected!);
    if (!mounted) return;
    setState(() {
      _connecting = false;
      _status = ok ? 'برنامه VPN باز شد' : 'هیچ برنامه‌ای پیدا نشد';
    });
  }

  Future<void> _copyOne() async {
    if (_selected == null) return;
    await Clipboard.setData(ClipboardData(text: _selected!.shareLink));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('لینک ${_selected!.name} کپی شد'),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<void> _copyAll() async {
    final text = _servers.map((s) => s.shareLink).join('\n');
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${_servers.length} سرور کپی شد'),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF08090C),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Column(
                children: [
                  const Text(
                    'حسن',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 26,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _status,
                    style: const TextStyle(color: Colors.white54, fontSize: 12),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
            GestureDetector(
              onTap: _testing || _connecting ? null : _connect,
              child: Container(
                width: 130,
                height: 130,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: _selected != null
                        ? const Color(0xFF3DCF9A)
                        : Colors.white24,
                    width: 3,
                  ),
                  color: _selected != null
                      ? const Color(0xFF3DCF9A).withOpacity(0.1)
                      : Colors.transparent,
                ),
                child: Center(
                  child: _testing || _connecting
                      ? const CircularProgressIndicator(color: Colors.white)
                      : Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.power_settings_new,
                              color: _selected != null
                                  ? const Color(0xFF3DCF9A)
                                  : Colors.white38,
                              size: 36,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _selected != null ? 'اتصال' : 'انتخاب سرور',
                              style: TextStyle(
                                color: _selected != null
                                    ? const Color(0xFF3DCF9A)
                                    : Colors.white38,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                ),
              ),
            ),
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (_selected != null)
                  TextButton.icon(
                    onPressed: _copyOne,
                    icon: const Icon(Icons.copy,
                        color: Colors.white54, size: 13),
                    label: const Text('کپی لینک',
                        style:
                            TextStyle(color: Colors.white54, fontSize: 11)),
                  ),
                TextButton.icon(
                  onPressed: _copyAll,
                  icon: const Icon(Icons.copy_all,
                      color: Colors.white54, size: 13),
                  label: const Text('کپی همه',
                      style: TextStyle(color: Colors.white54, fontSize: 11)),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: const Color(0xFF12141A),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.white12),
                      ),
                      child: Row(
                        children: [
                          Transform.scale(
                            scale: 0.85,
                            child: Switch(
                              value: _autoMode,
                              onChanged: (v) => setState(() => _autoMode = v),
                              activeColor: const Color(0xFF3DCF9A),
                            ),
                          ),
                          const Expanded(
                            child: Text(
                              'اتصال خودکار',
                              style: TextStyle(
                                  color: Colors.white70, fontSize: 11),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  IconButton(
                    onPressed: _testing ? null : _runTest,
                    icon:
                        const Icon(Icons.refresh, color: Colors.white, size: 20),
                    padding: EdgeInsets.zero,
                    constraints:
                        const BoxConstraints(minWidth: 38, minHeight: 38),
                    style: IconButton.styleFrom(
                      backgroundColor: const Color(0xFF12141A),
                      side: const BorderSide(color: Colors.white12),
                    ),
                  ),
                  const SizedBox(width: 6),
                  IconButton(
                    onPressed: _deleteInvalid,
                    icon: const Icon(Icons.delete_sweep,
                        color: Color(0xFFE07070), size: 20),
                    padding: EdgeInsets.zero,
                    constraints:
                        const BoxConstraints(minWidth: 38, minHeight: 38),
                    style: IconButton.styleFrom(
                      backgroundColor: const Color(0xFF12141A),
                      side: const BorderSide(color: Colors.white12),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
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
                            'سرورها (${_servers.length})',
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          if (_testing)
                            Text(
                              '$_tested / $_total',
                              style: const TextStyle(
                                  color: Colors.white38, fontSize: 10),
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
                    onDelete: s.isDeletable ? () => _deleteServer(s) : null,
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
