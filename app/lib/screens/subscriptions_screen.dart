import 'package:flutter/material.dart';
import '../models/subscription.dart';
import '../services/subscription_service.dart';

class SubscriptionsScreen extends StatefulWidget {
  final List<Subscription> subscriptions;
  final Function(List<Subscription>) onChanged;
  const SubscriptionsScreen({
    super.key,
    required this.subscriptions,
    required this.onChanged,
  });

  @override
  State<SubscriptionsScreen> createState() => _SubscriptionsScreenState();
}

class _SubscriptionsScreenState extends State<SubscriptionsScreen> {
  late List<Subscription> _subs;
  final Set<String> _loading = {};

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
        backgroundColor: const Color(0xFF1A1D25),
        title: const Text('اشتراک جدید',
            style: TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtrl,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                labelText: 'نام',
                labelStyle: TextStyle(color: Colors.white54),
                enabledBorder: UnderlineInputBorder(
                  borderSide: BorderSide(color: Colors.white24),
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: urlCtrl,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                labelText: 'لینک اشتراک',
                labelStyle: TextStyle(color: Colors.white54),
                enabledBorder: UnderlineInputBorder(
                  borderSide: BorderSide(color: Colors.white24),
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('لغو',
                style: TextStyle(color: Colors.white54)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('افزودن',
                style: TextStyle(color: Color(0xFF3DCF9A))),
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${servers.length} سرور از ${sub.name} بارگیری شد'),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('خطا: $e'),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _loading.remove(sub.id));
    }
  }

  Future<void> _delete(Subscription sub) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1D25),
        title: const Text('حذف اشتراک؟',
            style: TextStyle(color: Colors.white)),
        content: Text(sub.name,
            style: const TextStyle(color: Colors.white70)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('لغو',
                style: TextStyle(color: Colors.white54)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child:
                const Text('حذف', style: TextStyle(color: Color(0xFFE07070))),
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
    final options = [1, 3, 6, 12, 24, 48, 168]; // ساعت
    final picked = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1D25),
        title: const Text('تایم بروزرسانی خودکار',
            style: TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: options
              .map((h) => ListTile(
                    title: Text(
                      h < 24 ? '$h ساعت' : '${h ~/ 24} روز',
                      style: const TextStyle(color: Colors.white),
                    ),
                    trailing: sub.intervalHours == h
                        ? const Icon(Icons.check,
                            color: Color(0xFF3DCF9A), size: 18)
                        : null,
                    onTap: () => Navigator.pop(ctx, h),
                  ))
              .toList(),
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
    if (dt == null) return 'هرگز';
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'همین الان';
    if (diff.inHours < 1) return '${diff.inMinutes} دقیقه پیش';
    if (diff.inDays < 1) return '${diff.inHours} ساعت پیش';
    return '${diff.inDays} روز پیش';
  }

  String _intervalLabel(int h) {
    if (h < 24) return 'هر $h ساعت';
    return 'هر ${h ~/ 24} روز';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF08090C),
      appBar: AppBar(
        backgroundColor: const Color(0xFF08090C),
        elevation: 0,
        title: const Text('اشتراک‌ها',
            style: TextStyle(color: Colors.white)),
        centerTitle: true,
        actions: [
          IconButton(
            onPressed: _subs.isEmpty ? null : _refreshAll,
            icon: const Icon(Icons.refresh, color: Colors.white),
          ),
          IconButton(
            onPressed: _addSub,
            icon: const Icon(Icons.add, color: Colors.white),
          ),
        ],
      ),
      body: _subs.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: const [
                  Icon(Icons.rss_feed, color: Colors.white24, size: 64),
                  SizedBox(height: 16),
                  Text('هیچ اشتراکی نداری',
                      style: TextStyle(color: Colors.white54, fontSize: 16)),
                  SizedBox(height: 8),
                  Text('با دکمه + یه اشتراک اضافه کن',
                      style:
                          TextStyle(color: Colors.white38, fontSize: 12)),
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
                    color: const Color(0xFF12141A),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.white12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              s.name,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          if (loading)
                            const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Color(0xFF3DCF9A)),
                            )
                          else
                            IconButton(
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                              icon: const Icon(Icons.refresh,
                                  color: Colors.white54, size: 18),
                              onPressed: () => _refresh(s),
                            ),
                          const SizedBox(width: 6),
                          IconButton(
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                            icon: const Icon(Icons.delete_outline,
                                color: Color(0xFFE07070), size: 18),
                            onPressed: () => _delete(s),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        s.url,
                        style: const TextStyle(
                            color: Colors.white38, fontSize: 10),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Text(
                            '${s.serverCount} سرور',
                            style: const TextStyle(
                                color: Color(0xFF3DCF9A), fontSize: 11),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'آخرین: ${_timeAgo(s.lastUpdated)}',
                              style: const TextStyle(
                                  color: Colors.white38, fontSize: 11),
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
                              activeColor: const Color(0xFF3DCF9A),
                            ),
                          ),
                          Text('بروزرسانی خودکار',
                              style: TextStyle(
                                  color: Colors.white70, fontSize: 11)),
                          const Spacer(),
                          if (s.autoUpdate)
                            GestureDetector(
                              onTap: () => _setInterval(s),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF1A1D25),
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(color: Colors.white12),
                                ),
                                child: Text(
                                  _intervalLabel(s.intervalHours),
                                  style: const TextStyle(
                                      color: Colors.white70, fontSize: 10),
                                ),
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
