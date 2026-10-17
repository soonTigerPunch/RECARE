import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:recare/data/inventory_repository.dart';
import 'package:recare/data/preferences.dart';
import 'package:recare/domain/inventory.dart';
import 'package:recare/main.dart';

void main() {
  testWidgets('render Korean phone-sized MVP previews', (tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.runAsync(() async {
      final font = File('C:/Windows/Fonts/malgun.ttf');
      if (await font.exists()) {
        final loader = FontLoader('Roboto')
          ..addFont(font.readAsBytes().then(ByteData.sublistView));
        await loader.load();
      }
    });
    await tester.runAsync(() async {
      final icons = File(
        'C:/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
      );
      if (await icons.exists()) {
        final loader = FontLoader('MaterialIcons')
          ..addFont(icons.readAsBytes().then(ByteData.sublistView));
        await loader.load();
      }
    });
    sqfliteFfiInit();
    final temp = await tester.runAsync(
      () => Directory.systemTemp.createTemp('recare-preview-'),
    );
    final repo = await tester.runAsync(
      () => InventoryRepository.open(
        factory: databaseFactoryFfi,
        databasePath: p.join(temp!.path, 'recare.db'),
      ),
    );
    final today = DateTime(2026, 10, 14);
    await tester.runAsync(() async {
      await repo!.save(
        Food(
          id: 'milk',
          name: '우유',
          unit: FoodUnit.ml,
          total: 1000000,
          expiry: today,
          price: 3000,
          created: today,
        ),
      );
      await repo.save(
        Food(
          id: 'carrot',
          name: '당근',
          unit: FoodUnit.gram,
          total: 100000,
          expiry: today.add(const Duration(days: 5)),
          price: null,
          created: today,
        ),
      );
      await repo.process(
        foodId: 'milk',
        kind: ActionKind.waste,
        amount: 250000,
        unit: FoodUnit.ml,
        date: today,
        requestId: 'preview',
        today: today,
      );
    });
    final key = GlobalKey();
    await tester.pumpWidget(
      RepaintBoundary(
        key: key,
        child: RecareApp(
          repositoryFactory: () async => repo!,
          preferencesFactory: () async =>
              PreferencesStore(p.join(temp!.path, 'prefs.json')),
          clock: () => today,
        ),
      ),
    );
    Future<void> waitForPage(String page, {bool loaded = true}) async {
      await tester.pump();
      final finder = find.byKey(ValueKey(page));
      for (var i = 0; i < 100; i++) {
        final isLoading =
            find.byType(CircularProgressIndicator).evaluate().isNotEmpty ||
            find.byType(LinearProgressIndicator).evaluate().isNotEmpty;
        if (finder.evaluate().isNotEmpty && (!loaded || !isLoading)) break;
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(finder, findsOneWidget);
      if (loaded) {
        expect(find.byType(CircularProgressIndicator), findsNothing);
        expect(find.byType(LinearProgressIndicator), findsNothing);
      }
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    }

    void repaint(RenderObject object) {
      object.markNeedsLayout();
      object.markNeedsPaint();
      object.visitChildren(repaint);
    }

    Future<void> capture(String name) async {
      expect(tester.takeException(), isNull);
      repaint(key.currentContext!.findRenderObject()!);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.runAsync(() async {
        final boundary =
            key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        final image = await boundary.toImage(pixelRatio: 3);
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        final output = Directory('docs/screenshots');
        await output.create(recursive: true);
        await File(p.join(output.path, name))
            .writeAsBytes(data!.buffer.asUint8List());
        image.dispose();
      });
    }

    Finder navigationLabel(String label) => find.descendant(
      of: find.byType(NavigationBar),
      matching: find.text(label),
    );

    await waitForPage('home-page');
    expect(find.text('RE:CARE'), findsOneWidget);
    expect(find.text('750원'), findsOneWidget);
    expect(find.text('우유'), findsOneWidget);
    await capture('home.png');

    await tester.tap(navigationLabel('목록'));
    await waitForPage('inventory-page');
    expect(find.text('식재료 목록'), findsOneWidget);
    expect(find.text('당근'), findsOneWidget);
    await capture('fridge.png');

    await tester.tap(find.byKey(const ValueKey('food-milk')));
    await waitForPage('food-detail');
    expect(find.text('3,000원'), findsOneWidget);
    expect(find.byKey(const ValueKey('remaining-stock')), findsOneWidget);
    await capture('food-detail.png');

    await tester.tap(find.text('폐기 기록'));
    await tester.pumpAndSettle();
    expect(find.byType(ProcessDialog), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('portion-2')));
    await tester.pumpAndSettle();
    expect(find.text('처리 수량 375 ml'), findsOneWidget);
    expect(find.text('처리 금액 1,125원'), findsOneWidget);
    expect(find.text('처리 후 375 ml'), findsOneWidget);
    await capture('processing-dialog.png');

    await tester.tap(find.byKey(const ValueKey('manual-amount')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('process-quantity')),
      '250',
    );
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    expect(find.text('처리 금액 750원'), findsOneWidget);
    expect(find.text('처리 후 500 ml'), findsOneWidget);
    await capture('manual-processing.png');
    await tester.tap(find.text('취소'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(BackButton));
    await waitForPage('inventory-page');

    await tester.tap(find.text('식재료 등록'));
    await waitForPage('food-editor');
    await capture('registration.png');
    await tester.enterText(find.byKey(const ValueKey('food-name')), '서울우');
    await tester.pumpAndSettle();
    await capture('autocomplete-suggestions.png');
    await tester.tap(find.byKey(const ValueKey('suggestion-seoul-lowfat-1l')));
    await tester.pumpAndSettle();
    await capture('autocomplete-selected.png');
    await tester.enterText(find.byKey(const ValueKey('food-name')), '우유');
    await tester.pumpAndSettle();
    await capture('autocomplete-history.png');
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    await tester.tap(find.byType(BackButton));
    await waitForPage('inventory-page');

    await tester.tap(navigationLabel('홈'));
    await waitForPage('home-page');
    await tester.tap(find.text('폐기 내역'));
    await waitForPage('weekly-page');
    expect(find.text('750원'), findsNWidgets(2));
    await capture('weekly-waste.png');
    await tester.tap(find.byType(BackButton));
    await waitForPage('home-page');

    await tester.tap(navigationLabel('설정'));
    await waitForPage('settings-page');
    expect(find.byKey(const ValueKey('include-finished')), findsOneWidget);
    await capture('settings.png');
    await tester.tap(find.byKey(const ValueKey('appearance-dark')));
    await waitForPage('settings-page');
    expect(
      Theme.of(tester.element(find.byKey(const ValueKey('settings-page'))))
          .brightness,
      Brightness.dark,
    );
    await capture('settings-dark.png');
    await tester.tap(navigationLabel('홈'));
    await waitForPage('home-page');
    await capture('home-dark.png');
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(() async {
      await repo!.close();
      if (!p.isWithin(
        Directory.systemTemp.resolveSymbolicLinksSync(),
        temp!.resolveSymbolicLinksSync(),
      )) {
        throw StateError('Unexpected preview directory');
      }
      await temp.delete(recursive: true);
    });
  });
}
