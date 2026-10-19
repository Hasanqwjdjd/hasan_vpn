import 'package:flutter/material.dart';

import '../services/app_colors.dart';
import '../services/test_budget.dart';

/// بخش ۲.۲ — صفحه «تنظیمات تست و رتبه‌بندی» (بازگشت به برنامه طبق
/// مشخصات جدید). همه‌ی مقادیر واقعاً در ServerTester اعمال می‌شوند.
class TestSettingsScreen extends StatefulWidget {
  final String language;

  const TestSettingsScreen({super.key, required this.language});

  @override
  State<TestSettingsScreen> createState() => _TestSettingsScreenState();
}

class _TestSettingsScreenState extends State<TestSettingsScreen> {
  bool get _isFa => widget.language == 'fa';
  String _t(String fa, String en) => _isFa ? fa : en;

  bool _loading = true;
  TestMode _mode = TestMode.accurate;
  int _tcpTimeout = 1500;
  int _tcpConcurrency = 64;
  int _realTimeout = 4;
  int _realConcurrency = 8;
  int _samples = 3;
  late final TextEditingController _urlCtrl;

  @override
  void initState() {
    super.initState();
    _urlCtrl = TextEditingController();
    _load();
  }

  @override
  void dispose() {
    _urlCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final b = await TestBudget.load();
    if (!mounted) return;
    setState(() {
      _mode = b.mode;
      _tcpTimeout = b.tcpTimeoutMs;
      _tcpConcurrency = b.tcpConcurrency;
      _realTimeout = b.realTimeoutSec;
      _realConcurrency = b.realConcurrency;
      _samples = b.realSamples;
      _urlCtrl.text = b.delayUrl;
      _loading = false;
    });
  }

