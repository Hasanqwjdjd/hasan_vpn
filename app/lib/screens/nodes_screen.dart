import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../controllers/connection.dart';
import '../controllers/servers.dart';
import '../l10n/s.dart';
import '../models/server.dart';
import '../services/connection_log_service.dart';
import '../services/link_parser.dart';
import '../services/server_overrides.dart';
import '../ui/fx/fx.dart';
import '../ui/kit/ios_kit.dart';
import '../ui/theme/ios_palette.dart';

/// تب V2Ray — لیست سرورها (پورت NodesTab.kt، ساختار iOS).
class NodesScreen extends StatefulWidget {
  const NodesScreen({super.key});

  @override
  State<NodesScreen> createState() => _NodesScreenState();
}

class _NodesScreenState extends State<NodesScreen> {
  final ServerRepository _repo = ServerRepository.instance;
  final ConnectionController _conn = ConnectionController.instance;
  bool _selectMode = false;
  final Set<String> _selected = {};
  String _query = '';

  @override
  void initState() {
    super.initState();
    _repo.addListener(_onChange);
    _conn.addListener(_onChange);
  }

  @override
  void dispose() {
    _repo.removeListener(_onChange);
    _conn.removeListener(_onChange);
    super.dispose();
  }

  void _onChange() {
    if (mounted) setState(() {});
  }

  String _t(String fa, String en) => S.isFa ? fa : en;

  List<VpnServer> get _servers {
    final q = _query.trim().toLowerCase();
    var list = _repo.servers;
    if (q.isNotEmpty) {
      list = list
          .where((s) =>
              s.displayName.toLowerCase().contains(q) ||
              s.host.toLowerCase().contains(q) ||
              s.protocol.name.toLowerCase().contains(q))
          .toList();
    }
    return list;
  }

