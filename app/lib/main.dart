import 'package:flutter/material.dart';
import 'models/subscription.dart';
import 'models/server.dart';
import 'services/subscription_service.dart';
import 'services/settings_service.dart';
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
        } catch (_) {}
      } else {
        // سرورهای ذخیره‌شده قبلی (بدون دانلود مجدد)
        // اینجا ساده کار می‌کنیم و اگه نیاز به بروزرسانی نبود از کش استفاده نمی‌کنیم
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
        colorScheme: const ColorScheme.dark(primary: const Color(0xFF3DCF9A)),
      );

  ThemeData _lightTheme() => ThemeData(
        brightness: Brightness.light,
        scaffoldBackgroundColor: const Color(0xFFF5F6F8),
        colorScheme: const ColorScheme.light(primary: const Color(0xFF3DCF9A)),
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
        textDirection: _language == 'fa'
            ? TextDirection.rtl
            : TextDirection.ltr,
        child: child!,
      ),
      home: _loading
          ? const Scaffold(
              backgroundColor: Color(0xFF08090C),
              body: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircularProgressIndicator(color: Color(0xFF3DCF9A)),
                    SizedBox(height: 16),
                    Text('در حال بارگذاری سرورها...',
                        style: TextStyle(color: Colors.white54, fontSize: 13)),
                  ],
                ),
              ),
            )
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

  void _openSettings() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SettingsScreen(
          themeMode: widget.themeMode,
          language: widget.language,
          onThemeChanged: widget.onThemeChanged,
          onLanguageChanged: widget.onLanguageChanged,
        ),
      ),
    ).then((_) {
      // وقتی برگشت، تم/زبان رو refresh کن
      setState(() {});
    });
  }

  @override
  Widget build(BuildContext context) {
    final isFa = widget.language == 'fa';
    final pages = [
      HomeScreen(
        extraServers: widget.subServers,
        onOpenSettings: _openSettings,
      ),
      SubscriptionsScreen(
        subscriptions: widget.subs,
        onChanged: widget.onSubsChanged,
      ),
    ];

    return Scaffold(
      backgroundColor: const Color(0xFF08090C),
      body: pages[_index],
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          color: Color(0xFF0E1015),
          border: Border(top: BorderSide(color: Colors.white12)),
        ),
        child: BottomNavigationBar(
          currentIndex: _index,
          onTap: (i) => setState(() => _index = i),
          backgroundColor: const Color(0xFF0E1015),
          selectedItemColor: const Color(0xFF3DCF9A),
          unselectedItemColor: Colors.white38,
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
