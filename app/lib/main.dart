import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'services/v2ray_engine.dart';

import 'package:flutter/material.dart';
import 'app/app_shell.dart';
import 'controllers/app_state.dart';
import 'controllers/home_layout.dart';
import 'controllers/servers.dart';
import 'models/server.dart';
import 'services/app_colors.dart';

/// Entry point برای اجرا از ویجت ۱×۱ در پس‌زمینه (بدون UI).
/// این تابع توسط WidgetHeadlessActivity اجرا می‌شود — یک Activity واقعی
/// (اما با تم Theme.Translucent.NoDisplay، پس هرگز روی صفحه رندر نمی‌شود)
/// که به همین دلیل، برخلاف یک FlutterEngine کاملاً headless، پلاگین
/// flutter_vless را با یک Activity متصل واقعی تغذیه می‌کند و درخواست
/// مجوز VPN آن به‌درستی کار می‌کند.
@pragma('vm:entry-point')
Future<void> widgetHeadlessMain() async {
  WidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('com.hasan.hasan_vpn/widget_headless');

  Map? args;
  try {
    args = await channel.invokeMethod<Map>('getHeadlessArgs');
  } catch (_) {}

  final payload = args?['payload']?.toString() ?? '';
  final title = args?['title']?.toString() ?? '';
  final action = args?['action']?.toString() ?? 'connect';

  bool ok = false;
  String? error;

  try {
    if (action == 'disconnect') {
      await V2RayEngine.init();
      // FIX_DISCONNECT_V3:
      // مشکل V2 این بود که isolate بعد از 4 تلاش می‌مرد و native layer
      // یه بار دیگه VPN رو وصل می‌کرد (همون 1 ثانیه‌ای که می‌دیدی).
      // راه‌حل: به مدت 20 ثانیه، هر 500 میلی‌ثانیه چک کن؛ اگه هنوز وصله،
      // دوباره قطع کن. این باعث می‌شه native layer نتونه دوباره وصل کنه.
      final disconnectEnd = DateTime.now().add(const Duration(seconds: 20));
      int disconnectAttempts = 0;
      while (DateTime.now().isBefore(disconnectEnd)) {
        try {
          await V2RayEngine.disconnect();
          disconnectAttempts++;
        } catch (_) {}
        await Future.delayed(const Duration(milliseconds: 500));
        // اگه 10 ثانیه گذشته و دیگه وصل نشد، زودتر بیا بیرون
        if (disconnectAttempts >= 3 &&
            DateTime.now().difference(disconnectEnd).inSeconds < -10) {
          if (!V2RayEngine.isConnected) {
            // هنوز 10 ثانیه مونده ولی disconnected پایداره؛ یکم بیشتر صبر کن
            // تا مطمئن شیم native layer ساکت شده
            await Future.delayed(const Duration(seconds: 5));
            if (!V2RayEngine.isConnected) break;
          }
        }
      }
      // آخرین قطع برای اطمینان
      try {
        await V2RayEngine.disconnect();
      } catch (_) {}
      ok = true;
    } else if (payload.isNotEmpty) {
      // type می‌تونه 'server' باشه یا اسم پروتکل (vless, trojan, ...).
      // در هر صورت، payload یک shareLink است و از روی آن server ساخته می‌شود.
      VpnServer? server = _buildServerFromShareLink(payload, title);
      if (server == null) {
        error = 'cannot build server from payload';
      } else {
        await V2RayEngine.init();
        // FIX: use V2RayEngine.connect (which builds the JSON config from
        // shareLink internally) instead of startConfig (which expects raw JSON)
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
  runZonedGuarded(() {
    WidgetsFlutterBinding.ensureInitialized();
    // در نسخهٔ نهایی هیچ لاگی (خطاها، آدرس‌ها، کانفیگ‌ها) روی logcat نمی‌رود.
    if (kReleaseMode) {
      debugPrint = (String? message, {int? wrapWidth}) {};
    }
    // به‌جای کادر خاکستری/سیاه، متن خطا نمایش داده می‌شود (عیب‌یابی).
    ErrorWidget.builder = (FlutterErrorDetails d) => Directionality(
          textDirection: TextDirection.ltr,
          child: Container(
            color: const Color(0xFF08090C),
            padding: const EdgeInsets.all(16),
            alignment: Alignment.center,
            child: Text(
              d.exceptionAsString(),
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            ),
          ),
        );
    runApp(const HasanApp());
  }, (error, stack) {
    // خطاهای async که قبلاً کاملاً بی‌صدا گم می‌شدند: حداقل در حالت debug
    // ثبت می‌شوند تا رگرسیون‌ها هنگام توسعه دیده شوند.
    debugPrint('uncaught async error: $error');
  });
}

class HasanApp extends StatefulWidget {
  const HasanApp({super.key});
  @override
  State<HasanApp> createState() => _HasanAppState();
}

class _HasanAppState extends State<HasanApp> {
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  /// راه‌اندازی استورهای سراسری.
  ///
  /// قبلاً نه `AppearanceStore.load()` صدا زده می‌شد و نه
  /// `ServerRepository.load()`: تنظیمات ظاهر (تم/اندازه/والپیپر) بعد از هر
  /// اجرا به پیش‌فرض برمی‌گشت و فهرست سرورها/اشتراک‌های پوستهٔ جدید خالی بود.
  Future<void> _bootstrap() async {
    try {
      await AppearanceStore.instance.load();
      await LocaleStore.instance.load();
      ThemeController.instance.bind(AppearanceStore.instance);
      // چیدمان صفحه‌خانه (ترتیب/پوشه‌ها) — بدون این فراخوانی برد خالی می‌ماند.
      await HomeLayoutStore.instance.load();
      await ServerRepository.instance.load();
      unawaited(ServerRepository.instance.refreshSubscriptions());
    } catch (e) {
      debugPrint('bootstrap failed: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final appearance = AppearanceStore.instance;
    final locale = LocaleStore.instance;
    final theme = ThemeController.instance;
    return AnimatedBuilder(
      animation: Listenable.merge([appearance, locale, theme]),
      builder: (context, _) => MaterialApp(
        title: locale.lang == 'fa' ? 'حسن' : 'Hasan',
        debugShowCheckedModeBanner: false,
        theme: theme.themeData(Brightness.light),
        darkTheme: theme.themeData(Brightness.dark),
        themeMode: theme.mode,
        builder: (context, child) => _AppFrame(
          appearance: appearance,
          locale: locale,
          child: child ?? const SizedBox.shrink(),
        ),
        home: _loading ? const _LoadingScreen() : const AppShell(),
      ),
    );
  }
}

/// جهت متن و مقیاس فونت بر اساس تنظیمات ظاهر (AppearanceStore).
class _AppFrame extends StatelessWidget {
  final AppearanceStore appearance;
  final LocaleStore locale;
  final Widget child;

  const _AppFrame({
    required this.appearance,
    required this.locale,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection:
          locale.lang == 'fa' ? TextDirection.rtl : TextDirection.ltr,
      child: Builder(
        builder: (ctx) {
          final system = MediaQuery.textScalerOf(ctx);
          final factor =
              appearance.textScaleAuto ? 1.0 : appearance.textScale / 100.0;
          final scaler = TextScaler.linear(system.scale(10) / 10 * factor);
          return MediaQuery(
            data: MediaQuery.of(ctx).copyWith(textScaler: scaler),
            child: child,
          );
        },
      ),
    );
  }
}

class _LoadingScreen extends StatelessWidget {
  const _LoadingScreen();
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg(context),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(color: AppColors.accent),
            const SizedBox(height: 16),
            Text('در حال بارگذاری سرورها...',
                style:
                    TextStyle(color: AppColors.muted(context), fontSize: 13)),
          ],
        ),
      ),
    );
  }
}