  Future<void> _openAddSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => const _AddServerSheet(),
    );
    setState(() {});
  }

  Future<void> _onTapServer(VpnServer s) async {
    lightHaptic();
    if (_selectMode) {
      setState(() {
        if (_selected.contains(s.id)) {
          _selected.remove(s.id);
        } else {
          _selected.add(s.id);
        }
      });
      return;
    }
    await _repo.select(s);
    if (_conn.connected || _conn.connecting) {
      await _conn.disconnect();
      await Future.delayed(const Duration(milliseconds: 400));
    }
    await _conn.connectServer(s);
  }

  Future<void> _onLongPressServer(VpnServer s) async {
    lightHaptic();
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: IosPal.of(context).dialog,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(Icons.push_pin_outlined,
                  color: s.isPinned ? IosPal.of(ctx).blue : Colors.white),
              title: Text(
                s.isPinned
                    ? _t('برداشتن پین', 'Unpin')
                    : _t('سنجاق به بالا', 'Pin to top'),
                style: const TextStyle(color: Colors.white),
              ),
              onTap: () {
                Navigator.pop(ctx);
                _repo.togglePin(s);
              },
            ),
            ListTile(
              leading:
                  const Icon(Icons.edit_outlined, color: Colors.white),
              title: Text(_t('تغییر نام', 'Rename'),
                  style: const TextStyle(color: Colors.white)),
              onTap: () async {
                Navigator.pop(ctx);
                final name = await showIosPrompt(context,
                    title: _t('نام سرور', 'Server name'),
                    initial: s.nameOverride ?? s.name);
                if (name != null && name.trim().isNotEmpty) {
                  await _repo.updateOverride(
                      s.id, {...(ServerOverrides.of(s)), 'name': name.trim()});
                }
              },
            ),
            ListTile(
              leading: Icon(Icons.delete_outline,
                  color: IosPal.of(ctx).red),
              title: Text(_t('حذف', 'Delete'),
                  style: TextStyle(color: IosPal.of(ctx).red)),
              onTap: () {
                Navigator.pop(ctx);
                _repo.deleteServers({s.id});
              },
            ),
          ],
        ),
      ),
    );
  }

  Color _pingColor(VpnServer s) {
    final pal = IosPal.of(context);
    switch (s.status) {
      case ServerStatus.testing:
        return pal.textMuted;
      case ServerStatus.online:
        final p = s.ping ?? 9999;
        if (p < 150) return pal.green;
        if (p < 400) return pal.orange;
        return pal.red;
      case ServerStatus.offline:
        return pal.red;
      case ServerStatus.idle:
      case ServerStatus.unknown:
        return pal.textDim;
    }
  }

  String _pingText(VpnServer s) {
    switch (s.status) {
      case ServerStatus.testing:
        return '···';
      case ServerStatus.online:
        return '${s.ping}ms';
      case ServerStatus.offline:
        return _t('خاموش', 'down');
      case ServerStatus.idle:
      case ServerStatus.unknown:
        return '·';
    }
  }

  @override
  Widget build(BuildContext context) {
    final pal = IosPal.of(context);
    final servers = _servers;
    final testing = _repo.testing;

    return IosScreen(
      largeTitle: S.t('home_v2ray'),
      title: S.t('home_v2ray'),
      backdropColor: Colors.transparent,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: testing
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                : Icon(Icons.bolt,
                    size: 22,
                    color: testing ? pal.textMuted : Colors.white),
            onPressed: () {
              if (testing) {
                _repo.cancelTesting();
              } else {
                _repo.testAll();
              }
            },
          ),
          IconButton(
            icon: Icon(
              _selectMode ? Icons.close : Icons.checklist,
              size: 22,
              color: Colors.white,
            ),
            onPressed: () {
              setState(() {
                _selectMode = !_selectMode;
                _selected.clear();
              });
            },
          ),
          IconButton(
            icon: const Icon(Icons.add_circle_outline,
                size: 22, color: Colors.white),
            onPressed: _openAddSheet,
          ),
        ],
      ),
      children: [
        // جست‌وجو
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
          child: TextField(
            onChanged: (v) => setState(() => _query = v),
            style: const TextStyle(color: Colors.white, fontSize: 15),
            decoration: InputDecoration(
              hintText: _t('جست‌وجوی سرور...', 'Search servers...'),
              hintStyle: TextStyle(color: pal.textDim, fontSize: 14),
              prefixIcon:
                  Icon(Icons.search, size: 20, color: pal.textMuted),
              filled: true,
              fillColor: Colors.white.withValues(alpha: 0.08),
              border: OutlineInputBorder(
                borderRadius:
                    BorderRadius.circular(IosRadius.control),
                borderSide: BorderSide.none,
              ),
              contentPadding: EdgeInsets.zero,
            ),
          ),
        ),
        if (_selectMode && _selected.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
            child: FrostedGlass(
              borderRadius:
                  BorderRadius.circular(IosRadius.control),
              blur: 16,
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      _t('${_selected.length} سرور انتخاب شده',
                          '${_selected.length} selected'),
                      style: const TextStyle(
                          color: Colors.white, fontSize: 14),
                    ),
                  ),
                  TextButton(
                    onPressed: () {
                      _repo.deleteServers(Set<String>.of(_selected));
                      setState(() {
                        _selected.clear();
                        _selectMode = false;
                      });
                    },
                    child: Text(_t('حذف', 'Delete'),
                        style: TextStyle(color: pal.red)),
                  ),
                ],
              ),
            ),
          ),
        if (servers.isEmpty)
          Padding(
            padding: const EdgeInsets.all(40),
            child: Column(
              children: [
                Icon(Icons.dns_outlined,
                    size: 44, color: pal.textDim),
                const SizedBox(height: 12),
                Text(
                  _t(
                      'سروری نیست — با + کانفیگ اضافه کن یا اشتراک را در «ابری» به‌روز کن',
                      'No servers — add a config with + or refresh subs in Cloud'),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      color: pal.textMuted,
                      fontSize: 13,
                      height: 1.4),
                ),
              ],
            ),
          )
        else
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Column(
              children: [
                for (final s in servers)
                  _serverCard(context, s),
              ],
            ),
          ),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _serverCard(BuildContext context, VpnServer s) {
    final pal = IosPal.of(context);
    final isSelected = _repo.selected?.id == s.id;
    final isConnected = _conn.connected &&
        (_conn.activeServer?.id == s.id ||
            (s.protocol == VpnProtocol.xrayJson &&
                _conn.activeServer?.protocol == VpnProtocol.xrayJson &&
                s.id.startsWith('tor_fake_')));
    final checked = _selected.contains(s.id);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: GestureDetector(
        onTap: () => _onTapServer(s),
        onLongPress: () => _onLongPressServer(s),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          decoration: BoxDecoration(
            color: isSelected
                ? Color.alphaBlend(
                    pal.blue.withValues(alpha: 0.16), pal.glassTint)
                : pal.glassTint,
            borderRadius: BorderRadius.circular(IosRadius.card),
            border: Border.all(
              color: isConnected
                  ? pal.green.withValues(alpha: 0.7)
                  : isSelected
                      ? pal.blue.withValues(alpha: 0.6)
                      : pal.glassRim,
              width: isConnected || isSelected ? 1.2 : 0.7,
            ),
          ),
          child: Row(
            children: [
              if (_selectMode) ...[
                Icon(
                  checked
                      ? Icons.check_circle
                      : Icons.radio_button_unchecked,
                  size: 20,
                  color: checked ? pal.blue : pal.textMuted,
                ),
                const SizedBox(width: 10),
              ],
              Text(
                s.flag.isEmpty ? '⚡' : s.flag,
                style: const TextStyle(fontSize: 20),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            s.displayName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 15,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                        if (s.isPinned) ...[
                          const SizedBox(width: 4),
                          Icon(Icons.push_pin,
                              size: 12, color: pal.textMuted),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${s.host}${s.port > 0 ? ':${s.port}' : ''} · ${s.protocol.name}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: pal.textMuted,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              if (isConnected) ...[
                const SizedBox(width: 8),
                Icon(Icons.circle, size: 10, color: pal.green),
                const SizedBox(width: 4),
              ],
              const SizedBox(width: 6),
              if (s.status == ServerStatus.testing)
                const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else
                Text(
                  _pingText(s),
                  textDirection: TextDirection.ltr,
                  style: TextStyle(
                    color: _pingColor(s),
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
}

// ─────────────────────────────────────────────────────────── افزودن سرور

class _AddServerSheet extends StatefulWidget {
  const _AddServerSheet();

  @override
  State<_AddServerSheet> createState() => _AddServerSheetState();
}

class _AddServerSheetState extends State<_AddServerSheet> {
  final TextEditingController _paste = TextEditingController();
  bool _busy = false;
  String? _result;

  String _t(String fa, String en) => S.isFa ? fa : en;

  Future<void> _addLinks(String text) async {
    if (text.trim().isEmpty) return;
    setState(() {
      _busy = true;
      _result = null;
    });
    final n = await ServerRepository.instance.addFromLink(text);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _result = n > 0
          ? _t('$n کانفیگ اضافه شد', '$n config(s) added')
          : _t('چیزی اضافه نشد (تکراری یا نامعتبر)',
              'Nothing added (duplicate or invalid)');
    });
    if (n > 0) {
      await ConnectionLogService.logError('IMPORT', 'added $n from links');
      if (mounted) Navigator.pop(context);
    }
  }

  Future<void> _scanQr() async {
    final link = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => const _QrScanPage()),
    );
    if (link != null && link.isNotEmpty) {
      await _addLinks(link);
    }
  }

  @override
  Widget build(BuildContext context) {
    final pal = IosPal.of(context);
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: FrostedGlass(
          borderRadius: const BorderRadius.vertical(
              top: Radius.circular(22)),
          blur: 30,
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                _t('افزودن کانفیگ', 'Add config'),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _paste,
                maxLines: 4,
                autofocus: false,
                style: const TextStyle(
                    color: Colors.white, fontSize: 14),
                decoration: InputDecoration(
                  hintText: _t(
                      'لینک کانفیگ را اینجا بچسبان (چند خط مجاز است)',
                      'Paste config link(s) here'),
                  hintStyle:
                      TextStyle(color: pal.textDim, fontSize: 13),
                  filled: true,
                  fillColor:
                      Colors.white.withValues(alpha: 0.08),
                  border: OutlineInputBorder(
                    borderRadius:
                        BorderRadius.circular(IosRadius.control),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        side:
                            BorderSide(color: pal.glassRim),
                        padding:
                            const EdgeInsets.symmetric(vertical: 12),
                      ),
                      onPressed: _busy ? null : _scanQr,
                      icon: const Icon(Icons.qr_code_scanner, size: 18),
                      label: Text(_t('اسکن QR', 'Scan QR')),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        side:
                            BorderSide(color: pal.glassRim),
                        padding:
                            const EdgeInsets.symmetric(vertical: 12),
                      ),
                      onPressed: _busy
                          ? null
                          : () async {
                              final s = await showManualForm(context);
                              if (s != null) {
                                final ok = await ServerRepository
                                    .instance
                                    .addServer(s);
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context)
                                      .showSnackBar(SnackBar(
                                    backgroundColor: pal.card,
                                    content: Text(
                                      ok
                                          ? _t('اضافه شد', 'Added')
                                          : _t('اضافه نشد',
                                              'Not added'),
                                      style: const TextStyle(
                                          color: Colors.white),
                                    ),
                                  ));
                                  if (ok && context.mounted) {
                                    Navigator.pop(context);
                                  }
                                }
                              }
                            },
                      icon:
                          const Icon(Icons.edit_note, size: 18),
                      label: Text(_t('دستی', 'Manual')),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor:
                      IosPal.of(context).blue,
                  foregroundColor: Colors.white,
                  padding:
                      const EdgeInsets.symmetric(vertical: 12),
                ),
                onPressed:
                    _busy ? null : () => _addLinks(_paste.text),
                child: _busy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white))
                    : Text(_t('افزودن', 'Add')),
              ),
              if (_result != null) ...[
                const SizedBox(height: 8),
                Text(_result!,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        color: pal.textMuted, fontSize: 12)),
              ],
              const SizedBox(height: 6),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────── اسکنر QR

