import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/app_colors.dart';

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
  int _concurrency = 0;
  String _delayUrl = 'http://cp.cloudflare.com/generate_204';
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
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw != null) {
      try {
        final m = jsonDecode(raw) as Map;
        _samples = (m['samples'] as num?)?.toInt() ?? 1;
        _tcpFallback = m['tcpFallback'] != false;
        _concurrency = (m['concurrency'] as num?)?.toInt() ?? 0;
        _delayUrl = m['delayUrl']?.toString() ?? _delayUrl;
        _urlController.text = _delayUrl;
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
                      color: AppColors.fg(context),
                      fontWeight: FontWeight.w600),
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
                const SizedBox(height: 16),
                Text(
                  _t('آدرس تست تأخیر', 'Delay test URL'),
                  style: TextStyle(
                      color: AppColors.fg(context),
                      fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 6),
                TextField(
                  controller: _urlController,
                  style: TextStyle(color: AppColors.fg(context), fontSize: 13),
                  decoration: InputDecoration(
                    hintText: 'http://cp.cloudflare.com/generate_204',
                    hintStyle: TextStyle(color: AppColors.muted2(context)),
                    filled: true,
                    fillColor: AppColors.surface(context),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: AppColors.border(context)),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: AppColors.border(context)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(
                          color: AppColors.accent, width: 1.5),
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
                const SizedBox(height: 8),
                Text(
                  _t(
                    'نمونه: https://www.gstatic.com/generate_204',
                    'Example: https://www.gstatic.com/generate_204',
                  ),
                  style: TextStyle(
                    color: AppColors.muted2(context),
                    fontSize: 11,
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  _t(
                    'رتبه‌بندی بر اساس تأخیر واقعی، jitter و نرخ موفقیت انجام می‌شود.',
                    'Ranking uses real latency, jitter and success rate.',
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
