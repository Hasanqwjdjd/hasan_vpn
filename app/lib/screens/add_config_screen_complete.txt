import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/server.dart';
import '../services/app_colors.dart';

class AddConfigScreen extends StatefulWidget {
  final String language;
  final Function(VpnServer) onServerAdded;

  const AddConfigScreen({
    super.key,
    required this.language,
    required this.onServerAdded,
  });

  @override
  State<AddConfigScreen> createState() => _AddConfigScreenState();
}

class _AddConfigScreenState extends State<AddConfigScreen> {
  final TextEditingController _linkController = TextEditingController();
  final TextEditingController _nameController = TextEditingController();
  bool _isFa = true;
  String _selectedType = 'manual'; // manual | aether | oblivion | siphon | tor

  @override
  void initState() {
    super.initState();
    _isFa = widget.language == 'fa';
  }

  String _t(String fa, String en) => _isFa ? fa : en;

  void _showMsg(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), duration: const Duration(seconds: 2)),
    );
  }

  VpnProtocol _detectProtocol(String link) {
    final l = link.trim().toLowerCase();
    if (l.startsWith('vless://')) return VpnProtocol.vless;
    if (l.startsWith('vmess://')) return VpnProtocol.vmess;
    if (l.startsWith('trojan://')) return VpnProtocol.trojan;
    if (l.startsWith('ss://') || l.startsWith('shadowsocks://')) {
      return VpnProtocol.shadowsocks;
    }
    if (l.startsWith('hysteria2://') || l.startsWith('hy2://')) {
      return VpnProtocol.hysteria2;
    }
    return VpnProtocol.custom;
  }

  String _extractName(String link) {
    try {
      final uri = Uri.parse(link);
      if (uri.fragment.isNotEmpty) {
        return Uri.decodeComponent(uri.fragment);
      }
    } catch (_) {}
    return 'Custom Server';
  }

  String _extractHost(String link) {
    try {
      final uri = Uri.parse(link);
      return uri.host.isNotEmpty ? uri.host : 'unknown';
    } catch (_) {
      return 'unknown';
    }
  }

  int _extractPort(String link) {
    try {
      final uri = Uri.parse(link);
      return uri.hasPort ? uri.port : 443;
    } catch (_) {
      return 443;
    }
  }

  void _addFromLink() {
    final link = _linkController.text.trim();
    if (link.isEmpty) {
      _showMsg(_t('لینک را وارد کنید', 'Enter a link'));
      return;
    }

    final protocol = _detectProtocol(link);
    final name = _nameController.text.trim().isNotEmpty
        ? _nameController.text.trim()
        : _extractName(link);

    final server = VpnServer(
      id: 'custom_${DateTime.now().millisecondsSinceEpoch}',
      name: name,
      flag: '🔧',
      shareLink: link,
      protocol: protocol,
      host: _extractHost(link),
      port: _extractPort(link),
      isDeletable: true,
    );

    widget.onServerAdded(server);
    Navigator.pop(context);
    _showMsg(_t('سرور اضافه شد', 'Server added'));
  }

  Future<void> _pasteFromClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (data?.text != null && data!.text!.trim().isNotEmpty) {
      setState(() {
        _linkController.text = data.text!.trim();
        if (_nameController.text.isEmpty) {
          _nameController.text = _extractName(data.text!.trim());
        }
      });
      _showMsg(_t('از کلیپ‌بورد پیست شد', 'Pasted from clipboard'));
    } else {
      _showMsg(_t('کلیپ‌بورد خالی است', 'Clipboard is empty'));
    }
  }

  // Placeholder for free generators
  void _generateFree(String type) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.elevated(ctx),
        title: Text(
          _t('ساخت کانفیگ رایگان', 'Generate Free Config'),
          style: TextStyle(color: AppColors.fg(ctx)),
        ),
        content: Text(
          _t(
            'این بخش در نسخه بعدی کامل می‌شود.\n\n'
            'در حال حاضر می‌توانید از اشتراک‌های عمومی موجود در تب «اشتراک‌ها» استفاده کنید.\n\n'
            'نوع انتخاب‌شده: $type',
            'This feature will be completed in the next version.\n\n'
            'For now you can use public subscriptions in the "Subs" tab.\n\n'
            'Selected type: $type',
          ),
          style: TextStyle(color: AppColors.muted(ctx), height: 1.6),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(_t('باشه', 'OK'),
                style: const TextStyle(color: AppColors.accent)),
          ),
        ],
      ),
    );
  }

  Widget _buildTypeCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required String type,
    required Color color,
  }) {
    final selected = _selectedType == type;
    return GestureDetector(
      onTap: () => setState(() => _selectedType = type),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: selected
              ? color.withOpacity(0.15)
              : AppColors.surface(context),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? color : AppColors.border(context),
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: color.withOpacity(0.2),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: color, size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: AppColors.fg(context),
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: AppColors.muted(context),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            if (selected)
              Icon(Icons.check_circle, color: color, size: 22),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg(context),
      appBar: AppBar(
        backgroundColor: AppColors.bg(context),
        elevation: 0,
        title: Text(
          _t('افزودن کانفیگ', 'Add Config'),
          style: TextStyle(color: AppColors.fg(context)),
        ),
        iconTheme: IconThemeData(color: AppColors.fg(context)),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // Type selection
            Text(
              _t('نوع کانفیگ', 'Config Type'),
              style: TextStyle(
                color: AppColors.muted(context),
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 10),

            _buildTypeCard(
              title: _t('دستی / لینک', 'Manual / Link'),
              subtitle: _t('Paste لینک VLESS / Trojan / ...',
                  'Paste VLESS / Trojan / ... link'),
              icon: Icons.link,
              type: 'manual',
              color: AppColors.accent,
            ),
            _buildTypeCard(
              title: 'Aether',
              subtitle: _t('ساخت کانفیگ رایگان Aether',
                  'Generate free Aether config'),
              icon: Icons.auto_awesome,
              type: 'aether',
              color: const Color(0xFF7C4DFF),
            ),
            _buildTypeCard(
              title: 'Oblivion',
              subtitle: _t('ساخت کانفیگ رایگان Oblivion (WARP)',
                  'Generate free Oblivion (WARP) config'),
              icon: Icons.cloud,
              type: 'oblivion',
              color: const Color(0xFF29B6F6),
            ),
            _buildTypeCard(
              title: 'Siphon',
              subtitle: _t('ساخت کانفیگ رایگان Siphon',
                  'Generate free Siphon config'),
              icon: Icons.water_drop,
              type: 'siphon',
              color: const Color(0xFF26A69A),
            ),
            _buildTypeCard(
              title: 'Tor',
              subtitle: _t('ساخت کانفیگ رایگان Tor',
                  'Generate free Tor config'),
              icon: Icons.security,
              type: 'tor',
              color: const Color(0xFFEF5350),
            ),

            const SizedBox(height: 20),

            if (_selectedType == 'manual') ...[
              // Manual input
              Text(
                _t('لینک کانفیگ', 'Config Link'),
                style: TextStyle(
                  color: AppColors.muted(context),
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _linkController,
                maxLines: 4,
                style: TextStyle(color: AppColors.fg(context), fontSize: 13),
                decoration: InputDecoration(
                  hintText: 'vless://... یا trojan://... یا ss://...',
                  hintStyle: TextStyle(color: AppColors.muted2(context)),
                  filled: true,
                  fillColor: AppColors.surface(context),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: AppColors.border(context)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: AppColors.border(context)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide:
                        const BorderSide(color: AppColors.accent, width: 1.5),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _pasteFromClipboard,
                      icon: const Icon(Icons.paste, size: 18),
                      label: Text(_t('پیست از کلیپ‌بورد', 'Paste')),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.accent,
                        side: const BorderSide(color: AppColors.accent),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () {
                        // QR scan placeholder
                        _showMsg(_t(
                            'اسکن QR در نسخه بعدی اضافه می‌شود',
                            'QR scan will be added in next version'));
                      },
                      icon: const Icon(Icons.qr_code_scanner, size: 18),
                      label: Text(_t('اسکن QR', 'Scan QR')),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.muted(context),
                        side: BorderSide(color: AppColors.border(context)),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                _t('نام سرور (اختیاری)', 'Server Name (optional)'),
                style: TextStyle(
                  color: AppColors.muted(context),
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _nameController,
                style: TextStyle(color: AppColors.fg(context)),
                decoration: InputDecoration(
                  hintText: _t('مثال: سرور من', 'e.g. My Server'),
                  hintStyle: TextStyle(color: AppColors.muted2(context)),
                  filled: true,
                  fillColor: AppColors.surface(context),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: AppColors.border(context)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: AppColors.border(context)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide:
                        const BorderSide(color: AppColors.accent, width: 1.5),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: _addFromLink,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.accent,
                    foregroundColor: Colors.black,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: Text(
                    _t('افزودن سرور', 'Add Server'),
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ] else ...[
              // Free generator section
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.surface(context),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppColors.border(context)),
                ),
                child: Column(
                  children: [
                    Icon(Icons.construction,
                        size: 40, color: AppColors.muted(context)),
                    const SizedBox(height: 12),
                    Text(
                      _t(
                        'قابلیت ساخت خودکار کانفیگ رایگان\nدر نسخه بعدی کامل می‌شود.',
                        'Automatic free config generation\nwill be completed in the next version.',
                      ),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: AppColors.muted(context),
                        height: 1.5,
                      ),
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: () => _generateFree(_selectedType),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.accent.withOpacity(0.2),
                        foregroundColor: AppColors.accent,
                      ),
                      child: Text(_t('اطلاعات بیشتر', 'More Info')),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _linkController.dispose();
    _nameController.dispose();
    super.dispose();
  }
}
