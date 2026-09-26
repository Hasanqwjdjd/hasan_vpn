import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../models/server.dart';
import '../models/ssh_profile.dart';
import 'ssh_service.dart';
import 'v2ray_engine.dart';

class SshSessionState {
  final bool running;
  final bool connecting;
  final bool routingThroughVpn;
  final int socksPort;
  final String? error;

  const SshSessionState({
    this.running = false,
    this.connecting = false,
    this.routingThroughVpn = false,
    this.socksPort = 0,
    this.error,
  });

  SshSessionState copyWith({
    bool? running,
    bool? connecting,
    bool? routingThroughVpn,
    int? socksPort,
    String? error,
    bool clearError = false,
  }) =>
      SshSessionState(
        running: running ?? this.running,
        connecting: connecting ?? this.connecting,
        routingThroughVpn: routingThroughVpn ?? this.routingThroughVpn,
        socksPort: socksPort ?? this.socksPort,
        error: clearError ? null : (error ?? this.error),
      );
}

/// مدیریت اتصال SSH + routing ترافیک از طریق SOCKS5 روی سرور SSH.
class SshSessionService {
  SshSessionService._();
  static final SshSessionService instance = SshSessionService._();

  final Map<String, ValueNotifier<SshSessionState>> _notifiers = {};
  final ValueNotifier<int> routingCount = ValueNotifier(0);

  String? _activeServerId;
  bool _routing = false;
  bool _wasRouting = false;
  Timer? _pollTimer;

  ValueNotifier<SshSessionState> notifierFor(String serverId) =>
      _notifiers.putIfAbsent(
        serverId,
        () => ValueNotifier(const SshSessionState()),
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

  Future<void> connect(String serverId, SshProfile profile) async {
    if (_activeServerId != null && _activeServerId != serverId) {
      await disconnect();
    }
    _activeServerId = serverId;
    final n = notifierFor(serverId);
    n.value = n.value.copyWith(connecting: true, clearError: true);

    try {
      final localPort = await SshService.connect(profile);
      if (localPort <= 0) {
        n.value = n.value.copyWith(
          connecting: false,
          error: SshService.lastError ?? 'SSH connect failed',
        );
        _activeServerId = null;
        return;
      }

      n.value = n.value.copyWith(
        running: true,
        socksPort: localPort,
        connecting: false,
      );

      await _startVpnRouting(serverId, localPort);
      _startPolling();
    } catch (e) {
      n.value = n.value.copyWith(connecting: false, error: e.toString());
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
      await SshService.disconnect();
    } catch (_) {}
    final id = _activeServerId;
    if (id != null) notifierFor(id).value = const SshSessionState();
    _activeServerId = null;
    _updateRoutingFlag();
  }

  void _startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(
      const Duration(seconds: 4),
      (_) => _poll(),
    );
  }

  Future<void> _poll() async {
    final id = _activeServerId;
    if (id == null) return;
    final n = notifierFor(id);
    if (!SshService.isConnected) {
      n.value = n.value.copyWith(
        running: false,
        routingThroughVpn: false,
        error: 'SSH connection lost',
      );
      _updateRoutingFlag();
      _pollTimer?.cancel();
      _pollTimer = null;
      return;
    }
    final alive = await SshService.ping();
    if (!alive && mounted(id)) {
      n.value = n.value.copyWith(
        running: false,
        routingThroughVpn: false,
        error: 'SSH server not responding',
      );
      _updateRoutingFlag();
    }
  }

  bool mounted(String id) => _notifiers.containsKey(id);

  Future<void> _startVpnRouting(String serverId, int socksPort) async {
    if (_routing) return;
    _routing = true;
    try {
      final cfg = _buildXrayConfig(socksPort);
      final fake = VpnServer(
        id: 'ssh_${serverId}_${DateTime.now().millisecondsSinceEpoch}',
        name: 'SSH',
        flag: '🖥️',
        shareLink: 'xrayjson://ssh',
        protocol: VpnProtocol.xrayJson,
        host: '127.0.0.1',
        port: socksPort,
        isDeletable: false,
      );
      final ok = await V2RayEngine.startConfig(
        remark: 'SSH',
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
          'tag': 'ssh-out',
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
