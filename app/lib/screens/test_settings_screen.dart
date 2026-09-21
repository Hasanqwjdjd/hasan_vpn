import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/app_colors.dart';

/// تنظیمات تست و رتبه‌بندی سرورها
class TestSettingsScreen extends StatefulWidget {
  final String language;

  const TestSettingsScreen({super.key, required this.language});

  @override
  State<TestSettingsScreen> createState() => _TestSettingsScreenState();
}

class _TestSettingsScreenState extends State<TestSettingsScreen> {
  static const String _key = 'test_settings_v1';

  int _samples = 1;
  bool _tcpFallback = true;
  int _concurrency = 0; // 0 = خودکار
  String _delayUrl = 'http://cp.cloudflare.com/generate_204';
  bool _loading = true;

  bool get _isFa => widget.language == 'fa';
  String _t(String fa, String en) => _isFa ? fa : en;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw != null) {
      try {
        final m = jsonDecode(raw) as Map;
        _samples = (m['samples'] as num?)?.toInt() ?? 1;
        _tcpFallback = m['tcpFallback'] != false;
        _concurrency = (m['concurrency'] as num?)?.toInt() ?? 0;
        _delayUrl = m['delayUrl']?.toString() ?? _delayUrl;
      } catch (_) {}
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _key,
      jsonEncode({
        'samples': _samples,
        'tcpFallback': _tcpFallback,
        'concurrency': _concurrency,
        'delayUrl': _delayUrl,
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg(context),
      appBar: AppBar(
        backgroundColor: AppColors.bg(context),
        elevation: 0,
        title: Text(_t('تنظیمات تست', 'Test Settings')),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(
                  _t('تعداد نمونه برای هر سرور', 'Samples per server'),
                  style: TextStyle(
                      color: AppColors.fg(context), fontWeight: FontWeight.w600),
                ),
                Slider(
                  value: _samples.toDouble(),
                  min: 1,
                  max: 5,
                  divisions: 4,
                  label: '$_samples',
                  activeColor: AppColors.accent,
                  onChanged: (v) {
                    setState(() => _samples = v.round());
                    _save();
                  },
                ),
                SwitchListTile(
                  title: Text(_t('پشتیبان TCP', 'TCP fallback')),
                  subtitle: Text(
                    _t(
                      'اگر پینگ واقعی در دسترس نبود، TCP امتحان شود',
                      'Fall back to TCP if real delay is unavailable',
                    ),
                    style: TextStyle(
                        color: AppColors.muted(context), fontSize: 12),
                  ),
                  value: _tcpFallback,
                  activeColor: AppColors.accent,
                  onChanged: (v) {
                    setState(() => _tcpFallback = v);
                    _save();
                  },
                ),
                ListTile(
                  title: Text(_t('هم‌زمانی', 'Concurrency')),
                  subtitle: Text(
                    _concurrency == 0
                        ? _t('خودکار (بر اساس CPU)', 'Auto (based on CPU)')
                        : '$_concurrency',
                    style: TextStyle(color: AppColors.muted(context)),
                  ),
                  trailing: DropdownButton<int>(
                    value: _concurrency,
                    dropdownColor: AppColors.elevated(context),
                    items: [
                      DropdownMenuItem(
                          value: 0, child: Text(_t('خودکار', 'Auto'))),
                      for (final n in [2, 4, 6, 8, 10])
                        DropdownMenuItem(value: n, child: Text('$n')),
                    ],
                    onChanged: (v) {
                      if (v == null) return;
                      setState(() => _concurrency = v);
                      _save();
                    },
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  _t('آدرس تست تأخیر', 'Delay test URL'),
                  style: TextStyle(
                      color: AppColors.fg(context), fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 6),
                TextFormField(
                  initialValue: _delayUrl,
                  decoration: InputDecoration(
                    border: const OutlineInputBorder(),
                    hintText: 'http://cp.cloudflare.com/generate_204',
                    isDense: true,
                  ),
                  onFieldSubmitted: (v) {
                    final t = v.trim();
                    if (t.startsWith('http')) {
                      setState(() => _delayUrl = t);
                      _save();
                    }
                  },
                ),
                const SizedBox(height: 24),
                Text(
                  _t(
                    'رتبه‌بندی بر اساس تأخیر واقعی، jitter و نرخ موفقیت انجام می‌شود. سقف ۸ سرور وجود ندارد.',
                    'Ranking uses real latency, jitter and success rate. No 8-server cap.',
                  ),
                  style: TextStyle(
                    color: AppColors.muted2(context),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
    );
  }
}
