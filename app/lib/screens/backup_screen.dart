import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import '../services/app_colors.dart';
import '../services/backup_service.dart';

/// صفحه پشتیبان‌گیری و بازیابی.
class BackupScreen extends StatefulWidget {
  final String language;
  const BackupScreen({super.key, required this.language});

  @override
  State<BackupScreen> createState() => _BackupScreenState();
}

class _BackupScreenState extends State<BackupScreen> {
  String _t(String fa, String en) =>
      widget.language == 'fa' ? fa : en;

  /// Human-friendly error string with the exception type so a failed
  /// restore/export never hides what actually broke.
  String _formatError(Object e) {
    if (e is FileSystemException) {
      return 'File error: ${e.message} (${e.path ?? "?"})';
    }
    if (e is FormatException) {
      return 'Invalid JSON at offset ${e.offset}: ${e.message}';
    }
    if (e is PlatformException) {
      return 'Platform error: ${e.code} ${e.message ?? ""}'.trim();
    }
    return 'Error (${e.runtimeType}): $e';
  }

  static const int _maxImportBytes = 10 * 1024 * 1024;

  bool _busy = false;
  String? _status;
  final TextEditingController _importCtrl = TextEditingController();

  @override
  void dispose() {
    _importCtrl.dispose();
    super.dispose();
  }

  Future<void> _exportToClipboard() async {
    setState(() {
      _busy = true;
      _status = null;
    });
    try {
      final json = await BackupService.export();
      await Clipboard.setData(ClipboardData(text: json));
      if (!mounted) return;
      setState(() {
        _status = _t(
            'پشتیبان در کلیپ‌بورد کپی شد (${json.length} کاراکتر)',
            'Backup copied to clipboard (${json.length} chars)');
        _busy = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _status = _formatError(e);
        _busy = false;
      });
    }
  }

  Future<void> _exportToFile() async {
    setState(() {
      _busy = true;
      _status = null;
    });
    try {
      final json = await BackupService.export();
      final dir = await getApplicationDocumentsDirectory();
      final stamp = DateTime.now()
          .toIso8601String()
          .replaceAll(':', '-')
          .substring(0, 19);
      final f = File('${dir.path}/hasan_backup_$stamp.json');
      await f.writeAsString(json);
      if (!mounted) return;
      setState(() {
        _status = _t(
            'فایل ذخیره شد:\n${f.path}',
            'File saved:\n${f.path}');
        _busy = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _status = _formatError(e);
        _busy = false;
      });
    }
  }

  Future<void> _importFromClipboard() async {
    try {
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      if (data?.text == null || data!.text!.isEmpty) {
        setState(() => _status = _t('کلیپ‌بورد خالی است', 'Clipboard empty'));
        return;
      }
      _importCtrl.text = data.text!;
      if (!mounted) return;
      setState(() {});
    } catch (e) {
      setState(() => _status = 'Error: $e');
    }
  }

