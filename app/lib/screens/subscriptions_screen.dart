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
