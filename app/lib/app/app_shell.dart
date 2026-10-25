import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../controllers/app_state.dart';
import '../controllers/connection.dart';
import '../l10n/s.dart';
import '../screens/home_board.dart';
import '../ui/kit/ios_kit.dart';
import '../ui/theme/ios_palette.dart';
import 'registry.dart';

/// پوستهٔ ناوبری — پورت `ui/AppScreen.kt`:
/// استک تب‌ها + حالت پارک (Offstage/TickerMode) + خروج با دیالوگ.
class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => AppShellState();
}

class AppShellState extends State<AppShell> {
  static AppShellState? _instance;
  final List<String> _stack = []; // تب‌های باز روی home
  final Set<String> _visited = {'home'};

  @override
  void initState() {
    super.initState();
    _instance = this;
  }

  @override
  void dispose() {
    if (_instance == this) _instance = null;
    super.dispose();
  }

  static void openTab(String id) => _instance?._open(id);

  void _open(String id) {
    if (_stack.isNotEmpty && _stack.last == id) return;
    setState(() {
      _stack.add(id);
      _visited.add(id);
    });
  }

  void goBack() {
    if (_stack.isNotEmpty) {
      setState(() => _stack.removeLast());
      return;
    }
    _confirmExit();
  }

  Future<bool> _onWillPop() async {
    if (_stack.isNotEmpty) {
      goBack();
      return false;
    }
    await _confirmExit();
    return false;
  }

  Future<void> _confirmExit() async {
    await showIosAlert(
      context,
      title: S.t('exit_the_app'),
      confirmLabel: S.t('exit'),
      cancelLabel: S.t('stay'),
      destructive: true,
      onConfirm: () {
        SystemNavigator.pop();
      },
    );
  }

  bool get _isHome => _stack.isEmpty;

  @override
  Widget build(BuildContext context) {
    final pal = IosPal.of(context);
    final ap = AppearanceStore.instance;
    return WillPopScope(
      onWillPop: _onWillPop,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: Stack(
          children: [
            for (final id in _visited) _tabLayer(id, pal, ap),
          ],
        ),
      ),
    );
  }

  Widget _tabLayer(String id, IosPal pal, AppearanceStore ap) {
    final top = _isHome ? 'home' : _stack.last;
    final isActive = id == top;
    final builder = _builderFor(id);
    if (builder == null) return const SizedBox();

    Widget layer;
    if (id == 'home') {
      layer = builder(context);
    } else {
      layer = Stack(
        children: [
          Positioned.fill(
            child: ColoredBox(
              color: ap.wallpaperEverywhere
                  ? pal.featureScrim
                  : pal.background,
            ),
          ),
          Positioned.fill(child: builder(context)),
        ],
      );
    }

    return Offstage(
      offstage: !isActive,
      child: TickerMode(
        enabled: isActive,
        child: RepaintBoundary(child: layer),
      ),
    );
  }

  WidgetBuilder? _builderFor(String id) {
    if (id == 'home') {
      return (ctx) {
        final ap = AppearanceStore.instance;
        final conn = ConnectionController.instance;
        return AnimatedBuilder(
          animation: Listenable.merge([ap, conn]),
          builder: (ctx, _) => HomeBoard(
            appearance: ap,
            onOpenTab: (id) {
              if (id == 'home') return;
              _open(id);
            },
          ),
        );
      };
    }
    final d = destinationById(id);
    if (d == null) return null;
    return (ctx) => Navigator(
          onGenerateRoute: (settings) => MaterialPageRoute(
            builder: (ctx) => d.builder(ctx),
          ),
        );
  }
}
