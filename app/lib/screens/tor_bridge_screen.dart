import 'package:flutter/material.dart';

import '../services/app_colors.dart';
import '../services/network_prober.dart';
import '../services/tor_bridges.dart';
import '../services/tor_service.dart';

/// Manage / fetch Tor bridge lines per type (Moat + custom paste).
class TorBridgeScreen extends StatefulWidget {
  final String language;
  final String initialType;
  final List<String>? initialCustom;

  const TorBridgeScreen({
    super.key,
    this.language = 'fa',
    this.initialType = 'obfs4',
    this.initialCustom,
  });

  @override
  State<TorBridgeScreen> createState() => _TorBridgeScreenState();
}

class _TorBridgeScreenState extends State<TorBridgeScreen> {
  static const _types = <Map<String, String>>[
    {'id': 'obfs4', 'fa': 'obfs4', 'en': 'obfs4'},
    {'id': 'snowflake', 'fa': 'Snowflake', 'en': 'Snowflake'},
    {'id': 'meek_lite', 'fa': 'Meek / Azure', 'en': 'Meek / Azure'},
    {'id': 'webtunnel', 'fa': 'WebTunnel', 'en': 'WebTunnel'},
    {'id': 'conjure', 'fa': 'Conjure', 'en': 'Conjure'},
    {'id': 'custom', 'fa': 'سفارشی (چسباندن)', 'en': 'Custom (paste)'},
  ];

  late String _type;
  final TextEditingController _pasteCtrl = TextEditingController();
  List<String> _lines = [];
  bool _fetching = false;
  String? _error;
  final Map<String, int?> _rtts = {};

  bool get _isFa => widget.language == 'fa';
  String _t(String fa, String en) => _isFa ? fa : en;

  bool get _moatSupported =>
      const {'obfs4', 'snowflake', 'meek_lite', 'webtunnel'}.contains(_type);

  bool get _needsTextarea => _type == 'custom' || _type == 'conjure';

  @override
  void initState() {
    super.initState();
    _type = widget.initialType;
    if (widget.initialCustom != null && widget.initialCustom!.isNotEmpty) {
      _lines = List<String>.from(widget.initialCustom!);
      _pasteCtrl.text = _lines.join('\n');
    } else {
      _loadStatic();
    }
  }

  @override
  void dispose() {
    _pasteCtrl.dispose();
    super.dispose();
  }

  void _loadStatic() {
    if (_type == 'custom') {
      _lines = [];
      _pasteCtrl.clear();
    } else {
      _lines = List<String>.from(TorBridges.forType(_type));
      _pasteCtrl.text = _lines.join('\n');
    }
    setState(() {});
  }

  Future<void> _fetchMoat() async {
    if (!_moatSupported || _fetching) return;
    setState(() {
      _fetching = true;
      _error = null;
    });
    try {
      final native = await TorService.fetchMoatBridges(_type, country: 'ir');
      List<String> bridges = [];
      if (native['ok'] == true && native['bridges'] is List) {
        bridges = (native['bridges'] as List)
            .map((e) => e.toString().trim())
            .where((s) => s.isNotEmpty)
            .toList();
      }
      if (bridges.isEmpty) {
        try {
          final dart = await TorBridges.fetchDynamic(_type, country: 'ir');
          if (dart != null && dart.isNotEmpty) bridges = dart;
        } catch (_) {}
      }
      if (bridges.isEmpty) {
        if (!mounted) return;
        setState(() {
          _error = _t('هیچ پلی از Moat دریافت نشد', 'No bridges from Moat');
          _fetching = false;
        });
        return;
      }
      if (!mounted) return;
      setState(() {
        _lines = bridges;
        _pasteCtrl.text = bridges.join('\n');
        _fetching = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _fetching = false;
      });
    }
  }

