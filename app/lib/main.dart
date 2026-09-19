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
    _themeMode = await SettingsService.getThemeMode();
    _language = await SettingsService.getLanguage();
    final subs = await SubscriptionService.load();
    setState(() => _subs = subs);
    await _refreshSubscriptions();
    setState(() => _loading = false);
  }

  Future<void> _refreshSubscriptions({bool force = false}) async {
    final all = <VpnServer>[];
    for (final s in _subs) {
      if (force || s.needsUpdate()) {
        try {
          final servers = await SubscriptionService.fetch(s);
          s.lastUpdated = DateTime.now();
          s.serverCount = servers.length;
          all.addAll(servers);
        } catch (_) {
          all.addAll(SubscriptionService.fromCache(s));
        }
      } else {
        all.addAll(SubscriptionService.fromCache(s));
      }
    }
    await SubscriptionService.save(_subs);
    if (mounted) setState(() => _subServers = all);
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
        textDirection: _language == 'fa' ? TextDirection.rtl : TextDirection.ltr,
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
                style: TextStyle(color: AppColors.muted(context), fontSize: 13)),
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
      body: pages[_index],
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
