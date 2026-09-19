import 'package:flutter/material.dart';
import '../models/subscription.dart';
import '../services/subscription_service.dart';
import '../services/app_colors.dart';

class SubscriptionsScreen extends StatefulWidget {
  final List<Subscription> subscriptions;
  final Function(List<Subscription>) onChanged;
  final String language;

  const SubscriptionsScreen({
    super.key,
    required this.subscriptions,
    required this.onChanged,
    this.language = 'fa',
  });

  @override
  State<SubscriptionsScreen> createState() => _SubscriptionsScreenState();
}

class _SubscriptionsScreenState extends State<SubscriptionsScreen> {
  late List<Subscription> _subs;
  final Set<String> _loading = {};

  bool get _isFa => widget.language == 'fa';
  String _t(String fa, String en) => _isFa ? fa : en;

  @override
  void initState() {
    super.initState();
    _subs = List.from(widget.subscriptions);
  }

  Future<void> _addSub() async {
    final nameCtrl = TextEditingController();
    final urlCtrl = TextEditingController();

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.elevated(ctx),
        title: Text(_t('اشتراک جدید', 'New Subscription'), style: TextStyle(color: AppColors.fg(ctx))),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtrl,
              style: TextStyle(color: AppColors.fg(ctx)),
              decoration: InputDecoration(
                labelText: _t('نام', 'Name'),
                labelStyle: TextStyle(color: AppColors.muted(ctx)),
                enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: AppColors.border(ctx))),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: urlCtrl,
              style: TextStyle(color: AppColors.fg(ctx)),
              decoration: InputDecoration(
                labelText: _t('لینک اشتراک', 'Subscription URL'),
                labelStyle: TextStyle(color: AppColors.muted(ctx)),
                enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: AppColors.border(ctx))),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(_t('لغو', 'Cancel'), style: TextStyle(color: AppColors.muted(ctx))),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(_t('افزودن', 'Add'), style: const TextStyle(color: AppColors.accent)),
          ),
        ],
      ),
    );

    if (ok != true) return;
    if (nameCtrl.text.trim().isEmpty || urlCtrl.text.trim().isEmpty) return;

    final newSub = Subscription(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      name: nameCtrl.text.trim(),
      url: urlCtrl.text.trim(),
    );

    setState(() => _subs.add(newSub));
    await SubscriptionService.save(_subs);
    widget.onChanged(_subs);
    _refresh(newSub);
  }

  Future<void> _refresh(Subscription sub) async {
    setState(() => _loading.add(sub.id));
    try {
      final servers = await SubscriptionService.fetch(sub);
      sub.lastUpdated = DateTime.now();
      sub.serverCount = servers.length;
      await SubscriptionService.save(_subs);
      widget.onChanged(_subs);
      if (mounted) {
        _showMsg('${servers.length} ${_t('سرور بارگیری شد از', 'servers loaded from')} ${sub.name}');
      }
    } catch (e) {
      _showMsg('${_t('خطا', 'Error')}: $e');
    } finally {
      if (mounted) setState(() => _loading.remove(sub.id));
    }
  }

  Future<void> _delete(Subscription sub) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.elevated(ctx),
        title: Text(_t('حذف اشتراک؟', 'Delete subscription?'), style: TextStyle(color: AppColors.fg(ctx))),
        content: Text(sub.name, style: TextStyle(color: AppColors.muted(ctx))),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(_t('لغو', 'Cancel'), style: TextStyle(color: AppColors.muted(ctx))),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(_t('حذف', 'Delete'), style: const TextStyle(color: AppColors.danger)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _subs.removeWhere((s) => s.id == sub.id));
    await SubscriptionService.save(_subs);
    widget.onChanged(_subs);
  }

  Future<void> _refreshAll() async {
    for (final s in _subs) {
      await _refresh(s);
    }
  }

  Future<void> _setInterval(Subscription sub) async {
    final options = [1, 3, 6, 12, 24, 48, 168];
    final picked = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.elevated(ctx),
        title: Text(_t('تایم بروزرسانی خودکار', 'Auto-update interval'), style: TextStyle(color: AppColors.fg(ctx))),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: options
                .map((h) => ListTile(
                      title: Text(
                        h < 24 ? '$h ${_t('ساعت', 'hours')}' : '${h ~/ 24} ${_t('روز', 'days')}',
                        style: TextStyle(color: AppColors.fg(ctx)),
                      ),
                      trailing: sub.intervalHours == h ? const Icon(Icons.check, color: AppColors.accent, size: 18) : null,
                      onTap: () => Navigator.pop(ctx, h),
                    ))
                .toList(),
          ),
        ),
      ),
    );
    if (picked != null) {
      setState(() => sub.intervalHours = picked);
      await SubscriptionService.save(_subs);
      widget.onChanged(_subs);
    }
  }

  String _timeAgo(DateTime? dt) {
    if (dt == null) return _t('هرگز', 'never');
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return _t('همین الان', 'just now');
    if (diff.inHours < 1) return '${diff.inMinutes} ${_t('دقیقه پیش', 'min ago')}';
    if (diff.inDays < 1) return '${diff.inHours} ${_t('ساعت پیش', 'h ago')}';
    return '${diff.inDays} ${_t('روز پیش', 'd ago')}';
  }

  String _intervalLabel(int h) {
    if (h < 24) return '${_t('هر', 'every')} $h ${_t('ساعت', 'h')}';
    return '${_t('هر', 'every')} ${h ~/ 24} ${_t('روز', 'd')}';
  }

  void _showMsg(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), duration: const Duration(seconds: 2)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg(context),
      appBar: AppBar(
        backgroundColor: AppColors.bg(context),
        elevation: 0,
        iconTheme: IconThemeData(color: AppColors.fg(context)),
        title: Text(_t('اشتراک‌ها', 'Subscriptions'), style: TextStyle(color: AppColors.fg(context))),
        centerTitle: true,
        actions: [
          IconButton(onPressed: _subs.isEmpty ? null : _refreshAll, icon: Icon(Icons.refresh, color: AppColors.fg(context))),
          IconButton(onPressed: _addSub, icon: Icon(Icons.add, color: AppColors.fg(context))),
        ],
      ),
      body: _subs.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.rss_feed, color: AppColors.muted2(context), size: 64),
                  const SizedBox(height: 16),
                  Text(_t('هیچ اشتراکی نداری', 'No subscriptions'), style: TextStyle(color: AppColors.muted(context), fontSize: 16)),
                  const SizedBox(height: 8),
                  Text(_t('با دکمه + اضافه کن', 'Add with + button'), style: TextStyle(color: AppColors.muted2(context), fontSize: 12)),
                ],
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _subs.length,
              itemBuilder: (_, i) {
                final s = _subs[i];
                final loading = _loading.contains(s.id);
                return Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.surface(context),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.border(context)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              s.name,
                              style: TextStyle(color: AppColors.fg(context), fontSize: 14, fontWeight: FontWeight.w600),
                            ),
                          ),
                          if (loading)
                            const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.accent))
                          else
                            IconButton(
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                              icon: Icon(Icons.refresh, color: AppColors.muted(context), size: 18),
                              onPressed: () => _refresh(s),
                            ),
                          const SizedBox(width: 6),
                          IconButton(
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                            icon: const Icon(Icons.delete_outline, color: AppColors.danger, size: 18),
                            onPressed: () => _delete(s),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(s.url, style: TextStyle(color: AppColors.muted2(context), fontSize: 10), maxLines: 1, overflow: TextOverflow.ellipsis),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Text('${s.serverCount} ${_t('سرور', 'servers')}', style: const TextStyle(color: AppColors.accent, fontSize: 11)),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              '${_t('آخرین', 'last')}: ${_timeAgo(s.lastUpdated)}',
                              style: TextStyle(color: AppColors.muted2(context), fontSize: 11),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Transform.scale(
                            scale: 0.7,
                            child: Switch(
                              value: s.autoUpdate,
                              onChanged: (v) async {
                                setState(() => s.autoUpdate = v);
                                await SubscriptionService.save(_subs);
                                widget.onChanged(_subs);
                              },
                              activeColor: AppColors.accent,
                            ),
                          ),
                          Text(_t('بروزرسانی خودکار', 'Auto update'), style: TextStyle(color: AppColors.muted(context), fontSize: 11)),
                          const Spacer(),
                          if (s.autoUpdate)
                            GestureDetector(
                              onTap: () => _setInterval(s),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: AppColors.elevated(context),
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(color: AppColors.border(context)),
                                ),
                                child: Text(_intervalLabel(s.intervalHours), style: TextStyle(color: AppColors.muted(context), fontSize: 10)),
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                );
              },
            ),
    );
  }
}
