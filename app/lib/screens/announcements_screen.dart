import 'package:flutter/material.dart';

import '../models/announcement.dart';
import '../services/announcement_service.dart';
import '../services/app_colors.dart';
import '../services/telemetry_service.dart';

class AnnouncementsScreen extends StatefulWidget {
  final String language;

  const AnnouncementsScreen({super.key, required this.language});

  @override
  State<AnnouncementsScreen> createState() => _AnnouncementsScreenState();
}

class _AnnouncementsScreenState extends State<AnnouncementsScreen> {
  List<Announcement> _items = [];
  bool _loading = true;
  bool _telemetry = false;

  bool get _isFa => widget.language == 'fa';
  String _t(String fa, String en) => _isFa ? fa : en;

  @override
  void initState() {
    super.initState();
    _reload();
    _loadTelemetry();
  }

  Future<void> _reload() async {
    final items = await AnnouncementService.load();
    if (!mounted) return;
    setState(() {
      _items = items;
      _loading = false;
    });
  }

  IconData _icon(AnnouncementCategory c) {
    switch (c) {
      case AnnouncementCategory.connection:
        return Icons.vpn_key;
      case AnnouncementCategory.recovery:
        return Icons.restore;
      case AnnouncementCategory.privacy:
        return Icons.shield;
      case AnnouncementCategory.network:
        return Icons.wifi;
      case AnnouncementCategory.subscription:
        return Icons.rss_feed;
      case AnnouncementCategory.core:
        return Icons.memory;
      case AnnouncementCategory.telemetry:
        return Icons.speed;
    }
  }

  String _timeAgo(DateTime t) {
    final d = DateTime.now().difference(t);
    if (d.inMinutes < 1) return _t('همین الان', 'just now');
    if (d.inMinutes < 60) return _t('${d.inMinutes} دقیقه پیش', '${d.inMinutes}m ago');
    if (d.inHours < 24) return _t('${d.inHours} ساعت پیش', '${d.inHours}h ago');
    return _t('${d.inDays} روز پیش', '${d.inDays}d ago');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg(context),
      appBar: AppBar(
        backgroundColor: AppColors.bg(context),
        elevation: 0,
        title: Text(_t('اعلان‌ها', 'Announcements')),
        actions: [
          if (_items.any((a) => !a.read))
            TextButton(
              onPressed: () async {
                await AnnouncementService.markAllRead();
                await _reload();
              },
              child: Text(_t('خوانده شد', 'Mark all read')),
            ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: _t('پاک کردن همه', 'Clear all'),
            onPressed: () async {
              await AnnouncementService.clear();
              await _reload();
            },
          ),
        ],
      ),
      body: _withTelemetry(_loading
          ? const Center(child: CircularProgressIndicator())
          : _items.isEmpty
              ? Center(
                  child: Text(
                    _t('اعلانی نیست', 'No announcements'),
                    style: TextStyle(color: AppColors.muted(context)),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: _items.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (ctx, i) {
                    final a = _items[i];
                    return Material(
                      color: a.read
                          ? AppColors.elevated(context)
                          : AppColors.elevated(context).withOpacity(0.95),
                      borderRadius: BorderRadius.circular(12),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: () async {
                          if (!a.read) {
                            await AnnouncementService.markRead(a.id);
                            await _reload();
                          }
                        },
                        child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(_icon(a.category),
                                  color: AppColors.accent, size: 22),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            a.title(widget.language),
                                            style: TextStyle(
                                              fontWeight: a.read
                                                  ? FontWeight.w500
                                                  : FontWeight.w700,
                                              color: AppColors.fg(context),
                                            ),
                                          ),
                                        ),
                                        if (!a.read)
                                          Container(
                                            width: 8,
                                            height: 8,
                                            decoration: const BoxDecoration(
                                              color: AppColors.accent,
                                              shape: BoxShape.circle,
                                            ),
                                          ),
                                      ],
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      a.body(widget.language),
                                      style: TextStyle(
                                        color: AppColors.muted(context),
                                        fontSize: 13,
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      _timeAgo(a.createdAt),
                                      style: TextStyle(
                                        color: AppColors.muted2(context),
                                        fontSize: 11,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                )),
    );
  }

  Future<void> _loadTelemetry() async {
    await TelemetryService.load();
    if (mounted) setState(() => _telemetry = TelemetryService.enabled);
  }

  Widget _withTelemetry(Widget list) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Container(
            decoration: BoxDecoration(
              color: AppColors.surface(context),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.border(context)),
            ),
            child: SwitchListTile(
              title: Text(_t('تله‌متری زنده اتصال', 'Live connection telemetry')),
              subtitle: Text(
                _t('پینگ و سرعت در نوار وضعیت',
                    'Ping and speed in the status bar'),
                style: TextStyle(color: AppColors.muted(context), fontSize: 12),
              ),
              value: _telemetry,
              activeColor: AppColors.accent,
              onChanged: (v) async {
                setState(() => _telemetry = v);
                await TelemetryService.setEnabled(v);
              },
            ),
          ),
        ),
        Expanded(child: list),
      ],
    );
  }
}
