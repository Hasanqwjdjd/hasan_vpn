import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/server.dart';
import '../services/aether_service.dart';
import '../services/connection_log_service.dart';
import '../services/connection_quality.dart';
import '../services/desync_service.dart';
import '../services/home_widget_service.dart';
import '../services/master_dns_session_service.dart';
import '../services/psiphon_service.dart';
import '../services/quality_alert.dart';
import '../services/ssh_session_service.dart';
import '../services/telemetry_service.dart';
import '../services/tor_service.dart';
import '../services/tor_session_service.dart';
import '../services/tunnel_session_service.dart';
import '../services/v2ray_engine.dart';
import '../services/warp_endpoint_health_monitor.dart';
import '../services/warp_masque_session_service.dart';
import '../services/warp_service.dart';
import '../l10n/s.dart';

/// شناسهٔ موتورهای صفحهٔ Transport (پورت Transports.kt — ۷ ورودی).
enum TransportId { masque, wireguard, warpOnWarp, warp, psiphon, tor, geph }

enum ConnStage { idle, preparing, connecting, connected, failed }

/// کنترلر اتصال — استخراج ۱:۱ منطق dispatch از home_screen.dart قدیمی
/// (تعدادها و ترتیب قطع‌ها عیناً حفظ شده).
class ConnectionController extends ChangeNotifier {
  ConnectionController._();
  static final ConnectionController instance = ConnectionController._();

  bool _connecting = false;
  bool _connected = false;
  bool _cancelConnect = false;
  bool _polling = false;
  int _deadStrikes = 0;
  int _pollTick = 0;
  Timer? _pollTimer;
  Timer? _widgetTimer;
  DateTime? _lastConnectTime;
  VpnServer? _active;
  VpnServer? _connectingServer;
  final QualityMonitor _qualityMonitor = QualityMonitor();

  ConnStage stage = ConnStage.idle;
  String statusText = '';
  String? attemptLabel;
  String? attemptTarget;
  int? progress; // 0..100
  int? livePing;

  // ترافیک زنده — از TelemetryService (پرشده توسط وضعیت پلاگین).
  int downSpeed = 0;
  int upSpeed = 0;
  Timer? _trafficTimer;

  bool get connecting => _connecting;
  bool get connected => _connected;
  VpnServer? get activeServer => _active;

  String _t(String fa, String en) => S.isFa ? fa : en;

  void startLoops() {
    _pollTimer ??=
        Timer.periodic(const Duration(seconds: 4), (_) => _poll());
    _trafficTimer ??= Timer.periodic(const Duration(milliseconds: 1200),
        (_) {
      downSpeed = TelemetryService.lastDown;
      upSpeed = TelemetryService.lastUp;
      if (downSpeed != 0 || upSpeed != 0) notifyListeners();
    });
  }

  void stopLoops() {
    _pollTimer?.cancel();
    _pollTimer = null;
    _trafficTimer?.cancel();
    _trafficTimer = null;
  }

  void _setStatus(String s, {ConnStage? st}) {
    statusText = s;
    if (st != null) stage = st;
    notifyListeners();
  }

  // ── قطع همهٔ sessionها قبل از اتصال جدید (پورت ۱:۱) ──
  Future<void> _disconnectAllSessionsForNewConnect() async {
    try {
      if (TorSessionService.instance.anyRouting) {
        await TorSessionService.instance.disconnect();
      }
    } catch (_) {}
    try {
      if (TunnelSessionService.instance.anyRouting) {
        await TunnelSessionService.instance.disconnect();
      }
    } catch (_) {}
    try {
      if (SshSessionService.instance.anyRouting) {
        await SshSessionService.instance.disconnect();
      }
    } catch (_) {}
    try {
      if (MasterDnsSessionService.instance.anyRouting) {
        await MasterDnsSessionService.instance.disconnect();
      }
    } catch (_) {}
    try {
      if (WarpMasqueSessionService.instance.anyRouting) {
        await WarpMasqueSessionService.instance.disconnect();
      }
    } catch (_) {}
    try {
      if (DesyncService.isRunning) {
        await DesyncService.stop();
      }
    } catch (_) {}
    try {
      await PsiphonService.stop();
    } catch (_) {}
    try {
      if (AetherService.isConnected) {
        await AetherService.disconnect();
      }
    } catch (_) {}
    try {
      if (V2RayEngine.isConnected) {
        await V2RayEngine.disconnect();
      }
    } catch (_) {}
    _connected = false;
    _active = null;
    livePing = null;
    notifyListeners();
  }