  void _applyPaste() {
    setState(() {
      _lines = _pasteCtrl.text
          .split(RegExp(r'[\r\n]+'))
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty && !s.startsWith('#'))
          .toList();
    });
  }

  Future<void> _testLine(String line) async {
    final ep = TorBridges.parseEndpoint(line);
    if (ep == null) {
      setState(() => _rtts[line] = -1);
      return;
    }
    setState(() => _rtts[line] = null);
    try {
      final r = await NetworkProber.probeTcp(
        ep.host,
        port: ep.port,
        samples: 2,
        timeout: const Duration(seconds: 3),
      );
      if (!mounted) return;
      setState(() => _rtts[line] = r.avgMs ?? -1);
    } catch (_) {
      if (!mounted) return;
      setState(() => _rtts[line] = -1);
    }
  }

  void _popWithResult() {
    Navigator.of(context).pop(<String, dynamic>{
      'type': _type == 'custom' ? 'obfs4' : _type,
      'bridges': _lines,
    });
  }

  @override
  Widget build(BuildContext context) {
    final fg = AppColors.fg(context);
    final muted = AppColors.muted(context);
    final surface = AppColors.surface(context);
    final accent = AppColors.accent;

    return Scaffold(
      backgroundColor: AppColors.bg(context),
      appBar: AppBar(
        backgroundColor: surface,
        title: Text(
          _t('مدیریت پل‌های Tor', 'Tor Bridges'),
          style: TextStyle(color: fg, fontSize: 16),
        ),
        iconTheme: IconThemeData(color: fg),
        actions: [
          TextButton(
            onPressed: _lines.isEmpty ? null : _popWithResult,
            child: Text(
              _t('اعمال', 'Apply'),
              style: TextStyle(color: accent),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: _types.map((t) {
              final id = t['id']!;
              final selected = _type == id;
              return ChoiceChip(
                label: Text(_isFa ? t['fa']! : t['en']!),
                selected: selected,
                onSelected: (_) {
                  setState(() {
                    _type = id;
                    _error = null;
                  });
                  _loadStatic();
                },
                selectedColor: accent.withOpacity(0.25),
                labelStyle: TextStyle(
                  color: selected ? accent : fg,
                  fontSize: 12,
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 12),
          if (_moatSupported)
            ElevatedButton.icon(
              onPressed: _fetching ? null : _fetchMoat,
              icon: _fetching
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.cloud_download, size: 18),
              label: Text(_t('دریافت از Tor (Moat)', 'Fetch from Tor (Moat)')),
              style: ElevatedButton.styleFrom(
                backgroundColor: accent,
                foregroundColor: Colors.white,
              ),
            ),
          if (_needsTextarea) ...[
            const SizedBox(height: 8),
            TextField(
              controller: _pasteCtrl,
              maxLines: 8,
              style: TextStyle(
                color: fg,
                fontSize: 12,
                fontFamily: 'monospace',
              ),
              decoration: InputDecoration(
                filled: true,
                fillColor: surface,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                hintText: 'obfs4 host:port FINGERPRINT cert=... iat-mode=0',
                hintStyle: TextStyle(color: muted, fontSize: 11),
              ),
              onChanged: (_) => _applyPaste(),
            ),
          ],
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                _error!,
                style: const TextStyle(
                  color: Colors.redAccent,
                  fontSize: 12,
                ),
              ),
            ),
          const SizedBox(height: 8),
          ..._lines.map((line) {
            final rtt = _rtts[line];
            String label = '';
            if (rtt == null && _rtts.containsKey(line)) {
              label = '...';
            } else if (rtt != null && rtt >= 0) {
              label = '$rtt ms';
            } else if (rtt != null) {
              label = 'fail';
            }
            return Card(
              color: surface,
              margin: const EdgeInsets.only(bottom: 6),
              child: ListTile(
                dense: true,
                title: Text(
                  TorBridges.shortLabel(line),
                  style: TextStyle(color: fg, fontSize: 12),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  line,
                  style: TextStyle(
                    color: muted,
                    fontSize: 10,
                    fontFamily: 'monospace',
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (label.isNotEmpty)
                      Text(
                        label,
                        style: TextStyle(color: muted, fontSize: 11),
                      ),
                    IconButton(
                      icon: const Icon(Icons.speed, size: 18),
                      onPressed: () => _testLine(line),
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete_outline, size: 18),
                      onPressed: () {
                        setState(() {
                          _lines.remove(line);
                          _pasteCtrl.text = _lines.join('\n');
                        });
                      },
                    ),
                  ],
                ),
              ),
            );
          }),
        ],
      ),
    );
  }
}
