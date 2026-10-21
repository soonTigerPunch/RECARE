import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:recare/data/inventory_repository.dart';
import 'package:recare/data/preferences.dart';
import 'package:recare/domain/inventory.dart';
import 'package:recare/main.dart';
import 'package:recare/ui/ingredient_autocomplete.dart';

import 'widget_test.dart' show settlePage, reveal, waitFor;

void main() {
  sqfliteFfiInit();
  late Directory temp;
  late InventoryRepository repo;
  final today = DateTime(2026, 10, 17);

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('recare-autocomplete-');
    repo = await InventoryRepository.open(
      factory: databaseFactoryFfi,
      databasePath: p.join(temp.path, 'recare.db'),
    );
  });
  tearDown(() async {
    await repo.close();
    if (!p.isWithin(
      Directory.systemTemp.resolveSymbolicLinksSync(),
      temp.resolveSymbolicLinksSync(),
    )) {
      throw StateError('Unexpected temporary directory');
    }
    await temp.delete(recursive: true);
  });

  Future<void> openRegistration(WidgetTester tester) async {
    await tester.pumpWidget(
      RecareApp(
        automaticCheckIns: false,
        repositoryFactory: () async => repo,
        preferencesFactory: () async =>
            PreferencesStore(p.join(temp.path, 'prefs.json')),
        clock: () => today,
      ),
    );
    await settlePage(tester, const ValueKey('home-page'));
    await tester.tap(find.text('식재료 등록'));
    await settlePage(tester, const ValueKey('food-editor'));
  }

  String field(WidgetTester tester, String key) =>
      tester.widget<TextFormField>(find.byKey(ValueKey(key))).controller!.text;

  testWidgets(
    'partial Korean query selects a pictured product without price or expiry',
    (tester) async {
      await openRegistration(tester);
      await tester.enterText(find.byKey(const ValueKey('food-name')), '서울우');
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('food-suggestions')), findsOneWidget);
      await tester.tap(
        find.byKey(const ValueKey('suggestion-seoul-lowfat-1l')),
      );
      await tester.pumpAndSettle();
      expect(field(tester, 'food-name'), '서울우유 나100% 저지방우유');
      expect(field(tester, 'food-quantity'), '1');
      expect(field(tester, 'food-price'), isEmpty);
      expect(find.text('날짜 선택'), findsOneWidget);
      expect(find.byKey(const ValueKey('selected-food-image')), findsOneWidget);
      final unit = tester.widget<ChoiceChip>(
        find.widgetWithText(ChoiceChip, 'L'),
      );
      expect(unit.selected, isTrue);
      await reveal(tester, find.text('등록하기'));
      await tester.tap(find.text('등록하기'));
      await tester.pumpAndSettle();
      expect(find.text('소비기한을 선택해주세요.'), findsOneWidget);
      expect((await tester.runAsync(repo.load))!.foods, isEmpty);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'history selection copies original quantity but requires new purchase details',
    (tester) async {
      await tester.runAsync(() async {
        await repo.save(
          Food(
            id: 'old',
            name: '우리집 우유',
            unit: FoodUnit.litre,
            total: 1000000,
            expiry: today.subtract(const Duration(days: 2)),
            price: 3000,
            created: today,
          ),
        );
        await repo.process(
          foodId: 'old',
          kind: ActionKind.waste,
          amount: 250000,
          unit: FoodUnit.ml,
          date: today,
          requestId: 'old-waste',
          today: today,
        );
      });
      await openRegistration(tester);
      await tester.enterText(find.byKey(const ValueKey('food-price')), '9999');
      await tester.tap(find.text('소비기한'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('선택'));
      await tester.pumpAndSettle();
      await reveal(tester, find.byKey(const ValueKey('food-name')));
      await tester.enterText(find.byKey(const ValueKey('food-name')), '우리집');
      await waitFor(
        tester,
        find.byKey(const ValueKey('suggestion-history-old')),
      );
      await tester.tap(find.byKey(const ValueKey('suggestion-history-old')));
      await tester.pumpAndSettle();
      expect(field(tester, 'food-quantity'), '1');
      expect(field(tester, 'food-price'), isEmpty);
      expect(find.text('날짜 선택'), findsOneWidget);
      final snapshot = (await tester.runAsync(repo.load))!;
      expect(snapshot.foods.single.remaining, 750000);
      expect(snapshot.foods.single.price, 3000);
      expect(snapshot.records.single.cost, 750);
      await tester.pumpWidget(const SizedBox());
    },
  );

  Future<void> chooseTodayAndSave(WidgetTester tester) async {
    await reveal(tester, find.text('소비기한'));
    await tester.tap(find.text('소비기한'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('선택'));
    await tester.pumpAndSettle();
    await reveal(tester, find.text('등록하기'));
    await tester.tap(find.text('등록하기'));
    await settlePage(tester, const ValueKey('home-page'));
  }

  testWidgets(
    'selected catalogue product saves as new stock with missing price and survives reopening',
    (tester) async {
      await openRegistration(tester);
      await tester.enterText(find.byKey(const ValueKey('food-name')), '서울우');
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('suggestion-seoul-lowfat-1l')),
      );
      await tester.pumpAndSettle();
      await chooseTodayAndSave(tester);
      final snapshot = (await tester.runAsync(repo.load))!;
      expect(snapshot.foods, hasLength(1));
      expect(snapshot.foods.single.total, 1000000);
      expect(snapshot.foods.single.price, isNull);
      expect(snapshot.foods.single.expiry, civilDate(today));
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(() async {
        await repo.close();
        repo = await InventoryRepository.open(
          factory: databaseFactoryFfi,
          databasePath: p.join(temp.path, 'recare.db'),
        );
      });
      await openRegistration(tester);
      await tester.enterText(find.byKey(const ValueKey('food-name')), '서울우');
      await waitFor(
        tester,
        find.byKey(ValueKey('suggestion-history-${snapshot.foods.single.id}')),
      );
      expect(
        find.byKey(const ValueKey('suggestion-seoul-lowfat-1l')),
        findsNothing,
      );
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'renaming a selected ingredient removes its preview and unmatched manual entry still saves',
    (tester) async {
      await openRegistration(tester);
      await tester.enterText(find.byKey(const ValueKey('food-name')), '당근');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('suggestion-carrot')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('selected-food-image')), findsOneWidget);
      await tester.enterText(
        find.byKey(const ValueKey('food-name')),
        '직접 만든 반찬',
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('selected-food-image')), findsNothing);
      expect(find.text('일치하는 재료가 없어요. 그대로 직접 입력할 수 있어요.'), findsOneWidget);
      await tester.enterText(find.byKey(const ValueKey('food-quantity')), '3');
      await chooseTodayAndSave(tester);
      final saved = (await tester.runAsync(repo.load))!.foods.single;
      expect(saved.name, '직접 만든 반찬');
      expect(saved.total, 3000);
      expect(saved.unit, FoodUnit.piece);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'small screen with keyboard and larger text retains focus and selectable suggestions',
    (tester) async {
      tester.view.physicalSize = const Size(320, 720);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 1.3;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetViewInsets);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await openRegistration(tester);
      tester.view.viewInsets = const FakeViewPadding(bottom: 260);
      await tester.enterText(find.byKey(const ValueKey('food-name')), '서울');
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('food-name')), '서울우');
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<EditableText>(
              find.descendant(
                of: find.byKey(const ValueKey('food-name')),
                matching: find.byType(EditableText),
              ),
            )
            .focusNode
            .hasFocus,
        isTrue,
      );
      final suggestion = find.byKey(
        const ValueKey('suggestion-seoul-lowfat-1l'),
      );
      await tester.ensureVisible(suggestion);
      await tester.pumpAndSettle();
      await tester.tap(suggestion);
      tester.view.resetViewInsets();
      await tester.pumpAndSettle();
      await reveal(tester, find.byKey(const ValueKey('food-name')));
      expect(field(tester, 'food-name'), '서울우유 나100% 저지방우유');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'historical edit keeps restricted fields and never offers replacement autocomplete',
    (tester) async {
      await tester.runAsync(() async {
        await repo.save(
          Food(
            id: 'old',
            name: '우유',
            unit: FoodUnit.litre,
            total: 1000000,
            expiry: today,
            price: 3000,
            created: today,
          ),
        );
        await repo.process(
          foodId: 'old',
          kind: ActionKind.eat,
          amount: 250000,
          unit: FoodUnit.ml,
          date: today,
          requestId: 'eat',
          today: today,
        );
      });
      await tester.pumpWidget(
        RecareApp(
          automaticCheckIns: false,
          repositoryFactory: () async => repo,
          preferencesFactory: () async =>
              PreferencesStore(p.join(temp.path, 'prefs.json')),
          clock: () => today,
        ),
      );
      await settlePage(tester, const ValueKey('home-page'));
      await tester.tap(find.byKey(const ValueKey('food-old')));
      await settlePage(tester, const ValueKey('food-detail'));
      await tester.tap(find.text('수정'));
      await settlePage(tester, const ValueKey('food-editor'));
      await tester.enterText(find.byKey(const ValueKey('food-name')), '서울우');
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('food-suggestions')), findsNothing);
      expect(
        tester
            .widget<TextFormField>(find.byKey(const ValueKey('food-quantity')))
            .enabled,
        isFalse,
      );
      expect(field(tester, 'food-price'), '3000');
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'failed recent-history lookup leaves catalogue usable and retry restores history',
    (tester) async {
      final controller = TextEditingController();
      var attempts = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: IngredientAutocomplete(
                controller: controller,
                enabled: true,
                loadHistory: () async {
                  if (++attempts == 1) {
                    throw StateError('temporary read failure');
                  }
                  return [
                    Food(
                      id: 'retry',
                      name: '우리집 두부',
                      unit: FoodUnit.gram,
                      total: 300000,
                      expiry: today,
                      price: 1000,
                      created: today,
                    ),
                  ];
                },
                onSelected: (_) {},
                onNameChanged: () {},
                onActiveChanged: (_) {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('food-name')), '서울우');
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('suggestion-seoul-lowfat-1l')),
        findsOneWidget,
      );
      expect(find.text('이전 기록 재시도'), findsOneWidget);
      await tester.tap(find.text('이전 기록 재시도'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('food-name')), '우리집');
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('suggestion-history-retry')),
        findsOneWidget,
      );
      expect(attempts, 2);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
    },
  );
}
