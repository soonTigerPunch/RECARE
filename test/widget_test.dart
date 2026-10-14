import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:recare/data/inventory_repository.dart';
import 'package:recare/data/preferences.dart';
import 'package:recare/domain/inventory.dart';
import 'package:recare/main.dart';

const homePage = ValueKey('home-page');
const inventoryPage = ValueKey('inventory-page');
const settingsPage = ValueKey('settings-page');
const weeklyPage = ValueKey('weekly-page');
const detailPage = ValueKey('food-detail');
const editorPage = ValueKey('food-editor');

Future<void> waitFor(WidgetTester tester, Finder finder) async {
  for (var i = 0; i < 100; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump(const Duration(milliseconds: 100));
    if (finder.evaluate().isNotEmpty) return;
  }
  expect(finder, findsWidgets);
}

Future<void> settlePage(WidgetTester tester, Key page) async {
  await waitFor(tester, find.byKey(page));
  for (var i = 0; i < 100; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump(const Duration(milliseconds: 100));
    if (find.byType(CircularProgressIndicator).evaluate().isEmpty &&
        find.byType(LinearProgressIndicator).evaluate().isEmpty) {
      break;
    }
  }
  await tester.pumpAndSettle();
}

Future<void> reveal(WidgetTester tester, Finder finder) async {
  if (finder.evaluate().isEmpty) {
    await tester.scrollUntilVisible(
      finder,
      150,
      scrollable: find
          .byWidgetPredicate(
            (widget) =>
                widget is Scrollable &&
                (widget.axisDirection == AxisDirection.down ||
                    widget.axisDirection == AxisDirection.up),
          )
          .first,
    );
  }
  await tester.ensureVisible(finder);
  await tester.pump();
}

Future<void> navigate(WidgetTester tester, String label, Key page) async {
  await tester.tap(
    find.descendant(of: find.byType(NavigationBar), matching: find.text(label)),
  );
  await settlePage(tester, page);
}

Future<void> openWeeklyDetails(WidgetTester tester) async {
  await reveal(tester, find.text('폐기 내역'));
  await tester.tap(find.text('폐기 내역'));
  await settlePage(tester, weeklyPage);
}

Future<void> enterManualAmount(
  WidgetTester tester,
  String quantity,
  String unit,
) async {
  await reveal(tester, find.byKey(const ValueKey('manual-amount')));
  await tester.tap(find.byKey(const ValueKey('manual-amount')));
  await tester.pumpAndSettle();
  await reveal(tester, find.byKey(const ValueKey('process-quantity')));
  await tester.enterText(
    find.byKey(const ValueKey('process-quantity')),
    quantity,
  );
  await tester.tap(find.text(unit));
  await tester.pump();
}

