import 'dart:async';

import 'package:flutter/material.dart';
import 'models/subscription.dart';
import 'models/server.dart';
import 'services/subscription_service.dart';
import 'services/settings_service.dart';
import 'services/app_colors.dart';
import 'screens/home_screen.dart';
import 'screens/subscriptions_screen.dart';
import 'screens/settings_screen.dart';

void main() {
  runApp(const HasanApp());
}

class HasanApp extends StatefulWidget {
  const HasanApp({super.key});
  @override
  State<HasanApp> createState() => _HasanAppState();
}

class _HasanAppState extends State<HasanApp> {
  List<Subscription> _subs = [];
  List<VpnServer> _subServers = [];
  bool _loading = true;
  String _themeMode = 'dark';
  String _language = 'fa';

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    await SettingsService.loadVersion();
    _themeMode = await SettingsService.getThemeMode();
    _language = await SettingsService.getLanguage();

    final subs = await SubscriptionService.load();
    _subs = subs;

    // سرورهای ذخیره‌شده فوراً نشان داده می‌شوند؛ به‌روزرسانی از شبکه در پس‌زمینه
    // انجام می‌شود (قبلاً برنامه تا پایان دانلود همه‌ی اشتراک‌ها روی «در حال
    // بارگذاری» می‌ماند و با شبکه‌ی کند تا چند دقیقه طول می‌کشید).
    _subServers = _merge(subs.map(SubscriptionService.fromCache).toList());

    if (!mounted) return;
    setState(() => _loading = false);

