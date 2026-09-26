import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../models/server.dart';
import 'tor_service.dart';
import 'v2ray_engine.dart';

class TorSessionState {
  final bool running;
  final bool connecting;
  final bool routingThroughVpn;
  final int bootstrap;
  final String bootstrapMsg;
  final int socksPort;
  final String? error;

  const TorSessionState({
    this.running = false,
    this.connecting = false,
    this.routingThroughVpn = false,
    this.bootstrap = 0,
    this.bootstrapMsg = '',
    this.socksPort = 0,
    this.error,
  });

  TorSessionState copyWith({
    bool? running,
    bool? connecting,
    bool? routingThroughVpn,
    int? bootstrap,
    String? bootstrapMsg,
    int? socksPort,
    String? error,
    bool clearError = false,
  }) =>
      TorSessionState(
        running: running ?? this.running,
        connecting: connecting ?? this.connecting,
        routingThroughVpn: routingThroughVpn ?? this.routingThroughVpn,
        bootstrap: bootstrap ?? this.bootstrap,
        bootstrapMsg: bootstrapMsg ?? this.bootstrapMsg,
        socksPort: socksPort ?? this.socksPort,
        error: clearError ? null : (error ?? this.error),
      );
}

/// Manages a quick-connect Tor session from the Home screen.
/// Shares state via ValueNotifier per bridge type.
class TorSessionService {
  TorSessionService._();
  static final TorSessionService instance = TorSessionService._();

  static const String presetVanillaId = 'tor_preset_vanilla';
  static const String presetWebtunnelId = 'tor_preset_webtunnel';

  final Map<String, ValueNotifier<TorSessionState>> _notifiers = {};
  final Map<String, String> _bridgeTypes = {};
  String? _activeBridgeId;
  Timer? _pollTimer;
  bool _routing = false;

  ValueNotifier<TorSessionState> notifierFor(String bridgeId) => _notifiers
      .putIfAbsent(bridgeId, () => ValueNotifier(const TorSessionState()));

  String bridgeTypeFor(String bridgeId) =>
      bridgeId == presetWebtunnelId ? 'webtunnel' : 'vanilla';

  bool isPreset(String id) =>
      id == presetVanillaId || id == presetWebtunnelId;

  Future<void> connect(String bridgeId) =>
      connectWithType(bridgeId, bridgeTypeFor(bridgeId));

  /// اتصال Tor با نوع پل صریح — برای پنل inline و ویجت.
  Future<void> connectWithType(String bridgeId, String bridgeType) async {
    if (_activeBridgeId != null && _activeBridgeId != bridgeId) {
      await disconnect();
    }
    _activeBridgeId = bridgeId;
    _bridgeTypes[bridgeId] = bridgeType;
    final n = notifierFor(bridgeId);
    n.value = n.value.copyWith(
      connecting: true,
      clearError: true,
      bootstrap: 0,
      bootstrapMsg: 'Starting...',
    );
    final r = await TorService.start(bridgeType: bridgeType);
    if (r['ok'] != true) {
      n.value = n.value.copyWith(
        connecting: false,
        error: r['error']?.toString() ?? 'Tor start failed',
      );
      _activeBridgeId = null;
      return;
    }
    final port = (r['socksPort'] as num?)?.toInt() ?? 9050;
    n.value = n.value.copyWith(socksPort: port);
    _startPolling();
  }

  Future<void> disconnect() async {
    _pollTimer?.cancel();
    _pollTimer = null;
    _routing = false;
    try {
      await V2RayEngine.disconnect();
    } catch (_) {}
    try {
      await TorService.stop();
    } catch (_) {}
    final id = _activeBridgeId;
    if (id != null) {
      notifierFor(id).value = const TorSessionState();
    }
    _activeBridgeId = null;
  }

  void _startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(
        const Duration(milliseconds: 700), (_) => _poll());
  }

  Future<void> _poll() async {
    final id = _activeBridgeId;
    if (id == null) return;
    final n = notifierFor(id);
    try {
      final s = await TorService.status();
      final running = s['running'] == true;
      final bp = (s['bootstrapPercent'] as num?)?.toInt() ?? 0;
      final msg = s['bootstrapMessage']?.toString() ?? '';
      final port = (s['socksPort'] as num?)?.toInt() ?? n.value.socksPort;
      final err = s['error']?.toString();
      final stillConnecting =
          running && bp < 100 && n.value.routingThroughVpn == false;
      n.value = n.value.copyWith(
        running: running,
        connecting: stillConnecting,
        bootstrap: bp,
        bootstrapMsg: msg,
        socksPort: port,
        error: (err == null || err.isEmpty) ? null : err,
        clearError: err == null || err.isEmpty,
      );
      if (running && bp >= 100 && !_routing) {
        await _startVpnRouting(port);
      }
      if (!running && !n.value.routingThroughVpn) {
        _pollTimer?.cancel();
        _pollTimer = null;
      }
    } catch (_) {}
  }

  Future<void> _startVpnRouting(int socksPort) async {
    if (_routing) return;
    _routing = true;
    final id = _activeBridgeId;
    try {
      final cfg = _buildTorXrayConfig(socksPort > 0 ? socksPort : 9050);
      final fakeServer = VpnServer(
        id: 'tor_fake_$id',
        name: 'Tor',
        flag: '\u{1F9C5}',
        shareLink: 'xrayjson://tor',
        protocol: VpnProtocol.xrayJson,
        host: '127.0.0.1',
        port: socksPort,
        isDeletable: false,
      );
      final ok = await V2RayEngine.startConfig(
        remark: 'Tor',
        config: cfg,
        server: fakeServer,
      );
      if (id != null) {
        notifierFor(id).value = notifierFor(id).value.copyWith(
              routingThroughVpn: ok,
              connecting: false,
              error: ok ? null : 'VPN routing failed',
              clearError: ok,
            );
      }
      if (!ok) _routing = false;
    } catch (_) {
      _routing = false;
    }
  }

  String _buildTorXrayConfig(int socksPort) {
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
          'tag': 'tor-out',
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