void main() {
  sqfliteFfiInit();
  final today = DateTime(2026, 10, 12);
  late InventoryRepository repo;
  late Directory temp;
  late String databasePath;
  late String preferencesPath;

  Food milk({int? price = 3000, String name = '우유'}) => Food(
    id: 'milk',
    name: name,
    unit: FoodUnit.litre,
    total: 1000000,
    expiry: today,
    price: price,
    created: today,
  );

  Future<void> seedWaste({int? price = 3000, String name = '우유'}) async {
    await repo.save(milk(price: price, name: name));
    await repo.process(
      foodId: 'milk',
      kind: ActionKind.waste,
      amount: 250000,
      unit: FoodUnit.ml,
      date: today,
      requestId: 'initial-waste',
      today: today,
    );
  }

  Future<void> openApp(WidgetTester tester) async {
    await tester.pumpWidget(
      RecareApp(
        repositoryFactory: () async => repo,
        preferencesFactory: () async => PreferencesStore(preferencesPath),
        clock: () => today,
      ),
    );
    await settlePage(tester, homePage);
  }

  Future<void> openMilk(WidgetTester tester) async {
    await reveal(tester, find.byKey(const ValueKey('food-milk')));
    await tester.tap(find.byKey(const ValueKey('food-milk')));
    await settlePage(tester, detailPage);
    await waitFor(tester, find.text('폐기 기록'));
    // The detail screen loads its history separately from opening its route.
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pumpAndSettle();
  }

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('recare-widget-test-');
    databasePath = p.join(temp.path, 'recare.db');
    preferencesPath = p.join(temp.path, 'preferences.json');
    repo = await InventoryRepository.open(
      factory: databaseFactoryFfi,
      databasePath: databasePath,
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

  testWidgets(
    'registration partial waste and weekly total connect end to end',
    (tester) async {
      await openApp(tester);
      await tester.tap(find.text('식재료 등록'));
      await settlePage(tester, editorPage);
      await tester.enterText(find.byKey(const ValueKey('food-name')), '우유');
      await tester.enterText(find.byKey(const ValueKey('food-quantity')), '1');
      await tester.tap(find.text('L'));
      await tester.pump();
      await tester.ensureVisible(find.text('소비기한'));
      await tester.tap(find.text('소비기한'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('선택'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const ValueKey('food-price')));
      await tester.enterText(find.byKey(const ValueKey('food-price')), '3000');
      await tester.ensureVisible(find.text('등록하기'));
      await tester.tap(find.text('등록하기'));
      await settlePage(tester, homePage);
      await tester.tap(find.text('우유'));
      await settlePage(tester, detailPage);
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('폐기 기록'));
      await tester.tap(find.text('폐기 기록'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('process-quantity')), findsNothing);
      await enterManualAmount(tester, '250', 'ml');
      expect(find.text('처리 금액 750원'), findsOneWidget);
      await tester.tap(find.text('폐기 저장'));
      await waitFor(tester, find.text('0.75 L'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('먹음 기록'));
      await tester.tap(find.text('먹음 기록'));
      await tester.pumpAndSettle();
      await enterManualAmount(tester, '250', 'ml');
      await tester.tap(find.text('먹음 저장'));
      await waitFor(tester, find.text('0.5 L'));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(BackButton));
      await settlePage(tester, homePage);
      expect(
        find.descendant(
          of: find.byKey(homePage),
          matching: find.byKey(const ValueKey('weekly-total')),
        ),
        findsOneWidget,
      );
      expect(find.text('750원'), findsOneWidget);
      await openWeeklyDetails(tester);
      expect(find.text('750원'), findsNWidgets(2));
      expect(find.text('폐기 1건'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('missing purchase price is visible and never rendered as zero', (
    tester,
  ) async {
    await tester.runAsync(() => seedWaste(price: null));
    await openApp(tester);
    expect(find.text('금액 미입력'), findsOneWidget);
    expect(find.text('폐기 1건 · 금액 미입력 1건'), findsOneWidget);
    await openWeeklyDetails(tester);
    expect(find.text('금액 미입력'), findsNWidgets(2));
    expect(find.text('0원'), findsNothing);
    expect(find.text('폐기 1건 · 금액 미입력 1건'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'list orders groceries by expiry and displays the matching D-Day',
    (tester) async {
      await tester.runAsync(() async {
        await repo.save(milk());
        await repo.save(
          Food(
            id: 'later',
            name: '당근',
            unit: FoodUnit.gram,
            total: 500000,
            expiry: today.add(const Duration(days: 2)),
            price: 2000,
            created: today,
          ),
        );
        await repo.save(
          Food(
            id: 'expired',
            name: '두부',
            unit: FoodUnit.piece,
            total: 1000,
            expiry: today.subtract(const Duration(days: 2)),
            price: 1000,
            created: today,
          ),
        );
      });
      await openApp(tester);
      await navigate(tester, '목록', inventoryPage);
      final expired = find.byKey(const ValueKey('food-expired'));
      final due = find.byKey(const ValueKey('food-milk'));
      final later = find.byKey(const ValueKey('food-later'));
      expect(
        tester.getTopLeft(expired).dy,
        lessThan(tester.getTopLeft(due).dy),
      );
      expect(tester.getTopLeft(due).dy, lessThan(tester.getTopLeft(later).dy));
      expect(
        find.descendant(of: expired, matching: find.text('2일 지남')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: due, matching: find.text('D-Day')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: later, matching: find.text('D-2')),
        findsOneWidget,
      );
      for (final food in ['expired', 'milk', 'later']) {
        expect(
          find.descendant(
            of: find.byKey(ValueKey('food-$food')),
            matching: find.textContaining('소비기한'),
          ),
          findsOneWidget,
        );
      }
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('editing and confirmed deletion update the saved grocery list', (
    tester,
  ) async {
    await tester.runAsync(() => repo.save(milk()));
    await openApp(tester);
    await navigate(tester, '목록', inventoryPage);
    await openMilk(tester);
    expect(find.text('3,000원'), findsOneWidget);
    await tester.tap(find.text('수정'));
    await settlePage(tester, editorPage);
    await tester.enterText(find.byKey(const ValueKey('food-name')), '저지방 우유');
    await tester.enterText(find.byKey(const ValueKey('food-price')), '3200');
    await reveal(tester, find.text('수정 저장'));
    await tester.tap(find.text('수정 저장'));
    await settlePage(tester, detailPage);
    expect(find.text('저지방 우유'), findsOneWidget);
    expect(find.text('3,200원'), findsOneWidget);
    await tester.tap(find.byType(BackButton));
    await settlePage(tester, inventoryPage);
    expect(find.text('저지방 우유'), findsOneWidget);
    expect(find.text('우유'), findsNothing);
    await openMilk(tester);
    await tester.tap(find.text('삭제'));
    await tester.pumpAndSettle();
    expect(find.text('식재료 삭제'), findsOneWidget);
    await tester.tap(find.text('취소'));
    await tester.pumpAndSettle();
    expect(find.byKey(detailPage), findsOneWidget);
    await tester.tap(find.text('삭제'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('삭제하기'));
    await settlePage(tester, inventoryPage);
    expect(find.text('저지방 우유'), findsNothing);
    final snapshot = await tester.runAsync(() => repo.load());
    expect(snapshot!.foods, isEmpty);
    expect(snapshot.records, isEmpty);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'deletion with processing history preserves inventory and waste total',
    (tester) async {
      await tester.runAsync(() => seedWaste());
      await openApp(tester);
      await navigate(tester, '목록', inventoryPage);
      await openMilk(tester);
      await tester.tap(find.text('삭제'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.textContaining('처리 기록'), findsWidgets);
      expect(find.text('삭제하기'), findsNothing);
      await tester.tap(find.text('확인'));
      await tester.pumpAndSettle();
      final snapshot = await tester.runAsync(() => repo.load());
      expect(snapshot!.foods.single.remaining, 750000);
      expect(snapshot.records.single.cost, 750);
      await tester.tap(find.byType(BackButton));
      await settlePage(tester, inventoryPage);
      await navigate(tester, '홈', homePage);
      await openWeeklyDetails(tester);
      expect(find.text('750원'), findsNWidgets(2));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('narrow phone with larger text keeps core actions reachable', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 720);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 1.3;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    const longName = '오늘 구매한 아주 신선한 국산 유기농 냉장 우유 1리터';
    await tester.runAsync(() => seedWaste(name: longName));
    await openApp(tester);
    expect(find.text(longName), findsOneWidget);
    expect(tester.takeException(), isNull);
    await navigate(tester, '목록', inventoryPage);
    await openMilk(tester);
    await tester.ensureVisible(find.text('폐기 기록'));
    await tester.tap(find.text('폐기 기록'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await enterManualAmount(tester, '100', 'ml');
    await reveal(tester, find.byKey(const ValueKey('portion-1')));
    await tester.tap(find.byKey(const ValueKey('portion-1')));
    await tester.pump();
    expect(find.text('처리 금액 2,250원'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('취소'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('수정'));
    await settlePage(tester, editorPage);
    await tester.ensureVisible(find.byKey(const ValueKey('food-price')));
    expect(tester.takeException(), isNull);
    await reveal(tester, find.text('수정 저장'));
    await tester.tap(find.text('수정 저장'));
    await settlePage(tester, detailPage);
    await tester.tap(find.byType(BackButton));
    await settlePage(tester, inventoryPage);
    await navigate(tester, '설정', settingsPage);
    expect(tester.takeException(), isNull);
    await navigate(tester, '홈', homePage);
    await openWeeklyDetails(tester);
    expect(find.text('750원'), findsNWidgets(2));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'portion choices use current remaining stock and update home totals',
    (tester) async {
      await tester.runAsync(() => seedWaste());
      await openApp(tester);
      await openMilk(tester);
      await reveal(tester, find.text('먹음 기록'));
      await tester.tap(find.text('먹음 기록'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('process-quantity')), findsNothing);
      expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, '먹음 저장'))
            .onPressed,
        isNull,
      );
      await tester.tap(find.byKey(const ValueKey('portion-2')));
      await tester.pump();
      expect(find.text('처리 수량 375 ml'), findsOneWidget);
      expect(find.text('처리 금액 1,125원'), findsOneWidget);
      await tester.tap(find.text('먹음 저장'));
      await waitFor(tester, find.text('0.375 L'));
      await settlePage(tester, detailPage);
      await reveal(tester, find.text('폐기 기록'));
      await tester.tap(find.text('폐기 기록'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('portion-3')));
      await tester.pump();
      expect(find.text('처리 수량 125 ml'), findsOneWidget);
      expect(find.text('처리 금액 375원'), findsOneWidget);
      await tester.tap(find.text('폐기 저장'));
      await waitFor(tester, find.text('0.25 L'));
      await settlePage(tester, detailPage);
      final snapshot = await tester.runAsync(() => repo.load());
      expect(snapshot!.foods.single.remaining, 250000);
      expect(
        snapshot.records.where((r) => r.kind == ActionKind.eat).single.amount,
        375000,
      );
      expect(weeklyWaste(snapshot.records, today).knownTotal, 1125);
      await tester.tap(find.byType(BackButton));
      await settlePage(tester, homePage);
      expect(find.text('1,125원'), findsOneWidget);
      expect(find.text('폐기 2건'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'manual entry preserves the exact quantity from a fractional preset',
    (tester) async {
      await tester.runAsync(() => repo.save(milk()));
      await openApp(tester);
      await openMilk(tester);
      await reveal(tester, find.text('먹음 기록'));
      await tester.tap(find.text('먹음 기록'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('portion-3')));
      await tester.pump();
      expect(find.text('처리 수량 333.333 ml'), findsOneWidget);
      expect(find.text('처리 금액 1,000원'), findsOneWidget);
      await reveal(tester, find.byKey(const ValueKey('manual-amount')));
      await tester.tap(find.byKey(const ValueKey('manual-amount')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('process-quantity')), findsOneWidget);
      expect(find.text('처리 수량 333.333 ml'), findsOneWidget);
      expect(find.text('처리 금액 1,000원'), findsOneWidget);
      await tester.tap(find.text('먹음 저장'));
      await waitFor(tester, find.text('0.666667 L'));
      await settlePage(tester, detailPage);
      final snapshot = await tester.runAsync(() => repo.load());
      expect(snapshot!.foods.single.remaining, 666667);
      expect(snapshot.records.single.amount, 333333);
      expect(snapshot.records.single.cost, 1000);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'three navigation destinations and settings survive an app restart',
    (tester) async {
      await tester.runAsync(() async {
        await repo.save(milk());
        await repo.save(
          Food(
            id: 'future',
            name: '다음 주 당근',
            unit: FoodUnit.gram,
            total: 500000,
            expiry: today.add(const Duration(days: 5)),
            price: 2000,
            created: today,
          ),
        );
        await repo.save(
          Food(
            id: 'finished',
            name: '먹은 사과',
            unit: FoodUnit.piece,
            total: 1000,
            expiry: today.add(const Duration(days: 2)),
            price: 1000,
            created: today,
          ),
        );
        await repo.process(
          foodId: 'finished',
          kind: ActionKind.eat,
          amount: 1000,
          unit: FoodUnit.piece,
          date: today,
          requestId: 'finished-apple',
          today: today,
        );
      });
      await openApp(tester);
      for (final label in ['홈', '목록', '설정']) {
        expect(
          find.descendant(
            of: find.byType(NavigationBar),
            matching: find.text(label),
          ),
          findsOneWidget,
        );
      }
      expect(find.text('이번 주 폐기 금액'), findsOneWidget);
      expect(find.byKey(const ValueKey('food-future')), findsNothing);
      await navigate(tester, '목록', inventoryPage);
      expect(find.byKey(const ValueKey('food-future')), findsOneWidget);
      expect(find.byKey(const ValueKey('food-finished')), findsNothing);
      await navigate(tester, '설정', settingsPage);
      await tester.tap(find.text('다크'));
      for (var i = 0; i < 100; i++) {
        final saved = await tester.runAsync(() async {
          await Future<void>.delayed(const Duration(milliseconds: 20));
          return PreferencesStore(preferencesPath).load();
        });
        await tester.pump(const Duration(milliseconds: 100));
        if (saved!.appearance == AppAppearance.dark) break;
      }
      await settlePage(tester, settingsPage);
      expect(
        tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode,
        ThemeMode.dark,
      );
      await tester.tap(find.text('처리 완료 표시'));
      AppPreferences? saved;
      for (var i = 0; i < 100; i++) {
        saved = await tester.runAsync(() async {
          await Future<void>.delayed(const Duration(milliseconds: 20));
          return PreferencesStore(preferencesPath).load();
        });
        await tester.pump(const Duration(milliseconds: 100));
        if (saved!.includeFinished) break;
      }
      await settlePage(tester, settingsPage);
      expect(saved!.appearance, AppAppearance.dark);
      expect(saved.includeFinished, isTrue);
      await navigate(tester, '목록', inventoryPage);
      await reveal(tester, find.byKey(const ValueKey('food-finished')));
      expect(find.byKey(const ValueKey('food-finished')), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(() => repo.close());
      final reopened = await tester.runAsync(
        () => InventoryRepository.open(
          factory: databaseFactoryFfi,
          databasePath: databasePath,
        ),
      );
      repo = reopened!;
      await openApp(tester);
      await navigate(tester, '설정', settingsPage);
      expect(
        tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode,
        ThemeMode.dark,
      );
      expect(
        tester
            .widget<SwitchListTile>(
              find.widgetWithText(SwitchListTile, '처리 완료 표시'),
            )
            .value,
        isTrue,
      );
      await navigate(tester, '목록', inventoryPage);
      await reveal(tester, find.byKey(const ValueKey('food-finished')));
      expect(find.byKey(const ValueKey('food-finished')), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'failed settings load can retry without changing food inventory',
    (tester) async {
      await tester.runAsync(() => repo.save(milk()));
      var attempts = 0;
      await tester.pumpWidget(
        RecareApp(
          repositoryFactory: () async => repo,
          preferencesFactory: () async {
            attempts++;
            if (attempts == 1) throw const FileSystemException('unavailable');
            return PreferencesStore(preferencesPath);
          },
          clock: () => today,
        ),
      );
      await settlePage(tester, homePage);
      await navigate(tester, '설정', settingsPage);
      expect(find.text('설정을 불러오지 못했어요. 다시 시도해주세요.'), findsOneWidget);
      expect(
        tester
            .widget<ChoiceChip>(find.byKey(const ValueKey('appearance-dark')))
            .onSelected,
        isNull,
      );
      expect(
        tester
            .widget<SwitchListTile>(
              find.byKey(const ValueKey('include-finished')),
            )
            .onChanged,
        isNull,
      );
      await reveal(tester, find.text('다시 시도'));
      await tester.tap(find.text('다시 시도'));
      await settlePage(tester, settingsPage);
      expect(find.text('설정을 불러오지 못했어요. 다시 시도해주세요.'), findsNothing);
      expect(attempts, 2);
      await tester.tap(find.text('다크'));
      await settlePage(tester, settingsPage);
      expect(
        tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode,
        ThemeMode.dark,
      );
      final snapshot = await tester.runAsync(() => repo.load());
      expect(snapshot!.foods.single.remaining, 1000000);
      expect(snapshot.records, isEmpty);
      await navigate(tester, '목록', inventoryPage);
      expect(find.byKey(const ValueKey('food-milk')), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