class _QrScanPage extends StatelessWidget {
  const _QrScanPage();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        title: Text(S.isFa ? 'اسکن QR' : 'Scan QR'),
      ),
      body: MobileScanner(
        onDetect: (capture) {
          final barcodes = capture.barcodes;
          for (final b in barcodes) {
            final v = b.rawValue;
            if (v != null && v.isNotEmpty) {
              Navigator.pop(context, v);
              return;
            }
          }
        },
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────── فرم دستی

/// فرم دستی سرور — فیلدهای اصلی هر پروتکل و ساخت share-link استاندارد.
Future<VpnServer?> showManualForm(BuildContext context) async {
  return showModalBottomSheet<VpnServer>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (ctx) => const _ManualForm(),
  );
}

class _ManualForm extends StatefulWidget {
  const _ManualForm();

  @override
  State<_ManualForm> createState() => _ManualFormState();
}

class _ManualFormState extends State<_ManualForm> {
  VpnProtocol _proto = VpnProtocol.vless;
  final _name = TextEditingController();
  final _host = TextEditingController();
  final _port = TextEditingController();
  final _secret = TextEditingController(); // uuid / password
  final _sni = TextEditingController();
  String _net = 'tcp';
  bool _tls = true;

  String _t(String fa, String en) => S.isFa ? fa : en;

