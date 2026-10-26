import 'dart:async';
import 'dart:convert';
import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app/app_shell.dart';
import 'app/splash.dart';
import 'controllers/app_state.dart';
import 'controllers/connection.dart';
import 'controllers/home_layout.dart';
import 'controllers/servers.dart';
import 'l10n/s.dart';
import 'models/server.dart';
import 'services/app_log.dart';
import 'services/package_info_proxy.dart';
import 'services/tor_service.dart';
import 'services/v2ray_engine.dart';
import 'services/widget_connect_handler.dart';
import 'ui/fx/fx.dart';
import 'ui/theme/ios_palette.dart';

/// Entry point برای اجرا از ویجت ۱×۱ در پس‌زمینه (بدون UI).
/// این تابع توسط WidgetHeadlessActivity اجرا می‌شود — یک Activity واقعی
/// (اما با تم Theme.Translucent.NoDisplay، پس هرگز روی صفحه رندر نمی‌شود)
/// که به همین دلیل، برخلاف یک FlutterEngine کاملاً headless، پلاگین
/// flutter_vless را با یک Activity متصل واقعی تغذیه می‌کند و درخواست
/// مجوز VPN آن به‌درستی کار می‌کند. (منطق ۱:۱ از نسخهٔ قبل حفظ شده.)
@pragma('vm:entry-point')
Future<void> widgetHeadlessMain() async {
  WidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('com.hasan.hasan_vpn/widget_headless');

  Map? args;
  try {
    args = await channel.invokeMethod<Map>('getHeadlessArgs');
  } catch (_) {}

  final type = args?['type']?.toString() ?? 'server';
  final payload = args?['payload']?.toString() ?? '';
  final title = args?['title']?.toString() ?? '';
  final action = args?['action']?.toString() ?? 'connect';

  bool ok = false;
  String? error;

  try {
    // type="current": از notification یا boot اومده — باید آخرین سرور
    // فعلی رو وصل کنه. payload ممکنه id سرور باشه.
    if (type == 'current' && action == 'connect') {
      if (payload.isNotEmpty) {
        try {
          final prefs = await SharedPreferences.getInstance();
          final raw = prefs.getString('custom_servers_v1');
          if (raw != null) {
            final list = jsonDecode(raw);
            if (list is List) {
              for (final e in list) {
                if (e is Map && e['id']?.toString() == payload) {
                  final link = e['shareLink']?.toString() ?? '';
                  if (link.isNotEmpty) {
                    final server = _buildServerFromShareLink(
                        link, e['name']?.toString() ?? '');
                    if (server != null) {
                      await V2RayEngine.init();
                      ok = await V2RayEngine.connect(server);
                      if (!ok) error = V2RayEngine.lastError;
                      break;
                    }
                  }
                }
              }
            }
          }
        } catch (e) {
          error = 'current-connect: $e';
        }
      }
      if (ok == false && error == null) {
        error = 'no server payload';
      }
    } else if (type == 'tor' && action == 'connect') {
      final parts = payload.split('|');
      final mode = parts.length >= 2 && parts[1].isNotEmpty
          ? parts[1]
          : 'vanilla';
      try {
        final r = await TorService.start(bridgeType: mode);
        if (r['ok'] != true) {
          ok = false;
          error = r['error']?.toString() ?? 'tor start failed';
        } else {
          // صبر کن تا bootstrap 100% بشه (timeout 180s).
          final deadline =
              DateTime.now().add(const Duration(seconds: 180));
          while (DateTime.now().isBefore(deadline)) {
            await Future.delayed(const Duration(milliseconds: 800));
            final st = await TorService.status();
            final pct = (st['bootstrapPercent'] as num?)?.toInt() ?? 0;
            if (pct >= 100) {
              ok = true;
              try {
                final port =
                    (st['socksPort'] as num?)?.toInt() ?? 9050;
                final cfg = _buildTorXrayConfigHeadless(port);
                final fakeServer = VpnServer(
                  id:
                      'tor_widget_${DateTime.now().millisecondsSinceEpoch}',
                  name: 'Tor',
                  flag: '🧅',
                  shareLink: 'xrayjson://tor',
                  protocol: VpnProtocol.xrayJson,
                  host: '127.0.0.1',
                  port: port,
                  isDeletable: false,
                );
                await V2RayEngine.init();
                final routeOk = await V2RayEngine.startConfig(
                  remark: 'Tor',
                  config: cfg,
                  server: fakeServer,
                );
                if (!routeOk) {
                  ok = false;
                  error =
                      'VPN routing failed: ${V2RayEngine.lastError ?? "unknown"}';
                }
              } catch (e) {
                ok = false;
                error = 'routing error: $e';
              }
              break;
            }
            if (st['running'] != true) {
              ok = false;
              error = st['error']?.toString() ?? 'tor stopped early';
              break;
            }
          }
          if (!ok && error == null) {
            error = 'bootstrap timeout (180s)';
          }
        }
      } catch (e) {
        ok = false;
        error = e.toString();
      }
    } else if (type == 'tor' && action == 'disconnect') {
      try {
        // اول Xray route رو قطع کن تا ترافیک دیگه از Tor رد نشه،
        // بعد Tor رو stop کن.
        try {
          await V2RayEngine.init();
          await V2RayEngine.disconnect();
        } catch (_) {}
        await TorService.stop();
        try {
          await V2RayEngine.disconnect();
        } catch (_) {}
        ok = true;
      } catch (e) {
        ok = false;
        error = e.toString();
      }
    } else if (action == 'disconnect') {
      try {
        await TorService.stop();
      } catch (_) {}
      await V2RayEngine.init();
      // FIX_DISCONNECT_V3: به مدت 20 ثانیه، هر 500ms چک و قطع کن تا
      // native layer نتونه دوباره وصل کنه.
      final disconnectEnd = DateTime.now().add(const Duration(seconds: 20));
      int disconnectAttempts = 0;
      while (DateTime.now().isBefore(disconnectEnd)) {
        try {
          await V2RayEngine.disconnect();
          disconnectAttempts++;
        } catch (_) {}
        await Future.delayed(const Duration(milliseconds: 500));
        if (disconnectAttempts >= 3 &&
            DateTime.now().difference(disconnectEnd).inSeconds < -10) {
          if (!V2RayEngine.isConnected) {
            await Future.delayed(const Duration(seconds: 5));
            if (!V2RayEngine.isConnected) break;
          }
        }
      }
      try {
        await V2RayEngine.disconnect();
      } catch (_) {}
      ok = true;
    } else if (payload.isNotEmpty) {
      VpnServer? server = _buildServerFromShareLink(payload, title);
      if (server == null) {
        error = 'cannot build server from payload';
      } else {
        await V2RayEngine.init();
        ok = await V2RayEngine.connect(server);
        if (!ok) error = V2RayEngine.lastError;
      }
    } else {
      error = 'empty payload';
    }
  } catch (e) {
    ok = false;
    error = e.toString();
  }

  try {
    await channel.invokeMethod('headlessDone', {'ok': ok, 'error': error});
  } catch (_) {}
}

