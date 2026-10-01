import 'package:flutter/material.dart';

import '../models/server.dart';
import '../services/app_colors.dart';
import '../services/free_config_engine.dart';
import '../services/server_health.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// "دریافت کانفیگ رایگان" wizard — الگو از mlmvpn_android/FreeConfigWizard.
///
/// ۴ مرحله:
///   1. CHECKING — منابع رو می‌کشه، تعداد candidate رو می‌شماره
///   2. PICK_COUNT — کاربر انتخاب می‌کنه چند تا کانفیگ سالم می‌خواد
///   3. FETCHING — two-stage funnel + progress + stop-early
///   4. RESULTS — لیست + انتقال
class FreeConfigScreen extends StatefulWidget {
  final String language;
  final void Function(List<VpnServer>) onImport;
  const FreeConfigScreen({
    super.key,
    required this.language,
    required this.onImport,
  });

  @override
  State<FreeConfigScreen> createState() => _FreeConfigScreenState();
}

enum _Step { checking, pickCount, fetching, results, failed }

class _FreeConfigScreenState extends State<FreeConfigScreen> {
  String _t(String fa, String en) =>
      widget.language.startsWith('fa') ? fa : en;

  _Step _step = _Step.checking;
  List<String> _candidates = const [];
  int _desired = 100;
  int _tested = 0;
  int _working = 0;
  int _target = 0;
  bool _stopRequested = false;
  List<VpnServer> _results = const [];
  List<VpnServer> _newResults = const [];
  int _alreadyOwned = 0;
  String? _error;

  @override
  void initState() {
    super.initState();
    _startCheck();
  }

