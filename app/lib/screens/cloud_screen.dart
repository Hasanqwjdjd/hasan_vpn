import 'package:flutter/material.dart';

import '../controllers/servers.dart';
import '../l10n/s.dart';
import '../models/subscription.dart';
import '../services/subscription_service.dart';
import '../ui/fx/fx.dart';
import '../ui/kit/ios_kit.dart';
import '../ui/theme/ios_palette.dart';

/// تب Cloud — مدیریت اشتراک‌ها (پورت CloudTab.kt؛ عملکرد واقعی
/// SubscriptionService: افزودن/حذف/به‌روزرسانی/شمارش سرورها).
class CloudScreen extends StatefulWidget {
  const CloudScreen({super.key});

  @override
  State<CloudScreen> createState() => _CloudScreenState();
}

class _CloudScreenState extends State<CloudScreen> {
  final ServerRepository _repo = ServerRepository.instance;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _repo.addListener(_onChange);
  }

  @override
  void dispose() {
    _repo.removeListener(_onChange);
    super.dispose();
  }

  void _onChange() {
    if (mounted) setState(() {});
  }

  String _t(String fa, String en) => S.isFa ? fa : en;

  Future<void> _addSub() async {
    final url = await showIosPrompt(
      context,
      title: _t('افزودن اشتراک', 'Add subscription'),
      message: _t('آدرس subscription را وارد کن', 'Enter subscription URL'),
      hint: 'https://',
      keyboardType: TextInputType.url,
      confirmLabel: _t('افزودن', 'Add'),
      cancelLabel: _t('انصراف', 'Cancel'),
    );
    if (url == null || url.trim().isEmpty) return;
    final clean = url.trim();
    final next = [
      ..._repo.subs,
      Subscription(
        id: 'sub_${DateTime.now().millisecondsSinceEpoch}',
        name: clean,
        url: clean,
      ),
    ];
    await _repo.setSubs(next);
  }

  Future<void> _refreshAll() async {
    setState(() => _busy = true);
    try {
      await _repo.refreshSubscriptions(force: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final pal = IosPal.of(context);
    final subs = _repo.subs;
    return IosScreen(
      largeTitle: S.t('nav_cloud'),
      title: S.t('nav_cloud'),
      backdropColor: Colors.transparent,
      trailing: _busy
          ? const Padding(
              padding: EdgeInsets.all(12),
              child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white)),
            )
          : IconButton(
              icon: const Icon(Icons.refresh, color: Colors.white),
              onPressed: _refreshAll,
            ),
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: FrostedGlass(
            borderRadius: BorderRadius.circular(IosRadius.card),
            blur: 16,
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    borderRadius:
                        BorderRadius.circular(IosRadius.control),
                    color: Ios.cfOrange.withValues(alpha: 0.2),
                  ),
                  child: const Icon(Icons.cloud_outlined,
                      size: 30, color: Ios.cfOrange),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _t('کانفیگ‌های ابری', 'Cloud configs'),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 17,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _t(
                            '${_repo.servers.length} سرور از ${subs.length} اشتراک',
                            '${_repo.servers.length} servers from ${subs.length} subscriptions'),
                        style: TextStyle(
                            color: pal.textMuted, fontSize: 13),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        SettingsSectionHeader(_t('اشتراک‌ها', 'Subscriptions')),
        if (subs.isEmpty)
          Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              _t(
                  'هنوز اشتراکی نیست — با دکمهٔ پایین آدرس subscription اضافه کن',
                  'No subscriptions yet — add a URL below'),
              textAlign: TextAlign.center,
              style: TextStyle(color: pal.textMuted, fontSize: 13),
            ),
          )
        else
          SettingsGroup(
            children: [
              for (final s in subs)
                SettingsRow(
                  title: s.name.isEmpty ? s.url : s.name,
                  value: '${s.serverCount}',
                  leading: SettingsGlyph(
                      tint: Ios.cfOrange, icon: Icons.rss_feed),
                  onTap: () => _editSub(s),
                ),
              SettingsActionRow(
                icon: Icons.add,
                iconColor: pal.blue,
                title: _t('افزودن اشتراک', 'Add subscription'),
                onTap: _addSub,
              ),
            ],
          ),
        SettingsFooter(_t(
            'سرورهای اشتراک‌ها در تب V2Ray ظاهر می‌شوند و مستقیم قابل تست و اتصال‌اند.',
            'Subscription servers appear in the V2Ray tab and can be tested and connected directly.')),
        const SizedBox(height: 24),
      ],
    );
  }

  Future<void> _editSub(Subscription s) async {
    final action = await showModalBottomSheet<String>(
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
              leading: const Icon(Icons.refresh, color: Colors.white),
              title: Text(_t('به‌روزرسانی', 'Refresh'),
                  style: const TextStyle(color: Colors.white)),
              onTap: () => Navigator.pop(ctx, 'refresh'),
            ),
            ListTile(
              leading: const Icon(Icons.edit, color: Colors.white),
              title: Text(_t('تغییر نام', 'Rename'),
                  style: const TextStyle(color: Colors.white)),
              onTap: () => Navigator.pop(ctx, 'rename'),
            ),
            ListTile(
              leading:
                  Icon(Icons.delete_outline, color: IosPal.of(ctx).red),
              title: Text(_t('حذف اشتراک', 'Delete subscription'),
                  style: TextStyle(color: IosPal.of(ctx).red)),
              onTap: () => Navigator.pop(ctx, 'delete'),
            ),
          ],
        ),
      ),
    );
    if (action == null) return;
    if (action == 'refresh') {
      setState(() => _busy = true);
      try {
        try {
          final servers = await _fetchOne(s);
          s.lastUpdated = DateTime.now();
          s.serverCount = servers.length;
          s.lastError = null;
          s.lastErrorCode = null;
        } catch (e) {
          s.lastError = e.toString();
        }
        await _repo.saveSubs();
        await _repo.refreshSubscriptions();
      } finally {
        if (mounted) setState(() => _busy = false);
      }
    } else if (action == 'rename') {
      final name = await showIosPrompt(context,
          title: _t('نام اشتراک', 'Subscription name'),
          initial: s.name);
      if (name != null && name.trim().isNotEmpty) {
        s.name = name.trim();
        await _repo.saveSubs();
      }
    } else if (action == 'delete') {
      final next = _repo.subs.where((x) => x.id != s.id).toList();
      await _repo.setSubs(next);
    }
  }

  Future<dynamic> _fetchOne(Subscription s) async {
    return SubscriptionService.fetch(s);
  }
}