String _buildTorXrayConfigHeadless(int socksPort) {
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

/// ساخت VpnServer از یک shareLink (vless://, vmess://, trojan://, ss://)
VpnServer? _buildServerFromShareLink(String shareLink, String title) {
  try {
    final uri = Uri.parse(shareLink);
    final scheme = uri.scheme.toLowerCase();
    VpnProtocol proto;
    switch (scheme) {
      case 'vless':
        proto = VpnProtocol.vless;
        break;
      case 'vmess':
        proto = VpnProtocol.vmess;
        break;
      case 'trojan':
        proto = VpnProtocol.trojan;
        break;
      case 'ss':
        proto = VpnProtocol.shadowsocks;
        break;
      case 'hysteria2':
        proto = VpnProtocol.hysteria2;
        break;
      default:
        return null;
    }
    final host = uri.host;
    final port = uri.port;
    if (host.isEmpty || port <= 0) return null;
    return VpnServer(
      id: 'widget_${DateTime.now().millisecondsSinceEpoch}',
      name: title.isNotEmpty ? title : host,
      flag: '⚡',
      shareLink: shareLink,
      protocol: proto,
      host: host,
      port: port,
      isDeletable: false,
    );
  } catch (_) {
    return null;
  }
}

void main() {
  if (kReleaseMode) {
    debugPrint = (String? message, {int? wrapWidth}) {};
  }
  // قانون لاگ اجباری: هر خطای فریم‌ورک/زون‌گرفته‌نشده در AppLog ثبت می‌شود
  // تا «صفحهٔ سیاه» یا هر خرابی دیگر همیشه سرنخ دقیق در گزارش‌ها داشته باشد.
  FlutterError.onError = (details) {
    try {
      AppLog.e('FLUTTER',
          '${details.exception}\n${details.stack?.toString() ?? ''}');
    } catch (_) {}
  };
  PlatformDispatcher.instance.onError = (e, st) {
    try {
      AppLog.e('UNCAUGHT', '$e\n$st');
    } catch (_) {}
    return false;
  };
  // FIX v2.10.1: در release هر خطای build به‌صورت ناحیهٔ خالی/سیاه
  // رندر می‌شد (همان «صفحهٔ سیاه» گزارش‌شده) بدون هیچ سرنخی. از این
  // به‌بعد خطا در AppLog ثبت می‌شود و یک کارت خطای خوانا جای آن
  // نمایش داده می‌شود — هم قانون لاگ اجباری، هم رفع کوریِ دیباگ.
  ErrorWidget.builder = (FlutterErrorDetails details) {
    try {
      AppLog.e('WIDGET',
          'build error: ${details.exception}\n${details.stack?.toString() ?? ''}');
    } catch (_) {}
    return Material(
      color: const Color(0xFF1C1C1E),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'render: ${details.exception.toString()}',
            textDirection: TextDirection.ltr,
            style: const TextStyle(
                color: Colors.white, fontSize: 12, height: 1.4),
          ),
        ),
      ),
    );
  };
  runApp(const HasanApp());
}