  static const List<VpnProtocol> kProtocols = [
    VpnProtocol.vless,
    VpnProtocol.vmess,
    VpnProtocol.trojan,
    VpnProtocol.shadowsocks,
    VpnProtocol.hysteria2,
    VpnProtocol.socks5,
  ];

  String get _secretLabel {
    switch (_proto) {
      case VpnProtocol.vless:
        return 'UUID';
      case VpnProtocol.vmess:
        return 'UUID';
      case VpnProtocol.trojan:
      case VpnProtocol.hysteria2:
        return _t('رمز', 'Password');
      case VpnProtocol.shadowsocks:
        return _t('رمز (method: pass)', 'Password');
      case VpnProtocol.socks5:
        return _t('user:pass', 'user:pass');
      default:
        return _t('شناسه', 'Secret');
    }
  }

  String? _buildLink() {
    final host = _host.text.trim();
    final port = int.tryParse(_port.text.trim()) ?? 0;
    if (host.isEmpty || port <= 0) return null;
    final sec = _secret.text.trim();
    final sni = _sni.text.trim();
    switch (_proto) {
      case VpnProtocol.vless:
        final q = <String, String>{
          'type': _net,
          if (_tls) 'security': 'tls',
          if (!_tls) 'security': 'none',
          if (sni.isNotEmpty) 'sni': sni,
        };
        return 'vless://$sec@$host:$port?${Uri(queryParameters: q).query}';
      case VpnProtocol.vmess:
        final json = jsonEncode(<String, dynamic>{
          'v': '2',
          'ps': _name.text.trim().isEmpty
              ? '$host:$port'
              : _name.text.trim(),
          'add': host,
          'port': '$port',
          'id': sec,
          'aid': '0',
          'net': _net,
          'type': 'none',
          'tls': _tls ? 'tls' : '',
          if (sni.isNotEmpty) 'sni': sni,
        });
        return 'vmess://${base64Url.encode(utf8.encode(json))}';
      case VpnProtocol.trojan:
        final q = <String, String>{
          'type': _net,
          if (sni.isNotEmpty) 'sni': sni,
          'security': _tls ? 'tls' : 'none',
        };
        return 'trojan://$sec@$host:$port?${Uri(queryParameters: q).query}';
      case VpnProtocol.shadowsocks:
        if (!sec.contains(':')) return null;
        return 'ss://${base64Url.encode(utf8.encode(sec))}@$host:$port';
      case VpnProtocol.hysteria2:
        final q = <String, String>{
          if (sni.isNotEmpty) 'sni': sni,
        };
        return 'hysteria2://$sec@$host:$port${q.isEmpty ? '' : '?${Uri(queryParameters: q).query}'}';
      case VpnProtocol.socks5:
        return 'socks5://$sec@$host:$port';
      default:
        return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final pal = IosPal.of(context);
    return SafeArea(
      child: Padding(
        padding:
            EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
        child: FrostedGlass(
          borderRadius:
              const BorderRadius.vertical(top: Radius.circular(22)),
          blur: 30,
          padding: const EdgeInsets.all(16),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  _t('کانفیگ دستی', 'Manual config'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final p in kProtocols)
                      ChoiceChip(
                        label: Text(p.name,
                            style: TextStyle(
                              fontSize: 12,
                              color: p == _proto
                                  ? Colors.white
                                  : pal.textMuted,
                            )),
                        selected: p == _proto,
                        selectedColor: pal.blue,
                        backgroundColor:
                            Colors.white.withValues(alpha: 0.08),
                        onSelected: (_) => setState(() => _proto = p),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                _field(_name, _t('نام (اختیاری)', 'Name (optional)')),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                        flex: 3, child: _field(_host, _t('آدرس', 'Address'))),
                    const SizedBox(width: 8),
                    Expanded(
                        child: _field(_port, _t('پورت', 'Port'),
                            number: true)),
                  ],
                ),
                const SizedBox(height: 8),
                _field(_secret, _secretLabel),
                const SizedBox(height: 8),
                if (_proto == VpnProtocol.vless ||
                    _proto == VpnProtocol.vmess ||
                    _proto == VpnProtocol.trojan) ...[
                  Row(
                    children: [
                      Expanded(
                        child: SegmentedButton<String>(
                          segments: const [
                            ButtonSegment(
                                value: 'tcp', label: Text('TCP')),
                            ButtonSegment(
                                value: 'ws', label: Text('WS')),
                            ButtonSegment(
                                value: 'grpc', label: Text('gRPC')),
                          ],
                          selected: {_net},
                          onSelectionChanged: (v) =>
                              setState(() => _net = v.first),
                          style: ButtonStyle(
                            textStyle: WidgetStateProperty.all(
                                const TextStyle(fontSize: 12)),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text('TLS',
                        style: TextStyle(
                            color: Colors.white, fontSize: 14)),
                    value: _tls,
                    onChanged: (v) => setState(() => _tls = v),
                    activeColor: pal.blue,
                  ),
                ],
                const SizedBox(height: 8),
                _field(_sni,
                    '${_t('SNI / Host', 'SNI / Host')} (${_t('اختیاری', 'optional')})'),
                const SizedBox(height: 14),
                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: pal.blue,
                    foregroundColor: Colors.white,
                    padding:
                        const EdgeInsets.symmetric(vertical: 12),
                  ),
                  onPressed: () {
                    final link = _buildLink();
                    if (link == null) {
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                        backgroundColor: pal.card,
                        content: Text(
                            _t('آدرس/پورت/رمز را کامل کن',
                                'Fill address/port/secret'),
                            style: const TextStyle(
                                color: Colors.white)),
                      ));
                      return;
                    }
                    final name = _name.text.trim().isEmpty
                        ? '${_host.text.trim()}'
                        : _name.text.trim();
                    final server = VpnServer(
                      id: LinkParser.stableId('c', link),
                      name: name,
                      flag: '⚡',
                      shareLink: link,
                      protocol: _proto,
                      host: _host.text.trim(),
                      port: int.tryParse(_port.text.trim()) ?? 0,
                    );
                    Navigator.pop(context, server);
                  },
                  child: Text(_t('ساخت و افزودن', 'Build & add')),
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _field(TextEditingController c, String hint, {bool number = false}) {
    final pal = IosPal.of(context);
    return TextField(
      controller: c,
      keyboardType: number ? TextInputType.number : null,
      style: const TextStyle(color: Colors.white, fontSize: 14),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(color: pal.textDim, fontSize: 13),
        filled: true,
        fillColor: Colors.white.withValues(alpha: 0.08),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(IosRadius.control),
          borderSide: BorderSide.none,
        ),
        contentPadding: const EdgeInsets.symmetric(
            horizontal: 12, vertical: 10),
      ),
    );
  }
}