  Future<void> disconnectAll() async {
    try {
      await PsiphonService.stop();
    } catch (_) {}
    try {
      if (AetherService.isConnected) {
        await AetherService.disconnect();
      }
    } catch (_) {}
    try {
      await TorService.stop();
    } catch (_) {}
    try {
      await V2RayEngine.disconnect();
    } catch (_) {}
  }

  void _markDisconnected(String status) {
    SharedPreferences.getInstance()
        .then((p) => p.remove('last_active_server_id_v1'))
        .catchError((_) => false);
    if (_active != null) {
      ConnectionLogService.logDisconnect(_active!.displayName);
    }
    final wasConnected = _connected;
    _active = null;
    livePing = null;
    _deadStrikes = 0;
    _pollTick = 0;
    try {
      WarpEndpointHealthMonitor.instance.stop();
    } catch (_) {}
    _stopWidgetTimerRefresh();
    HomeWidgetService.clearQuality();
    HomeWidgetService.clearConnectedStart();
    HomeWidgetService.setCountryFlag('');
    _connected = false;
    _connecting = false;
    _setStatus(status, st: ConnStage.idle);
    if (wasConnected) {
      debugPrint('[Conn] disconnected (wasConnected=true)');
    }
  }

  Future<void> _poll() async {
    if (_connecting || _polling || !_connected) return;
    _polling = true;
    try {
      // sessionهای ابزاری strike نمی‌خورند ولی sample کیفیت می‌گیرند.
      if (TorSessionService.instance.anyRouting ||
          TunnelSessionService.instance.anyRouting ||
          SshSessionService.instance.anyRouting ||
          MasterDnsSessionService.instance.anyRouting ||
          WarpMasqueSessionService.instance.anyRouting ||
          PsiphonService.isConnected ||
          V2RayEngine.isUtilitySession) {
        _pollTick++;
        if (_pollTick % 3 == 1) {
          try {
            await _measureLive();
          } catch (_) {}
        }
        return;
      }
      var alive = V2RayEngine.isConnected;
      if (!alive) {
        try {
          final probe = await V2RayEngine.probeConnected();
          if (probe.ok) alive = true;
        } catch (_) {}
      }
      if (!alive) {
        _deadStrikes++;
        if (_deadStrikes >= 5) {
          ConnectionLogService.logError('TRACE',
              'Conn._poll dead-strikes hit threshold (5) — killing tunnel');
          try {
            await disconnectAll();
          } catch (_) {}
          _markDisconnected(_t('اتصال قطع شد', 'Connection lost'));
        }
        return;
      }
      _deadStrikes = 0;
      _pollTick++;
      if (_pollTick % 3 == 1) {
        try {
          await _measureLive();
        } catch (_) {}
      }
    } finally {
      _polling = false;
    }
  }

  /// پورت ۱:۱ _measureLive — پینگ واقعی از داخل تونل + کیفیت + هشدار.
  Future<void> _measureLive() async {
    if (!_connected) return;
    final result = await V2RayEngine.probeConnected();
    livePing = result.ms;
    final active = _active;
    if (active != null && result.ok) {
      active.ping = result.ms;
      active.jitter = result.jitter;
      active.pingKind = PingKind.real;
      active.status = ServerStatus.online;
    }
    if (result.ok && result.ms != null) {
      _qualityMonitor.addSample(
        pingMs: result.ms!,
        jitterMs: result.jitter ?? 0,
      );
      ConnectionLogService.recordSample(
        rttMs: result.ms,
        jitterMs: result.jitter,
      );
      final latest = _qualityMonitor.latest.value;
      if (latest != null) {
        unawaited(Future<void>.microtask(() {
          TelemetryService.setQuality(latest.score, latest.grade.emoji);
          HomeWidgetService.setQuality(latest.score, latest.grade.emoji);
        }));
        QualityAlert.instance.evaluate(latest.score);
      }
    }
    notifyListeners();
  }

