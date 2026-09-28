import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/app_colors.dart';
import '../services/mtu_probe.dart';
import '../services/server_health.dart';
import '../services/xray_settings.dart';

/// صفحه‌ی «سلامت سرورها» — dashboard وضعیت همه سرورها.
class ServerHealthScreen extends StatefulWidget {
  final String language;
  const ServerHealthScreen({super.key, required this.language});

  @override
  State<ServerHealthScreen> createState() => _ServerHealthScreenState();
}

class _ServerHealthScreenState extends State<ServerHealthScreen> {
  String _t(String fa, String en) =>
      widget.language.startsWith('fa') ? fa : en;

  /// MTU های probe شده per-server.id
  final Map<String, int> _mtuCache = {};
  /// نشانگر فعال بودن probe هر سرور
  final Set<String> _mtuProbing = {};

  List<ServerHealth> _all = const [];
  List<ServerHealth> _filtered = const [];
  Map<HealthTier, int> _counts = const {};
  HealthTier? _filter;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      final servers = await ServerHealthCalculator.loadServersFromCache({
        'quick_export_servers_v1': prefs.getString('quick_export_servers_v1'),
      });
      final list = ServerHealthCalculator.computeAll(servers);
      // sort: critical → warning → untested → healthy
      list.sort((a, b) {
        const order = {
          HealthTier.critical: 0,
          HealthTier.warning: 1,
          HealthTier.untested: 2,
          HealthTier.healthy: 3,
        };
        final c = (order[a.tier] ?? 99).compareTo(order[b.tier] ?? 99);
        if (c != 0) return c;
        return (a.lastPingMs ?? 99999)
            .compareTo(b.lastPingMs ?? 99999);
      });
      // load cached MTU per server
      final mtuCache = <String, int>{};
      for (final h in list) {
        final v = await MtuProbe.load(h.server.id);
        if (v != null) mtuCache[h.server.id] = v;
      }
      if (!mounted) return;
      setState(() {
        _all = list;
        _mtuCache
          ..clear()
          ..addAll(mtuCache);
        _counts = ServerHealthCalculator.countByTier(list);
        _applyFilter();
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _applyFilter() {
    _filtered = ServerHealthCalculator.filter(_all, _filter);
  }

  Future<void> _export() async {
    if (_all.isEmpty) {
      _showMsg(_t('داده‌ای برای خروجی نیست', 'Nothing to export'));
      return;
    }
    try {
      final json = ServerHealthCalculator.exportReport(_all);
      await Clipboard.setData(ClipboardData(text: json));
      if (!mounted) return;
      _showMsg(_t('گزارش کپی شد (${_all.length} سرور)',
          'Report copied (${_all.length} servers)'));
    } catch (e) {
      if (!mounted) return;
      _showMsg(_t('خطا: $e', 'Error: $e'));
    }
  }

  void _showMsg(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Color _tierColor(HealthTier tier) {
    switch (tier) {
      case HealthTier.healthy:
        return AppColors.accent;
      case HealthTier.warning:
        return AppColors.warn;
      case HealthTier.critical:
        return AppColors.danger;
      case HealthTier.untested:
        return AppColors.muted(context);
    }
  }

  IconData _tierIcon(HealthTier tier) {
    switch (tier) {
      case HealthTier.healthy:
        return Icons.check_circle;
      case HealthTier.warning:
        return Icons.warning_amber;
      case HealthTier.critical:
        return Icons.error_outline;
      case HealthTier.untested:
        return Icons.help_outline;
    }
  }

  String _tierLabel(HealthTier tier) {
    switch (tier) {
      case HealthTier.healthy:
        return _t('سالم', 'Healthy');
      case HealthTier.warning:
        return _t('هشدار', 'Warning');
      case HealthTier.critical:
        return _t('مشکل‌دار', 'Critical');
      case HealthTier.untested:
        return _t('تست نشده', 'Untested');
    }
  }

  Future<void> _runMtuProbe(ServerHealth h) async {
    if (_mtuProbing.contains(h.server.id)) return;
    setState(() => _mtuProbing.add(h.server.id));
    try {
      final mtu = await MtuProbe.probePath();
      if (!mounted) return;
      if (mtu == null) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(_t(
            'پاسخی از سرور probe نیامد. مسیر ممکن است همهٔ UDP را ببندد.',
            'No probe answer. The path may block all UDP.',
          )),
        ));
        return;
      }
      await MtuProbe.save(h.server.id, mtu);
      if (!mounted) return;
      setState(() => _mtuCache[h.server.id] = mtu);
      final mss = MtuProbe.mssFromMtu(mtu);
      final currentMss =
          (await XraySettings.get<int>('mssClampValue')) ?? 0;
      final currentEnabled =
          (await XraySettings.get<bool>('mssClampEnable')) ?? false;
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(_t(
          'MTU=$mtu  →  MSS توصیه: $mss  (فعلی: $currentMss، فعال: $currentEnabled)',
          'MTU=$mtu  ->  suggested MSS: $mss  (current: $currentMss, enabled: $currentEnabled)',
        )),
        action: SnackBarAction(
          label: _t('اعمال', 'Apply'),
          onPressed: () async {
            await XraySettings.set('mssClampEnable', true);
            await XraySettings.set('mssClampValue', mss);
            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text(_t('MSS $mss اعمال شد',
                  'MSS $mss applied')),
            ));
          },
        ),
      ));
    } finally {
      if (mounted) {
        setState(() => _mtuProbing.remove(h.server.id));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg(context),
      appBar: AppBar(
        backgroundColor: AppColors.bg(context),
        elevation: 0,
        iconTheme: IconThemeData(color: AppColors.fg(context)),
        title: Text(
          _t('سلامت سرورها', 'Server health'),
          style: TextStyle(color: AppColors.fg(context)),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: _t('بارگذاری مجدد', 'Reload'),
            onPressed: _load,
          ),
          IconButton(
            icon: const Icon(Icons.ios_share),
            tooltip: _t('خروجی گزارش', 'Export report'),
            onPressed: _export,
          ),
        ],
      ),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _all.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        _t(
                          'هیچ سروری برای بررسی نیست.\nاول یه سرور اضافه کن.',
                          'No servers to inspect.\nAdd a server first.',
                        ),
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            color: AppColors.muted(context),
                            fontSize: 13,
                            height: 1.6),
                      ),
                    ),
                  )
                : Column(
                    children: [
                      _buildSummaryRow(),
                      _buildFilterRow(),
                      const Divider(height: 1),
                      Expanded(
                        child: _filtered.isEmpty
                            ? Center(
                                child: Text(
                                  _t('سروری در این دسته نیست',
                                      'No servers in this category'),
                                  style: TextStyle(
                                      color: AppColors.muted2(context),
                                      fontSize: 12),
                                ),
                              )
                            : ListView.builder(
                                padding:
                                    const EdgeInsets.all(12),
                                itemCount: _filtered.length,
                                itemBuilder: (ctx, i) =>
                                    _buildHealthTile(_filtered[i]),
                              ),
                      ),
                    ],
                  ),
      ),
    );
  }

  Widget _buildSummaryRow() {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
      child: Row(
        children: [
          _summaryCell(
            HealthTier.healthy,
            _counts[HealthTier.healthy] ?? 0,
          ),
          const SizedBox(width: 8),
          _summaryCell(
            HealthTier.warning,
            _counts[HealthTier.warning] ?? 0,
          ),
          const SizedBox(width: 8),
          _summaryCell(
            HealthTier.critical,
            _counts[HealthTier.critical] ?? 0,
          ),
          const SizedBox(width: 8),
          _summaryCell(
            HealthTier.untested,
            _counts[HealthTier.untested] ?? 0,
          ),
        ],
      ),
    );
  }

  Widget _summaryCell(HealthTier tier, int count) {
    final color = _tierColor(tier);
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: color.withOpacity(0.12),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withOpacity(0.4), width: 1),
        ),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(_tierIcon(tier), color: color, size: 14),
                const SizedBox(width: 4),
                Text(
                  '$count',
                  style: TextStyle(
                    color: color,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              _tierLabel(tier),
              style: TextStyle(
                  color: color, fontSize: 9.5),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterRow() {
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            _filterChip(null, _t('همه', 'All'), _all.length,
                AppColors.accent),
            const SizedBox(width: 6),
            _filterChip(HealthTier.critical, _t('مشکل‌دار', 'Critical'),
                _counts[HealthTier.critical] ?? 0, AppColors.danger),
            const SizedBox(width: 6),
            _filterChip(HealthTier.warning, _t('هشدار', 'Warning'),
                _counts[HealthTier.warning] ?? 0, AppColors.warn),
            const SizedBox(width: 6),
            _filterChip(HealthTier.healthy, _t('سالم', 'Healthy'),
                _counts[HealthTier.healthy] ?? 0, AppColors.accent),
            const SizedBox(width: 6),
            _filterChip(HealthTier.untested, _t('تست نشده', 'Untested'),
                _counts[HealthTier.untested] ?? 0,
                AppColors.muted(context)),
          ],
        ),
      ),
    );
  }

  Widget _filterChip(
    HealthTier? tier,
    String label,
    int count,
    Color color,
  ) {
    final active = _filter == tier;
    return ChoiceChip(
      label: Text(
        count > 0 ? '$label ($count)' : label,
        style: TextStyle(
          color: active ? Colors.black : color,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
      selected: active,
      selectedColor: color,
      backgroundColor: color.withOpacity(0.1),
      side: BorderSide(color: color.withOpacity(0.5)),
      onSelected: (_) {
        setState(() {
          _filter = tier;
          _applyFilter();
        });
      },
    );
  }

  Widget _buildHealthTile(ServerHealth h) {
    final color = _tierColor(h.tier);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: color.withOpacity(0.35),
          width: 1,
        ),
      ),
      child: Row(
        children: [
          // tier icon
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: color.withOpacity(0.15),
              shape: BoxShape.circle,
            ),
            child: Icon(_tierIcon(h.tier), color: color, size: 18),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(h.flag,
                        style: const TextStyle(fontSize: 14)),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        h.displayName,
                        style: TextStyle(
                          color: AppColors.fg(context),
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Wrap(
                  spacing: 8,
                  children: [
                    if (h.lastPingMs != null && h.lastPingMs! > 0)
                      Text(
                        '${h.lastPingMs}ms',
                        style: TextStyle(
                          color: color,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    if (h.lastQualityScore != null)
                      Text(
                        'Q${h.lastQualityScore}',
                        style: TextStyle(
                          color: AppColors.muted2(context),
                          fontSize: 10.5,
                        ),
                      ),
                    if (h.consecutiveFails > 0)
                      Text(
                        '${h.consecutiveFails}× fail',
                        style: TextStyle(
                          color: AppColors.danger,
                          fontSize: 10.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    if (h.note != null)
                      Text(
                        h.note!,
                        style: TextStyle(
                          color: AppColors.muted2(context),
                          fontSize: 10,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
          // MTU probe button + result
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_mtuCache.containsKey(h.server.id))
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    'MTU ${_mtuCache[h.server.id]}',
                    style: TextStyle(
                      color: AppColors.accent,
                      fontSize: 10.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              _mtuProbing.contains(h.server.id)
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : IconButton(
                      icon: const Icon(Icons.speed, size: 20),
                      tooltip: _t('اندازه‌گیری MTU مسیر',
                          'Measure path MTU'),
                      onPressed: () => _runMtuProbe(h),
                    ),
            ],
          ),
          const SizedBox(width: 6),
          // tier label
          Text(
            _tierLabel(h.tier),
            style: TextStyle(
              color: color,
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
