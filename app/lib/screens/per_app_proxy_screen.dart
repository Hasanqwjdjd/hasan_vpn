import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/app_colors.dart';
import '../services/settings_service.dart';

/// صفحه‌ی «پراکسی هر برنامه» — سه حالت مثل v2rayNG.
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
  final Set<String> _selected = {};
  String _mode = 'all';
  String _q = '';
  // فیلتر نوع اپ
  String _appFilter = 'all'; // all | user | system
  // sort
  String _sort = 'az'; // az | za | selected_first


  String _t(String fa, String en) =>
      widget.language.startsWith('fa') ? fa : en;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final mode = await SettingsService.getProxyMode();
    final selected = await SettingsService.getBlockedApps();
    _mode = mode;
    _selected.addAll(selected);
    try {
      final raw = await _ch.invokeMethod<List<dynamic>>('listApps');
      final list = <Map<String, dynamic>>[];
      if (raw != null) {
        for (final e in raw) {
          if (e is Map) list.add(Map<String, dynamic>.from(e));
        }
      }
      list.sort((a, b) {
        final la = (a['label'] ?? '').toString().toLowerCase();
        final lb = (b['label'] ?? '').toString().toLowerCase();
        return la.compareTo(lb);
      });
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

  Future<void> _setMode(String mode) async {
    setState(() => _mode = mode);
    await SettingsService.setProxyMode(mode);
  }

  Future<void> _toggle(String pkg, bool on) async {
    setState(() {
      if (on) {
        _selected.add(pkg);
      } else {
        _selected.remove(pkg);
      }
    });
    await SettingsService.setBlockedApps(_selected.toList()..sort());
  }

  @override
  Widget build(BuildContext context) {
    // فیلتر نوع (user/system)
    var filtered = _apps.where((a) {
      if (_appFilter == 'user') {
        return a['isSystem'] != true;
      }
      if (_appFilter == 'system') {
        return a['isSystem'] == true;
      }
      return true;
    }).toList();

    // search
    if (_q.isNotEmpty) {
      final q = _q.toLowerCase();
      filtered = filtered.where((a) {
        final l = '${a['label']} ${a['package']}'.toLowerCase();
        return l.contains(q);
      }).toList();
    }

    // sort
    switch (_sort) {
      case 'az':
        filtered.sort((a, b) => (a['label'] ?? '')
            .toString()
            .toLowerCase()
            .compareTo((b['label'] ?? '').toString().toLowerCase()));
        break;
      case 'za':
        filtered.sort((a, b) => (b['label'] ?? '')
            .toString()
            .toLowerCase()
            .compareTo((a['label'] ?? '').toString().toLowerCase()));
        break;
      case 'selected_first':
        filtered.sort((a, b) {
          final aSel = _selected.contains(a['package']?.toString() ?? '');
          final bSel = _selected.contains(b['package']?.toString() ?? '');
          if (aSel != bSel) return aSel ? -1 : 1;
          return (a['label'] ?? '')
              .toString()
              .toLowerCase()
              .compareTo((b['label'] ?? '').toString().toLowerCase());
        });
        break;
    }

    final listEnabled = _mode != 'all';

    return Scaffold(
      backgroundColor: AppColors.bg(context),
      appBar: AppBar(
        title: Text(_t('پراکسی هر برنامه', 'Per-app proxy')),
        backgroundColor: AppColors.bg(context),
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.import_export),
            tooltip: _t('پشتیبان‌گیری / بازیابی', 'Backup / Restore'),
            color: AppColors.surface(context),
            onSelected: (v) {
              if (v == 'export') {
                _exportBackup();
              } else if (v == 'import') {
                _importBackup();
              }
            },
            itemBuilder: (bCtx) => <PopupMenuEntry<String>>[
              PopupMenuItem(
                value: 'export',
                child: Row(children: [
                  Icon(Icons.upload_file,
                      size: 16, color: AppColors.fg(bCtx)),
                  const SizedBox(width: 8),
                  Text(_t('برون‌بری به کلیپ‌بورد (کپی)',
                      'Export to clipboard (copy)'),
                      style: TextStyle(color: AppColors.fg(bCtx))),
                ]),
              ),
              PopupMenuItem(
                value: 'import',
                child: Row(children: [
                  Icon(Icons.download,
                      size: 16, color: AppColors.fg(bCtx)),
                  const SizedBox(width: 8),
                  Text(_t('درون‌ریزی از کلیپ‌بورد (پیست)',
                      'Import from clipboard (paste)'),
                      style: TextStyle(color: AppColors.fg(bCtx))),
                ]),
              ),
            ],
          ),
          if (_mode != 'all')
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert),
              color: AppColors.surface(context),
              onSelected: _onBulkAction,
              itemBuilder: (bCtx) => <PopupMenuEntry<String>>[
                PopupMenuItem(
                  value: 'select_visible',
                  child: Row(children: [
                    Icon(Icons.check_circle_outline,
                        size: 16, color: AppColors.fg(bCtx)),
                    const SizedBox(width: 8),
                    Text(_t('انتخاب همه نمایش‌داده‌شده',
                        'Select all visible'),
                        style: TextStyle(color: AppColors.fg(bCtx))),
                  ]),
                ),
                PopupMenuItem(
                  value: 'clear_visible',
                  child: Row(children: [
                    Icon(Icons.remove_circle_outline,
                        size: 16, color: AppColors.fg(bCtx)),
                    const SizedBox(width: 8),
                    Text(_t('لغو انتخاب نمایش‌داده‌شده',
                        'Deselect visible'),
                        style: TextStyle(color: AppColors.fg(bCtx))),
                  ]),
                ),
                PopupMenuItem(
                  value: 'invert_visible',
                  child: Row(children: [
                    Icon(Icons.swap_horiz,
                        size: 16, color: AppColors.fg(bCtx)),
                    const SizedBox(width: 8),
                    Text(_t('معکوس انتخاب', 'Invert visible selection'),
                        style: TextStyle(color: AppColors.fg(bCtx))),
                  ]),
                ),
                const PopupMenuDivider(),
                PopupMenuItem(
                  value: 'clear_all',
                  child: Row(children: [
                    const Icon(Icons.delete_sweep_outlined,
                        size: 16, color: Colors.red),
                    const SizedBox(width: 8),
                    Text(_t('پاک کردن همه', 'Clear all'),
                        style: const TextStyle(color: Colors.red)),
                  ]),
                ),
              ],
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _modeCard(context, 'all',
                          'همه برنامه‌ها تونل بشن',
                          'All apps through VPN',
                          'تمام ترافیک برنامه‌ها از تونل عبور می‌کند',
                          'All app traffic goes through the tunnel'),
                      const SizedBox(height: 6),
                      _modeCard(context, 'blacklist',
                          'برنامه‌های انتخاب‌شده تونل نشن',
                          'Selected apps bypass VPN',
                          'این برنامه‌ها از تونل مستثنی می‌شوند',
                          'These apps are excluded from the tunnel'),
                      const SizedBox(height: 6),
                      _modeCard(context, 'whitelist',
                          'فقط برنامه‌های انتخاب‌شده تونل بشن',
                          'Only selected apps through VPN',
                          'بقیه‌ی برنامه‌ها از تونل مستثنی می‌شوند',
                          'All other apps bypass the tunnel'),
                    ],
                  ),
                ),
                const Divider(height: 1),
                if (listEnabled)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                    child: Column(
                      children: [
                        // Filter chips
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: [
                              _filterChip('all',
                                  _t('همه', 'All'), Icons.apps),
                              const SizedBox(width: 6),
                              _filterChip('user',
                                  _t('کاربر', 'User'), Icons.person),
                              const SizedBox(width: 6),
                              _filterChip('system',
                                  _t('سیستم', 'System'), Icons.settings),
                              const SizedBox(width: 6),
                              _sortChip(),
                            ],
                          ),
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          decoration: InputDecoration(
                            hintText: _t('جستجو', 'Search'),
                            prefixIcon: const Icon(Icons.search),
                            isDense: true,
                            suffixIcon: _q.isNotEmpty
                                ? IconButton(
                                    icon: const Icon(Icons.clear, size: 18),
                                    onPressed: () =>
                                        setState(() => _q = ''),
                                  )
                                : null,
                          ),
                          onChanged: (v) => setState(() => _q = v),
                        ),
                        const SizedBox(height: 6),
                        // Selection count
                        Row(
                          children: [
                            Icon(Icons.checklist,
                                size: 14,
                                color: AppColors.muted(context)),
                            const SizedBox(width: 6),
                            Text(
                              _t(
                                '${_selected.length} از ${_apps.length} انتخاب‌شده · ${filtered.length} نمایش',
                                '${_selected.length}/${_apps.length} selected · ${filtered.length} shown',
                              ),
                              style: TextStyle(
                                color: AppColors.muted2(context),
                                fontSize: 10.5,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                Expanded(
                  child: !listEnabled
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Text(
                              _t(
                                'در این حالت همه‌ی برنامه‌ها از تونل رد می‌شوند.',
                                'In this mode all apps go through the tunnel.',
                              ),
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                  color: AppColors.muted(context),
                                  height: 1.7),
                            ),
                          ),
                        )
                      : ListView.builder(
                          itemCount: filtered.length,
                          itemBuilder: (ctx, i) {
                            final a = filtered[i];
                            final pkg = a['package']?.toString() ?? '';
                            final label = a['label']?.toString() ?? pkg;
                            final on = _selected.contains(pkg);
                            final iconB64 =
                                a['icon']?.toString() ?? '';
                            Uint8List? iconBytes;
                            if (iconB64.isNotEmpty) {
                              try {
                                iconBytes = base64Decode(iconB64);
                              } catch (_) {}
                            }
                            return SwitchListTile(
                              secondary: iconBytes != null
                                  ? ClipRRect(
                                      borderRadius:
                                          BorderRadius.circular(6),
                                      child: Image.memory(
                                        iconBytes,
                                        width: 32,
                                        height: 32,
                                        gaplessPlayback: true,
                                      ),
                                    )
                                  : const Icon(Icons.android,
                                      size: 28),
                              title: Text(label,
                                  style: TextStyle(
                                      color: AppColors.fg(context))),
                              subtitle: Text(pkg,
                                  style: TextStyle(
                                      color: AppColors.muted2(context),
                                      fontSize: 11)),
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

  /// Backup: mode + selected packages → JSON in clipboard.
  Future<void> _exportBackup() async {
    final data = <String, dynamic>{
      'version': 1,
      'mode': _mode,
      'apps': (_selected.toList()..sort()),
      'exportedAt': DateTime.now().toIso8601String(),
    };
    final json = const JsonEncoder.withIndent('  ').convert(data);
    await Clipboard.setData(ClipboardData(text: json));
    if (!mounted) return;
    _showMsg(_t(
      'کپی شد در کلیپ‌بورد (${_selected.length} برنامه)',
      'Copied to clipboard (${_selected.length} apps)',
    ));
  }

  /// Restore: read JSON from clipboard, apply mode + apps.
  Future<void> _importBackup() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim() ?? '';
    if (text.isEmpty) {
      _showMsg(_t('کلیپ‌بورد خالی است', 'Clipboard is empty'));
      return;
    }
    try {
      final decoded = jsonDecode(text);
      if (decoded is! Map) {
        _showMsg(_t('فرمت نامعتبر', 'Invalid format'));
        return;
      }
      final mode = decoded['mode']?.toString() ?? 'all';
      if (!const {'all', 'blacklist', 'whitelist'}.contains(mode)) {
        _showMsg(_t('حالت نامعتبر در JSON', 'Invalid mode in JSON'));
        return;
      }
      final appsRaw = decoded['apps'];
      if (appsRaw is! List) {
        _showMsg(_t('لیست apps پیدا نشد', 'apps list missing'));
        return;
      }
      final apps = appsRaw
          .map((e) => e.toString().trim())
          .where((s) => s.isNotEmpty)
          .toList()
        ..sort();
      await SettingsService.setProxyMode(mode);
      await SettingsService.setBlockedApps(apps);
      if (!mounted) return;
      setState(() {
        _mode = mode;
        _selected.clear();
        _selected.addAll(apps);
      });
      _showMsg(_t(
        'بازیابی شد: ${apps.length} برنامه (حالت $mode)',
        'Restored: ${apps.length} apps (mode $mode)',
      ));
    } catch (e) {
      _showMsg(_t('خطا در بازیابی: $e', 'Import error: $e'));
    }
  }

  void _onBulkAction(String action) async {
    var filtered = _apps.where((a) {
      if (_appFilter == 'user') return a['isSystem'] != true;
      if (_appFilter == 'system') return a['isSystem'] == true;
      return true;
    }).toList();
    if (_q.isNotEmpty) {
      final q = _q.toLowerCase();
      filtered = filtered.where((a) {
        final l = '${a['label']} ${a['package']}'.toLowerCase();
        return l.contains(q);
      }).toList();
    }
    final visiblePkgs = filtered
        .map((a) => a['package']?.toString() ?? '')
        .where((p) => p.isNotEmpty)
        .toList();

    setState(() {
      switch (action) {
        case 'select_visible':
          _selected.addAll(visiblePkgs);
          break;
        case 'clear_visible':
          _selected.removeAll(visiblePkgs);
          break;
        case 'invert_visible':
          for (final p in visiblePkgs) {
            if (_selected.contains(p)) {
              _selected.remove(p);
            } else {
              _selected.add(p);
            }
          }
          break;
        case 'clear_all':
          _selected.clear();
          break;
      }
    });
    await SettingsService.setBlockedApps(_selected.toList()..sort());
    if (!mounted) return;
    _showMsg(_t('ذخیره شد', 'Saved'));
  }

  void _showMsg(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        duration: const Duration(seconds: 1),
      ),
    );
  }

  Widget _filterChip(String key, String label, IconData icon) {
    final active = _appFilter == key;
    return ChoiceChip(
      avatar: Icon(
        icon,
        size: 16,
        color: active ? Colors.black : AppColors.fg(context),
      ),
      label: Text(
        label,
        style: TextStyle(
          color: active ? Colors.black : AppColors.fg(context),
          fontSize: 11,
        ),
      ),
      selected: active,
      selectedColor: AppColors.accent,
      backgroundColor: AppColors.surface(context),
      side: BorderSide(color: AppColors.border(context)),
      onSelected: (_) => setState(() => _appFilter = key),
    );
  }

  Widget _sortChip() {
    final label = switch (_sort) {
      'za' => 'Z→A',
      'selected_first' => _t('انتخاب‌شده اول', 'Selected first'),
      _ => 'A→Z',
    };
    return PopupMenuButton<String>(
      color: AppColors.surface(context),
      onSelected: (v) => setState(() => _sort = v),
      child: Chip(
        avatar: Icon(
          Icons.sort,
          size: 16,
          color: AppColors.fg(context),
        ),
        label: Text(
          label,
          style: TextStyle(color: AppColors.fg(context), fontSize: 11),
        ),
        backgroundColor: AppColors.surface(context),
        side: BorderSide(color: AppColors.border(context)),
      ),
      itemBuilder: (bCtx) => [
        PopupMenuItem(
          value: 'az',
          child: Text(_t('حروف A→Z', 'A → Z')),
        ),
        PopupMenuItem(
          value: 'za',
          child: Text(_t('حروف Z→A', 'Z → A')),
        ),
        PopupMenuItem(
          value: 'selected_first',
          child: Text(_t('انتخاب‌شده اول', 'Selected first')),
        ),
      ],
    );
  }

  Widget _modeCard(BuildContext context, String key, String tFa, String tEn,
      String sFa, String sEn) {
    final active = _mode == key;
    return InkWell(
      onTap: () => _setMode(key),
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: active
              ? AppColors.accent.withValues(alpha: 0.15)
              : AppColors.surface(context),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: active ? AppColors.accent : AppColors.border(context),
            width: active ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            Icon(
              active ? Icons.radio_button_checked : Icons.radio_button_off,
              color: active ? AppColors.accent : AppColors.muted(context),
              size: 20,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(_t(tFa, tEn),
                      style: TextStyle(
                          color: AppColors.fg(context),
                          fontSize: 13,
                          fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Text(_t(sFa, sEn),
                      style: TextStyle(
                          color: AppColors.muted2(context),
                          fontSize: 11,
                          height: 1.4)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
