import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../models/subscription.dart';
import '../services/subscription_service.dart'
    show SubscriptionService, SubscriptionFetchException, SubFetchErrorKind;
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
    final choice = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: AppColors.elevated(context),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.border(ctx),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 12),
            ListTile(
              leading: Icon(Icons.link, color: AppColors.accent),
              title: Text(_t('اشتراک با لینک', 'Subscription from URL'),
                  style: TextStyle(color: AppColors.fg(ctx))),
              subtitle: Text(
                  _t('یک لینک http/https یا کانفیگ اشتراک بده',
                      'Provide a http/https URL or subscription link'),
                  style:
                      TextStyle(color: AppColors.muted2(ctx), fontSize: 11)),
              onTap: () => Navigator.pop(ctx, 'url'),
            ),
            ListTile(
              leading: Icon(Icons.folder_special, color: AppColors.accent),
              title: Text(_t('گروه خالی (بدون لینک)',
                  'Empty group (no link)'),
                  style: TextStyle(color: AppColors.fg(ctx))),
              subtitle: Text(
                  _t('گروه بساز و کانفیگ‌ها را دستی داخلش بریز',
                      'Create a group and paste configs manually'),
                  style:
                      TextStyle(color: AppColors.muted2(ctx), fontSize: 11)),
              onTap: () => Navigator.pop(ctx, 'empty'),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );

    if (!mounted || choice == null) return;
    if (choice == 'url') {
      await _addSubWithUrl();
    } else if (choice == 'empty') {
      await _addEmptyGroup();
    }
  }

  Future<void> _addEmptyGroup() async {
    final nameCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.elevated(ctx),
        title: Text(_t('گروه جدید', 'New group'),
            style: TextStyle(color: AppColors.fg(ctx))),
        content: TextField(
          controller: nameCtrl,
          autofocus: true,
          style: TextStyle(color: AppColors.fg(ctx)),
          decoration: InputDecoration(
            labelText: _t('نام گروه', 'Group name'),
            labelStyle: TextStyle(color: AppColors.muted(ctx)),
            enabledBorder: UnderlineInputBorder(
                borderSide: BorderSide(color: AppColors.border(ctx))),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(_t('لغو', 'Cancel'),
                style: TextStyle(color: AppColors.muted(ctx))),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(_t('بساز', 'Create'),
                style: const TextStyle(color: AppColors.accent)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final name = nameCtrl.text.trim();
    if (name.isEmpty) {
      _showMsg(_t('نام گروه لازم است', 'Group name is required'));
      return;
    }
    final sub = Subscription(
      id: 'manual_${DateTime.now().millisecondsSinceEpoch}',
      name: name,
      url: '',
      isDefault: false,
      autoUpdate: false,
      intervalHours: 0,
    );
    setState(() => _subs.add(sub));
    await SubscriptionService.save(_subs);
    widget.onChanged(_subs);
    if (!mounted) return;
    await _showPasteConfigDialog(sub);
  }

  Future<void> _showPasteConfigDialog(Subscription sub) async {
    final ctrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.elevated(ctx),
        title: Text(
            _t('کانفیگ‌ها را داخل گروه بریز', 'Paste configs into group'),
            style: TextStyle(color: AppColors.fg(ctx))),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _t(
                  'هر خط یک کانفیگ: vless://, vmess://, trojan://, ss://, hysteria2:// یا JSON کامل Xray',
                  'One config per line: vless://, vmess://, trojan://, ss://, hysteria2:// or full Xray JSON',
                ),
                style: TextStyle(
                    color: AppColors.muted2(ctx), fontSize: 11, height: 1.5),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: ctrl,
                maxLines: 8,
                style: TextStyle(color: AppColors.fg(ctx), fontSize: 12),
                decoration: InputDecoration(
                  hintText: 'vless://...\nvmess://...\ntrojan://...',
                  hintStyle: TextStyle(
                      color: AppColors.muted2(ctx), fontSize: 11),
                  enabledBorder: OutlineInputBorder(
                      borderSide: BorderSide(color: AppColors.border(ctx))),
                  border: OutlineInputBorder(
                      borderSide: BorderSide(color: AppColors.border(ctx))),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(_t('بعداً', 'Later'),
                style: TextStyle(color: AppColors.muted(ctx))),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(_t('ذخیره', 'Save'),
                style: const TextStyle(color: AppColors.accent)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final raw = ctrl.text;
    if (raw.trim().isEmpty) return;
    final servers = SubscriptionService.parseContent(raw, sub.id);
    if (servers.isEmpty) {
      _showMsg(_t('هیچ کانفیگ معتبری پیدا نشد',
          'No valid config found'));
      return;
    }
    sub.cachedLinks = servers.map((s) => s.shareLink).toList();
    sub.serverCount = servers.length;
    sub.lastUpdated = DateTime.now();
    sub.lastError = null;
    sub.lastErrorCode = null;
    await SubscriptionService.save(_subs);
    widget.onChanged(_subs);
    if (mounted) {
      setState(() {});
      _showMsg('${servers.length} ${_t('کانفیگ اضافه شد', 'configs added')}');
    }
  }

  Future<void> _addSubWithUrl() async {
    final nameCtrl = TextEditingController();
    final urlCtrl = TextEditingController();

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.elevated(ctx),
        title: Text(_t('اشتراک جدید', 'New Subscription'),
            style: TextStyle(color: AppColors.fg(ctx))),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtrl,
              style: TextStyle(color: AppColors.fg(ctx)),
              decoration: InputDecoration(
                labelText: _t('نام', 'Name'),
                labelStyle: TextStyle(color: AppColors.muted(ctx)),
                enabledBorder: UnderlineInputBorder(
                    borderSide: BorderSide(color: AppColors.border(ctx))),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: urlCtrl,
              style: TextStyle(color: AppColors.fg(ctx)),
              decoration: InputDecoration(
                labelText: _t('لینک اشتراک', 'Subscription URL'),
                labelStyle: TextStyle(color: AppColors.muted(ctx)),
                enabledBorder: UnderlineInputBorder(
                    borderSide: BorderSide(color: AppColors.border(ctx))),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(_t('لغو', 'Cancel'),
                style: TextStyle(color: AppColors.muted(ctx))),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(_t('افزودن', 'Add'),
                style: const TextStyle(color: AppColors.accent)),
          ),
        ],
      ),
    );

    final typedName = nameCtrl.text.trim();
    final typedUrl = urlCtrl.text.trim();

    if (ok != true) return;

    final url = typedUrl;
    final uri = Uri.tryParse(url);
    final validUrl = uri != null &&
        (uri.scheme == 'http' || uri.scheme == 'https') &&
        uri.host.isNotEmpty;

    if (typedName.isEmpty || !validUrl) {
      _showMsg(_t('نام و یک لینک http/https معتبر لازم است',
          'A name and a valid http/https URL are required'));
      return;
    }

    if (_subs.any((s) => !s.isDefault && s.url == url)) {
      _showMsg(_t('این اشتراک قبلاً اضافه شده',
          'This subscription already exists'));
      return;
    }

    final newSub = Subscription(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      name: typedName,
      url: url,
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
      sub.lastError = null;
      sub.lastErrorCode = null;
      await SubscriptionService.save(_subs);
      widget.onChanged(_subs);
      if (mounted) {
        setState(() {});
        _showMsg(
            '${servers.length} ${_t('سرور بارگیری شد از', 'servers loaded from')} ${sub.name}');
      }
    } on SubscriptionFetchException catch (e) {
      // کش/serverCount قبلی دست‌نخورده می‌ماند (fetch قبل از تغییر آن‌ها
      // throw می‌کند)؛ فقط پیام خطا برای نوار هشدار ذخیره می‌شود.
      sub.lastError = e.message;
      sub.lastErrorCode = e.statusCode;
      if (mounted) {
        setState(() {});
        _showMsg(_errorLabel(sub, e));
      }
    } catch (e) {
      sub.lastError = e.toString();
      sub.lastErrorCode = null;
      if (mounted) {
        setState(() {});
        _showMsg('${_t('خطا', 'Error')}: $e');
      }
    } finally {
      if (mounted) setState(() => _loading.remove(sub.id));
    }
  }

  String _errorLabel(Subscription sub, SubscriptionFetchException e) {
    final kept = sub.serverCount > 0
        ? ' — ${_t('سرورهای قبلی نگه داشته شدند', 'previous servers kept')} (${sub.serverCount})'
        : '';
    switch (e.kind) {
      case SubFetchErrorKind.httpError:
        return '${_t('خطای HTTP', 'HTTP error')} ${e.statusCode}$kept';
      case SubFetchErrorKind.timeout:
        return '${_t('اتصال timeout شد', 'Connection timed out')}$kept';
      case SubFetchErrorKind.dnsFailure:
        return '${_t('خطای DNS — آدرس resolve نشد', 'DNS error — could not resolve address')}$kept';
      case SubFetchErrorKind.networkError:
        return '${_t('خطای شبکه', 'Network error')}$kept';
      case SubFetchErrorKind.emptyOrInvalid:
        return '${_t('پاسخ نامعتبر یا خالی بود', 'Response was empty or invalid')}$kept';
      case SubFetchErrorKind.unknown:
        return '${_t('خطا', 'Error')}: ${e.message}$kept';
    }
  }


  /// Edit group: rename + list/add/remove configs (Task D).
  Future<void> _editGroup(Subscription sub) async {
    final nameCtrl = TextEditingController(text: sub.name);
    final links = List<String>.from(sub.cachedLinks);
    final addedCtrl = TextEditingController();

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setLocal) {
            return AlertDialog(
              backgroundColor: AppColors.surface(ctx),
              title: Text(
                _t('ویرایش گروه', 'Edit group'),
                style: TextStyle(color: AppColors.fg(ctx), fontSize: 16),
              ),
              content: SizedBox(
                width: double.maxFinite,
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(_t('نام گروه', 'Group name'),
                          style: TextStyle(
                              color: AppColors.muted(ctx), fontSize: 12)),
                      const SizedBox(height: 6),
                      TextField(
                        controller: nameCtrl,
                        style: TextStyle(
                            color: AppColors.fg(ctx), fontSize: 13),
                        decoration: InputDecoration(
                          enabledBorder: OutlineInputBorder(
                              borderSide:
                                  BorderSide(color: AppColors.border(ctx))),
                          border: OutlineInputBorder(
                              borderSide:
                                  BorderSide(color: AppColors.border(ctx))),
                        ),
                      ),
                      const SizedBox(height: 14),
                      Text(
                        _t('کانفیگ‌های داخل گروه (${links.length})',
                            'Configs in group (${links.length})'),
                        style: TextStyle(
                            color: AppColors.muted(ctx), fontSize: 12),
                      ),
                      const SizedBox(height: 6),
                      if (links.isEmpty)
                        Text(_t('خالی', 'Empty'),
                            style: TextStyle(
                                color: AppColors.muted2(ctx), fontSize: 12))
                      else
                        ...List.generate(links.length, (i) {
                          final link = links[i];
                          final short = link.length > 48
                              ? '${link.substring(0, 48)}…'
                              : link;
                          return ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            title: Text(short,
                                style: TextStyle(
                                    color: AppColors.fg(ctx),
                                    fontSize: 11),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis),
                            trailing: IconButton(
                              icon: const Icon(Icons.close,
                                  color: AppColors.danger, size: 16),
                              onPressed: () {
                                setLocal(() => links.removeAt(i));
                              },
                            ),
                          );
                        }),
                      const SizedBox(height: 10),
                      Text(
                        _t(
                          'افزودن کانفیگ (هر خط یکی: vless/vmess/trojan/ss/hysteria2 یا JSON)',
                          'Add configs (one per line: vless/vmess/trojan/ss/hysteria2 or JSON)',
                        ),
                        style: TextStyle(
                            color: AppColors.muted(ctx), fontSize: 11),
                      ),
                      const SizedBox(height: 6),
                      TextField(
                        controller: addedCtrl,
                        maxLines: 4,
                        style: TextStyle(
                            color: AppColors.fg(ctx), fontSize: 12),
                        decoration: InputDecoration(
                          hintText: 'vless://...\nvmess://...',
                          hintStyle: TextStyle(
                              color: AppColors.muted2(ctx), fontSize: 11),
                          enabledBorder: OutlineInputBorder(
                              borderSide:
                                  BorderSide(color: AppColors.border(ctx))),
                          border: OutlineInputBorder(
                              borderSide:
                                  BorderSide(color: AppColors.border(ctx))),
                        ),
                      ),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          onPressed: () {
                            final raw = addedCtrl.text.trim();
                            if (raw.isEmpty) return;
                            final servers =
                                SubscriptionService.parseContent(raw, sub.id);
                            setLocal(() {
                              for (final srv in servers) {
                                final sl = srv.shareLink;
                                if (sl.isNotEmpty && !links.contains(sl)) {
                                  links.add(sl);
                                }
                              }
                              addedCtrl.clear();
                            });
                          },
                          icon: const Icon(Icons.add, size: 16),
                          label: Text(_t('افزودن', 'Add')),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: Text(_t('لغو', 'Cancel'),
                      style: TextStyle(color: AppColors.muted(ctx))),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: Text(_t('ذخیره', 'Save'),
                      style: const TextStyle(color: AppColors.accent)),
                ),
              ],
            );
          },
        );
      },
    );
    if (ok != true) return;
    final newName = nameCtrl.text.trim();
    if (newName.isNotEmpty) sub.name = newName;
    sub.cachedLinks = links;
    sub.serverCount = links.length;
    sub.lastUpdated = DateTime.now();
    await SubscriptionService.save(_subs);
    widget.onChanged(_subs);
    if (mounted) setState(() {});
  }

  Future<void> _delete(Subscription sub) async {

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.elevated(ctx),
        title: Text(_t('حذف اشتراک؟', 'Delete subscription?'),
            style: TextStyle(color: AppColors.fg(ctx))),
        content: Text(sub.name, style: TextStyle(color: AppColors.muted(ctx))),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(_t('لغو', 'Cancel'),
                style: TextStyle(color: AppColors.muted(ctx))),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(_t('حذف', 'Delete'),
                style: const TextStyle(color: AppColors.danger)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await SubscriptionService.markRemoved(sub);
    setState(() => _subs.removeWhere((s) => s.id == sub.id));
    await SubscriptionService.save(_subs);
    widget.onChanged(_subs);
  }

  Future<void> _refreshAll() async {
    await Future.wait(List<Subscription>.from(_subs).map(_refresh));
  }

  Future<void> _showIntervalDialog(Subscription sub) => _setInterval(sub);

  Future<void> _setInterval(Subscription sub) async {
    final options = [1, 3, 6, 12, 24, 48, 168];
    final picked = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.elevated(ctx),
        title: Text(_t('تایم بروزرسانی خودکار', 'Auto-update interval'),
            style: TextStyle(color: AppColors.fg(ctx))),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: options
                .map((h) => ListTile(
                      title: Text(
                        h < 24
                            ? '$h ${_t('ساعت', 'hours')}'
                            : '${h ~/ 24} ${_t('روز', 'days')}',
                        style: TextStyle(color: AppColors.fg(ctx)),
                      ),
                      trailing: sub.intervalHours == h
                          ? const Icon(Icons.check,
                              color: AppColors.accent, size: 18)
                          : null,
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
    if (diff.inHours < 1) {
      return '${diff.inMinutes} ${_t('دقیقه پیش', 'min ago')}';
    }
    if (diff.inDays < 1) {
      return '${diff.inHours} ${_t('ساعت پیش', 'h ago')}';
    }
    return '${diff.inDays} ${_t('روز پیش', 'd ago')}';
  }

  String _intervalLabel(int h) {
    if (h < 24) return '${_t('هر', 'every')} $h ${_t('ساعت', 'h')}';
    return '${_t('هر', 'every')} ${h ~/ 24} ${_t('روز', 'd')}';
  }

  void _showMsg(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), duration: const Duration(seconds: 2)));
  }

  void _shareSub(Subscription sub) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.elevated(ctx),
        title: Text(
          _t('اشتراک‌گذاری اشتراک', 'Share Subscription'),
          style: TextStyle(color: AppColors.fg(ctx)),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
              ),
              child: QrImageView(
                data: sub.url,
                version: QrVersions.auto,
                size: 220,
                backgroundColor: Colors.white,
              ),
            ),
            const SizedBox(height: 12),
            SelectableText(
              sub.url,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppColors.fg(ctx),
                fontSize: 11,
                fontFamily: 'monospace',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: sub.url));
              Navigator.pop(ctx);
              _showMsg(_t('کپی شد', 'Copied'));
            },
            child: Text(
              _t('کپی', 'Copy'),
              style: TextStyle(color: AppColors.muted(ctx)),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(
              _t('بستن', 'Close'),
              style: const TextStyle(color: AppColors.accent),
            ),
          ),
        ],
      ),
    );
  }

  @override
  bool _isPatternihaPresent() {
    for (final s in _subs) {
      if ('${s.id} ${s.name}'.toLowerCase().contains('patterniha')) {
        return true;
      }
    }
    return false;
  }

  Widget _patternihaBanner() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: const Color(0xFF3A2A00),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFF8A6A00)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.info_outline, color: Color(0xFFFFB300), size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                _t(
                  'اشتراک Patterniha فقط یوتیوب، ایکس و بیشتر وب‌سایت‌های معمولی را باز می‌کند. اینستاگرام، تیک‌تاک، تلگرام و واتساپ کار نمی‌کنند.',
                  'Patterniha only works for YouTube, X and most websites. Instagram, TikTok, Telegram and WhatsApp will NOT work.',
                ),
                style: const TextStyle(
                  color: Color(0xFFFFD54F),
                  fontSize: 11.5,
                  height: 1.5,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg(context),
      appBar: AppBar(
        backgroundColor: AppColors.bg(context),
        elevation: 0,
        iconTheme: IconThemeData(color: AppColors.fg(context)),
        title: Text(_t('اشتراک‌ها', 'Subscriptions'),
            style: TextStyle(color: AppColors.fg(context))),
        centerTitle: true,
        actions: [
          IconButton(
              onPressed: _subs.isEmpty ? null : _refreshAll,
              icon: Icon(Icons.refresh, color: AppColors.fg(context))),
          IconButton(
              onPressed: _addSub,
              icon: Icon(Icons.add, color: AppColors.fg(context))),
        ],
      ),
      body: _subs.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.rss_feed,
                      color: AppColors.muted2(context), size: 64),
                  const SizedBox(height: 16),
                  Text(_t('هیچ اشتراکی نداری', 'No subscriptions'),
                      style: TextStyle(
                          color: AppColors.muted(context), fontSize: 16)),
                  const SizedBox(height: 8),
                  Text(_t('با دکمه + اضافه کن', 'Add with + button'),
                      style: TextStyle(
                          color: AppColors.muted2(context), fontSize: 12)),
                ],
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _subs.length + (_isPatternihaPresent() ? 1 : 0),
              itemBuilder: (_, i) {
                final _hasPat = _isPatternihaPresent();
                if (_hasPat && i == 0) return _patternihaBanner();
                final s = _subs[_hasPat ? i - 1 : i];
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
                              s.serverCount > 0
                                  ? '${s.name} (${s.serverCount})'
                                  : s.name,
                              style: TextStyle(
                                color: AppColors.fg(context),
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
                                    color: AppColors.accent))
                          else
                            IconButton(
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                              icon: Icon(Icons.refresh,
                                  color: AppColors.muted(context), size: 18),
                              onPressed: () => _refresh(s),
                            ),
                          const SizedBox(width: 6),
                          if (!s.isDefault)
                            IconButton(
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                              icon: Icon(Icons.share_outlined,
                                  color: AppColors.muted(context), size: 18),
                              onPressed: () => _shareSub(s),
                            ),
                          const SizedBox(width: 6),
                          IconButton(
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                            icon: Icon(Icons.edit_outlined,
                                color: AppColors.muted(context), size: 18),
                            onPressed: () => _editGroup(s),
                          ),
                          const SizedBox(width: 6),
                          IconButton(
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                            icon: const Icon(Icons.delete_outline,
                                color: AppColors.danger, size: 18),
                            onPressed: () => _delete(s),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                          s.isDefault
                              ? _t('🔒 لینک محافظت‌شده', '🔒 Protected link')
                              : s.url,
                          style: TextStyle(
                              color: AppColors.muted2(context), fontSize: 10),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                      if (s.lastError != null) ...[
                        const SizedBox(height: 6),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 6),
                          decoration: BoxDecoration(
                            color: AppColors.danger.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(8),
                            border:
                                Border.all(color: AppColors.danger.withOpacity(0.4)),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Icon(Icons.error_outline,
                                  color: AppColors.danger, size: 14),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  s.lastErrorCode != null
                                      ? '${_t('خطا', 'Error')} ${s.lastErrorCode}: ${s.lastError}'
                                      : s.lastError!,
                                  style: const TextStyle(
                                      color: AppColors.danger, fontSize: 10),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Text('${s.serverCount} ${_t('سرور', 'servers')}',
                              style: const TextStyle(
                                  color: AppColors.accent, fontSize: 11)),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              '${_t('آخرین', 'last')}: ${_timeAgo(s.lastUpdated)}',
                              style: TextStyle(
                                  color: AppColors.muted2(context),
                                  fontSize: 11),
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
                          Text(_t('بروزرسانی خودکار', 'Auto update'),
                              style: TextStyle(
                                  color: AppColors.muted(context),
                                  fontSize: 11)),
                          const Spacer(),
                          if (s.autoUpdate)
                            GestureDetector(
                              onTap: () => _showIntervalDialog(s),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: AppColors.elevated(context),
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(
                                      color: AppColors.border(context)),
                                ),
                                child: Text(
                                    _intervalLabel(s.intervalHours),
                                    style: TextStyle(
                                        color: AppColors.muted(context),
                                        fontSize: 10)),
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