  // ── اتصال به یک سرور از لیست (dispatch مثل قدیم) ──
  Future<bool> connectServer(VpnServer selected) async {
    if (_connecting) return false;
    if (selected.protocol == VpnProtocol.ssh) {
      _setStatus(
          _t('برای این نوع سرور، روی خود سرور در لیست ضربه بزن',
              'For this server type, tap the server in the list instead'),
          st: ConnStage.failed);
      return false;
    }
    _cancelConnect = false;
    _connecting = true;
    livePing = null;
    attemptLabel = null;
    attemptTarget = null;
    _setStatus(_t('آماده‌سازی...', 'Preparing...'), st: ConnStage.preparing);
    notifyListeners();

    _setStatus(
        _t('قطع اتصال قبلی...', 'Disconnecting previous...'),
        st: ConnStage.connecting);
    await _disconnectAllSessionsForNewConnect();
    _setStatus(_t('در حال اتصال...', 'Connecting...'),
        st: ConnStage.connecting);

    try {
      selected = await _verifyWarpEndpointBeforeConnect(selected);
      if (_cancelConnect) {
        await _finishCancelled();
        return false;
      }
      _connectingServer = selected;

      final bool ok;
      if (selected.isAether) {
        _setStatus(_t('Aether · آماده‌سازی...', 'Aether · preparing...'),
            st: ConnStage.connecting);
        ok = await AetherService.connect(
          selected,
          isCancelled: () => _cancelConnect,
          onProgress: (message) {
            if (_cancelConnect) return;
            final flat = message.replaceAll('\n', ' · ');
            final m =
                RegExp(r'Aether\s+(\d+/\d+)\s*·\s*([^·\n]+)').firstMatch(flat);
            _setStatus(flat, st: ConnStage.connecting);
            if (m != null) {
              attemptLabel = m.group(1);
              attemptTarget = m.group(2)?.trim();
              notifyListeners();
            }
          },
        );
      } else if (selected.isPsiphon) {
        _setStatus(_t('Psiphon · آماده‌سازی...', 'Psiphon · preparing...'),
            st: ConnStage.connecting);
        ok = await PsiphonService.connect(
          selected,
          isCancelled: () => _cancelConnect,
          onProgress: (message) {
            if (_cancelConnect) return;
            final flat = message.replaceAll('\n', ' · ');
            final m =
                RegExp(r'\(([^)]+)\)\s*(\d+/\d+)?').firstMatch(flat);
            _setStatus(flat, st: ConnStage.connecting);
            if (m != null) {
              attemptTarget = m.group(1);
              attemptLabel = m.group(2);
              notifyListeners();
            }
          },
        );
      } else {
        ok = await V2RayEngine.connect(selected);
      }

      if (_cancelConnect && ok) {
        try {
          await disconnectAll();
        } catch (_) {}
        _markDisconnected(_t('لغو شد', 'Cancelled'));
        return false;
      }
      _deadStrikes = 0;
      _pollTick = 0;
      if (ok) {
        _lastConnectTime = DateTime.now();
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('last_active_server_id_v1', selected.id);
        HomeWidgetService.setConnectedStart(DateTime.now());
        _startWidgetTimerRefresh();
      }
      _connected = ok;
      _active = ok ? selected : null;
      _connecting = false;
      if (ok) {
        _setStatus(
            _t('متصل — ${selected.displayName}', 'Connected — ${selected.displayName}'),
            st: ConnStage.connected);
        ConnectionLogService.logConnect(selected.displayName);
      } else {
        final err = selected.isAether
            ? AetherService.lastError
            : (selected.isPsiphon
                ? PsiphonService.lastError
                : V2RayEngine.lastError);
        _setStatus(
            _t('اتصال ناموفق', 'Could not connect') +
                (err == null || err.isEmpty ? '' : ' · $err'),
            st: ConnStage.failed);
        ConnectionLogService.logError(
            selected.displayName, err ?? 'unknown');
      }
      return ok;
    } catch (e) {
      _connected = false;
      _connecting = false;
      _setStatus(_t('اتصال ناموفق', 'Could not connect') + ' · $e',
          st: ConnStage.failed);
      return false;
    } finally {
      _connectingServer = null;
      notifyListeners();
    }
  }

  Future<bool> _finishCancelled() async {
    _connecting = false;
    _markDisconnected(_t('لغو شد', 'Cancelled'));
    return false;
  }