  Future<void> _importFromFile() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final files = dir
          .listSync()
          .where((e) =>
              e is File && e.path.endsWith('.json') &&
              e.path.contains('hasan_backup_'))
          .cast<File>()
          .toList()
        ..sort((a, b) => b.path.compareTo(a.path));
      if (files.isEmpty) {
        setState(() => _status =
            _t('هیچ فایل پشتیبانی پیدا نشد', 'No backup files found'));
        return;
      }
      if (!mounted) return;
      final picked = await showDialog<File>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: AppColors.elevated(ctx),
          title: Text(_t('انتخاب فایل', 'Pick file'),
              style: TextStyle(color: AppColors.fg(ctx))),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView(
              shrinkWrap: true,
              children: files.map((f) {
                final name = f.path.split('/').last;
                return ListTile(
                  title: Text(name,
                      style: TextStyle(
                          color: AppColors.fg(ctx), fontSize: 12)),
                  onTap: () => Navigator.pop(ctx, f),
                );
              }).toList(),
            ),
          ),
        ),
      );
      if (picked == null) return;
      final size = await picked.length();
      if (size > _maxImportBytes) {
        if (!mounted) return;
        setState(() => _status = _t(
            'فایل خیلی بزرگ است (${(size / 1048576).toStringAsFixed(1)} MB — حداکثر ۱۰ MB)',
            'File too large (${(size / 1048576).toStringAsFixed(1)} MB — max 10 MB)'));
        return;
      }
      final content = await picked.readAsString();
      final trimmed = content.trim();
      if (trimmed.isEmpty) {
        if (!mounted) return;
        setState(() => _status = _t('فایل خالی است', 'File is empty'));
        return;
      }
      // Basic format sniff so a wrong file never reaches the restore step.
      try {
        final parsed = jsonDecode(trimmed);
        if (parsed is! Map) {
          if (!mounted) return;
          setState(() => _status = _t(
              'فایل باید یک شیء JSON باشد',
              'File must be a JSON object'));
          return;
        }
        if (parsed['_version'] == null) {
          if (!mounted) return;
          setState(() => _status = _t(
              'نسخه پشتیبان مشخص نیست (_version missing)',
              'Backup version unknown (_version missing)'));
          return;
        }
      } catch (e) {
        if (!mounted) return;
        setState(() => _status = _formatError(e));
        return;
      }
      _importCtrl.text = content;
      if (!mounted) return;
      setState(() => _status =
          _t('فایل بارگذاری شد — دکمه بازیابی را بزن',
              'File loaded — tap Restore'));
    } catch (e) {
      if (!mounted) return;
      setState(() => _status = 'Error: $e');
    }
  }

  Future<void> _restore() async {
    final text = _importCtrl.text.trim();
    if (text.isEmpty) {
      setState(() => _status = _t('متنی وارد نشده', 'No text entered'));
      return;
    }
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.elevated(ctx),
        title: Text(_t('بازیابی پشتیبان', 'Restore backup'),
            style: TextStyle(color: AppColors.fg(ctx))),
        content: Text(
          _t(
            'تمام تنظیمات فعلی با پشتیبان جایگزین می‌شود. مطمئنی؟',
            'All current settings will be replaced by the backup. Are you sure?',
          ),
          style: TextStyle(color: AppColors.muted2(ctx)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(_t('لغو', 'Cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(_t('بازیابی', 'Restore'),
                style: const TextStyle(color: AppColors.accent)),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    setState(() {
      _busy = true;
      _status = null;
    });
    try {
      final dynamic parsed;
      try {
        parsed = jsonDecode(text);
      } on FormatException catch (e) {
        if (!mounted) return;
        setState(() {
          _status = _t(
              'JSON نامعتبر است (offset ${e.offset}): ${e.message}',
              'Invalid JSON (offset ${e.offset}): ${e.message}');
          _busy = false;
        });
        return;
      }
      if (parsed is! Map) {
        if (!mounted) return;
        setState(() {
          _status = _t(
              'محتوای پشتیبان باید یک شیء JSON باشد',
              'Backup content must be a JSON object');
          _busy = false;
        });
        return;
      }
      if (parsed['_version'] == null) {
        if (!mounted) return;
        setState(() {
          _status = _t(
              'نسخه پشتیبان مشخص نیست (_version missing)',
              'Backup version unknown (_version missing)');
          _busy = false;
        });
        return;
      }
      final n = await BackupService.restore(text);
      if (!mounted) return;
      setState(() {
        _status = _t(
            '$n کلید بازیابی شد — برنامه را دوباره باز کن',
            '$n keys restored — reopen the app');
        _busy = false;
      });
    } on FormatException catch (e) {
      if (!mounted) return;
      setState(() {
        _status = _t(
            'خطای فرمت: ${e.message}', 'Format error: ${e.message}');
        _busy = false;
      });
    } on FileSystemException catch (e) {
      if (!mounted) return;
      setState(() {
        _status = _t(
            'خطای فایل: ${e.message}', 'File error: ${e.message}');
        _busy = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _status = _formatError(e);
        _busy = false;
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
          _t('پشتیبان‌گیری', 'Backup'),
          style: TextStyle(color: AppColors.fg(context)),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _card(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _t('خروجی گرفتن', 'Export'),
                    style: TextStyle(
                        color: AppColors.fg(context),
                        fontSize: 14,
                        fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _t(
                      'تمام تنظیمات (اشتراک‌ها، سرورها، Xray، DNS، Tor، ...) در یک فایل JSON.',
                      'All settings (subscriptions, servers, Xray, DNS, Tor, ...) in one JSON.',
                    ),
                    style: TextStyle(
                        color: AppColors.muted2(context), fontSize: 12),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _busy ? null : _exportToClipboard,
                          icon: const Icon(Icons.copy, size: 16),
                          label: Text(_t('کپی', 'Copy')),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _busy ? null : _exportToFile,
                          icon: const Icon(Icons.save_alt, size: 16),
                          label: Text(_t('ذخیره فایل', 'Save file')),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            _card(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _t('بازیابی', 'Restore'),
                    style: TextStyle(
                        color: AppColors.fg(context),
                        fontSize: 14,
                        fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _t(
                      'فایل پشتیبان را paste کن یا از کلیپ‌بورد بگیر.',
                      'Paste a backup file or import from clipboard.',
                    ),
                    style: TextStyle(
                        color: AppColors.muted2(context), fontSize: 12),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _importCtrl,
                    maxLines: 6,
                    style: TextStyle(
                        color: AppColors.fg(context), fontSize: 11),
                    decoration: InputDecoration(
                      hintText: '{ "_version": 1, ... }',
                      hintStyle: TextStyle(
                          color: AppColors.muted2(context), fontSize: 11),
                      filled: true,
                      fillColor: AppColors.surface(context),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _busy ? null : _importFromClipboard,
                          icon: const Icon(Icons.paste, size: 16),
                          label: Text(_t('از کلیپ‌بورد', 'From clipboard')),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _busy ? null : _importFromFile,
                          icon: const Icon(Icons.folder_open, size: 16),
                          label: Text(_t('از فایل', 'From file')),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _busy ? null : _restore,
                      icon: const Icon(Icons.restore, size: 16),
                      label: Text(_t('بازیابی', 'Restore')),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.accent,
                        foregroundColor: Colors.black,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (_status != null) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.elevated(context),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.border(context)),
                ),
                child: SelectableText(
                  _status!,
                  style: TextStyle(
                      color: AppColors.fg(context), fontSize: 12),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _card({required Widget child}) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.surface(context),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border(context)),
        ),
        child: child,
      );
}
