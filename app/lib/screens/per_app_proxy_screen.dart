import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/app_colors.dart';
import '../services/settings_service.dart';

class PerAppProxyScreen extends StatefulWidget {
  const PerAppProxyScreen({super.key, required this.language});
  final String language;

  @override
  State<PerAppProxyScreen> createState() => _PerAppProxyScreenState();
}

class _PerAppProxyScreenState extends State<PerAppProxyScreen> {
  static const _ch = MethodChannel('com.hasan.hasan_vpn/device');
  bool _loading = true;
  List<Map<String, dynamic>> _apps = [];
  final Set<String> _blocked = {};
  String _q = '';

  String _t(String fa, String en) =>
      widget.language.startsWith('fa') ? fa : en;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final blocked = await SettingsService.getBlockedApps();
    _blocked.addAll(blocked);
    try {
      final raw = await _ch.invokeMethod<List<dynamic>>('listApps');
      final list = <Map<String, dynamic>>[];
      if (raw != null) {
        for (final e in raw) {
          if (e is Map) {
            list.add(Map<String, dynamic>.from(e));
          }
        }
      }
      if (mounted) {
        setState(() {
          _apps = list;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _toggle(String pkg, bool on) async {
    setState(() {
      if (on) {
        _blocked.add(pkg);
      } else {
        _blocked.remove(pkg);
      }
    });
    await SettingsService.setBlockedApps(_blocked.toList()..sort());
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _q.isEmpty
        ? _apps
        : _apps.where((a) {
            final l = '${a['label']} ${a['package']}'.toLowerCase();
            return l.contains(_q.toLowerCase());
          }).toList();

    return Scaffold(
      backgroundColor: AppColors.bg(context),
      appBar: AppBar(
        title: Text(_t('پراکسی هر برنامه', 'Per-app proxy')),
        backgroundColor: AppColors.bg(context),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: TextField(
                    decoration: InputDecoration(
                      hintText: _t('جستجو', 'Search'),
                      prefixIcon: const Icon(Icons.search),
                    ),
                    onChanged: (v) => setState(() => _q = v),
                  ),
                ),
                Expanded(
                  child: ListView.builder(
                    itemCount: filtered.length,
                    itemBuilder: (ctx, i) {
                      final a = filtered[i];
                      final pkg = a['package']?.toString() ?? '';
                      final label = a['label']?.toString() ?? pkg;
                      final on = _blocked.contains(pkg);
                      return SwitchListTile(
                        title: Text(label,
                            style: TextStyle(color: AppColors.fg(context))),
                        subtitle: Text(pkg,
                            style: TextStyle(
                                color: AppColors.muted2(context), fontSize: 11)),
                        value: on,
                        onChanged: (v) => _toggle(pkg, v),
                      );
                    },
                  ),
                ),
              ],
            ),
    );
  }
}
