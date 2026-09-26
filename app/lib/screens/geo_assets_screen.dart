import 'package:flutter/material.dart';
import '../services/app_colors.dart';
import '../services/geo_assets_service.dart';

class GeoAssetsScreen extends StatefulWidget {
  final String language;
  const GeoAssetsScreen({super.key, required this.language});
  @override
  State<GeoAssetsScreen> createState() => _GeoAssetsScreenState();
}

class _GeoAssetsScreenState extends State<GeoAssetsScreen> {
  List<Map<String, dynamic>> _assets = [];
  bool _loading = true;
  final Set<String> _busy = {};
  bool get _isFa => widget.language.startsWith('fa');
  String _t(String fa, String en) => _isFa ? fa : en;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final list = await GeoAssetsService.listAssets();
    if (!mounted) return;
    setState(() {
      _assets = list;
      _loading = false;
    });
  }

  Future<void> _download(Map<String, dynamic> a) async {
    final name = a['name'] as String;
    final url = a['url'] as String? ?? '';
    setState(() => _busy.add(name));
    final ok = await GeoAssetsService.download(name, url);
    setState(() => _busy.remove(name));
    await _load();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(ok
              ? _t('دانلود شد', 'Downloaded')
              : _t('خطا در دانلود', 'Download failed'))));
    }
  }

  Future<void> _delete(Map<String, dynamic> a) async {
    final name = a['name'] as String;
    await GeoAssetsService.delete(name);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg(context),
      appBar: AppBar(
        title: Text(_t('فایل‌های Geo', 'Geo asset files')),
        backgroundColor: AppColors.bg(context),
        actions: [
          IconButton(
            icon: const Icon(Icons.download),
            tooltip: _t('منابع پیش‌فرض', 'Default sources'),
            onPressed: _pickSource,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView.builder(
              itemCount: _assets.length,
              itemBuilder: (ctx, i) {
                final a = _assets[i];
                final busy = _busy.contains(a['name']);
                final exists = a['exists'] == true;
                final size = a['size'] as int? ?? 0;
                return ListTile(
                  title: Text(a['name']?.toString() ?? ''),
                  subtitle: Text(exists
                      ? '${(size / 1024).toStringAsFixed(1)} KB'
                      : _t('موجود نیست', 'Not present')),
                  trailing: busy
                      ? const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if ((a['url'] as String?)?.isNotEmpty == true)
                              IconButton(
                                icon: const Icon(Icons.download),
                                onPressed: () => _download(a),
                              ),
                            if (exists)
                              IconButton(
                                icon: const Icon(Icons.delete_outline,
                                    color: Colors.red),
                                onPressed: () => _delete(a),
                              ),
                          ],
                        ),
                );
              },
            ),
    );
  }
}
