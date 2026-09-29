import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/app_colors.dart';
import '../services/core_engines.dart';
import '../services/engine_version_checker.dart';

/// صفحه‌ی «هسته‌ها» — لیست هسته‌های native با نسخه و چک آپدیت خودکار.
class EnginesScreen extends StatefulWidget {
  final String language;
  const EnginesScreen({super.key, required this.language});

  @override
  State<EnginesScreen> createState() => _EnginesScreenState();
}

class _EnginesScreenState extends State<EnginesScreen> {
  String _t(String fa, String en) =>
      widget.language.startsWith('fa') ? fa : en;

  bool _checking = true;
  bool _forceRefreshNext = false;

  @override
  void initState() {
    super.initState();
    EngineVersionChecker.instance.onUpdated = () {
      if (mounted) setState(() => _checking = false);
    };
    // Do not hit the GitHub API just because the screen opened. The
    // updater is now driven by the Refresh button only; cached results
    // from a previous run are shown immediately.
    _checking = false;
    _loadCachedOnly();
  }

  /// Populate the version badges from the on-disk cache without any
  /// network call. Called once in initState.
  Future<void> _loadCachedOnly() async {
    try {
      await EngineVersionChecker.instance.loadFromCache();
      if (mounted) setState(() {});
    } catch (_) {}
  }

  @override
  void dispose() {
    EngineVersionChecker.instance.onUpdated = null;
    super.dispose();
  }

  Future<void> _check() async {
    setState(() => _checking = true);
    try {
      await EngineVersionChecker.instance.checkAll(
        force: _forceRefreshNext,
      );
    } catch (_) {}
    _forceRefreshNext = false;
    if (mounted) setState(() => _checking = false);
  }

  Future<void> _forceRefresh() async {
    _forceRefreshNext = true;
    await EngineVersionChecker.instance.clearCache();
    await _check();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(_t('همه هسته‌ها دوباره چک شدند',
            'All engines rechecked')),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<void> _openGithub(String url) async {
    try {
      final uri = Uri.parse(url);
      final ok = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );
      if (!ok) throw Exception('launch failed');
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_t('لینک: $url', 'Link: $url')),
          duration: const Duration(seconds: 4),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final checker = EngineVersionChecker.instance;
    final updateCount = checker.updateCount;

    return Scaffold(
      backgroundColor: AppColors.bg(context),
      appBar: AppBar(
        backgroundColor: AppColors.bg(context),
        elevation: 0,
        iconTheme: IconThemeData(color: AppColors.fg(context)),
        title: Text(
          _t('هسته‌ها', 'Engines'),
          style: TextStyle(color: AppColors.fg(context)),
        ),
        actions: [
          if (_checking)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Center(
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            )
          else
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: _t('چک دوباره', 'Recheck'),
              onPressed: _forceRefresh,
            ),
        ],
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _forceRefresh,
          color: AppColors.accent,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (updateCount > 0)
                Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.warn.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color: AppColors.warn.withOpacity(0.5), width: 1),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.system_update_alt,
                          color: AppColors.warn, size: 20),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          _t(
                            '$updateCount هسته نسخه جدید داره',
                            '$updateCount engine(s) have updates',
                          ),
                          style: TextStyle(
                            color: AppColors.fg(context),
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              for (final engine in CoreEngines.all)
                _buildEngineTile(context, engine, checker),
              const SizedBox(height: 20),
              Center(
                child: Text(
                  _t(
                    'ساخته شده با ❤️ برای آزادی اینترنت',
                    'Made with ❤️ for internet freedom',
                  ),
                  style: TextStyle(
                    color: AppColors.muted2(context),
                    fontSize: 11,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEngineTile(
    BuildContext context,
    CoreEngine engine,
    EngineVersionChecker checker,
  ) {
    final info = checker.infoFor(engine.id);
    final hasUpdate = info?.hasUpdate == true;
    final latestVer = info?.latestVersion ?? '';

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surface(context),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: hasUpdate
                ? AppColors.warn.withOpacity(0.5)
                : AppColors.border(context),
            width: hasUpdate ? 1.2 : 1,
          ),
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => _openGithub(engine.githubUrl),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(engine.icon,
                          color: AppColors.accent, size: 22),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              engine.name,
                              style: TextStyle(
                                color: AppColors.fg(context),
                                fontSize: 13.5,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              _t(engine.descriptionFa,
                                  engine.descriptionEn),
                              style: TextStyle(
                                color: AppColors.muted2(context),
                                fontSize: 10.5,
                                height: 1.35,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      // نسخه
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            engine.currentVersion,
                            style: TextStyle(
                              color: AppColors.fg(context),
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Icon(Icons.open_in_new,
                              size: 14,
                              color: AppColors.muted2(context)),
                        ],
                      ),
                    ],
                  ),
                  if (hasUpdate && latestVer.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 5),
                      decoration: BoxDecoration(
                        color: AppColors.warn.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                            color: AppColors.warn.withOpacity(0.4),
                            width: 0.8),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.new_releases,
                              size: 12, color: AppColors.warn),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              _t(
                                'نسخه $latestVer اضافه نشده است',
                                'Version $latestVer not yet added',
                              ),
                              style: TextStyle(
                                color: AppColors.warn,
                                fontSize: 10.5,
                                fontWeight: FontWeight.w600,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
