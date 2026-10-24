import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:recare/services/reminder_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:recare/data/inventory_repository.dart';
import 'package:recare/data/preferences.dart';
import 'package:recare/domain/inventory.dart';
import 'package:recare/main.dart';

import 'widget_test.dart' show settlePage, reveal, waitFor;

void main() {
  sqfliteFfiInit();
  late Directory temp;
  late InventoryRepository repo;
  final today = DateTime(2026, 10, 21);
  setUp(() async {
    temp = await Directory.systemTemp.createTemp('recare-usability-ui-');
    repo = await InventoryRepository.open(
      factory: databaseFactoryFfi,
      databasePath: p.join(temp.path, 'recare.db'),
    );
    await repo.save(
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
  });
  tearDown(() async {
    await repo.close();
    await temp.delete(recursive: true);
  });
  Future<void> launch(WidgetTester tester) async {
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
  }

  testWidgets(
    'list quick processing offers undo and restores stock and active history',
    (tester) async {
      await launch(tester);
      await tester.tap(find.text('목록'));
      await settlePage(tester, const ValueKey('inventory-page'));
      final quick = find.byKey(const ValueKey('quick-eat-milk'));
      expect(quick, findsOneWidget);
      await tester.tap(quick);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('portion-2')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('먹음 저장'));
      await settlePage(tester, const ValueKey('inventory-page'));
      final processed = await tester.runAsync(repo.load);
      expect(processed!.foods.single.remaining, 500000);
      expect(processed.records.single.cost, 1500);
      await tester.tap(find.text('실행 취소'));
      await settlePage(tester, const ValueKey('inventory-page'));
      final restored = await tester.runAsync(repo.load);
      expect(restored!.foods.single.remaining, 1000000);
      expect(restored.records, isEmpty);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'batch registration leaves inventory unchanged when dates are missing',
    (tester) async {
      await launch(tester);
      final entry = find.byKey(const ValueKey('open-batch'));
      expect(entry, findsOneWidget);
      await tester.tap(entry);
      await settlePage(tester, const ValueKey('batch-page'));
      await tester.tap(find.byKey(const ValueKey('batch-manual')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('batch-name-0')), '토마토');
      await reveal(tester, find.byKey(const ValueKey('batch-save')));
      await tester.tap(find.byKey(const ValueKey('batch-save')));
      await tester.pumpAndSettle();
      expect(find.text('모든 재료의 소비기한을 선택해주세요.'), findsOneWidget);
      expect((await tester.runAsync(repo.load))!.foods.length, 1);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'waste reason persists and a finished ingredient can be added to shopping',
    (tester) async {
      await launch(tester);
      await tester.tap(find.text('목록'));
      await settlePage(tester, const ValueKey('inventory-page'));
      await tester.tap(find.byKey(const ValueKey('quick-waste-milk')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('portion-1')));
      await tester.pumpAndSettle();
      await reveal(tester, find.byKey(const ValueKey('waste-reason-forgot')));
      await tester.tap(find.byKey(const ValueKey('waste-reason-forgot')));
      await tester.tap(find.text('폐기 저장'));
      await settlePage(tester, const ValueKey('inventory-page'));
      final snapshot = await tester.runAsync(repo.load);
      expect(snapshot!.records.single.wasteReason, WasteReason.forgot);
      expect(snapshot.foods.single.remaining, 0);
      // Detail remains openable from the home summary only while stock exists;
      // use the same detail route with the persisted finished ingredient.
      final navigator = tester.state<NavigatorState>(
        find.byType(Navigator).first,
      );
      navigator.push(
        MaterialPageRoute<void>(
          builder: (_) => FoodDetail(
            repository: repo,
            food: snapshot.foods.single,
            clock: () => today,
          ),
        ),
      );
      await settlePage(tester, const ValueKey('food-detail'));
      await reveal(tester, find.byKey(const ValueKey('detail-shopping-add')));
      await tester.tap(find.byKey(const ValueKey('detail-shopping-add')));
      for (var i = 0; i < 5; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump();
      }
      final shopping = await tester.runAsync(repo.loadShoppingList);
      expect(shopping!.single.name, '우유');
      expect(shopping.single.amount, 1000000);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets('notification opens urgent inventory and excludes later expiry', (
    tester,
  ) async {
    const channel = MethodChannel('recare/urgent_integration_test');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'consumeOpenUrgent') return true;
      return null;
    });
    final service = ReminderService(channel: channel, supported: true);
    addTearDown(() {
      service.dispose();
      messenger.setMockMethodCallHandler(channel, null);
    });
    await tester.runAsync(
      () => repo.save(
        Food(
          id: 'later',
          name: '오래 보관할 재료',
          unit: FoodUnit.piece,
          total: 1000,
          expiry: today.add(const Duration(days: 5)),
          price: null,
          created: today,
        ),
      ),
    );
    await tester.pumpWidget(
      RecareApp(
        automaticCheckIns: false,
        repositoryFactory: () async => repo,
        preferencesFactory: () async =>
            PreferencesStore(p.join(temp.path, 'prefs.json')),
        reminderService: service,
        clock: () => today,
      ),
    );
    await settlePage(tester, const ValueKey('inventory-page'));
    expect(
      tester
          .widget<ChoiceChip>(find.byKey(const ValueKey('inventory-urgent')))
          .selected,
      isTrue,
    );
    expect(find.byKey(const ValueKey('food-milk')), findsOneWidget);
    expect(find.byKey(const ValueKey('food-later')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('inventory-all')));
    await tester.pumpAndSettle();
    await reveal(tester, find.byKey(const ValueKey('food-later')));
    expect(find.byKey(const ValueKey('food-later')), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('detail undo remains active after returning to inventory', (
    tester,
  ) async {
    await launch(tester);
    await tester.tap(find.text('목록'));
    await settlePage(tester, const ValueKey('inventory-page'));
    await tester.tap(find.byKey(const ValueKey('food-milk')));
    await settlePage(tester, const ValueKey('food-detail'));
    await reveal(tester, find.text('먹음 기록'));
    await tester.tap(find.text('먹음 기록'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('portion-2')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('먹음 저장'));
    await settlePage(tester, const ValueKey('food-detail'));
    await tester.tap(find.byType(BackButton));
    await settlePage(tester, const ValueKey('inventory-page'));
    await tester.tap(find.text('실행 취소'));
    await settlePage(tester, const ValueKey('inventory-page'));
    // The page already exists while the async undo and parent refresh run.
    await waitFor(tester, find.text('처리를 되돌렸어요. 재고와 금액을 복원했어요.'));
    expect((await tester.runAsync(repo.load))!.foods.single.remaining, 1000000);
    expect(find.text('1000 ml'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('batch save stays above the keyboard', (tester) async {
    tester.view.physicalSize = const Size(360, 780);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetViewInsets);
    await launch(tester);
    await tester.tap(find.byKey(const ValueKey('open-batch')));
    await settlePage(tester, const ValueKey('batch-page'));
    await tester.tap(find.byKey(const ValueKey('batch-manual')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('batch-name-0')), '토마토');
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    await tester.pumpAndSettle();
    expect(
      tester.getBottomRight(find.byKey(const ValueKey('batch-save'))).dy,
      lessThanOrEqualTo(480),
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