class HasanApp extends StatefulWidget {
  const HasanApp({super.key});

  @override
  State<HasanApp> createState() => _HasanAppState();
}

class _HasanAppState extends State<HasanApp> {
  bool _ready = false;
  String? _bootError;

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    try {
      await PackageInfoProxy.load();
      await LocaleStore.instance.load();
      await AppearanceStore.instance.load();
      ThemeController.instance.bind(AppearanceStore.instance);
      await HomeLayoutStore.instance.load();
      await ServerRepository.instance.load();
      WidgetConnectHandler.listen(
        (req) {
          if (req.action == 'disconnect') {
            ConnectionController.instance.disconnect();
          }
        },
        onChooseTorBridge: _openTorBridgePicker,
      );
      await ConnectionController.instance.reconcileOnBoot();
      ConnectionController.instance.startLoops();
      if (!mounted) return;
      setState(() => _ready = true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _bootError = e.toString());
    }
  }

  Future<void> _openTorBridgePicker(int widgetId) async {
    final nav = Navigator.of(this.context, rootNavigator: true);
    String? defaultMode;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('widget_server_$widgetId') ?? '';
      final parts = raw.split('|');
      if (parts.length >= 2 && parts[0] == 'tor' && parts[1].isNotEmpty) {
        defaultMode = parts[1];
      }
    } catch (_) {}

    const modes = <(String, String, String)>[
      ('vanilla', 'ساده (بدون پل)', 'Vanilla (no bridge)'),
      ('obfs4', 'obfs4', 'obfs4'),
      ('snowflake', 'Snowflake (P2P)', 'Snowflake (P2P)'),
      ('meek_lite', 'Meek / Azure', 'Meek / Azure'),
      ('webtunnel', 'WebTunnel', 'WebTunnel'),
    ];

    final mode = await showModalBottomSheet<String>(
      context: nav.context,
      backgroundColor: IosPal.darkPal.dialog,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(14),
              child: Text(
                S.isFa
                    ? 'نوع اتصال Tor را انتخاب کنید'
                    : 'Choose Tor mode',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            for (final m in modes)
              ListTile(
                leading: Icon(
                  m.$1 == defaultMode
                      ? Icons.radio_button_checked
                      : Icons.radio_button_off,
                  color: IosPal.darkPal.blue,
                ),
                title: Text(
                  S.isFa ? m.$2 : m.$3,
                  style: const TextStyle(color: Colors.white),
                ),
                onTap: () => Navigator.pop(ctx, m.$1),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (mode == null) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('transport_tor_mode', mode);
    AppShellState.openTab('tor');
    await ConnectionController.instance.connectTransport(TransportId.tor);
  }

  @override
  Widget build(BuildContext context) {
    final theme = ThemeController.instance;
    final locale = LocaleStore.instance;
    return AnimatedBuilder(
      animation: Listenable.merge([theme, locale, AppearanceStore.instance]),
      builder: (context, _) {
        return MaterialApp(
          title: S.t('app_name'),
          debugShowCheckedModeBanner: false,
          theme: theme.themeData(Brightness.light),
          darkTheme: theme.themeData(Brightness.dark),
          themeMode: theme.mode,
          builder: (context, child) {
            final systemScale =
                MediaQuery.textScalerOf(context).scale(1.0);
            return Directionality(
              textDirection: S.isFa ? TextDirection.rtl : TextDirection.ltr,
              child: AnnotatedRegion<SystemUiOverlayStyle>(
                value: SystemUiOverlayStyle.light.copyWith(
                  statusBarColor: Colors.transparent,
                  systemNavigationBarColor: Colors.transparent,
                ),
                child: MediaQuery(
                  data: MediaQuery.of(context).copyWith(
                    textScaler: TextScaler.linear(
                        AppearanceStore.instance
                            .effectiveTextScaler(systemScale)),
                  ),
                  child: child!,
                ),
              ),
            );
          },
          home: _bootError != null
              ? _BootErrorView(error: _bootError!)
              : (_ready ? const _Root() : const _BootSplash()),
        );
      },
    );
  }
}

class _BootErrorView extends StatelessWidget {
  final String error;
  const _BootErrorView({required this.error});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Ios.splashBase,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(
            'boot: $error',
            style: const TextStyle(color: Colors.white, fontSize: 13),
          ),
        ),
      ),
    );
  }
}

