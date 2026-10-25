import 'package:flutter/material.dart';

import '../controllers/connection.dart';
import '../controllers/servers.dart';
import '../l10n/s.dart';
import '../models/server.dart';
import '../services/warp_service.dart';
import '../ui/kit/ios_kit.dart';
import '../ui/theme/ios_palette.dart';

/// WireGuard — لیست سرورهای AmneziaWG/WireGuard (پورت WireguardTab.kt).
/// داده: سرورهای `amneziaWg` از مخزن (ساخت WARP یا ایمپورت `vpn://`).
/// تونل: خروجی WireGuard هستهٔ Xray — مسیر واقعی موجود.
class WireGuardScreen extends StatefulWidget {
  const WireGuardScreen({super.key});

  @override
  State<WireGuardScreen> createState() => _WireGuardScreenState();
}

class _WireGuardScreenState extends State<WireGuardScreen> {
  final ServerRepository _repo = ServerRepository.instance;
  final ConnectionController _conn = ConnectionController.instance;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _repo.addListener(_onChange);
    _conn.addListener(_onChange);
  }

  @override
  void dispose() {
    _repo.removeListener(_onChange);
    _conn.removeListener(_onChange);
    super.dispose();
  }

  void _onChange() {
    if (mounted) setState(() {});
  }

  String _t(String fa, String en) => S.isFa ? fa : en;

  List<VpnServer> get _wgServers =>
      _repo.servers.where((s) => s.protocol == VpnProtocol.amneziaWg).toList();

  Future<void> _import() async {
    final link = await showIosPrompt(
      context,
      title: _t('ایمپورت WireGuard', 'Import WireGuard'),
      message: _t(
          'لینک Amnezia را بچسبان (vpn://…)',
          'Paste an Amnezia link (vpn://...)'),
      keyboardType: TextInputType.multiline,
      confirmLabel: _t('افزودن', 'Add'),
      cancelLabel: _t('انصراف', 'Cancel'),
    );
    if (link == null || link.trim().isEmpty) return;
    setState(() => _busy = true);
    try {
      final n = await _repo.addFromLink(link.trim());
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          backgroundColor: IosPal.of(context).card,
          content: Text(
            n > 0
                ? _t('$n کانفیگ اضافه شد', '$n config(s) added')
                : _t('لینک نامعتبر یا تکراری', 'Invalid or duplicate link'),
            style: const TextStyle(color: Colors.white),
          ),
        ));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _newWarpIdentity() async {
    setState(() => _busy = true);
    try {
      final gen = await WarpService.generate();
      if (!mounted) return;
      if (gen.server != null) {
        await _repo.addServer(gen.server!);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          backgroundColor: IosPal.of(context).card,
          content: Text(_t('هویت WARP ساخته شد', 'WARP identity created'),
              style: const TextStyle(color: Colors.white)),
        ));
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          backgroundColor: IosPal.of(context).card,
          content: Text(gen.error ?? _t('خطا', 'Error'),
              style: const TextStyle(color: Colors.white)),
        ));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _connect(VpnServer s) async {
    lightHaptic();
    await _repo.select(s);
    if (_conn.connected || _conn.connecting) {
      await _conn.disconnect();
      await Future.delayed(const Duration(milliseconds: 400));
    }
    await _conn.connectServer(s);
  }

  @override
  Widget build(BuildContext context) {
    final pal = IosPal.of(context);
    final servers = _wgServers;
    final connectedId = _conn.connected ? _conn.activeServer?.id : null;

    return IosScreen(
      title: S.t('home_wireguard'),
      onBack: () => Navigator.pop(context),
      trailing: _busy
          ? const Padding(
              padding: EdgeInsets.all(12),
              child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white)),
            )
          : IconButton(
              icon: const Icon(Icons.add, color: Colors.white),
              onPressed: _import,
            ),
      children: [
        SettingsGroup(
          children: [
            SettingsActionRow(
              icon: Icons.badge_outlined,
              iconColor: pal.blue,
              title: _t('ساخت هویت WARP', 'Create WARP identity'),
              busy: _busy,
              onTap: _busy ? null : _newWarpIdentity,
            ),
          ],
        ),
        SettingsFooter(_t(
            'WARP یک سرور WireGuard آماده می‌سازد؛ کانفیگ‌های Amnezia را هم می‌توانی با + ایمپورت کنی.',
            'WARP creates a ready WireGuard server; import Amnezia configs with +.')),
        SettingsSectionHeader(
            _t('${servers.length} سرور', '${servers.length} servers')),
        if (servers.isEmpty)
          Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              _t('هنوز سروری نیست — هویت WARP بساز یا ایمپورت کن',
                  'No servers yet — create a WARP identity or import'),
              textAlign: TextAlign.center,
              style: TextStyle(color: pal.textMuted, fontSize: 13),
            ),
          )
        else
          SettingsGroup(
            children: [
              for (final s in servers)
                SettingsRow(
                  title: s.displayName,
                  value: s.ping != null && s.status == ServerStatus.online
                      ? '${s.ping}ms'
                      : (s.status == ServerStatus.offline
                          ? _t('خاموش', 'down')
                          : null),
                  leading: Text(
                    s.flag.isEmpty ? '🛡️' : s.flag,
                    style: const TextStyle(fontSize: 20),
                  ),
                  trailing: connectedId == s.id
                      ? Icon(Icons.circle,
                          size: 10, color: pal.green)
                      : null,
                  onTap: () => _connect(s),
                  onLongPress: () {
                    showIosAlert(
                      context,
                      title: _t('حذف سرور؟', 'Delete server?'),
                      message: s.displayName,
                      confirmLabel: _t('حذف', 'Delete'),
                      destructive: true,
                      onConfirm: () => _repo.deleteServers({s.id}),
                    );
                  },
                ),
            ],
          ),
        const SizedBox(height: 24),
      ],
    );
  }
}
