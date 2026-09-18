import 'package:flutter/material.dart';
import 'models/subscription.dart';
import 'models/server.dart';
import 'services/subscription_service.dart';
import 'screens/home_screen.dart';
import 'screens/subscriptions_screen.dart';

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

  @override
  void initState() {
    super.initState();
    _loadSubs();
  }

  Future<void> _loadSubs() async {
    final subs = await SubscriptionService.load();
    setState(() => _subs = subs);
    await _refreshSubscriptions();
  }

  Future<void> _refreshSubscriptions() async {
    final all = <VpnServer>[];
    for (final s in _subs) {
      if (s.autoUpdate) {
        try {
          final servers = await SubscriptionService.fetch(s);
          s.lastUpdated = DateTime.now();
          s.serverCount = servers.length;
          all.addAll(servers);
        } catch (_) {}
      }
    }
    await SubscriptionService.save(_subs);
    setState(() => _subServers = all);
  }

  Future<void> _onSubsChanged(List<Subscription> subs) async {
    setState(() => _subs = subs);
    await _refreshSubscriptions();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'حسن',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF08090C),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF3DCF9A),
        ),
      ),
      builder: (context, child) => Directionality(
        textDirection: TextDirection.rtl,
        child: child!,
      ),
      home: RootTabs(
        subs: _subs,
        subServers: _subServers,
        onSubsChanged: _onSubsChanged,
        onRefreshAll: _refreshSubscriptions,
      ),
    );
  }
}

class RootTabs extends StatefulWidget {
  final List<Subscription> subs;
  final List<VpnServer> subServers;
  final Function(List<Subscription>) onSubsChanged;
  final Future<void> Function() onRefreshAll;

  const RootTabs({
    super.key,
    required this.subs,
    required this.subServers,
    required this.onSubsChanged,
    required this.onRefreshAll,
  });

  @override
  State<RootTabs> createState() => _RootTabsState();
}

class _RootTabsState extends State<RootTabs> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    // ترکیب سرورهای ثابت + سرورهای اشتراک
    final allServers = <VpnServer>[
      ...kServers,
      ...widget.subServers,
    ];

    final pages = [
      HomeScreen(extraServers: widget.subServers),
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
          items: const [
            BottomNavigationBarItem(
              icon: Icon(Icons.shield_outlined),
              activeIcon: Icon(Icons.shield),
              label: 'اتصال',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.rss_feed),
              label: 'اشتراک‌ها',
            ),
          ],
        ),
      ),
    );
  }
}
