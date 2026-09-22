import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/app_colors.dart';
import '../services/test_budget.dart';

class TestSettingsScreen extends StatefulWidget {
  final String language;

  const TestSettingsScreen({super.key, required this.language});

  @override
  State<TestSettingsScreen> createState() => _TestSettingsScreenState();
}

class _TestSettingsScreenState extends State<TestSettingsScreen> {
  int _timeout = 10;
  int _direct = 16;
  int _samples = 1;
  bool _tcp = true;
  String _delayUrl = 'https://www.gstatic.com/generate_204';
  bool _loading = true;

  late final TextEditingController _urlController;

  bool get _isFa => widget.language == 'fa';
  String _t(String fa, String en) => _isFa ? fa : en;

  @override
  void initState() {
    super.initState();
    _urlController = TextEditingController(text: _delayUrl);
    _load();
  }

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final b = await TestBudget.load();
    _timeout = b.timeoutSec;
    _direct = b.direct;
    _samples = b.samples;
    _tcp = b.tcpFallback;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(TestBudget.storageKey);
      if (raw != null) {
        final m = jsonDecode(raw);
        if (m is Map && m['delayUrl'] != null) {
          _delayUrl = m['delayUrl'].toString();
        }
      }
    } catch (_) {}
    _urlController.text = _delayUrl;
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      TestBudget.storageKey,
      jsonEncode({
        'timeoutSec': _timeout,
        'directConcurrency': _direct,
        'samples': _samples,
        'tcpFallback': _tcp,
        'delayUrl': _delayUrl,
      }),
    );
  }

  Future<void> _saveUrl() async {
    final t = _urlController.text.trim();
    if (!t.startsWith('http://') && !t.startsWith('https://')) {
      _showMsg(_t('آدرس باید با http:// یا https:// شروع بشه',
          'URL must start with http:// or https://'));
      return;
    }
    setState(() => _delayUrl = t);
    await _save();
    if (!mounted) return;
    _showMsg(_t('آدرس ذخیره شد', 'URL saved'));
  }

  void _showMsg(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), duration: const Duration(seconds: 2)),
    );
  }

  Widget _title(String text) => Padding(
        padding: const EdgeInsets.only(top: 18, bottom: 4),
        child: Text(text,
            style: TextStyle(
                color: AppColors.fg(context),
                fontWeight: FontWeight.w700,
                fontSize: 15)),
      );

  Widget _sub(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Text(text,
            style: TextStyle(
                color: AppColors.muted(context), fontSize: 12, height: 1.6)),
      );

  Widget _chips(List<int> options, int value, String Function(int) label,
      void Function(int) onPick) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final o in options)
          ChoiceChip(
            label: Text(label(o)),
            selected: o == value,
            selectedColor: AppColors.accent.withOpacity(0.25),
            onSelected: (_) {
              setState(() => onPick(o));
              _save();
            },
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg(context),
      appBar: AppBar(
        backgroundColor: AppColors.bg(context),
        elevation: 0,
        title: Text(_t('تنظیمات تست و رتبه‌بندی', 'Test & ranking')),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _title(_t('بودجه اندازه‌گیری', 'Measurement budget')),
                _sub(_t(
                  'مهلت و تعداد نمونه برای هر روش اعمال می‌شود. سرورهای هم‌زمان، هم‌زمانی روش‌های مستقیم (TCP) است؛ تست واقعی به دلیل اجرای یک هسته Xray برای هر سرور به ۲ تا ۴ محدود است.',
                  'Timeout and samples apply to every method. Concurrent servers is the concurrency of direct (TCP) methods; the real test is capped at 2-4 because one Xray core runs per server.',
                )),
                _title(_t('مهلت هر سرور', 'Timeout per server')),
                _sub(_t('هر سرور چقدر فرصت دارد تا پیش از «در دسترس نیست» پاسخ دهد',
                    'How long each server has to answer before "unreachable"')),
                _chips(TestBudget.timeoutOptions, _timeout, (o) => '${o}s',
                    (o) => _timeout = o),
                _title(_t('سرورهای مستقیم هم‌زمان', 'Concurrent direct servers')),
                _sub(_t(
                    'تعداد کمتر کندتر ولی روی اتصال ضعیف بسیار دقیق‌تر است',
                    'Fewer is slower but far more accurate on a weak connection')),
                _chips(TestBudget.directOptions, _direct, (o) => '$o',
                    (o) => _direct = o),
                _title(_t('تعداد نمونه هر سرور', 'Samples per server')),
                _sub(_t(
                    'تأخیر نهایی میانه‌ی نمونه‌هاست (نمونه‌ی اول به‌عنوان warm-up کنار گذاشته می‌شود)',
                    'Published latency is the median after the warm-up sample is discarded')),
                _chips(TestBudget.sampleOptions, _samples, (o) => '×$o',
                    (o) => _samples = o),
                const SizedBox(height: 10),
                Text(
                  _t(
                    'بدترین حالت برای هر سرور: ${_timeout * _samples} ثانیه • $_direct مستقیم هم‌زمان',
                    'Worst case per server: ${_timeout * _samples}s • $_direct direct concurrent',
                  ),
                  style: TextStyle(
                      color: AppColors.muted2(context), fontSize: 11),
                ),
                const SizedBox(height: 8),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(_t('پشتیبان TCP', 'TCP fallback')),
                  subtitle: Text(
                    _t('اگر پینگ واقعی در دسترس نبود، TCP امتحان شود',
                        'Fall back to TCP if real delay is unavailable'),
                    style: TextStyle(
                        color: AppColors.muted(context), fontSize: 12),
                  ),
                  value: _tcp,
                  activeColor: AppColors.accent,
                  onChanged: (v) {
                    setState(() => _tcp = v);
                    _save();
                  },
                ),
                _title(_t('آدرس تست تأخیر', 'Delay test URL')),
                const SizedBox(height: 6),
                TextField(
                  controller: _urlController,
                  style: TextStyle(color: AppColors.fg(context), fontSize: 13),
                  decoration: InputDecoration(
                    hintText: 'https://www.gstatic.com/generate_204',
                    hintStyle: TextStyle(color: AppColors.muted2(context)),
                    filled: true,
                    fillColor: AppColors.surface(context),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: AppColors.border(context)),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _saveUrl,
                    icon: const Icon(Icons.save, size: 18),
                    label: Text(_t('ذخیره آدرس', 'Save URL')),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.accent,
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  _t('رتبه‌بندی بر اساس تأخیر واقعی و jitter انجام می‌شود.',
                      'Ranking uses real latency and jitter.'),
                  style:
                      TextStyle(color: AppColors.muted2(context), fontSize: 12),
                ),
              ],
            ),
    );
  }
}
