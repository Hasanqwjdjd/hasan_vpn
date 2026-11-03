import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:hasan_vpn/app/app_shell.dart';
import 'package:hasan_vpn/app/registry.dart';
import 'package:hasan_vpn/controllers/app_state.dart';
import 'package:hasan_vpn/controllers/home_layout.dart';

/// تست دود پوسته: برنامه باید بالا بیاید، همهٔ مقصدهای رجیستری قابل باز شدن
/// باشند و هیچ صفحه‌ای در اولین فریم استثنا ندهد.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await AppearanceStore.instance.load();
    await LocaleStore.instance.load();
    await HomeLayoutStore.instance.load();
  });

  testWidgets('home board renders and every destination opens',
      (tester) async {
    tester.view.physicalSize = const Size(1080, 2280);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const MaterialApp(home: AppShell()));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byType(AppShell), findsOneWidget);
    expect(tester.takeException(), isNull);

    // چیدمان بعد از load باید همهٔ مقصدهای پیش‌فرض را داشته باشد.
    expect(kBoardDefault.isNotEmpty, isTrue);
    final ids = kDestinations.map((d) => d.id).toSet();
    expect(ids.length, kDestinations.length, reason: 'duplicate destination id');

    for (final d in kDestinations) {
      AppShellState.openTab(d.id);
      await tester.pump(const Duration(milliseconds: 250));
      final err = tester.takeException();
      expect(err, isNull, reason: 'destination ${d.id} threw on open');
    }
  });

  addConfigTypesTest();

  test('every destination id used by the board exists in the registry', () {
    for (final id in [...kBoardDefault, ...kDockIds]) {
      expect(destinationById(id), isNotNull, reason: 'unknown id $id');
    }
  });
}

/// فرم‌های پروتکل در صفحهٔ «افزودن کانفیگ» باید با انتخاب هر نوع رندر شوند؛
/// چند فرم قبلاً ساخته شده بودند ولی هیچ کارتی آن‌ها را باز نمی‌کرد.
void addConfigTypesTest() {
  testWidgets('every add-config protocol type renders its form',
      (tester) async {
    tester.view.physicalSize = const Size(1080, 2280);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const MaterialApp(home: AppShell()));
    await tester.pump(const Duration(milliseconds: 300));

    AppShellState.openTab('addconfig');
    await tester.pump(const Duration(milliseconds: 400));
    expect(tester.takeException(), isNull);

    for (final title in [
      'WARP / WARP+',
      'WARP MASQUE',
      'SSH',
      'SOCKS5',
      'MasterDNS',
    ]) {
      final card = find.text(title);
      expect(card, findsOneWidget, reason: 'type card $title is missing');
      await tester.ensureVisible(card.first);
      await tester.pump();
      await tester.tap(card.first);
      await tester.pump(const Duration(milliseconds: 200));
      final err = tester.takeException();
      expect(err, isNull, reason: 'form for $title threw while rendering');
    }
  });
}
