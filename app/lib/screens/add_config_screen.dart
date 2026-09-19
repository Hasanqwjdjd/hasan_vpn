# مسیر مقصد در ریپو: app/lib/screens/add_config_screen.dart
# ------------------------------------------------------------
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/server.dart';
import '../services/app_colors.dart';
import '../services/aether_service.dart';
import 'qr_scan_screen.dart';

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

  // تنظیمات Aether
  String _aetherScan = 'balanced'; // fast | balanced | full
  String _aetherProtocol = 'auto'; // auto | masque_h3 | masque_h2 | wireguard | gool

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
    if (l.startsWith('aether://')) return VpnProtocol.aether;
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
      flag: protocol == VpnProtocol.aether ? '🟣' : '🔧',
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

  Future<void> _scanQr() async {
    final result = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => QrScanScreen(language: widget.language)),
    );
    if (result != null && result.trim().isNotEmpty) {
      setState(() {
        _linkController.text = result.trim();
        if (_nameController.text.isEmpty) {
          _nameController.text = _extractName(result.trim());
        }
      });
      _showMsg(_t('کانفیگ از QR خوانده شد', 'Config read from QR'));
    }
  }

  void _addAetherServer() {
    final link = AetherService.buildConfigLink(
      scanMode: _aetherScan,
      protocolMode: _aetherProtocol,
    );
    final name = _nameController.text.trim().isNotEmpty
        ? _nameController.text.trim()
        : (_isFa ? 'Aether - دور زدن فیلترینگ' : 'Aether - Auto Discover');

    final server = VpnServer(
      id: 'aether_${DateTime.now().millisecondsSinceEpoch}',
      name: name,
      flag: '🟣',
      shareLink: link,
      protocol: VpnProtocol.aether,
      host: 'auto-discover',
      port: 1819,
      isDeletable: true,
    );

    widget.onServerAdded(server);
    Navigator.pop(context);
    _showMsg(_t('سرور Aether اضافه شد', 'Aether server added'));
  }

  // Placeholder for the still-unimplemented free generators (Oblivion/Siphon/Tor)
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

  Widget _buildChoiceRow({
    required String label,
    required List<String> values,
    required Map<String, String> valueLabelsFa,
    required Map<String, String> valueLabelsEn,
    required String selected,
    required ValueChanged<String> onSelected,
    required Color color,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            color: AppColors.muted(context),
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: values.map((v) {
            final isSel = v == selected;
            final label = _isFa ? (valueLabelsFa[v] ?? v) : (valueLabelsEn[v] ?? v);
            return ChoiceChip(
              label: Text(label),
              selected: isSel,
              onSelected: (_) => onSelected(v),
              selectedColor: color.withOpacity(0.25),
              backgroundColor: AppColors.surface(context),
              labelStyle: TextStyle(
                color: isSel ? color : AppColors.muted(context),
                fontWeight: isSel ? FontWeight.w600 : FontWeight.w400,
                fontSize: 12.5,
              ),
              side: BorderSide(color: isSel ? color : AppColors.border(context)),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildAetherForm() {
    const color = Color(0xFF7C4DFF);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: color.withOpacity(0.08),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: color.withOpacity(0.3)),
          ),
          child: Row(
            children: [
              const Icon(Icons.auto_awesome, color: color, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  _t(
                    'Aether یک سیستم دور زدن فیلترینگ است که خودش مسیر آزاد را پیدا و به آن وصل می‌شود؛ نیازی به لینک سرور نیست.',
                    'Aether automatically discovers a working route and connects; no server link is needed.',
                  ),
                  style: TextStyle(color: AppColors.muted(context), fontSize: 12.5, height: 1.5),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        _buildChoiceRow(
          label: _t('سرعت اسکن', 'Scan speed'),
          values: AetherService.scanModes,
          valueLabelsFa: const {
            'fast': 'سریع',
            'balanced': 'متعادل',
            'full': 'کامل (دقیق‌تر)',
          },
          valueLabelsEn: const {
            'fast': 'Fast',
            'balanced': 'Balanced',
            'full': 'Full (thorough)',
          },
          selected: _aetherScan,
          onSelected: (v) => setState(() => _aetherScan = v),
          color: color,
        ),
        const SizedBox(height: 18),
        _buildChoiceRow(
          label: _t('پروتکل انتقال', 'Transport protocol'),
          values: AetherService.protocolModes,
          valueLabelsFa: const {
            'auto': 'خودکار',
            'masque_h3': 'MASQUE (HTTP/3)',
            'masque_h2': 'MASQUE (HTTP/2)',
            'wireguard': 'WireGuard',
            'gool': 'Nested WireGuard (gool)',
          },
          valueLabelsEn: const {
            'auto': 'Auto',
            'masque_h3': 'MASQUE (HTTP/3)',
            'masque_h2': 'MASQUE (HTTP/2)',
            'wireguard': 'WireGuard',
            'gool': 'Nested WireGuard (gool)',
          },
          selected: _aetherProtocol,
          onSelected: (v) => setState(() => _aetherProtocol = v),
          color: color,
        ),
        const SizedBox(height: 18),
        Text(
          _t('نام (اختیاری)', 'Name (optional)'),
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
            hintText: _t('مثال: Aether من', 'e.g. My Aether'),
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
              borderSide: const BorderSide(color: color, width: 1.5),
            ),
          ),
        ),
        const SizedBox(height: 24),
        SizedBox(
          width: double.infinity,
          height: 50,
          child: ElevatedButton(
            onPressed: _addAetherServer,
            style: ElevatedButton.styleFrom(
              backgroundColor: color,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            child: Text(
              _t('افزودن Aether', 'Add Aether'),
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
          ),
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
        title: Text(
          _t('افزودن کانفیگ', 'Add Config'),
          style: TextStyle(color: AppColors.fg(context)),
        ),
        iconTheme: IconThemeData(color: AppColors.fg(context)),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
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
              subtitle: _t('Paste یا اسکن QR لینک VLESS / Trojan / ...',
                  'Paste or scan a VLESS / Trojan / ... link'),
              icon: Icons.link,
              type: 'manual',
              color: AppColors.accent,
            ),
            _buildTypeCard(
              title: 'Aether',
              subtitle: _t('دور زدن فیلترینگ با اسکن خودکار مسیر',
                  'Censorship circumvention with automatic route scanning'),
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
                      onPressed: _scanQr,
                      icon: const Icon(Icons.qr_code_scanner, size: 18),
                      label: Text(_t('اسکن QR', 'Scan QR')),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.accent,
                        side: const BorderSide(color: AppColors.accent),
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
            ] else if (_selectedType == 'aether') ...[
              _buildAetherForm(),
            ] else ...[
              // Free generator section (Oblivion / Siphon / Tor - still placeholder)
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