class _Root extends StatelessWidget {
  const _Root();

  @override
  Widget build(BuildContext context) {
    final ap = AppearanceStore.instance;
    return AnimatedBuilder(
      animation: ap,
      builder: (context, _) {
        final preset = wallpaperById(ap.wallpaperId);
        return Stack(
          children: [
            Positioned.fill(
              child: WallpaperView(
                preset: preset,
                blur: ap.wallpaperBlur,
              ),
            ),
            const Positioned.fill(child: AppShell()),
            const _SplashGate(),
          ],
        );
      },
    );
  }
}

/// اسپلش — یک‌بار در هر process، روی همه‌چیز.
class _SplashGate extends StatefulWidget {
  const _SplashGate();

  @override
  State<_SplashGate> createState() => _SplashGateState();
}

class _SplashGateState extends State<_SplashGate> {
  bool _visible = true;
  bool _fading = false;

  @override
  void initState() {
    super.initState();
    Timer(const Duration(milliseconds: 2720), () {
      if (mounted) setState(() => _fading = true);
    });
    Timer(const Duration(milliseconds: 3060), () {
      if (mounted) setState(() => _visible = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_visible) return const SizedBox.shrink();
    return Positioned.fill(
      child: IgnorePointer(
        child: AnimatedOpacity(
          opacity: _fading ? 0.0 : 1.0,
          duration: const Duration(milliseconds: 340),
          child: const SplashScreen(),
        ),
      ),
    );
  }
}

/// صفحهٔ انتظار بوت — روی کاغذدیواری پیش‌فرض.
class _BootSplash extends StatelessWidget {
  const _BootSplash();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Center(
        child: SizedBox(
          width: 44,
          height: 44,
          child: CircularProgressIndicator(
            strokeWidth: 4,
            value: 0.75,
            valueColor:
                AlwaysStoppedAnimation<Color>(IosPal.darkPal.blue),
            backgroundColor:
                IosPal.darkPal.blue.withValues(alpha: 0.15),
            strokeCap: StrokeCap.round,
          ),
        ),
      ),
    );
  }
}
