import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../models/server.dart';
import 'v2ray_engine.dart';
import 'warp_masque_service.dart';

class WarpMasqueState {
  final bool running;
  final bool connecting;
  final bool routingThroughVpn;
  final String? error;

  const WarpMasqueState({
    this.running = false,
    this.connecting = false,
    this.routingThroughVpn = false,
    this.error,
  });

  WarpMasqueState copyWith({
    bool? running,
    bool? connecting,
    bool? routingThroughVpn,
    String? error,
    bool clearError = false,
  }) =>
      WarpMasqueState(
        running: running ?? this.running,
        connecting: connecting ?? this.connecting,
        routingThroughVpn: routingThroughVpn ?? this.routingThroughVpn,
        error: clearError ? null : (error ?? this.error),
      );
}

class WarpMasqueSessionService {
  WarpMasqueSessionService._();
  static final WarpMasqueSessionService instance =
      WarpMasqueSessionService._();

  final Map<String, ValueNotifier<WarpMasqueState>> _notifiers = {};
  final ValueNotifier<int> routingCount = ValueNotifier(0);

  String? _activeServerId;
  bool _routing = false;
  bool _wasRouting = false;

  ValueNotifier<WarpMasqueState> notifierFor(String serverId) =>
      _notifiers.putIfAbsent(
        serverId,
        () => ValueNotifier(const WarpMasqueState()),
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

  Future<void> connect(
    String serverId, {
    required String endpoint,
    String sni = WarpMasqueService.defaultSni,
    String dns = WarpMasqueService.defaultDns,
    bool http2 = true,
    bool desyncEnabled = false,
    int desyncSocksPort = 0,
  }) async {
    if (_activeServerId != null && _activeServerId != serverId) {
      await disconnect();
    }
    _activeServerId = serverId;
    final n = notifierFor(serverId);
    n.value = n.value.copyWith(connecting: true, clearError: true);

    WarpMasqueService.onError = (msg) {
      n.value = n.value.copyWith(error: msg, connecting: false, running: false);
    };
    WarpMasqueService.onReady = () {};

    final ok = await WarpMasqueService.start(
      endpoint: endpoint,
      endpointCandidates: WarpMasqueService.defaultEndpointCandidates,
      sni: sni,
      dns: dns,
      http2: http2,
      desyncEnabled: desyncEnabled,
      desyncSocksPort: desyncSocksPort,
    );

    if (!ok) {
      n.value = n.value.copyWith(
        connecting: false,
        error: WarpMasqueService.lastError ?? 'start failed',
      );
      _activeServerId = null;
      return;
    }

    n.value = n.value.copyWith(running: true, connecting: false);
    await _startVpnRouting(serverId);
  }

  Future<void> disconnect() async {
    _routing = false;
    try {
      await V2RayEngine.disconnect();
    } catch (_) {}
    try {
      await WarpMasqueService.stop();
    } catch (_) {}
    final id = _activeServerId;
    if (id != null) notifierFor(id).value = const WarpMasqueState();
    _activeServerId = null;
    _updateRoutingFlag();
  }

  Future<void> _startVpnRouting(String serverId) async {
    if (_routing) return;
    _routing = true;
    try {
      final cfg = _buildMasqueXrayConfig();
      final fake = VpnServer(
        id: 'wmq_${serverId}_${DateTime.now().millisecondsSinceEpoch}',
        name: 'WARP MASQUE',
        flag: '\u{1F310}',
        shareLink: 'xrayjson://wmq',
        protocol: VpnProtocol.xrayJson,
        host: '127.0.0.1',
        port: WarpMasqueService.socksPort,
        isDeletable: false,
      );
      final ok = await V2RayEngine.startConfig(
        remark: 'WARP MASQUE',
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

  String _buildMasqueXrayConfig() {
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
          'tag': 'wmq-out',
          'protocol': 'socks',
          'settings': {
            'servers': [
              {'address': '127.0.0.1', 'port': WarpMasqueService.socksPort},
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