  /// بررسی endpoint قبل از اتصال WARP (پورت ۱:۱ از قدیمی).
  Future<VpnServer> _verifyWarpEndpointBeforeConnect(VpnServer server) async {
    final isWarp = server.protocol == VpnProtocol.amneziaWg ||
        server.protocol == VpnProtocol.chain;
    if (!isWarp) return server;
    if (!server.isDeletable) return server; // built-in

    final endpoint = '${server.host}:${server.port}';
    try {
      _setStatus(
          _t('بررسی endpoint $endpoint ...', 'Verifying endpoint $endpoint ...'),
          st: ConnStage.connecting);
      final alive = await WarpEndpointHealthMonitor.quickCheck(
        endpoint,
        timeoutMs: 2500,
      );
      if (alive) {
        debugPrint('preconnect: $endpoint is alive');
        return server;
      }
      debugPrint('preconnect: $endpoint dead — rescanning');
      _setStatus(
          _t('endpoint خراب — پیدا کردن جایگزین...',
              'Endpoint dead — finding replacement...'),
          st: ConnStage.connecting);
      final rescan = await WarpService.rescanEndpoints(server);
      if (rescan.endpoint == null) {
        debugPrint('preconnect: rescan failed — using original');
        return server;
      }
      final parts = rescan.endpoint!.split(':');
      if (parts.length == 2) {
        ConnectionLogService.logWarpRescanResult(
          server: server.displayName,
          endpoint: rescan.endpoint!,
          ms: rescan.ms ?? 0,
        );
        return VpnServer(
          id: server.id,
          name: server.name,
          flag: server.flag,
          shareLink: server.shareLink,
          protocol: server.protocol,
          host: parts[0],
          port: int.tryParse(parts[1]) ?? server.port,
        );
      }
    } catch (e) {
      debugPrint('preconnect verify error: $e');
    }
    return server;
  }

  // ── Transport مستقیم: MASQUE / WARP / WARP² / Psiphon / Tor ──

  /// اتصال از تایل Transport. تنظیمات هر transport در prefs ذخیره می‌شود.
  Future<bool> connectTransport(
    TransportId id, {
    void Function(String msg)? onLog,
  }) async {
    switch (id) {
      case TransportId.masque:
        return _connectAetherTransport(protocol: 'masque', onLog: onLog);
      case TransportId.warpOnWarp:
        return _connectAetherTransport(protocol: 'gool', onLog: onLog);
      case TransportId.warp:
        return _connectWarpTransport(onLog: onLog);
      case TransportId.psiphon:
        return _connectPsiphonTransport(onLog: onLog);
      case TransportId.tor:
        return _connectTorTransport(onLog: onLog);
      case TransportId.wireguard:
      case TransportId.geph:
        // در فازهای بعدی (P2a/P2b) کامل می‌شود.
        onLog?.call('engine not available in this build');
        return false;
    }
  }