    unawaited(_refreshSubscriptions());
  }

  Future<void>? _refreshing;

  Future<void> _refreshSubscriptions({bool force = false}) {
    final running = _refreshing;
    if (running != null && !force) {
      // یک به‌روزرسانی در جریان است؛ بعد از آن یک دور دیگر (ارزان، از کش) تا
      // تغییرات تازه‌ی لیست اشتراک‌ها هم اعمال شود.
      return running.then((_) => _refreshSubscriptions());
    }

    final future = _doRefresh(force);
    _refreshing = future;
    future.whenComplete(() {
      if (identical(_refreshing, future)) _refreshing = null;
    });
    return future;
  }

  Future<void> _doRefresh(bool force) async {
    final subs = List<Subscription>.from(_subs);

    // همه‌ی اشتراک‌ها هم‌زمان دریافت می‌شوند (نه پشت‌سرهم).
    final results = await Future.wait(
      subs.map((s) async {
        if (force || s.needsUpdate()) {
          try {
            final servers = await SubscriptionService.fetch(s);
            s.lastUpdated = DateTime.now();
            s.serverCount = servers.length;
            return servers;
          } catch (_) {
            return SubscriptionService.fromCache(s);
          }
        }
        return SubscriptionService.fromCache(s);
      }),
    );

    await SubscriptionService.save(_subs);
    if (mounted) setState(() => _subServers = _merge(results));
  }

  /// ادغام لیست‌ها: تکراری‌ها (همان لینک در چند اشتراک) حذف می‌شوند و برای
  /// سرورهای قبلاً دیده‌شده همان شیء قبلی نگه داشته می‌شود تا نتیجه‌ی تست
  /// پینگ با هر به‌روزرسانی اشتراک پاک نشود.
  List<VpnServer> _merge(List<List<VpnServer>> lists) {
    final previous = <String, VpnServer>{
      for (final server in _subServers) server.id: server,
    };
    final seen = <String>{};
    final merged = <VpnServer>[];

    for (final list in lists) {
      for (final server in list) {
        if (!seen.add(server.id)) continue;
        merged.add(previous[server.id] ?? server);
      }
    }
    return merged;
  }

  Future<void> _onSubsChanged(List<Subscription> subs) async {
    setState(() => _subs = subs);
    await _refreshSubscriptions();
  }

  ThemeMode _themeModeEnum() {
    switch (_themeMode) {
      case 'light':
        return ThemeMode.light;
      case 'system':
        return ThemeMode.system;
      default:
        return ThemeMode.dark;
    }
  }

  ThemeData _darkTheme() => ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF08090C),
        colorScheme: const ColorScheme.dark(
            primary: Color(0xFF3DCF9A), surface: Color(0xFF12141A)),
      );

  ThemeData _lightTheme() => ThemeData(
        brightness: Brightness.light,
        scaffoldBackgroundColor: const Color(0xFFF5F6F8),
        colorScheme: const ColorScheme.light(
            primary: Color(0xFF3DCF9A), surface: Colors.white),
      );

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: _language == 'fa' ? 'حسن' : 'Hasan',
      debugShowCheckedModeBanner: false,
      theme: _lightTheme(),
      darkTheme: _darkTheme(),
      themeMode: _themeModeEnum(),
      builder: (context, child) => Directionality(
        textDirection:
            _language == 'fa' ? TextDirection.rtl : TextDirection.ltr,
        child: child!,
      ),
      home: _loading
          ? const _LoadingScreen()
          : RootTabs(
              subs: _subs,
              subServers: _subServers,
              themeMode: _themeMode,
              language: _language,
              onSubsChanged: _onSubsChanged,
              onRefreshAll: () => _refreshSubscriptions(force: true),
              onThemeChanged: (t) async {
                await SettingsService.setThemeMode(t);
                setState(() => _themeMode = t);
              },
              onLanguageChanged: (l) async {
                await SettingsService.setLanguage(l);
                setState(() => _language = l);
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

class RootTabs extends StatefulWidget {
  final List<Subscription> subs;
  final List<VpnServer> subServers;
  final String themeMode;
  final String language;
  final Function(List<Subscription>) onSubsChanged;
  final Future<void> Function() onRefreshAll;
  final Function(String) onThemeChanged;
  final Function(String) onLanguageChanged;

  const RootTabs({
    super.key,
    required this.subs,
    required this.subServers,
    required this.themeMode,
    required this.language,
    required this.onSubsChanged,
    required this.onRefreshAll,
    required this.onThemeChanged,
    required this.onLanguageChanged,
  });

  @override
  State<RootTabs> createState() => _RootTabsState();
}

class _RootTabsState extends State<RootTabs> {
  int _index = 0;

  void _openSettings() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SettingsScreen(
          themeMode: widget.themeMode,
          language: widget.language,
          onThemeChanged: widget.onThemeChanged,
          onLanguageChanged: widget.onLanguageChanged,
        ),
      ),
    );
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final isFa = widget.language == 'fa';
    final pages = [
      HomeScreen(
        extraServers: widget.subServers,
        onOpenSettings: _openSettings,
        language: widget.language,
      ),
      SubscriptionsScreen(
        subscriptions: widget.subs,
        onChanged: widget.onSubsChanged,
        language: widget.language,
      ),
    ];

    return Scaffold(
      backgroundColor: AppColors.bg(context),
      body: IndexedStack(index: _index, children: pages),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: AppColors.navBar(context),
          border: Border(top: BorderSide(color: AppColors.border(context))),
        ),
        child: BottomNavigationBar(
          currentIndex: _index,
          onTap: (i) => setState(() => _index = i),
          backgroundColor: AppColors.navBar(context),
          selectedItemColor: AppColors.accent,
          unselectedItemColor: AppColors.muted2(context),
          type: BottomNavigationBarType.fixed,
          items: [
            BottomNavigationBarItem(
              icon: const Icon(Icons.shield_outlined),
              activeIcon: const Icon(Icons.shield),
              label: isFa ? 'اتصال' : 'Connect',
            ),
            BottomNavigationBarItem(
              icon: const Icon(Icons.rss_feed),
              label: isFa ? 'اشتراک‌ها' : 'Subs',
            ),
          ],
        ),
      ),
    );
  }
}