  Future<void> _save() async {
    final url = _urlCtrl.text.trim();
    final b = TestBudget(
      mode: _mode,
      tcpTimeoutMs: _tcpTimeout,
      tcpConcurrency: _tcpConcurrency,
      realTimeoutSec: _realTimeout,
      realConcurrency: _realConcurrency,
      realSamples: _samples,
      delayUrl: url.isEmpty ? TestBudget.defaults.delayUrl : url,
    );
    await TestBudget.save(b);
    if (!mounted) return;
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(_t('تنظیمات تست ذخیره شد', 'Test settings saved'))),
    );
    setState(() {});
  }

  Future<void> _resetDefaults() async {
    await TestBudget.save(TestBudget.defaults);
    await _load();
    if (!mounted) return;
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(_t('به پیش‌فرض برگشت', 'Reset to defaults'))),
    );
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
          _t('تست و رتبه‌بندی', 'Test & Ranking'),
          style: TextStyle(color: AppColors.fg(context)),
        ),
        actions: [
          IconButton(
            tooltip: _t('بازگشت به پیش‌فرض', 'Reset to defaults'),
            icon: const Icon(Icons.restart_alt),
            onPressed: _loading ? null : _resetDefaults,
          ),
        ],
      ),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _section(_t('حالت تست', 'Test mode')),
                  _card(
                    Column(
                      children: [
                        _modeTile(
                          TestMode.turbo,
                          'تربوز — فقط TCP',
                          'فقط دست‌دهی TCP؛ برای ۱۰۰۰+ سرور در چند ثانیه',
                          'Turbo — TCP only',
                          'TCP handshake only; 1000+ servers in seconds',
                          Icons.bolt,
                        ),
                        _divider(),
                        _modeTile(
                          TestMode.balanced,
                          'متعادل — TCP همه + Real برترین‌ها',
                          'تست واقعی فقط برای ۲۴ پاسخ‌دهندهٔ برتر',
                          'Balanced — TCP all + Real top-24',
                          'Real test only for the top 24 responders',
                          Icons.balance,
                        ),
                        _divider(),
                        _modeTile(
                          TestMode.accurate,
                          'دقیق — TCP همه + Real همه',
                          'تست واقعی از داخل تونل برای همهٔ پاسخ‌دهنده‌ها (کندترین، دقیق‌ترین)',
                          'Accurate — TCP all + Real all',
                          'Real in-tunnel test for every responder (slowest, most accurate)',
                          Icons.verified_outlined,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  _section(_t('پینگ TCP', 'TCP ping')),
                  _card(
                    Column(
                      children: [
                        _optionRow(
                          _t('تایم‌اوت (میلی‌ثانیه)', 'Timeout (ms)'),
                          TestBudget.tcpTimeoutOptions,
                          _tcpTimeout,
                          (v) => setState(() => _tcpTimeout = v),
                        ),
                        _divider(),
                        _optionRow(
                          _t('هم‌زمانی (تست موازی)', 'Concurrency'),
                          TestBudget.tcpConcurrencyOptions,
                          _tcpConcurrency,
                          (v) => setState(() => _tcpConcurrency = v),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  _section(_t('پینگ واقعی (Real Delay)', 'Real delay')),
                  _card(
                    Column(
                      children: [
                        _optionRow(
                          _t('تایم‌اوت (ثانیه)', 'Timeout (s)'),
                          TestBudget.realTimeoutOptions,
                          _realTimeout,
                          (v) => setState(() => _realTimeout = v),
                        ),
                        _divider(),
                        _optionRow(
                          _t('هم‌زمانی', 'Concurrency'),
                          TestBudget.realConcurrencyOptions,
                          _realConcurrency,
                          (v) => setState(() => _realConcurrency = v),
                        ),
                        _divider(),
                        _optionRow(
                          _t('تعداد نمونه (median)', 'Samples (median)'),
                          TestBudget.sampleOptions,
                          _samples,
                          (v) => setState(() => _samples = v),
                        ),
                        _divider(),
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          child: TextField(
                            controller: _urlCtrl,
                            style: TextStyle(
                                color: AppColors.fg(context), fontSize: 13),
                            decoration: InputDecoration(
                              labelText: _t('آدرس تست واقعی',
                                  'Real delay URL'),
                              hintText:
                                  'https://www.gstatic.com/generate_204',
                              hintStyle: TextStyle(
                                  color: AppColors.muted2(context),
                                  fontSize: 11),
                              labelStyle: TextStyle(
                                  color: AppColors.muted(context),
                                  fontSize: 12),
                              isDense: true,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                          ),
                        ),
                        Text(
                          _t(
                            'زمان واقعی پاسخ‌دهی از داخل تونل با درخواست HTTP به این آدرس اندازه‌گیری می‌شود (مثل v2rayNG/PingNG).',
                            'Real response time is measured inside the tunnel with an HTTP request to this URL (like v2rayNG/PingNG).',
                          ),
                          style: TextStyle(
                            color: AppColors.muted2(context),
                            fontSize: 10,
                            height: 1.4,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.accent,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      onPressed: _save,
                      icon: const Icon(Icons.save_outlined, size: 18),
                      label: Text(_t('ذخیره', 'Save')),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _t(
                      'منطق تست: ابتدا همهٔ سرورها TCP می‌شوند، سپس پاسخ‌دهنده‌ها تست واقعی می‌گیرند و لیست بر اساس کمترین پینگ مرتب می‌شود. سرورهای سایفون/لوکال پینگ نمی‌گیرند (N/A).',
                      'Logic: TCP for all first, responders get the real test, list sorts by lowest ping. Psiphon/local servers are skipped (N/A).',
                    ),
                    style: TextStyle(
                      color: AppColors.muted2(context),
                      fontSize: 11,
                      height: 1.5,
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _section(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(
          text,
          style: TextStyle(
            color: AppColors.muted(context),
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
      );

  Widget _card(Widget child) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        decoration: BoxDecoration(
          color: AppColors.surface(context),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border(context)),
        ),
        child: child,
      );

  Widget _divider() =>
      Divider(height: 1, color: AppColors.border(context));

  Widget _modeTile(
    TestMode mode,
    String faTitle,
    String faSub,
    String enTitle,
    String enSub,
    IconData icon,
  ) {
    final selected = _mode == mode;
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      leading: Icon(
        icon,
        color: selected ? AppColors.accent : AppColors.muted2(context),
        size: 20,
      ),
      title: Text(
        _t(faTitle, enTitle),
        style: TextStyle(
          color: selected ? AppColors.accent : AppColors.fg(context),
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
      ),
      subtitle: Text(
        _t(faSub, enSub),
        style: TextStyle(
          color: AppColors.muted2(context),
          fontSize: 10,
          height: 1.3,
        ),
      ),
      trailing: Radio<TestMode>(
        value: mode,
        groupValue: _mode,
        activeColor: AppColors.accent,
        onChanged: (v) => setState(() => _mode = v ?? TestMode.accurate),
      ),
      onTap: () => setState(() => _mode = mode),
    );
  }

  Widget _optionRow(
    String label,
    List<int> options,
    int current,
    ValueChanged<int> onPick,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(color: AppColors.fg(context), fontSize: 12),
            ),
          ),
          Wrap(
            spacing: 6,
            children: [
              for (final v in options)
                ChoiceChip(
                  label: Text('$v'),
                  selected: current == v,
                  selectedColor: AppColors.accent.withValues(alpha: 0.25),
                  labelStyle: TextStyle(
                    color: current == v
                        ? AppColors.accent
                        : AppColors.fg(context),
                    fontSize: 11,
                  ),
                  visualDensity: VisualDensity.compact,
                  onSelected: (_) => onPick(v),
                ),
              if (!options.contains(current))
                ChoiceChip(
                  label: Text('$current'),
                  selected: true,
                  selectedColor: AppColors.accent.withValues(alpha: 0.25),
                  labelStyle: TextStyle(
                      color: AppColors.accent, fontSize: 11),
                  visualDensity: VisualDensity.compact,
                  onSelected: (_) {},
                ),
            ],
          ),
        ],
      ),
    );
  }
}