  Future<bool> _connectAetherTransport({
    required String protocol,
    void Function(String msg)? onLog,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    // گزینه‌های پیشرفتهٔ ذخیره‌شده از صفحهٔ Transport (کلید‌های جدا).
    final scan = prefs.getString('transport_masque_scan') ?? 'balanced';
    final noize = prefs.getString('transport_masque_noize') ?? 'auto';
    final ip = prefs.getString('transport_masque_ip') ?? 'v4';
    final perf = prefs.getString('transport_masque_perf') ?? 'auto';
    final quickReconnect = prefs.getBool('transport_masque_qr') ?? true;
    final blockQuic = prefs.getBool('transport_masque_noquic') ?? true;
    final h2 = prefs.getBool('transport_masque_h2') ?? false;
    // تایل MASQUE: masque | masque_h2 — تایل WARP²: gool (ثابت).
    final proto = protocol == 'gool' ? 'gool' : (h2 ? 'masque_h2' : 'masque');
    final q = <String, String>{
      'protocol': proto,
      'scan': scan,
      'noize': noize,
      'ip': ip,
      'perf': perf,
      if (!quickReconnect) 'qr': '0',
      if (!blockQuic) 'quic': 'allow',
    };
    final link = Uri(scheme: 'aether', host: 'config', queryParameters: q)
        .toString();
    final label = proto == 'gool' ? 'WARP²' : 'MASQUE';
    final server = VpnServer(
      id: 'aether_transport_$proto',
      name: label,
      flag: proto == 'gool' ? '🟠' : '🟣',
      shareLink: link,
      protocol: VpnProtocol.aether,
      host: 'auto-discover',
      port: 0,
      isDeletable: false,
    );
    onLog?.call('aether transport: $proto scan=$scan noize=$noize ip=$ip');
    return connectServer(server);
  }

  Future<bool> _connectWarpTransport(
      {void Function(String msg)? onLog}) async {
    _cancelConnect = false;
    _connecting = true;
    _setStatus(_t('WARP · آماده‌سازی...', 'WARP · preparing...'),
        st: ConnStage.preparing);
    notifyListeners();
    await _disconnectAllSessionsForNewConnect();
    try {
      _setStatus(_t('WARP · هویت...', 'WARP · identity...'),
          st: ConnStage.connecting);
      final gen = await WarpService.generate();
      if (gen.server == null) {
        _connecting = false;
        _setStatus(_t('WARP · ثبت‌نام ناموفق', 'WARP · registration failed') +
            (gen.error == null ? '' : ' · ${gen.error}'),
            st: ConnStage.failed);
        ConnectionLogService.logError('WARP', gen.error ?? 'register failed');
        notifyListeners();
        return false;
      }
      onLog?.call('warp endpoint: ${gen.server!.host}:${gen.server!.port}');
      final ok = await connectServer(gen.server!);
      return ok;
    } catch (e) {
      _connecting = false;
      _setStatus(_t('WARP · خطا', 'WARP · error') + ' · $e',
          st: ConnStage.failed);
      notifyListeners();
      return false;
    }
  }

  Future<bool> _connectPsiphonTransport(
      {void Function(String msg)? onLog}) async {
    final prefs = await SharedPreferences.getInstance();
    final region = prefs.getString('transport_psiphon_region') ?? 'auto';
    final link = PsiphonService.toShareLink(region: region);
    final server = VpnServer(
      id: 'psiphon_transport_auto',
      name: 'Psiphon',
      flag: '🌐',
      shareLink: link,
      protocol: VpnProtocol.psiphon,
      host: 'auto',
      port: 0,
      isDeletable: false,
    );
    onLog?.call('psiphon transport: region=$region');
    return connectServer(server);
  }

  Future<bool> _connectTorTransport(
      {void Function(String msg)? onLog}) async {
    final prefs = await SharedPreferences.getInstance();
    final mode = prefs.getString('transport_tor_mode') ?? 'vanilla';
    final rawCustom = prefs.getString('transport_tor_bridges') ?? '';
    final sni = prefs.getString('transport_tor_sni');
    final customBridges = rawCustom
        .split('\n')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();

    _cancelConnect = false;
    _connecting = true;
    _active = null;
    _setStatus(_t('Tor · راه‌اندازی...', 'Tor · starting...'),
        st: ConnStage.connecting);
    notifyListeners();
    await _disconnectAllSessionsForNewConnect();

    try {
      await V2RayEngine.init();
      final r = await TorService.start(
        bridgeType: mode,
        customBridges: customBridges.isEmpty ? null : customBridges,
        sni: (sni == null || sni.isEmpty) ? null : sni,
      );
      if (r['ok'] != true) {
        _connecting = false;
        _setStatus(_t('Tor · خطا', 'Tor · error') +
            (r['error'] == null ? '' : ' · ${r['error']}'),
            st: ConnStage.failed);
        ConnectionLogService.logError('Tor', r['error']?.toString() ?? 'start failed');
        notifyListeners();
        return false;
      }
      final deadline = DateTime.now().add(const Duration(seconds: 180));
      while (DateTime.now().isBefore(deadline)) {
        if (_cancelConnect) {
          await TorService.stop();
          await _finishCancelled();
          return false;
        }
        await Future.delayed(const Duration(milliseconds: 800));
        final st = await TorService.status();
        final pct = (st['bootstrapPercent'] as num?)?.toInt() ?? 0;
        progress = pct;
        _setStatus(
            _t('Tor · bootstrap $pct%', 'Tor · bootstrap $pct%'),
            st: ConnStage.connecting);
        if (pct >= 100) {
          final port = (st['socksPort'] as num?)?.toInt() ?? 9050;
          final cfg = TorSessionService.buildTorXrayConfig(port);
          final fake = VpnServer(
            id: 'tor_fake_${DateTime.now().millisecondsSinceEpoch}',
            name: 'Tor',
            flag: '🧅',
            shareLink: 'xrayjson://tor',
            protocol: VpnProtocol.xrayJson,
            host: '127.0.0.1',
            port: port,
            isDeletable: false,
          );
          final ok = await V2RayEngine.startConfig(
            remark: 'Tor',
            config: cfg,
            server: fake,
          );
          _connecting = false;
          if (ok) {
            _connected = true;
            _active = fake;
            _deadStrikes = 0;
            _pollTick = 0;
            _lastConnectTime = DateTime.now();
            HomeWidgetService.setConnectedStart(DateTime.now());
            _startWidgetTimerRefresh();
            _setStatus(_t('متصل — Tor', 'Connected — Tor'),
                st: ConnStage.connected);
            ConnectionLogService.logConnect('Tor ($mode)');
          } else {
            await TorService.stop();
            _setStatus(
                _t('Tor · routing ناموفق', 'Tor · routing failed') +
                    (V2RayEngine.lastError == null
                        ? ''
                        : ' · ${V2RayEngine.lastError}'),
                st: ConnStage.failed);
            ConnectionLogService.logError(
                'Tor', V2RayEngine.lastError ?? 'routing failed');
          }
          notifyListeners();
          return ok;
        }
        if (st['running'] != true) {
          _connecting = false;
          _setStatus(_t('Tor · متوقف شد', 'Tor · stopped early') +
              (st['error'] == null ? '' : ' · ${st['error']}'),
              st: ConnStage.failed);
          ConnectionLogService.logError(
              'Tor', st['error']?.toString() ?? 'stopped early');
          notifyListeners();
          return false;
        }
      }
      _connecting = false;
      _setStatus(_t('Tor · تایم‌اوت bootstrap', 'Tor · bootstrap timeout'),
          st: ConnStage.failed);
      ConnectionLogService.logError('Tor', 'bootstrap timeout (180s)');
      notifyListeners();
      return false;
    } catch (e) {
      _connecting = false;
      _setStatus(_t('Tor · خطا', 'Tor · error') + ' · $e',
          st: ConnStage.failed);
      notifyListeners();
      return false;
    }
  }

  /// قطع توسط کاربر.
  Future<void> disconnect() async {
    if (_connecting) {
      _cancelConnect = true;
      _setStatus(_t('در حال لغو...', 'Cancelling...'),
          st: ConnStage.connecting);
      final which = _connectingServer;
      if (which != null) {
        if (which.isPsiphon) {
          unawaited(PsiphonService.stop(reason: 'user-cancel'));
        }
        if (which.isAether) {
          unawaited(AetherService.disconnect());
        }
      }
      if (stage == ConnStage.connecting &&
          statusText.startsWith('Tor')) {
        await TorService.stop();
      }
      return;
    }
    if (_connected) {
      _connecting = true;
      _setStatus(_t('در حال قطع...', 'Disconnecting...'),
          st: ConnStage.connecting);
      try {
        await disconnectAll();
      } catch (_) {}
      _markDisconnected(_t('آماده', 'Ready'));
      return;
    }
    // هیچ session فعالی نیست — همه‌چیز را برای اطمینان قطع کن.
    try {
      await disconnectAll();
    } catch (_) {}
    _markDisconnected(_t('آماده', 'Ready'));
  }

  // ── ویجت‌ها ──
  void _startWidgetTimerRefresh() {
    _widgetTimer?.cancel();
    _widgetTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (!_connected) return;
      HomeWidgetService.setConnectedStart(_lastConnectTime ?? DateTime.now());
    });
  }

  void _stopWidgetTimerRefresh() {
    _widgetTimer?.cancel();
    _widgetTimer = null;
  }

  /// بوت‌استرپ پس از شروع UI: وضعیت OS را با state Dart آشتی بده.
  Future<void> reconcileOnBoot() async {
    await V2RayEngine.init();
    await V2RayEngine.refreshOsConnectionState();
    if (V2RayEngine.isConnected) {
      _connected = true;
      stage = ConnStage.connected;
      statusText = _t('متصل', 'Connected');
      _active = V2RayEngine.current;
      startLoops();
    } else if (PsiphonService.isConnected || AetherService.isConnected) {
      _connected = true;
      stage = ConnStage.connected;
      statusText = _t('متصل', 'Connected');
      startLoops();
    }
    notifyListeners();
  }
}