  Future<void> _startCheck() async {
    setState(() {
      _step = _Step.checking;
      _error = null;
    });
    try {
      final found = await FreeConfigEngine.fetchCandidates();
      if (!mounted) return;
      setState(() {
        _candidates = found;
        _desired = found.isEmpty ? 0 : (found.length < 100 ? found.length : 100);
        _step = found.isEmpty ? _Step.failed : _Step.pickCount;
        if (found.isEmpty) {
          _error = _t('هیچ کانفیگی از منابع پیدا نشد',
              'No configs found in any source');
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _step = _Step.failed;
        _error = e.toString();
      });
    }
  }

  Future<void> _startFetch() async {
    setState(() {
      _step = _Step.fetching;
      _tested = 0;
      _working = 0;
      _target = _desired;
      _stopRequested = false;
    });
    try {
      final working = await FreeConfigEngine.collectWorking(
        candidates: _candidates,
        targetCount: _desired,
        isCancelled: () => _stopRequested,
        onProgress: (t, w, target) {
          if (!mounted) return;
          setState(() {
            _tested = t;
            _working = w;
            _target = target;
          });
        },
      );
      if (!mounted) return;

      // Split vs existing servers
      final prefs = await SharedPreferences.getInstance();
      final existing = await ServerHealthCalculator.loadServersFromCache({
        'quick_export_servers_v1':
            prefs.getString('quick_export_servers_v1'),
      });
      final (fresh, owned) =
          FreeConfigEngine.splitAlreadyOwned(working, existing);

      if (!mounted) return;
      setState(() {
        _results = working;
        _newResults = fresh;
        _alreadyOwned = owned;
        _step = _Step.results;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _step = _Step.failed;
        _error = e.toString();
      });
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
          _t('دریافت کانفیگ رایگان', 'Get free configs'),
          style: TextStyle(color: AppColors.fg(context)),
        ),
      ),
      body: SafeArea(child: _buildStep()),
    );
  }

  Widget _buildStep() {
    switch (_step) {
      case _Step.checking:
        return _centeredStep(
          icon: Icons.travel_explore,
          title: _t('در حال بررسی منابع...', 'Checking sources...'),
          subtitle: _t(
            'چند لحظه صبر کنید تا تعداد کانفیگ‌های در دسترس مشخص شود',
            'Just a moment — counting available configs',
          ),
          child: const CircularProgressIndicator(),
        );
      case _Step.failed:
        return _centeredStep(
          icon: Icons.cloud_off,
          title: _t('دریافت منابع ناموفق', 'Fetch failed'),
          subtitle: _error ?? _t('اینترنت را بررسی کنید', 'Check your connection'),
          child: ElevatedButton(
            onPressed: _startCheck,
            child: Text(_t('تلاش مجدد', 'Retry')),
          ),
        );
      case _Step.pickCount:
        return _buildPickCount();
      case _Step.fetching:
        return _buildFetching();
      case _Step.results:
        return _buildResults();
    }
  }

  Widget _centeredStep({
    required IconData icon,
    required String title,
    required String subtitle,
    required Widget child,
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 60, color: AppColors.accent),
            const SizedBox(height: 16),
            Text(
              title,
              style: TextStyle(
                color: AppColors.fg(context),
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppColors.muted(context),
                fontSize: 13,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 20),
            child,
          ],
        ),
      ),
    );
  }

  Widget _buildPickCount() {
    final available = _candidates.length;
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Icon(Icons.check_circle,
              size: 44, color: AppColors.accent),
          const SizedBox(height: 12),
          Text(
            _t('می‌توانید تا $available کانفیگ دریافت کنید',
                'Up to $available configs available'),
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AppColors.fg(context),
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            _t('چند تا می‌خواهید؟', 'How many?'),
            style: TextStyle(color: AppColors.muted(context), fontSize: 13),
          ),
          const SizedBox(height: 16),
          Text(
            '$_desired',
            style: TextStyle(
              color: AppColors.accent,
              fontSize: 40,
              fontWeight: FontWeight.w800,
            ),
          ),
          Slider(
            value: _desired.toDouble().clamp(1, available.toDouble()),
            min: 1,
            max: available.toDouble().clamp(1, 2000),
            onChanged: (v) => setState(() => _desired = v.toInt()),
            activeColor: AppColors.accent,
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              for (final n in [25, 50, 100, 200]
                  .where((n) => n <= available).toList())
                ChoiceChip(
                  label: Text('$n'),
                  selected: _desired == n,
                  onSelected: (_) => setState(() => _desired = n),
                ),
            ],
          ),
          const Spacer(),
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton(
              onPressed: _startFetch,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.accent,
                foregroundColor: Colors.black,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: Text(
                _t('دریافت $_desired کانفیگ', 'Fetch $_desired configs'),
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFetching() {
    final frac = _candidates.isEmpty
        ? 0.0
        : (_tested / _candidates.length).clamp(0.0, 1.0);
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          const SizedBox(height: 20),
          Text(
            _t('در حال دریافت و تست کانفیگ‌ها...',
                'Fetching and testing configs...'),
            style: TextStyle(
              color: AppColors.fg(context),
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            _t('فقط کانفیگ‌های واقعاً متصل به لیست اضافه می‌شوند',
                'Only configs that actually connect will be added'),
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.muted(context), fontSize: 12),
          ),
          const SizedBox(height: 20),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: frac,
              minHeight: 8,
              color: AppColors.accent,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                _t('تست‌شده: $_tested', 'Tested: $_tested'),
                style:
                    TextStyle(color: AppColors.muted(context), fontSize: 12),
              ),
              Text(
                _t('متصل: $_working / $_target',
                    'Working: $_working / $_target'),
                style: TextStyle(
                  color: AppColors.accent,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const Spacer(),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: OutlinedButton(
              onPressed: (_working > 0 && !_stopRequested)
                  ? () => setState(() => _stopRequested = true)
                  : null,
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.accent,
                side: BorderSide(color: AppColors.accent),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: _stopRequested
                  ? Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: AppColors.accent),
                        ),
                        const SizedBox(width: 8),
                        Text(_t('در حال توقف...', 'Stopping...')),
                      ],
                    )
                  : Text(
                      _t('همین تعداد کافیه ($_working)',
                          'Enough ($_working)'),
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildResults() {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          Row(
            children: [
              Icon(Icons.verified_user,
                  color: AppColors.accent, size: 22),
              const SizedBox(width: 8),
              Text(
                _t('${_results.length} کانفیگ متصل و آماده',
                    '${_results.length} working configs'),
                style: TextStyle(
                  color: AppColors.fg(context),
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          if (_alreadyOwned > 0) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.warn.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.warn.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  Icon(Icons.info, color: AppColors.warn, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _t(
                        '$_alreadyOwned تا از این‌ها قبلاً در بخش اتصال داری — ${_newResults.length} کانفیگ جدید منتقل می‌شود',
                        '$_alreadyOwned already in your list — transferring ${_newResults.length} new ones',
                      ),
                      style: TextStyle(
                        color: AppColors.fg(context),
                        fontSize: 12,
                        height: 1.5,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 12),
          Expanded(
            child: ListView.builder(
              itemCount: _results.length,
              itemBuilder: (c, i) {
                final s = _results[i];
                return Container(
                  margin: const EdgeInsets.only(bottom: 6),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.surface(context),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                        color: AppColors.border(context)),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppColors.accent.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(5),
                        ),
                        child: Text(
                          'رایگان',
                          style: TextStyle(
                            color: AppColors.accent,
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          s.displayName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: AppColors.fg(context),
                            fontSize: 12.5,
                          ),
                        ),
                      ),
                      Text(
                        s.protocol.name.toUpperCase(),
                        style: TextStyle(
                          color: AppColors.muted2(context),
                          fontSize: 10.5,
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton(
              onPressed: _newResults.isEmpty
                  ? null
                  : () {
                      widget.onImport(_newResults);
                      Navigator.pop(context);
                    },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.accent,
                foregroundColor: Colors.black,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: Text(
                _t(
                  'انتقال ${_newResults.length} کانفیگ به بخش اتصال',
                  'Transfer ${_newResults.length} configs',
                ),
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
