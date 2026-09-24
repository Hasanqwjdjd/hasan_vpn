import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/app_colors.dart';
import '../services/hev_engine_settings.dart';

/// صفحهٔ تنظیمات HEV SOCKS5 Tunnel.
class HevEngineScreen extends StatefulWidget {
  final String language;
  const HevEngineScreen({super.key, required this.language});

  @override
  State<HevEngineScreen> createState() => _HevEngineScreenState();
}

class _HevEngineScreenState extends State<HevEngineScreen> {
  bool get _fa => widget.language == 'fa';
  String _t(String fa, String en) => _fa ? fa : en;

  final _name = TextEditingController();
  final _mtu = TextEditingController();
  final _ipv4 = TextEditingController();
  final _ipv6 = TextEditingController();
  final _socksPort = TextEditingController();
  final _socksAddr = TextEditingController();
  final _mapAddr = TextEditingController();
  final _mapPort = TextEditingController();
  final _mapNet = TextEditingController();
  final _mapMask = TextEditingController();
  final _mapCache = TextEditingController();
  final _connectTimeout = TextEditingController();
  final _username = TextEditingController();
  final _password = TextEditingController();

  bool _multiQueue = false;
  String _icmp = 'off';
  String _udp = 'udp';
  bool _pipeline = false;
  bool _tcpFastopen = false;
  bool _loading = true;
  String? _lastPath;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    _name.text = await HevEngineSettings.getString(
        'name', HevEngineSettings.defaultName);
    _mtu.text = (await HevEngineSettings.getInt(
            'mtu', HevEngineSettings.defaultMtu))
        .toString();
    _ipv4.text = await HevEngineSettings.getString(
        'ipv4', HevEngineSettings.defaultIpv4);
    _ipv6.text = await HevEngineSettings.getString(
        'ipv6', HevEngineSettings.defaultIpv6);
    _multiQueue = await HevEngineSettings.getBool(
        'multi_queue', HevEngineSettings.defaultMultiQueue);
    _icmp = await HevEngineSettings.getString(
        'icmp', HevEngineSettings.defaultIcmp);
    _socksPort.text = (await HevEngineSettings.getInt(
            'socks_port', HevEngineSettings.defaultSocksPort))
        .toString();
    _socksAddr.text = await HevEngineSettings.getString(
        'socks_address', HevEngineSettings.defaultSocksAddress);
    _udp = await HevEngineSettings.getString('udp', HevEngineSettings.defaultUdp);
    _pipeline = await HevEngineSettings.getBool(
        'pipeline', HevEngineSettings.defaultPipeline);
    _tcpFastopen = await HevEngineSettings.getBool(
        'tcp_fastopen', HevEngineSettings.defaultTcpFastopen);
    _username.text = await HevEngineSettings.getString('username', '');
    _password.text = await HevEngineSettings.getString('password', '');
    _mapAddr.text = await HevEngineSettings.getString(
        'mapdns_address', HevEngineSettings.defaultMapDnsAddress);
    _mapPort.text = (await HevEngineSettings.getInt(
            'mapdns_port', HevEngineSettings.defaultMapDnsPort))
        .toString();
    _mapNet.text = await HevEngineSettings.getString(
        'mapdns_network', HevEngineSettings.defaultMapDnsNetwork);
    _mapMask.text = await HevEngineSettings.getString(
        'mapdns_netmask', HevEngineSettings.defaultMapDnsNetmask);
    _mapCache.text = (await HevEngineSettings.getInt(
            'mapdns_cache_size', HevEngineSettings.defaultMapDnsCacheSize))
        .toString();
    _connectTimeout.text = (await HevEngineSettings.getInt(
            'connect_timeout_ms', HevEngineSettings.defaultConnectTimeoutMs))
        .toString();
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _save() async {
    await HevEngineSettings.setString('name', _name.text.trim());
    await HevEngineSettings.setInt(
        'mtu', int.tryParse(_mtu.text.trim()) ?? HevEngineSettings.defaultMtu);
    await HevEngineSettings.setString('ipv4', _ipv4.text.trim());
    await HevEngineSettings.setString('ipv6', _ipv6.text.trim());
    await HevEngineSettings.setBool('multi_queue', _multiQueue);
    await HevEngineSettings.setString('icmp', _icmp);
    await HevEngineSettings.setInt(
        'socks_port',
        int.tryParse(_socksPort.text.trim()) ??
            HevEngineSettings.defaultSocksPort);
    await HevEngineSettings.setString('socks_address', _socksAddr.text.trim());
    await HevEngineSettings.setString('udp', _udp);
    await HevEngineSettings.setBool('pipeline', _pipeline);
    await HevEngineSettings.setBool('tcp_fastopen', _tcpFastopen);
    await HevEngineSettings.setString('username', _username.text.trim());
    await HevEngineSettings.setString('password', _password.text.trim());
    await HevEngineSettings.setString('mapdns_address', _mapAddr.text.trim());
    await HevEngineSettings.setInt(
        'mapdns_port',
        int.tryParse(_mapPort.text.trim()) ??
            HevEngineSettings.defaultMapDnsPort);
    await HevEngineSettings.setString('mapdns_network', _mapNet.text.trim());
    await HevEngineSettings.setString('mapdns_netmask', _mapMask.text.trim());
    await HevEngineSettings.setInt(
        'mapdns_cache_size',
        int.tryParse(_mapCache.text.trim()) ??
            HevEngineSettings.defaultMapDnsCacheSize);
    await HevEngineSettings.setInt(
        'connect_timeout_ms',
        int.tryParse(_connectTimeout.text.trim()) ??
            HevEngineSettings.defaultConnectTimeoutMs);

    try {
      // بدون path_provider: از مسیر استاندارد Android filesDir استفاده می‌کنیم.
      final base = Directory('/data/data/com.hasan.hasan_vpn/files');
      if (!base.existsSync()) base.createSync(recursive: true);
      final path = await HevEngineSettings.writeConfigFile(base);
      _lastPath = path;
    } catch (_) {
      _lastPath = null;
    }

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(_lastPath == null
            ? _t('ذخیره شد (SharedPreferences)', 'Saved (SharedPreferences)')
            : _t('ذخیره شد: $_lastPath', 'Saved: $_lastPath')),
      ),
    );
  }

  Widget _field(TextEditingController c, String label) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextField(
        controller: c,
        style: TextStyle(color: AppColors.fg(context), fontSize: 14),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: TextStyle(color: AppColors.muted(context)),
          isDense: true,
          border: const OutlineInputBorder(),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg(context),
      appBar: AppBar(
        backgroundColor: AppColors.elevated(context),
        title: Text(_t('موتور HEV', 'HEV Engine'),
            style: TextStyle(color: AppColors.fg(context))),
        iconTheme: IconThemeData(color: AppColors.fg(context)),
        actions: [
          TextButton(
            onPressed: _loading ? null : _save,
            child: Text(_t('ذخیره', 'Save'),
                style: const TextStyle(color: AppColors.accent)),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(
                  _t(
                    'کانفیگ YAML مطابق heiher/hev-socks5-tunnel ذخیره می‌شود. '
                    'فعلاً TUN اصلی از flutter_vless است؛ این فایل برای sidecar آماده است.',
                    'YAML matches heiher/hev-socks5-tunnel. Main TUN is still '
                    'flutter_vless; this file is prepared for a sidecar.',
                  ),
                  style: TextStyle(
                      color: AppColors.muted(context), fontSize: 12),
                ),
                const SizedBox(height: 16),
                Text(_t('تونل', 'Tunnel'),
                    style: TextStyle(
                        color: AppColors.fg(context),
                        fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                _field(_name, 'name'),
                _field(_mtu, 'mtu'),
                _field(_ipv4, 'ipv4'),
                _field(_ipv6, 'ipv6'),
                SwitchListTile(
                  title: Text(_t('multi-queue', 'multi-queue'),
                      style: TextStyle(color: AppColors.fg(context))),
                  value: _multiQueue,
                  onChanged: (v) => setState(() => _multiQueue = v),
                ),
                DropdownButtonFormField<String>(
                  value: _icmp,
                  dropdownColor: AppColors.elevated(context),
                  decoration: InputDecoration(
                    labelText: 'icmp',
                    labelStyle: TextStyle(color: AppColors.muted(context)),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'off', child: Text('off')),
                    DropdownMenuItem(value: 'reply', child: Text('reply')),
                  ],
                  onChanged: (v) {
                    if (v != null) setState(() => _icmp = v);
                  },
                ),
                const SizedBox(height: 16),
                Text(_t('SOCKS5', 'SOCKS5'),
                    style: TextStyle(
                        color: AppColors.fg(context),
                        fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                _field(_socksAddr, 'address'),
                _field(_socksPort, 'port'),
                DropdownButtonFormField<String>(
                  value: _udp,
                  dropdownColor: AppColors.elevated(context),
                  decoration: InputDecoration(
                    labelText: 'udp',
                    labelStyle: TextStyle(color: AppColors.muted(context)),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'udp', child: Text('udp')),
                    DropdownMenuItem(value: 'tcp', child: Text('tcp')),
                  ],
                  onChanged: (v) {
                    if (v != null) setState(() => _udp = v);
                  },
                ),
                SwitchListTile(
                  title: Text('pipeline',
                      style: TextStyle(color: AppColors.fg(context))),
                  value: _pipeline,
                  onChanged: (v) => setState(() => _pipeline = v),
                ),
                SwitchListTile(
                  title: Text('tcp-fastopen',
                      style: TextStyle(color: AppColors.fg(context))),
                  value: _tcpFastopen,
                  onChanged: (v) => setState(() => _tcpFastopen = v),
                ),
                _field(_username, 'username'),
                _field(_password, 'password'),
                const SizedBox(height: 16),
                Text('mapdns',
                    style: TextStyle(
                        color: AppColors.fg(context),
                        fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                _field(_mapAddr, 'address'),
                _field(_mapPort, 'port'),
                _field(_mapNet, 'network'),
                _field(_mapMask, 'netmask'),
                _field(_mapCache, 'cache-size (0=off)'),
                const SizedBox(height: 16),
                Text('misc',
                    style: TextStyle(
                        color: AppColors.fg(context),
                        fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                _field(_connectTimeout, 'connect-timeout (ms)'),
                const SizedBox(height: 24),
                OutlinedButton(
                  onPressed: () async {
                    await HevEngineSettings.resetDefaults();
                    await _load();
                  },
                  child: Text(_t('بازنشانی پیش‌فرض', 'Reset defaults')),
                ),
              ],
            ),
    );
  }

  @override
  void dispose() {
    _name.dispose();
    _mtu.dispose();
    _ipv4.dispose();
    _ipv6.dispose();
    _socksPort.dispose();
    _socksAddr.dispose();
    _mapAddr.dispose();
    _mapPort.dispose();
    _mapNet.dispose();
    _mapMask.dispose();
    _mapCache.dispose();
    _connectTimeout.dispose();
    _username.dispose();
    _password.dispose();
    super.dispose();
  }
}
