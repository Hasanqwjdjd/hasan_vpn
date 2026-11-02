import 'package:flutter/material.dart';
import '../services/app_colors.dart';
import '../services/routing_service.dart';
import '../services/xray_settings.dart';

/// A6 + BLOCKER 6 — editable rules with drag-reorder.
class RoutingScreen extends StatefulWidget {
  final String language;
  const RoutingScreen({super.key, required this.language});
  @override
  State<RoutingScreen> createState() => _RoutingScreenState();
}

class _RoutingScreenState extends State<RoutingScreen> {
  List<Map<String, dynamic>> _rules = [];
  String _strategy = 'AsIs';
  bool _loading = true;
  bool get _isFa => widget.language.startsWith('fa');
  String _t(String fa, String en) => _isFa ? fa : en;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final r = await RoutingService.loadRules();
    final s = await RoutingService.getDomainStrategy();
    if (!mounted) return;
    setState(() {
      _rules = r;
      _strategy = s;
      _loading = false;
    });
  }

  Future<void> _save() async {
    await RoutingService.saveRules(_rules);
    await RoutingService.setDomainStrategy(_strategy);
    await XraySettings.set('domainStrategy', _strategy);
  }

  Future<void> _editRule(int? index) async {
    final isNew = index == null;
    final rule = isNew
        ? <String, dynamic>{
            'id': DateTime.now().millisecondsSinceEpoch.toString(),
            'enabled': true,
            'outboundTag': 'proxy',
            'domain': <String>[],
            'ip': <String>[],
            'port': '',
            'protocol': <String>[],
            'remark': '',
          }
        : Map<String, dynamic>.from(_rules[index]);
    final remarkCtrl =
        TextEditingController(text: rule['remark']?.toString() ?? '');
    final domainCtrl = TextEditingController(
        text: ((rule['domain'] as List?) ?? []).join(','));
    final ipCtrl =
        TextEditingController(text: ((rule['ip'] as List?) ?? []).join(','));
    final portCtrl =
        TextEditingController(text: rule['port']?.toString() ?? '');
    String tag = rule['outboundTag']?.toString() ?? 'proxy';

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface(ctx),
        title: Text(isNew
            ? _t('قانون جدید', 'New rule')
            : _t('ویرایش قانون', 'Edit rule')),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                  controller: remarkCtrl,
                  decoration:
                      InputDecoration(labelText: _t('توضیح', 'Remark'))),
              TextField(
                  controller: domainCtrl,
                  decoration:
                      const InputDecoration(labelText: 'domains (comma)')),
              TextField(
                  controller: ipCtrl,
                  decoration: const InputDecoration(labelText: 'IPs (comma)')),
              TextField(
                  controller: portCtrl,
                  decoration: const InputDecoration(labelText: 'port')),
              DropdownButtonFormField<String>(
                value: tag,
                items: ['proxy', 'direct', 'block']
                    .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                    .toList(),
                onChanged: (v) => tag = v ?? 'proxy',
                decoration: const InputDecoration(labelText: 'outbound'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(_t('لغو', 'Cancel'))),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(_t('ذخیره', 'Save'))),
        ],
      ),
    );
    if (ok != true) return;
    rule['remark'] = remarkCtrl.text.trim();
    rule['domain'] = domainCtrl.text
        .split(',')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    rule['ip'] = ipCtrl.text
        .split(',')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    rule['port'] = portCtrl.text.trim();
    rule['outboundTag'] = tag;
    setState(() {
      if (isNew) {
        _rules.add(rule);
      } else {
        _rules[index!] = rule;
      }
    });
    await _save();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg(context),
      appBar: AppBar(
        title: Text(_t('مسیریابی', 'Routing')),
        backgroundColor: AppColors.bg(context),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () => _editRule(null),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                ListTile(
                  title: Text(_t('استراتژی دامنه', 'Domain strategy')),
                  trailing: DropdownButton<String>(
                    value: _strategy,
                    items: ['AsIs', 'IPIfNonMatch', 'IPOnDemand']
                        .map((e) =>
                            DropdownMenuItem(value: e, child: Text(e)))
                        .toList(),
                    onChanged: (v) async {
                      if (v == null) return;
                      setState(() => _strategy = v);
                      await _save();
                    },
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Text(
                    _t('برای جابجایی قوانین، دسته را بکشید',
                        'Drag the handle to reorder rules'),
                    style: TextStyle(
                        color: AppColors.muted(context), fontSize: 11),
                  ),
                ),
                const Divider(),
                Expanded(
                  child: ReorderableListView.builder(
                    itemCount: _rules.length,
                    onReorder: (oldIndex, newIndex) async {
                      setState(() {
                        if (newIndex > oldIndex) newIndex -= 1;
                        final item = _rules.removeAt(oldIndex);
                        _rules.insert(newIndex, item);
                      });
                      await _save();
                    },
                    itemBuilder: (ctx, i) {
                      final r = _rules[i];
                      return ListTile(
                        key: ValueKey(r['id'] ?? i),
                        leading: Switch(
                          value: r['enabled'] == true,
                          onChanged: (v) async {
                            setState(() => r['enabled'] = v);
                            await _save();
                          },
                        ),
                        title: Text(r['remark']?.toString().isNotEmpty == true
                            ? r['remark'].toString()
                            : 'Rule ${i + 1}'),
                        subtitle: Text(
                            '→ ${r['outboundTag']}  domains:${(r['domain'] as List?)?.length ?? 0} ips:${(r['ip'] as List?)?.length ?? 0}'),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                                icon: const Icon(Icons.edit, size: 18),
                                onPressed: () => _editRule(i)),
                            IconButton(
                                icon: const Icon(Icons.delete_outline,
                                    size: 18, color: Colors.red),
                                onPressed: () async {
                                  setState(() => _rules.removeAt(i));
                                  await _save();
                                }),
                            ReorderableDragStartListener(
                              index: i,
                              child: const Icon(Icons.drag_handle),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
    );
  }
}
