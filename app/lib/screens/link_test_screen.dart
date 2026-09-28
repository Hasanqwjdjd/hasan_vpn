import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/server.dart';
import '../services/app_colors.dart';
import '../services/link_test.dart';
import '../services/server_health.dart';

/// صفحه‌ی تست لینک — مثل Link Test در BackPack.
class LinkTestScreen extends StatefulWidget {
  final String language;
  const LinkTestScreen({super.key, required this.language});

  @override
  State<LinkTestScreen> createState() => _LinkTestScreenState();
}

class _LinkTestScreenState extends State<LinkTestScreen> {
  String _t(String fa, String en) =>
      widget.language.startsWith('fa') ? fa : en;

  List<VpnServer> _servers = const [];
  List<LinkTestResult> _results = const [];
  bool _loading = true;
  bool _running = false;
  int _done = 0;
  int _total = 0;
  bool _cancel = false;

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
      final saved = await LinkTest.loadResults();
      if (!mounted) return;
      setState(() {
        _servers = servers;
        _results = saved;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  Future<void> _runAll() async {
    if (_running || _servers.isEmpty) return;
    setState(() {
      _running = true;
      _cancel = false;
      _results = const [];
      _done = 0;
      _total = _servers.length;
    });
    try {
      final results = await LinkTest.runMany(
        _servers,
        samples: LinkTest.defaultSamples,
        workers: 4,
        isCancelled: () => _cancel,
        onResult: (_) {
          if (!mounted) return;
          setState(() => _done++);
        },
      );
      await LinkTest.saveResults(results);
      if (!mounted) return;
      setState(() => _results = results);
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  Color _gradeColor(LinkGrade g) {
    switch (g) {
      case LinkGrade.a:
        return Colors.green;
      case LinkGrade.b:
        return AppColors.accent;
      case LinkGrade.c:
        return AppColors.warn;
      case LinkGrade.d:
        return Colors.orange;
      case LinkGrade.f:
        return AppColors.danger;
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
          _t('تست لینک', 'Link test'),
          style: TextStyle(color: AppColors.fg(context)),
        ),
        actions: [
          if (_running)
            IconButton(
              icon: const Icon(Icons.stop),
              tooltip: _t('توقف', 'Stop'),
              onPressed: () => setState(() => _cancel = true),
            )
          else
            IconButton(
              icon: const Icon(Icons.play_arrow),
              tooltip: _t('اجرای تست', 'Run test'),
              onPressed: _servers.isEmpty ? null : _runAll,
            ),
        ],
      ),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : Column(
                children: [
                  if (_running)
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        children: [
                          LinearProgressIndicator(
                            value: _total == 0 ? null : _done / _total,
                          ),
                          const SizedBox(height: 6),
                          Text(
                            _t('در حال تست $_done از $_total',
                                'Testing $_done of $_total'),
                            style: TextStyle(
                              color: AppColors.muted(context),
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                  Expanded(
                    child: _results.isEmpty
                        ? Center(
                            child: Padding(
                              padding: const EdgeInsets.all(24),
                              child: Text(
                                _t(
                                  'دکمهٔ Play بالای صفحه را بزن.\nتست روی TCP handshake انجام می‌شود (نه ICMP)،\nچون خیلی از مسیرهای ایران ICMP را می‌اندازند ولی TCP را عبور می‌دهند.',
                                  'Tap Play to start.\nMeasures TCP handshake RTT (not ICMP),\nbecause many Iranian routes drop ICMP but carry TCP.',
                                ),
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: AppColors.muted(context),
                                  fontSize: 12.5,
                                  height: 1.6,
                                ),
                              ),
                            ),
                          )
                        : ListView.builder(
                            padding: const EdgeInsets.all(12),
                            itemCount: _results.length,
                            itemBuilder: (ctx, i) => _tile(_results[i]),
                          ),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _tile(LinkTestResult r) {
    final color = _gradeColor(r.grade);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.35)),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: color.withOpacity(0.15),
              shape: BoxShape.circle,
              border: Border.all(color: color, width: 1.5),
            ),
            alignment: Alignment.center,
            child: Text(
              r.gradeLetter,
              style: TextStyle(
                color: color,
                fontSize: 16,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  r.serverName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: AppColors.fg(context),
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 3),
                Wrap(
                  spacing: 10,
                  children: [
                    if (r.medianRtt != null)
                      Text(
                        '${r.medianRtt}ms',
                        style: TextStyle(
                          color: color,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    Text(
                      'jit ${r.jitter}ms',
                      style: TextStyle(
                        color: AppColors.muted2(context),
                        fontSize: 10.5,
                      ),
                    ),
                    Text(
                      'loss ${(r.loss * 100).toStringAsFixed(0)}%',
                      style: TextStyle(
                        color: r.loss > 0
                            ? AppColors.danger
                            : AppColors.muted2(context),
                        fontSize: 10.5,
                      ),
                    ),
                    Text(
                      '${r.received}/${r.sent}',
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
        ],
      ),
    );
  }
}
