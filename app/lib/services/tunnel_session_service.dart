import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../models/server.dart';
import '../models/tunnel_profile.dart';
import 'tunnel_service.dart';
import 'v2ray_engine.dart';

class TunnelSessionState {
  final bool running;
  final bool connecting;
  final bool routingThroughVpn;
  final int socksPort;
  final String? error;

  const TunnelSessionState({
    this.running = false,
    this.connecting = false,
    this.routingThroughVpn = false,
    this.socksPort = 0,
    this.error,
  });

  TunnelSessionState copyWith({
    bool? running,
    bool? connecting,
    bool? routingThroughVpn,
    int? socksPort,
    String? error,
    bool clearError = false,
  }) =>
      TunnelSessionState(
        running: running ?? this.running,
        connecting: connecting ?? this.connecting,
        routingThroughVpn: routingThroughVpn ?? this.routingThroughVpn,
        socksPort: socksPort ?? this.socksPort,
        error: clearError ? null : (error ?? this.error),
      );
}

/// مدیریت اتصال تونل DNS/QUIC (DNSTT / NoizDNS / VayDNS / Slipstream).
///
/// جریان:
///   1) TunnelService.start() → SOCKS5 روی 127.0.0.1:<port>
///   2) Xray با outbound=socks5 روی همون پورت راه می‌افته
///   3) VPN سیستم از داخل تونل رد می‌شه
class TunnelSessionService {
  TunnelSessionService._();
  static final TunnelSessionService instance = TunnelSessionService._();

  final Map<String, ValueNotifier<TunnelSessionState>> _notifiers = {};
  final ValueNotifier<int> routingCount = ValueNotifier(0);

  String? _activeServerId;
  int _activeSocks = 0;
  Timer? _pollTimer;
  bool _routing = false;
  bool _wasRouting = false;

  ValueNotifier<TunnelSessionState> notifierFor(String serverId) =>
      _notifiers.putIfAbsent(
        serverId,
        () => ValueNotifier(const TunnelSessionState()),
      );

  bool get anyRouting {
    for (final n in _notifiers.values) {
      if (n.value.routingThroughVpn) return true;
    }
    return false;
  }

  void _updateRoutingFlag() {
    final now = anyRouting;
    if (now != _wasRouting) {
      _wasRouting = now;
      routingCount.value = now ? 1 : 0;
    }
  }

  Future<void> connect(String serverId, TunnelProfile profile) async {
    if (_activeServerId != null && _activeServerId != serverId) {
      await disconnect();
    }
    _activeServerId = serverId;
    final n = notifierFor(serverId);
    n.value = n.value.copyWith(
      connecting: true,
      clearError: true,
    );

    try {
      final r = await TunnelService.start(profile);
      if (r['ok'] != true) {
        n.value = n.value.copyWith(
          connecting: false,
          error: r['error']?.toString() ?? 'tunnel start failed',
        );
        _activeServerId = null;
        return;
      }

      final port = (r['socksPort'] as num?)?.toInt() ?? 0;
      if (port <= 0) {
        n.value = n.value.copyWith(
          connecting: false,
          error: 'no socks port',
        );
        _activeServerId = null;
        return;
      }

      _activeSocks = port;
      n.value = n.value.copyWith(
        running: true,
        socksPort: port,
        connecting: false,
      );

      await _startVpnRouting(serverId, port);
      _startPolling();
    } catch (e) {
      n.value = n.value.copyWith(
        connecting: false,
        error: e.toString(),
      );
      _activeServerId = null;
    }
  }

  Future<void> disconnect() async {
    _pollTimer?.cancel();
    _pollTimer = null;
    _routing = false;
    try {
      await V2RayEngine.disconnect();
    } catch (_) {}
    try {
      await TunnelService.stop();
    } catch (_) {}
    final id = _activeServerId;
    if (id != null) {
      notifierFor(id).value = const TunnelSessionState();
    }
    _activeServerId = null;
    _activeSocks = 0;
    _updateRoutingFlag();
  }

  void _startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(
      const Duration(milliseconds: 900),
      (_) => _poll(),
    );
  }

  Future<void> _poll() async {
    final id = _activeServerId;
    if (id == null) return;
    final n = notifierFor(id);
    try {
      final st = await TunnelService.status();
      final running = st['running'] == true && st['exited'] != true;
      final err = st['error']?.toString();
      n.value = n.value.copyWith(
        running: running,
        error: (err == null || err.isEmpty) ? null : err,
        clearError: err == null || err.isEmpty,
      );
      if (!running && n.value.routingThroughVpn) {
        n.value = n.value.copyWith(routingThroughVpn: false);
      }
      _updateRoutingFlag();
      if (!running && !n.value.connecting) {
        _pollTimer?.cancel();
        _pollTimer = null;
      }
    } catch (_) {}
  }

  Future<void> _startVpnRouting(String serverId, int socksPort) async {
    if (_routing) return;
    _routing = true;
    try {
      final cfg = _buildXrayConfig(socksPort);
      final fake = VpnServer(
        id: 'tunnel_${serverId}_${DateTime.now().millisecondsSinceEpoch}',
        name: 'Tunnel',
        flag: '🛰️',
        shareLink: 'xrayjson://tunnel',
        protocol: VpnProtocol.xrayJson,
        host: '127.0.0.1',
        port: socksPort,
        isDeletable: false,
      );
      final ok = await V2RayEngine.startConfig(
        remark: 'Tunnel',
        config: cfg,
        server: fake,
      );
      final n = notifierFor(serverId);
      n.value = n.value.copyWith(
        routingThroughVpn: ok,
        error: ok ? null : 'VPN routing failed',
        clearError: ok,
      );
      _updateRoutingFlag();
      if (!ok) _routing = false;
    } catch (_) {
      _routing = false;
    }
  }

  String _buildXrayConfig(int socksPort) {
    final cfg = <String, dynamic>{
      'inbounds': [
        {
          'tag': 'socks-in',
          'port': 10808,
          'listen': '127.0.0.1',
          'protocol': 'socks',
          'settings': {'auth': 'noauth', 'udp': true},
          'sniffing': {
            'enabled': true,
            'destOverride': ['http', 'tls', 'quic'],
          },
        },
      ],
      'outbounds': [
        {
          'tag': 'tunnel-out',
          'protocol': 'socks',
          'settings': {
            'servers': [
              {'address': '127.0.0.1', 'port': socksPort},
            ],
          },
        },
        {'tag': 'direct', 'protocol': 'freedom'},
      ],
      'routing': {
        'domainStrategy': 'AsIs',
        'rules': <Map<String, dynamic>>[],
      },
    };
    return jsonEncode(cfg);
  }
}
