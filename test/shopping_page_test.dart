import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:recare/data/inventory_repository.dart';
import 'package:recare/domain/inventory.dart';
import 'package:recare/domain/shopping.dart';
import 'package:recare/ui/batch_registration.dart';
import 'package:recare/ui/design_system.dart';
import 'package:recare/ui/shopping_page.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  late Directory temp;
  late InventoryRepository repo;
  final today = DateTime(2026, 10, 21);

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('recare-shopping-ui-');
    repo = await InventoryRepository.open(
      factory: databaseFactoryFfi,
      databasePath: '${temp.path}/recare.db',
    );
  });
  tearDown(() async {
    await repo.close();
    await temp.delete(recursive: true);
  });

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 100; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump(const Duration(milliseconds: 100));
      if (find.byType(CircularProgressIndicator).evaluate().isEmpty &&
          find.byType(LinearProgressIndicator).evaluate().isEmpty) {
        await tester.pumpAndSettle();
        return;
      }
    }
    fail('Shopping page did not finish loading');
  }

  Future<void> open(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: RecareTheme.light,
        home: ShoppingPage(repository: repo, clock: () => today),
      ),
    );
    await settle(tester);
  }

  ShoppingItem shopping(String id, String name, FoodUnit unit, int amount) =>
      ShoppingItem(
        id: id,
        name: name,
        unit: unit,
        amount: amount,
        created: today,
      );

  testWidgets('adds custom items persistently and explains duplicate no-op', (
    tester,
  ) async {
    await open(tester);
    await tester.tap(find.byKey(const ValueKey('shopping-add')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('shopping-name')), '우유');
    await tester.enterText(
      find.byKey(const ValueKey('shopping-quantity')),
      '2',
    );
    await tester.tap(find.byKey(const ValueKey('shopping-save')));
    await settle(tester);
    var items = await tester.runAsync(repo.loadShoppingList);
    expect(items!.single.name, '우유');
    expect(items.single.amount, 2000);
    expect(items.single.created, civilDate(today));
    expect(find.text('장볼 수량 2 개'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('shopping-add')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('shopping-name')), ' 우유 ');
    await tester.enterText(
      find.byKey(const ValueKey('shopping-quantity')),
      '2',
    );
    await tester.tap(find.byKey(const ValueKey('shopping-save')));
    await settle(tester);
    items = await tester.runAsync(repo.loadShoppingList);
    expect(items, hasLength(1));
    expect(find.text('같은 항목이 이미 장보기 목록에 있어요.'), findsOneWidget);
    expect(find.text('장보기 목록에 추가했어요.'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'shows compatible on-hand quantity separately from desired purchase',
    (tester) async {
      await tester.runAsync(() async {
        await repo.addShoppingItem(
          shopping('milk', ' 우유 ', FoodUnit.litre, 2000000),
        );
        for (final entry in [
          ('volume', ' 우유 ', FoodUnit.ml, 500000),
          ('different-unit', '우유', FoodUnit.piece, 10000),
          ('different-food', '두유', FoodUnit.litre, 9000000),
        ]) {
          await repo.save(
            Food(
              id: entry.$1,
              name: entry.$2,
              unit: entry.$3,
              total: entry.$4,
              expiry: today,
              price: null,
              created: today,
            ),
          );
        }
      });
      await open(tester);
      expect(find.text('장볼 수량 2 L'), findsOneWidget);
      expect(find.text('현재 재고 0.5 L'), findsOneWidget);
      expect(find.textContaining('현재 재고 10'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('cancelled purchased registration retains list and selection', (
    tester,
  ) async {
    await tester.runAsync(() async {
      await repo.addShoppingItem(
        shopping('milk', '우유', FoodUnit.litre, 1000000),
      );
      await repo.addShoppingItem(shopping('eggs', '달걀', FoodUnit.piece, 6000));
    });
    await open(tester);
    await tester.tap(find.byKey(const ValueKey('shopping-select-milk')));
    await tester.tap(find.byKey(const ValueKey('shopping-select-eggs')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('shopping-checkout')));
    await tester.pumpAndSettle();
    final batch = tester.widget<BatchRegistrationPage>(
      find.byType(BatchRegistrationPage),
    );
    expect(
      batch.initialItems.map((item) => item.id),
      containsAll(['milk', 'eggs']),
    );
    Navigator.of(tester.element(find.byType(BatchRegistrationPage))).pop(false);
    await settle(tester);
    expect((await tester.runAsync(repo.loadShoppingList))!, hasLength(2));
    expect(
      tester
          .widget<Checkbox>(find.byKey(const ValueKey('shopping-select-milk')))
          .value,
      isTrue,
    );
    expect(
      tester
          .widget<Checkbox>(find.byKey(const ValueKey('shopping-select-eggs')))
          .value,
      isTrue,
    );
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'successful multi-item checkout registers purchases and removes only selected items',
    (tester) async {
      await tester.runAsync(() async {
        await repo.addShoppingItem(
          shopping('milk', '우유', FoodUnit.litre, 1000000),
        );
        await repo.addShoppingItem(
          shopping('eggs', '달걀', FoodUnit.piece, 6000),
        );
        await repo.addShoppingItem(
          shopping('apple', '사과', FoodUnit.piece, 2000),
        );
        await repo.save(
          Food(
            id: 'old-milk',
            name: '우유',
            unit: FoodUnit.litre,
            total: 1000000,
            expiry: today.subtract(const Duration(days: 7)),
            price: 8000,
            created: today.subtract(const Duration(days: 14)),
          ),
        );
        await repo.process(
          foodId: 'old-milk',
          kind: ActionKind.eat,
          amount: 1000000,
          unit: FoodUnit.litre,
          date: today,
          requestId: 'finished-old-milk',
          today: today,
        );
      });
      await open(tester);
      for (final id in ['milk', 'eggs']) {
        await tester.tap(find.byKey(ValueKey('shopping-select-$id')));
      }
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('shopping-checkout')));
      await settle(tester);
      for (final id in ['milk', 'eggs']) {
        final date = find.byKey(ValueKey('batch-expiry-$id'));
        if (date.evaluate().isEmpty) {
          await tester.scrollUntilVisible(
            date,
            180,
            scrollable: find
                .descendant(
                  of: find.byKey(const ValueKey('batch-page')),
                  matching: find.byType(Scrollable),
                )
                .first,
          );
        }
        await tester.ensureVisible(date);
        await tester.tap(date);
        await tester.pumpAndSettle();
        await tester.tap(find.text('선택'));
        await tester.pumpAndSettle();
      }
      await tester.tap(find.byKey(const ValueKey('batch-save')));
      await settle(tester);
      expect(find.byType(BatchRegistrationPage), findsNothing);
      final items = (await tester.runAsync(repo.loadShoppingList))!;
      expect(items.single.id, 'apple');
      final snapshot = (await tester.runAsync(repo.load))!;
      final purchased = snapshot.foods
          .where((food) => food.id != 'old-milk')
          .toList();
      expect(purchased.map((food) => food.name), containsAll(['우유', '달걀']));
      expect(purchased, hasLength(2));
      expect(
        purchased.every(
          (food) => food.price == null && food.expiry == civilDate(today),
        ),
        isTrue,
      );
      expect(
        purchased.singleWhere((food) => food.name == '우유').remaining,
        1000000,
      );
      expect(
        purchased.singleWhere((food) => food.name == '달걀').remaining,
        6000,
      );
      expect(find.byKey(const ValueKey('shopping-item-milk')), findsNothing);
      expect(find.byKey(const ValueKey('shopping-item-eggs')), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'failed checkout validation keeps typed purchase data and shopping entries',
    (tester) async {
      await tester.runAsync(
        () => repo.addShoppingItem(
          shopping('milk', '우유', FoodUnit.litre, 1000000),
        ),
      );
      await open(tester);
      await tester.tap(find.byKey(const ValueKey('shopping-select-milk')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('shopping-checkout')));
      await settle(tester);
      await tester.enterText(
        find.byKey(const ValueKey('batch-name-0')),
        '저지방 우유',
      );
      await tester.tap(find.byKey(const ValueKey('batch-save')));
      await tester.pumpAndSettle();
      expect(find.text('모든 재료의 소비기한을 선택해주세요.'), findsOneWidget);
      expect(
        tester
            .widget<TextFormField>(find.byKey(const ValueKey('batch-name-0')))
            .controller!
            .text,
        '저지방 우유',
      );
      expect((await tester.runAsync(repo.loadShoppingList))!.single.id, 'milk');
      expect((await tester.runAsync(repo.load))!.foods, isEmpty);
      Navigator.of(tester.element(find.byType(BatchRegistrationPage)))
          .pop(false);
      await settle(tester);
      expect(
        tester
            .widget<Checkbox>(
              find.byKey(const ValueKey('shopping-select-milk')),
            )
            .value,
        isTrue,
      );
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('removing an item persists and clears its checkout selection', (
    tester,
  ) async {
    await tester.runAsync(
      () =>
          repo.addShoppingItem(shopping('milk', '우유', FoodUnit.litre, 1000000)),
    );
    await open(tester);
    await tester.tap(find.byKey(const ValueKey('shopping-select-milk')));
    await tester.tap(find.byKey(const ValueKey('shopping-remove-milk')));
    await settle(tester);
    expect((await tester.runAsync(repo.loadShoppingList))!, isEmpty);
    expect(find.text('장보기 목록이 비어 있어요.'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(find.byKey(const ValueKey('shopping-checkout')))
          .onPressed,
      isNull,
    );
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('small screens and large text keep add and checkout reachable', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: RecareTheme.light,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: const TextScaler.linear(1.6)),
          child: child!,
        ),
        home: ShoppingPage(repository: repo, clock: () => today),
      ),
    );
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('shopping-add')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('shopping-save')), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
