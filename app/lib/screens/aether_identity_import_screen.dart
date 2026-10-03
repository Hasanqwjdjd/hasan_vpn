// app/lib/screens/aether_identity_import_screen.dart
//
// Import an Aether WARP identity (aether.toml / aether-masque.toml /
// aether-secondary.toml) so the app can reuse it without hitting
// api.cloudflareclient.com — which is blocked on Iranian networks.
//
// User copies the file content from Termux:
//   ~/.config/aether/aether-masque.toml  (or wherever aether wrote it)
// pastes here, app writes it to filesDir/<filename>.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/app_colors.dart';

class AetherIdentityImportScreen extends StatefulWidget {
  final String language;
  const AetherIdentityImportScreen({super.key, this.language = 'fa'});

  @override
  State<AetherIdentityImportScreen> createState() =>
      _AetherIdentityImportScreenState();
}

class _AetherIdentityImportScreenState
    extends State<AetherIdentityImportScreen> {
  static const _channel = MethodChannel('com.hasan.hasan_vpn/aether');
  final _ctrl = TextEditingController();
  String _fileName = 'aether-masque.toml';
  bool _busy = false;

  bool get _isFa => widget.language == 'fa';
  String _t(String fa, String en) => _isFa ? fa : en;

  final List<String> _knownFiles = const [
    'aether-masque.toml',
    'aether.toml',
    'aether-secondary.toml',
  ];

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _importNow() async {
    final content = _ctrl.text.trim();
    if (content.isEmpty) {
      _snack(_t('چیزی برای ذخیره نیست', 'Nothing to save'));
      return;
    }
    setState(() => _busy = true);
    try {
      final r = await _channel.invokeMethod<bool>('importIdentity', {
        'fileName': _fileName,
        'content': content,
      });
      if (!mounted) return;
      if (r == true) {
        _snack(_t('ذخیره شد — Aether را دوباره امتحان کنید',
            'Saved — try Aether again'));
        Navigator.pop(context);
      } else {
        _snack(_t('ذخیره ناموفق', 'Save failed'));
      }
    } catch (e) {
      _snack(_t('خطا: $e', 'Error: $e'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final fg = AppColors.fg(context);
    final muted = AppColors.muted(context);
    final muted2 = AppColors.muted2(context);
    final surface = AppColors.surface(context);

    return Scaffold(
      backgroundColor: AppColors.bg(context),
      appBar: AppBar(
        backgroundColor: surface,
        title: Text(_t('ورود هویت Aether', 'Import Aether identity'),
            style: TextStyle(color: fg, fontSize: 16)),
        iconTheme: IconThemeData(color: fg),
      ),
      body: ListView(
        padding: const EdgeInsets.all(14),
        children: [
          Text(
            _t(
              'در Termux پس از یک بار اجرای موفق Aether، فایل‌های هویت '
              'ذخیره می‌شوند. مسیر معمولاً:',
              'After one successful Aether run in Termux, identity files '
              'are saved. The usual path is:',
            ),
            style: TextStyle(color: muted, fontSize: 12, height: 1.6),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: surface,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.border(context)),
            ),
            child: Directionality(
              textDirection: TextDirection.ltr,
              child: SelectableText(
                '~/.config/aether/aether-masque.toml\n'
                '~/.config/aether/aether.toml\n'
                '~/.config/aether/aether-secondary.toml',
                style: TextStyle(
                  color: fg,
                  fontSize: 11,
                  fontFamily: 'monospace',
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            _t('دستور کپی در Termux:',
                'Copy command in Termux:'),
            style: TextStyle(color: muted, fontSize: 12),
          ),
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: surface,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.border(context)),
            ),
            child: Directionality(
              textDirection: TextDirection.ltr,
              child: SelectableText(
                'cat ~/.config/aether/aether-masque.toml',
                style: TextStyle(
                  color: fg,
                  fontSize: 12,
                  fontFamily: 'monospace',
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(_t('کدام فایل؟', 'Which file?'),
              style: TextStyle(color: muted, fontSize: 12)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: _knownFiles.map((f) {
              final sel = f == _fileName;
              return ChoiceChip(
                label: Text(f,
                    style: TextStyle(
                        fontSize: 11,
                        color: sel ? Colors.black : fg)),
                selected: sel,
                selectedColor: AppColors.accent,
                backgroundColor: surface,
                onSelected: (_) => setState(() => _fileName = f),
              );
            }).toList(),
          ),
          const SizedBox(height: 16),
          Text(_t('محتوای فایل', 'File content'),
              style: TextStyle(color: muted, fontSize: 12)),
          const SizedBox(height: 8),
          TextField(
            controller: _ctrl,
            maxLines: 12,
            style: TextStyle(
              color: fg,
              fontSize: 11,
              fontFamily: 'monospace',
            ),
            decoration: InputDecoration(
              hintText: '[masque]\ndevice_id = "..."\nprivate_key = "..."',
              hintStyle: TextStyle(color: muted2, fontSize: 11),
              filled: true,
              fillColor: surface,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () async {
                    final d =
                        await Clipboard.getData('text/plain');
                    if (d?.text != null && d!.text!.isNotEmpty) {
                      _ctrl.text = d.text!;
                    }
                  },
                  icon: const Icon(Icons.paste, size: 16),
                  label: Text(_t('پیست از کلیپ‌بورد', 'Paste')),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _busy ? null : _importNow,
                  icon: _busy
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.save, size: 16),
                  label: Text(_t('ذخیره', 'Save')),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.accent,
                    foregroundColor: Colors.black,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
