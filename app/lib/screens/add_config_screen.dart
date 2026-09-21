import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/aether_profile.dart';
import '../models/server.dart';
import '../services/app_colors.dart';
import '../services/link_parser.dart';
import '../services/xray_json.dart';
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

  // تنظیمات Aether (مقدارهای پیش‌فرض همان پیش‌فرض AetherProfile هستند)
  String _aetherProtocol = 'auto';
  String _aetherScan = 'smart';
  String _aetherNoize = 'auto';
  String _aetherIp = 'v4';
  String _aetherPerf = 'auto';
  bool _aetherQuickReconnect = true;
  bool _aetherBlockQuic = true;
  bool _aetherAdvanced = false;

  final TextEditingController _aetherDnsController = TextEditingController();
  final TextEditingController _aetherPeerController = TextEditingController();
  final TextEditingController _psiphonSponsorController = TextEditingController();
  final TextEditingController _psiphonChannelController = TextEditingController();
  final TextEditingController _psiphonConfigController = TextEditingController();
  final TextEditingController _aetherUpstreamController =
      TextEditingController();

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

  void _addFromLink() {
    final text = _linkController.text.trim();
    if (text.isEmpty) {
      _showMsg(_t('لینک را وارد کنید', 'Enter a link'));
      return;
    }

    final customName = _nameController.text.trim();
    final stamp = DateTime.now().millisecondsSinceEpoch;
    var added = 0;

    // کانفیگ کامل JSON (Patterniha و مشابه)
    if (XrayJson.looksLike(text)) {
      var server = XrayJson.parse(text, id: 'custom_$stamp');
      if (server != null) {
        if (customName.isNotEmpty) {
          server = server.copyWith(name: customName);
        }
        widget.onServerAdded(server);
        added = 1;
      }
    } else {
      // ممکن است چند لینک (هر کدام در یک خط) پیست شده باشد.
      final links = LinkParser.extractLinks(text);
      if (links.isEmpty) {
        _showMsg(
          _t(
            'لینک معتبری پیدا نشد (vless / vmess / trojan / ss / hysteria2 / aether / JSON)',
            'No valid link found (vless / vmess / trojan / ss / hysteria2 / aether / JSON)',
          ),
        );
        return;
      }

      for (var i = 0; i < links.length; i++) {
        var server = LinkParser.parse(links[i], id: 'custom_${stamp}_$i');
        if (server == null) continue;

        if (customName.isNotEmpty && links.length == 1) {
          server = server.copyWith(name: customName);
        }

        widget.onServerAdded(server);
        added++;
      }
    }

    if (added == 0) {
      _showMsg(_t('لینک قابل خواندن نبود', 'Could not read the link'));
      return;
    }

    Navigator.pop(context);
    _showMsg(
      added == 1
          ? _t('سرور اضافه شد', 'Server added')
          : _t('$added سرور اضافه شد', '$added servers added'),
    );
  }

  String _firstLinkName(String text) {
    if (XrayJson.looksLike(text)) {
      return XrayJson.parse(text, id: 'preview')?.name ?? '';
    }
    final links = LinkParser.extractLinks(text);
    if (links.length != 1) return '';
    final parsed = LinkParser.parse(links.first, id: 'preview');
    return parsed?.name ?? '';
  }

  Future<void> _pasteFromClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim() ?? '';
    if (text.isNotEmpty) {
      setState(() {
        _linkController.text = text;
        if (_nameController.text.isEmpty) {
          _nameController.text = _firstLinkName(text);
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
    if (!mounted) return;
    if (result != null && result.trim().isNotEmpty) {
      setState(() {
        _linkController.text = result.trim();
        if (_nameController.text.isEmpty) {
          _nameController.text = _firstLinkName(result.trim());
        }
      });
      _showMsg(_t('کانفیگ از QR خوانده شد', 'Config read from QR'));
    }
  }

  static final RegExp _peerRegex = RegExp(r'^(\[[0-9a-fA-F:.]+\]|[0-9.]+):\d{1,5}$');

  void _addAetherServer() {
    final peer = _aetherPeerController.text.trim();
    final upstream = _aetherUpstreamController.text.trim();
    final dns = _aetherDnsController.text
        .split(RegExp(r'[\s,]+'))
        .where((e) => e.isNotEmpty)
        .join(',');

    if (peer.isNotEmpty && !_peerRegex.hasMatch(peer)) {
      _showMsg(_t('آدرس Peer باید به شکل ip:port باشد', 'Peer must look like ip:port'));
      return;
    }
    if (upstream.isNotEmpty && !upstream.contains('://')) {
      _showMsg(
        _t(
          'پراکسی بالادستی باید مثل socks5://127.0.0.1:1080 باشد',
          'Upstream must look like socks5://127.0.0.1:1080',
        ),
      );
      return;
    }

    final profile = AetherProfile(
      protocol: _aetherProtocol,
      scan: _aetherScan,
      noize: _aetherNoize,
      ip: _aetherIp,
      dns: dns,
      peer: peer,
      upstream: upstream,
      quickReconnect: _aetherQuickReconnect,
      blockQuic: _aetherBlockQuic,
      perf: _aetherPerf,
    );

    final name = _nameController.text.trim().isNotEmpty
        ? _nameController.text.trim()
        : 'Aether · ${profile.summary}';

    final server = VpnServer(
      id: 'aether_${DateTime.now().millisecondsSinceEpoch}',
      name: name,
      flag: '🟣',
      shareLink: profile.toLink(),
      protocol: VpnProtocol.aether,
      host: 'auto-discover',
      port: 0,
      isDeletable: true,
    );

    widget.onServerAdded(server);
    Navigator.pop(context);
    _showMsg(_t('سرور Aether اضافه شد', 'Aether server added'));
  }

  // ---------- Oblivion (WARP روی هسته Aether) ----------
  // Oblivion کلاینت غیررسمی WARP است و همین برنامه از هستهٔ Aether
  // (همان هسته‌ای که Oblivion جدید استفاده می‌کند) پشتیبانی می‌کند.

  void _addFreeEnginePack() {
    final stamp = DateTime.now().millisecondsSinceEpoch;
    final engines = <({String id, String name, String flag, AetherProfile profile})>[
      (
        id: 'oblivion_$stamp',
        name: 'Oblivion · Auto',
        flag: '☁️',
        profile: const AetherProfile(
          protocol: 'auto',
          scan: 'smart',
          noize: 'auto',
          quickReconnect: true,
          blockQuic: true,
        ),
      ),
      (
        id: 'siphon_$stamp',
        name: 'Siphon · Gool',
        flag: '💧',
        profile: const AetherProfile(
          protocol: 'gool',
          scan: 'smart',
          noize: 'gfw',
          quickReconnect: true,
          blockQuic: true,
        ),
      ),
      (
        id: 'tor_$stamp',
        name: 'Tor · Stealth',
        flag: '🧅',
        profile: const AetherProfile(
          protocol: 'masque',
          scan: 'stealth',
          noize: 'aggressive',
          quickReconnect: false,
          blockQuic: true,
          perf: 'medium',
        ),
      ),
    ];

    for (final e in engines) {
      widget.onServerAdded(VpnServer(
        id: e.id,
        name: e.name,
        flag: e.flag,
        shareLink: e.profile.toLink(),
        protocol: VpnProtocol.aether,
        host: 'auto',
        port: 0,
        isDeletable: true,
      ));
    }
    Navigator.pop(context);
    _showMsg(_t(
      '۳ موتور رایگان اضافه شد (Oblivion / Siphon / Tor)',
      '3 free engines added (Oblivion / Siphon / Tor)',
    ));
  }

  void _addOblivionServer() {
    final peer = _aetherPeerController.text.trim();
    final dns = _aetherDnsController.text
        .split(RegExp(r'[\s,]+'))
        .where((e) => e.isNotEmpty)
        .join(',');

    if (peer.isNotEmpty && !_peerRegex.hasMatch(peer)) {
      _showMsg(
          _t('آدرس Endpoint باید به شکل ip:port باشد', 'Endpoint must look like ip:port'));
      return;
    }

    // پیش‌فرض‌های نزدیک به Oblivion: اسکن هوشمند + MASQUE/WG خودکار
    final profile = AetherProfile(
      protocol: _aetherProtocol == 'auto' ? 'auto' : _aetherProtocol,
      scan: _aetherScan,
      noize: _aetherNoize,
      ip: _aetherIp,
      dns: dns,
      peer: peer,
      upstream: '',
      quickReconnect: _aetherQuickReconnect,
      blockQuic: _aetherBlockQuic,
      perf: _aetherPerf,
    );

    final name = _nameController.text.trim().isNotEmpty
        ? _nameController.text.trim()
        : 'Oblivion · ${profile.summary}';

    final server = VpnServer(
      id: 'oblivion_${DateTime.now().millisecondsSinceEpoch}',
      name: name,
      flag: '☁️',
      shareLink: profile.toLink(),
      protocol: VpnProtocol.aether,
      host: peer.isNotEmpty ? peer.split(':').first : 'warp-auto',
      port: 0,
      isDeletable: true,
    );

    widget.onServerAdded(server);
    Navigator.pop(context);
    _showMsg(_t('سرور Oblivion اضافه شد — وصل شو', 'Oblivion server added — connect'));
  }


  /// Siphon = مسیر Gool (WARP داخل WARP) برای عوض‌کردن IP خروجی
  /// سایفون واقعی (کتابخانهٔ ca.psiphon)
  void _addSiphonServer() {
    final sponsor = _psiphonSponsorController.text.trim();
    final channel = _psiphonChannelController.text.trim();
    final raw = _psiphonConfigController.text.trim();
    final region = _aetherPeerController.text.trim(); // reuse optional region field

    final String share;
    if (raw.startsWith('{')) {
      share = PsiphonService.toShareLink(rawJson: raw);
    } else {
      share = PsiphonService.toShareLink(
        sponsorId: sponsor,
        channelId: channel,
        region: region,
      );
    }

    final name = _nameController.text.trim().isNotEmpty
        ? _nameController.text.trim()
        : 'Psiphon · Real';

    final server = VpnServer(
      id: 'psiphon_${DateTime.now().millisecondsSinceEpoch}',
      name: name,
      flag: '💧',
      shareLink: share,
      protocol: VpnProtocol.psiphon,
      host: 'psiphon-network',
      port: 0,
      isDeletable: true,
    );

    widget.onServerAdded(server);
    Navigator.pop(context);
    _showMsg(_t(
      'سایفون واقعی اضافه شد — برای اتصال SponsorId معتبر لازم است',
      'Real Psiphon added — valid SponsorId required to connect',
    ));
  }

  Widget _buildSiphonForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFF26A69A).withOpacity(0.08),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFF26A69A).withOpacity(0.35)),
          ),
          child: Text(
            _t(
              'سایفون واقعی با کتابخانهٔ رسمی + تنظیمات bepass-org/warp-plus '
              '(همان Cfon در Oblivion) کار می‌کند.\n'
              'اگر SponsorId را خالی بگذاری، همان مقادیر Oblivion '
              '(FFFFFFFFFFFFFFFF + لیست سرور رسمی) استفاده می‌شود.\n'
              'در صورت نیاز می‌توانی Sponsor/Channel یا JSON کامل را جایگزین کنی.',
              'Real Psiphon uses the official library + bepass-org/warp-plus '
              'settings (same as Oblivion Cfon).\n'
              'Leave SponsorId empty to use Oblivion defaults '
              '(FFFFFFFFFFFFFFFF + official server list).\n'
              'Optionally override with your own Sponsor/Channel or full JSON.',
            ),
            style: TextStyle(
              color: AppColors.muted(context),
              fontSize: 12,
              height: 1.5,
            ),
          ),
        ),
        const SizedBox(height: 16),
        Text(
          _t('SponsorId', 'SponsorId'),
          style: TextStyle(
              color: AppColors.muted(context),
              fontSize: 13,
              fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _psiphonSponsorController,
          style: TextStyle(color: AppColors.fg(context), fontSize: 13),
          decoration: InputDecoration(
            hintText: 'خالی = پیش‌فرض Oblivion (FFFFFFFFFFFFFFFF)',
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
                  const BorderSide(color: Color(0xFF26A69A), width: 1.5),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          _t('PropagationChannelId', 'PropagationChannelId'),
          style: TextStyle(
              color: AppColors.muted(context),
              fontSize: 13,
              fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _psiphonChannelController,
          style: TextStyle(color: AppColors.fg(context), fontSize: 13),
          decoration: InputDecoration(
            hintText: 'Channel ID',
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
                  const BorderSide(color: Color(0xFF26A69A), width: 1.5),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          _t('منطقه خروجی (اختیاری)', 'Egress region (optional)'),
          style: TextStyle(
              color: AppColors.muted(context),
              fontSize: 13,
              fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _aetherPeerController,
          style: TextStyle(color: AppColors.fg(context), fontSize: 13),
          decoration: InputDecoration(
            hintText: 'US, DE, SG, ... یا خالی',
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
                  const BorderSide(color: Color(0xFF26A69A), width: 1.5),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          _t('یا کانفیگ JSON کامل', 'Or full JSON config'),
          style: TextStyle(
              color: AppColors.muted(context),
              fontSize: 13,
              fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _psiphonConfigController,
          maxLines: 4,
          style: TextStyle(color: AppColors.fg(context), fontSize: 12),
          decoration: InputDecoration(
            hintText: '{ "SponsorId": "...", "PropagationChannelId": "..." }',
            hintStyle: TextStyle(color: AppColors.muted2(context), fontSize: 11),
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
                  const BorderSide(color: Color(0xFF26A69A), width: 1.5),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          _t('نام (اختیاری)', 'Name (optional)'),
          style: TextStyle(
              color: AppColors.muted(context),
              fontSize: 13,
              fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _nameController,
          style: TextStyle(color: AppColors.fg(context)),
          decoration: InputDecoration(
            hintText: _t('مثال: سایفون من', 'e.g. My Psiphon'),
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
                  const BorderSide(color: Color(0xFF26A69A), width: 1.5),
            ),
          ),
        ),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          height: 50,
          child: ElevatedButton(
            onPressed: _addSiphonServer,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF26A69A),
              foregroundColor: Colors.black,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            child: Text(
              _t('افزودن سایفون واقعی', 'Add real Psiphon'),
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
          ),
        ),
      ],
    );
  }

  /// Tor-mode = حداکثر پنهان‌کاری روی هسته Aether (stealth + noize قوی)
  /// توجه: این شبکهٔ رسمی Tor نیست؛ از obfs/stealth روی Aether استفاده می‌کند.
  void _addTorServer() {
    final peer = _aetherPeerController.text.trim();
    if (peer.isNotEmpty && !_peerRegex.hasMatch(peer)) {
      _showMsg(
          _t('آدرس Endpoint باید به شکل ip:port باشد', 'Endpoint must look like ip:port'));
      return;
    }

    final profile = AetherProfile(
      protocol: _aetherProtocol == 'auto' ? 'masque' : _aetherProtocol,
      scan: 'stealth',
      noize: 'aggressive',
      ip: _aetherIp,
      dns: _aetherDnsController.text
          .split(RegExp(r'[\s,]+'))
          .where((e) => e.isNotEmpty)
          .join(','),
      peer: peer,
      quickReconnect: false,
      blockQuic: true,
      perf: 'medium',
    );

    final name = _nameController.text.trim().isNotEmpty
        ? _nameController.text.trim()
        : 'Tor · ${profile.summary}';

    final server = VpnServer(
      id: 'tor_${DateTime.now().millisecondsSinceEpoch}',
      name: name,
      flag: '🧅',
      shareLink: profile.toLink(),
      protocol: VpnProtocol.aether,
      host: peer.isNotEmpty ? peer.split(':').first : 'stealth-auto',
      port: 0,
      isDeletable: true,
    );

    widget.onServerAdded(server);
    Navigator.pop(context);
    _showMsg(_t('سرور Tor-mode اضافه شد — وصل شو', 'Tor-mode server added — connect'));
  }

  Widget _buildSiphonForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFF26A69A).withOpacity(0.08),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFF26A69A).withOpacity(0.35)),
          ),
          child: Text(
            _t(
              'Siphon از روش Gool (WARP داخل WARP) استفاده می‌کند تا IP خروجی '
              'غیر ایران شود و فیلترینگ سخت‌تر را دور بزند. اتصال ممکن است '
              'کندتر از Oblivion باشد ولی برای تحریم‌ها مناسب‌تر است.',
              'Siphon uses Gool (WARP-in-WARP) so the exit IP is less likely '
              'to be Iran. Slower than Oblivion, better against sanctions.',
            ),
            style: TextStyle(
              color: AppColors.muted(context),
              fontSize: 12,
              height: 1.5,
            ),
          ),
        ),
        const SizedBox(height: 16),
        Text(
          _t('حالت اسکن', 'Scan mode'),
          style: TextStyle(
              color: AppColors.muted(context),
              fontSize: 13,
              fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final s in const ['ironclad', 'thorough', 'balanced', 'smart'])
              ChoiceChip(
                label: Text(s),
                selected: _aetherScan == s ||
                    (_aetherScan == 'smart' && s == 'ironclad' &&
                        !const ['ironclad', 'thorough', 'balanced']
                            .contains(_aetherScan)),
                selectedColor: const Color(0xFF26A69A).withOpacity(0.25),
                labelStyle: TextStyle(
                  color: (_aetherScan == s)
                      ? const Color(0xFF26A69A)
                      : AppColors.muted(context),
                  fontSize: 12,
                ),
                onSelected: (_) => setState(() => _aetherScan = s),
              ),
          ],
        ),
        const SizedBox(height: 14),
        Text(
          _t('Endpoint دستی (اختیاری)', 'Manual endpoint (optional)'),
          style: TextStyle(
              color: AppColors.muted(context),
              fontSize: 13,
              fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _aetherPeerController,
          style: TextStyle(color: AppColors.fg(context), fontSize: 13),
          decoration: InputDecoration(
            hintText: '162.159.192.1:2408',
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
                  const BorderSide(color: Color(0xFF26A69A), width: 1.5),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          _t('نام (اختیاری)', 'Name (optional)'),
          style: TextStyle(
              color: AppColors.muted(context),
              fontSize: 13,
              fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _nameController,
          style: TextStyle(color: AppColors.fg(context)),
          decoration: InputDecoration(
            hintText: _t('مثال: Siphon من', 'e.g. My Siphon'),
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
                  const BorderSide(color: Color(0xFF26A69A), width: 1.5),
            ),
          ),
        ),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          height: 50,
          child: ElevatedButton(
            onPressed: _addSiphonServer,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF26A69A),
              foregroundColor: Colors.black,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            child: Text(
              _t('افزودن Siphon', 'Add Siphon'),
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTorForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFFEF5350).withOpacity(0.08),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFEF5350).withOpacity(0.35)),
          ),
          child: Text(
            _t(
              'حالت Tor در این برنامه از مسیر stealth هسته Aether با پنهان‌کاری '
              'قوی استفاده می‌کند (نه شبکهٔ رسمی Tor). برای فیلترینگ خیلی سخت '
              'مناسب است؛ اتصال کندتر از Oblivion خواهد بود.',
              'Tor mode here uses Aether stealth path with strong obfuscation '
              '(not the official Tor network). Best for heavy filtering; slower than Oblivion.',
            ),
            style: TextStyle(
              color: AppColors.muted(context),
              fontSize: 12,
              height: 1.5,
            ),
          ),
        ),
        const SizedBox(height: 16),
        Text(
          _t('پروتکل پایه', 'Base protocol'),
          style: TextStyle(
              color: AppColors.muted(context),
              fontSize: 13,
              fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final p in const ['masque', 'masque_h2', 'wg', 'mim'])
              ChoiceChip(
                label: Text(p.toUpperCase()),
                selected: _aetherProtocol == p ||
                    (_aetherProtocol == 'auto' && p == 'masque'),
                selectedColor: const Color(0xFFEF5350).withOpacity(0.25),
                labelStyle: TextStyle(
                  color: (_aetherProtocol == p ||
                          (_aetherProtocol == 'auto' && p == 'masque'))
                      ? const Color(0xFFEF5350)
                      : AppColors.muted(context),
                  fontSize: 12,
                ),
                onSelected: (_) => setState(() => _aetherProtocol = p),
              ),
          ],
        ),
        const SizedBox(height: 14),
        Text(
          _t('Endpoint دستی (اختیاری)', 'Manual endpoint (optional)'),
          style: TextStyle(
              color: AppColors.muted(context),
              fontSize: 13,
              fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _aetherPeerController,
          style: TextStyle(color: AppColors.fg(context), fontSize: 13),
          decoration: InputDecoration(
            hintText: '162.159.192.1:2408',
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
                  const BorderSide(color: Color(0xFFEF5350), width: 1.5),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          _t('نام (اختیاری)', 'Name (optional)'),
          style: TextStyle(
              color: AppColors.muted(context),
              fontSize: 13,
              fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _nameController,
          style: TextStyle(color: AppColors.fg(context)),
          decoration: InputDecoration(
            hintText: _t('مثال: Tor من', 'e.g. My Tor'),
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
                  const BorderSide(color: Color(0xFFEF5350), width: 1.5),
            ),
          ),
        ),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          height: 50,
          child: ElevatedButton(
            onPressed: _addTorServer,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFEF5350),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            child: Text(
              _t('افزودن Tor-mode', 'Add Tor-mode'),
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
          ),
        ),
      ],
    );
  }


  Widget _buildOblivionForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFF29B6F6).withOpacity(0.08),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFF29B6F6).withOpacity(0.35)),
          ),
          child: Text(
            _t(
              'Oblivion روی هستهٔ Aether (همان WARP / MASQUE / WireGuard) کار می‌کند. '
              'بدون نیاز به لینک سرور؛ مسیر آزاد را خودش پیدا می‌کند. '
              'در صورت نیاز می‌توانی Endpoint دستی (ip:port) بگذاری.',
              'Oblivion runs on the Aether core (WARP / MASQUE / WireGuard). '
              'No server link needed; it finds a working route. '
              'Optionally set a manual Endpoint (ip:port).',
            ),
            style: TextStyle(
              color: AppColors.muted(context),
              fontSize: 12,
              height: 1.5,
            ),
          ),
        ),
        const SizedBox(height: 16),
        // پروتکل
        Text(
          _t('پروتکل', 'Protocol'),
          style: TextStyle(
              color: AppColors.muted(context),
              fontSize: 13,
              fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final p in AetherProfile.protocols)
              ChoiceChip(
                label: Text(p == 'auto' ? _t('خودکار', 'Auto') : p.toUpperCase()),
                selected: _aetherProtocol == p,
                selectedColor: const Color(0xFF29B6F6).withOpacity(0.25),
                labelStyle: TextStyle(
                  color: _aetherProtocol == p
                      ? const Color(0xFF29B6F6)
                      : AppColors.muted(context),
                  fontSize: 12,
                ),
                onSelected: (_) => setState(() => _aetherProtocol = p),
              ),
          ],
        ),
        const SizedBox(height: 14),
        Text(
          _t('حالت اسکن', 'Scan mode'),
          style: TextStyle(
              color: AppColors.muted(context),
              fontSize: 13,
              fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final s in AetherProfile.scans)
              ChoiceChip(
                label: Text(s),
                selected: _aetherScan == s,
                selectedColor: const Color(0xFF29B6F6).withOpacity(0.25),
                labelStyle: TextStyle(
                  color: _aetherScan == s
                      ? const Color(0xFF29B6F6)
                      : AppColors.muted(context),
                  fontSize: 12,
                ),
                onSelected: (_) => setState(() => _aetherScan = s),
              ),
          ],
        ),
        const SizedBox(height: 14),
        Text(
          _t('Endpoint دستی (اختیاری)', 'Manual endpoint (optional)'),
          style: TextStyle(
              color: AppColors.muted(context),
              fontSize: 13,
              fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _aetherPeerController,
          style: TextStyle(color: AppColors.fg(context), fontSize: 13),
          decoration: InputDecoration(
            hintText: '162.159.192.1:2408',
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
                  const BorderSide(color: Color(0xFF29B6F6), width: 1.5),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          _t('نام (اختیاری)', 'Name (optional)'),
          style: TextStyle(
              color: AppColors.muted(context),
              fontSize: 13,
              fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _nameController,
          style: TextStyle(color: AppColors.fg(context)),
          decoration: InputDecoration(
            hintText: _t('مثال: Oblivion من', 'e.g. My Oblivion'),
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
                  const BorderSide(color: Color(0xFF29B6F6), width: 1.5),
            ),
          ),
        ),
        const SizedBox(height: 12),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(_t('اتصال مجدد سریع', 'Quick reconnect'),
              style: TextStyle(color: AppColors.fg(context), fontSize: 14)),
          value: _aetherQuickReconnect,
          activeColor: const Color(0xFF29B6F6),
          onChanged: (v) => setState(() => _aetherQuickReconnect = v),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(_t('مسدود کردن QUIC', 'Block QUIC'),
              style: TextStyle(color: AppColors.fg(context), fontSize: 14)),
          value: _aetherBlockQuic,
          activeColor: const Color(0xFF29B6F6),
          onChanged: (v) => setState(() => _aetherBlockQuic = v),
        ),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          height: 50,
          child: ElevatedButton(
            onPressed: _addOblivionServer,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF29B6F6),
              foregroundColor: Colors.black,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            child: Text(
              _t('افزودن Oblivion', 'Add Oblivion'),
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
          ),
        ),
      ],
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

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required Color color,
  }) {
    OutlineInputBorder border(Color c, [double w = 1]) => OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: c, width: w),
        );

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
        TextField(
          controller: controller,
          style: TextStyle(color: AppColors.fg(context), fontSize: 13),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(color: AppColors.muted2(context)),
            filled: true,
            fillColor: AppColors.surface(context),
            border: border(AppColors.border(context)),
            enabledBorder: border(AppColors.border(context)),
            focusedBorder: border(color, 1.5),
          ),
        ),
      ],
    );
  }

  Widget _buildAetherForm() {
    const color = Color(0xFF7C4DFF);
    const gap = SizedBox(height: 18);

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
                    'Aether خودش مسیر آزاد را پیدا می‌کند و به شبکه‌ی WARP وصل می‌شود؛ نیازی به لینک سرور نیست. در حالت «هوشمند» ابتدا سریع‌ترین روش امتحان می‌شود و اگر نشد، خودکار به روش‌های قوی‌تر می‌رود.',
                    'Aether finds a working route and connects to WARP by itself; no server link is needed. In Smart mode it tries the fastest method first and escalates automatically.',
                  ),
                  style: TextStyle(
                    color: AppColors.muted(context),
                    fontSize: 12.5,
                    height: 1.5,
                  ),
                ),
              ),
            ],
          ),
        ),
        gap,
        _buildChoiceRow(
          label: _t('پروتکل انتقال', 'Transport protocol'),
          values: AetherProfile.protocols,
          valueLabelsFa: const {
            'auto': 'خودکار (پیشنهادی)',
            'masque': 'MASQUE (HTTP/3)',
            'masque_h2': 'MASQUE (HTTP/2)',
            'wg': 'WireGuard',
            'gool': 'Gool (WARP در WARP)',
            'mim': 'MIM (MASQUE در MASQUE)',
          },
          valueLabelsEn: const {
            'auto': 'Auto (recommended)',
            'masque': 'MASQUE (HTTP/3)',
            'masque_h2': 'MASQUE (HTTP/2)',
            'wg': 'WireGuard',
            'gool': 'Gool (WARP-in-WARP)',
            'mim': 'MIM (MASQUE-in-MASQUE)',
          },
          selected: _aetherProtocol,
          onSelected: (v) => setState(() => _aetherProtocol = v),
          color: color,
        ),
        gap,
        _buildChoiceRow(
          label: _t('حالت اسکن', 'Scan mode'),
          values: AetherProfile.scans,
          valueLabelsFa: const {
            'smart': 'هوشمند',
            'turbo': 'توربو (سریع‌ترین اتصال)',
            'balanced': 'متعادل (پینگ بهتر)',
            'thorough': 'کامل',
            'stealth': 'مخفی',
            'ironclad': 'آهنین (مطمئن‌ترین)',
          },
          valueLabelsEn: const {
            'smart': 'Smart',
            'turbo': 'Turbo (fastest connect)',
            'balanced': 'Balanced (better ping)',
            'thorough': 'Thorough',
            'stealth': 'Stealth',
            'ironclad': 'Ironclad (most reliable)',
          },
          selected: _aetherScan,
          onSelected: (v) => setState(() => _aetherScan = v),
          color: color,
        ),
        gap,
        _buildChoiceRow(
          label: _t('نسخه‌ی IP', 'IP version'),
          values: AetherProfile.ips,
          valueLabelsFa: const {'v4': 'IPv4', 'v6': 'IPv6', 'both': 'هر دو'},
          valueLabelsEn: const {'v4': 'IPv4', 'v6': 'IPv6', 'both': 'Both'},
          selected: _aetherIp,
          onSelected: (v) => setState(() => _aetherIp = v),
          color: color,
        ),
        gap,
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          activeColor: color,
          title: Text(
            _t('اتصال مجدد سریع', 'Quick reconnect'),
            style: TextStyle(color: AppColors.fg(context), fontSize: 14),
          ),
          subtitle: Text(
            _t(
              'از آخرین مسیر سالم دوباره استفاده می‌کند (بدون اسکن تازه)',
              'Reuses the last working gateway (no fresh scan)',
            ),
            style: TextStyle(color: AppColors.muted2(context), fontSize: 11.5),
          ),
          value: _aetherQuickReconnect,
          onChanged: (v) => setState(() => _aetherQuickReconnect = v),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          activeColor: color,
          title: Text(
            _t('مسدود کردن QUIC', 'Block QUIC'),
            style: TextStyle(color: AppColors.fg(context), fontSize: 14),
          ),
          subtitle: Text(
            _t(
              'مرورگر و برنامه‌ها فوراً به TCP برمی‌گردند (بارگذاری صفحات سریع‌تر)',
              'Browsers/apps fall back to TCP immediately (faster page loads)',
            ),
            style: TextStyle(color: AppColors.muted2(context), fontSize: 11.5),
          ),
          value: _aetherBlockQuic,
          onChanged: (v) => setState(() => _aetherBlockQuic = v),
        ),
        const SizedBox(height: 4),
        InkWell(
          onTap: () => setState(() => _aetherAdvanced = !_aetherAdvanced),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              children: [
                Icon(
                  _aetherAdvanced ? Icons.expand_less : Icons.expand_more,
                  color: color,
                ),
                const SizedBox(width: 6),
                Text(
                  _t('تنظیمات پیشرفته', 'Advanced'),
                  style: const TextStyle(
                    color: color,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
        if (_aetherAdvanced) ...[
          const SizedBox(height: 8),
          _buildChoiceRow(
            label: _t('پروفایل نویز (مقابله با DPI)', 'Noize profile (anti-DPI)'),
            values: AetherProfile.noizes,
            valueLabelsFa: const {
              'auto': 'خودکار',
              'off': 'خاموش',
              'light': 'سبک',
              'firewall': 'فایروال',
              'balanced': 'متعادل',
              'gfw': 'GFW',
              'aggressive': 'شدید',
            },
            valueLabelsEn: const {
              'auto': 'Auto',
              'off': 'Off',
              'light': 'Light',
              'firewall': 'Firewall',
              'balanced': 'Balanced',
              'gfw': 'GFW',
              'aggressive': 'Aggressive',
            },
            selected: _aetherNoize,
            onSelected: (v) => setState(() => _aetherNoize = v),
            color: color,
          ),
          gap,
          _buildChoiceRow(
            label: _t('مصرف منابع', 'Performance profile'),
            values: AetherProfile.perfs,
            valueLabelsFa: const {
              'auto': 'خودکار',
              'low': 'کم',
              'medium': 'متوسط',
              'high': 'بالا (سرعت بیشتر)',
            },
            valueLabelsEn: const {
              'auto': 'Auto',
              'low': 'Low',
              'medium': 'Medium',
              'high': 'High (more speed)',
            },
            selected: _aetherPerf,
            onSelected: (v) => setState(() => _aetherPerf = v),
            color: color,
          ),
          gap,
          _buildTextField(
            controller: _aetherDnsController,
            label: _t('DNS داخل تونل (اختیاری)', 'DNS inside tunnel (optional)'),
            hint: '1.1.1.1, 1.0.0.1',
            color: color,
          ),
          gap,
          _buildTextField(
            controller: _aetherPeerController,
            label: _t('Peer دستی ip:port (اختیاری)', 'Manual peer ip:port (optional)'),
            hint: '162.159.192.1:2408',
            color: color,
          ),
          gap,
          _buildTextField(
            controller: _aetherUpstreamController,
            label: _t('پراکسی بالادستی (اختیاری)', 'Upstream proxy (optional)'),
            hint: 'socks5://127.0.0.1:1080',
            color: color,
          ),
        ],
        gap,
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
              subtitle: _t('هستهٔ واقعی Psiphon Labs',
                  'Real Psiphon Labs core'),
              icon: Icons.water_drop,
              type: 'siphon',
              color: const Color(0xFF26A69A),
            ),
            _buildTypeCard(
              title: 'Tor',
              subtitle: _t('مسیر stealth ضد فیلتر سخت',
                  'Stealth path for heavy filtering'),
              icon: Icons.security,
              type: 'tor',
              color: const Color(0xFFEF5350),
            ),

            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _addFreeEnginePack,
                icon: const Icon(Icons.flash_on, size: 18),
                label: Text(_t(
                  'افزودن هر ۳ موتور رایگان (پیشنهادی)',
                  'Add all 3 free engines (recommended)',
                )),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.accent,
                  side: const BorderSide(color: AppColors.accent),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
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
            ] else if (_selectedType == 'oblivion') ...[
              _buildOblivionForm(),
            ] else if (_selectedType == 'siphon') ...[
              _buildSiphonForm(),
            ] else if (_selectedType == 'tor') ...[
              _buildTorForm(),
            ],
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _linkController.dispose();
    _psiphonSponsorController.dispose();
    _psiphonChannelController.dispose();
    _psiphonConfigController.dispose();
    _nameController.dispose();
    _aetherDnsController.dispose();
    _aetherPeerController.dispose();
    _aetherUpstreamController.dispose();
    super.dispose();
  }
}
