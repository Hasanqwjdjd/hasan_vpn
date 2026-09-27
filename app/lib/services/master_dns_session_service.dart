import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../models/server.dart';
import 'master_dns_service.dart';
import 'v2ray_engine.dart';

/// Session state for a single MasterDNS profile.
class MasterDnsState {
  final bool running;
  final bool connecting;
  final bool routingThroughVpn;
  final int scanCompleted;
  final int scanTotal;
  final String? error;

  const MasterDnsState({
    this.running = false,
    this.connecting = false,
    this.routingThroughVpn = false,
    this.scanCompleted = 0,
    this.scanTotal = 0,
    this.error,
  });

  MasterDnsState copyWith({
    bool? running,
    bool? connecting,
    bool? routingThroughVpn,
    int? scanCompleted,
    int? scanTotal,
    String? error,
    bool clearError = false,
  }) =>
      MasterDnsState(
        running: running ?? this.running,
        connecting: connecting ?? this.connecting,
        routingThroughVpn: routingThroughVpn ?? this.routingThroughVpn,
        scanCompleted: scanCompleted ?? this.scanCompleted,
        scanTotal: scanTotal ?? this.scanTotal,
        error: clearError ? null : (error ?? this.error),
      );
}

/// Manages MasterDNS sessions — one per server id. When active, Xray
/// routes through the local SOCKS5 (port 18000) that MasterDNS opens.
class MasterDnsSessionService {
  MasterDnsSessionService._();
  static final MasterDnsSessionService instance =
      MasterDnsSessionService._();

  final Map<String, ValueNotifier<MasterDnsState>> _notifiers = {};
  final ValueNotifier<int> routingCount = ValueNotifier(0);

  String? _activeServerId;
  bool _routing = false;
  bool _wasRouting = false;

  ValueNotifier<MasterDnsState> notifierFor(String serverId) =>
      _notifiers.putIfAbsent(
        serverId,
        () => ValueNotifier(const MasterDnsState()),
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

  /// Connect a MasterDNS server. `server.shareLink` must be
  /// `masterdns://config?domain=...&key=...&method=1&resolvers=...`.
  Future<void> connect(String serverId, String domain, String key,
      {int method = 1, String resolvers = '', String? advancedToml}) async {
    if (_activeServerId != null && _activeServerId != serverId) {
      await disconnect();
    }
    _activeServerId = serverId;
    final n = notifierFor(serverId);
    n.value = n.value.copyWith(connecting: true, clearError: true);

    MasterDnsService.onProgress = (c, t) {
      n.value = n.value.copyWith(scanCompleted: c, scanTotal: t);
    };
    MasterDnsService.onError = (msg) {
      n.value = n.value.copyWith(error: msg, connecting: false, running: false);
    };
    MasterDnsService.onExit = () {
      n.value = n.value.copyWith(running: false, routingThroughVpn: false);
      _updateRoutingFlag();
    };

    final ok = await MasterDnsService.start(
      domain: domain,
      key: key,
      method: method,
      resolvers: resolvers,
      advancedToml: advancedToml,
    );

    if (!ok) {
      n.value = n.value.copyWith(
        connecting: false,
        error: MasterDnsService.lastError ?? 'start failed',
      );
      _activeServerId = null;
      return;
    }

    n.value = n.value.copyWith(running: true, connecting: false);

    // Start Xray with socks5-outbound → 127.0.0.1:18000
    await _startVpnRouting(serverId);
  }

  Future<void> disconnect() async {
    _routing = false;
    try {
      await V2RayEngine.disconnect();
    } catch (_) {}
    try {
      await MasterDnsService.stop();
    } catch (_) {}
    final id = _activeServerId;
    if (id != null) notifierFor(id).value = const MasterDnsState();
    _activeServerId = null;
    _updateRoutingFlag();
  }

  Future<void> _startVpnRouting(String serverId) async {
    if (_routing) return;
    _routing = true;
    try {
      final cfg = _buildMasterDnsXrayConfig();
      final fake = VpnServer(
        id: 'mdns_${serverId}_${DateTime.now().millisecondsSinceEpoch}',
        name: 'MasterDNS',
        flag: '\u{1F5FA}',
        shareLink: 'xrayjson://mdns',
        protocol: VpnProtocol.xrayJson,
        host: '127.0.0.1',
        port: MasterDnsService.socksPort,
        isDeletable: false,
      );
      final ok = await V2RayEngine.startConfig(
        remark: 'MasterDNS',
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

  String _buildMasterDnsXrayConfig() {
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
          'tag': 'mdns-out',
          'protocol': 'socks',
          'settings': {
            'servers': [
              {'address': '127.0.0.1', 'port': MasterDnsService.socksPort},
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
