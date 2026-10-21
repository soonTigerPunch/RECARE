import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:recare/data/inventory_repository.dart';
import 'package:recare/data/preferences.dart';
import 'package:recare/domain/inventory.dart';
import 'package:recare/main.dart';
import 'package:recare/services/reminder_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'widget_test.dart' show waitFor, settlePage, reveal;

void main() {
  sqfliteFfiInit();
  final today = DateTime(2026, 10, 21);
  late Directory temp;
  late InventoryRepository repo;
  setUp(() async {
    temp = await Directory.systemTemp.createTemp('recare-checkin-ui-');
    repo = await InventoryRepository.open(
      factory: databaseFactoryFfi,
      databasePath: '${temp.path}/recare.db',
    );
    await repo.save(
      Food(
        id: 'milk',
        name: '우유',
        unit: FoodUnit.ml,
        total: 900000,
        expiry: today.add(const Duration(days: 3)),
        price: 3000,
        created: today,
      ),
    );
  });
  tearDown(() async {
    await repo.close();
    await temp.delete(recursive: true);
  });
  Future<void> launch(WidgetTester tester, {ReminderService? service}) async {
    await tester.pumpWidget(
      RecareApp(
        repositoryFactory: () async => repo,
        preferencesFactory: () async =>
            PreferencesStore('${temp.path}/prefs.json'),
        reminderService: service,
        clock: () => today,
      ),
    );
    await settlePage(tester, const ValueKey('home-page'));
  }

  Future<void> waitClosed(WidgetTester tester) async {
    for (var i = 0; i < 100; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 15)),
      );
      await tester.pump(const Duration(milliseconds: 50));
      if (find.byKey(const ValueKey('expiry-check-in')).evaluate().isEmpty) {
        break;
      }
    }
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('expiry-check-in')), findsNothing);
  }

  testWidgets(
    'ordinary launch asks about due food and two-thirds saves real consumption',
    (tester) async {
      await launch(tester);
      expect(find.byKey(const ValueKey('expiry-check-in')), findsOneWidget);
      expect(find.text('이 식재료의 소비기한이 임박했어요! 얼마나 소비하셨나요?'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('check-in-twoThirds')));
      await tester.pumpAndSettle();
      expect(find.text('소비량 600 ml · 남을 재고 300 ml'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('check-in-save')));
      await waitClosed(tester);
      final snapshot = (await tester.runAsync(repo.load))!;
      expect(snapshot.foods.single.remaining, 300000);
      expect(snapshot.records.single.kind, ActionKind.eat);
      expect(snapshot.records.single.cost, 2000);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets('skip survives app restart without changing stock or records', (
    tester,
  ) async {
    await launch(tester);
    await tester.tap(find.byKey(const ValueKey('check-in-skip')));
    await waitClosed(tester);
    expect((await tester.runAsync(repo.load))!.records, isEmpty);
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(() async {
      repo = await InventoryRepository.open(
        factory: databaseFactoryFfi,
        databasePath: '${temp.path}/recare.db',
      );
    });
    await launch(tester);
    expect(find.byKey(const ValueKey('expiry-check-in')), findsNothing);
    expect((await tester.runAsync(repo.load))!.foods.single.remaining, 900000);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets(
    'notification entry shows the same check-in even with a cold app',
    (tester) async {
      const channel = MethodChannel('recare/checkin-test');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            channel,
            (call) async => call.method == 'consumeOpenUrgent' ? true : null,
          );
      final service = ReminderService(channel: channel, supported: true);
      addTearDown(() {
        service.dispose();
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null);
      });
      await tester.pumpWidget(
        RecareApp(
          repositoryFactory: () async => repo,
          preferencesFactory: () async =>
              PreferencesStore('${temp.path}/prefs.json'),
          reminderService: service,
          clock: () => today,
        ),
      );
      await waitFor(tester, find.byKey(const ValueKey('expiry-check-in')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('expiry-check-in')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('check-in-none')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('check-in-save')));
      await waitClosed(tester);
      expect((await tester.runAsync(repo.load))!.records, isEmpty);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets('small screen with large text keeps skip and save accessible', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 1.4;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await launch(tester);
    await reveal(tester, find.byKey(const ValueKey('check-in-half')));
    await tester.tap(find.byKey(const ValueKey('check-in-half')));
    await tester.pumpAndSettle();
    await reveal(tester, find.byKey(const ValueKey('check-in-save')));
    expect(tester.takeException(), isNull);
    await tester.tap(find.byKey(const ValueKey('check-in-skip-all')));
    await waitClosed(tester);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets(
    'multiple groceries appear sequentially in expiry order and skip only current',
    (tester) async {
      await tester.runAsync(
        () => repo.save(
          Food(
            id: 'tofu',
            name: '두부',
            unit: FoodUnit.piece,
            total: 2000,
            expiry: today,
            price: 2000,
            created: today,
          ),
        ),
      );
      await launch(tester);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('expiry-check-in')),
          matching: find.text('두부'),
        ),
        findsOneWidget,
      );
      expect(find.text('1 / 2 · 소비기한 당일'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('check-in-half')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('check-in-save')));
      await waitFor(tester, find.text('2 / 2 · 소비기한 3일 전'));
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('expiry-check-in')),
          matching: find.text('우유'),
        ),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('expiry-check-in')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('check-in-skip')));
      await waitClosed(tester);
      final snapshot = (await tester.runAsync(repo.load))!;
      expect(
        snapshot.foods.firstWhere((food) => food.id == 'tofu').remaining,
        1000,
      );
      expect(
        snapshot.foods.firstWhere((food) => food.id == 'milk').remaining,
        900000,
      );
      expect(snapshot.records.single.foodId, 'tofu');
      expect(
        (await tester.runAsync(() => repo.pendingExpiryCheckIns(today)))!,
        isEmpty,
      );
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'resuming on the next milestone opens one popup while inactive days do not',
    (tester) async {
      var now = today.add(const Duration(days: 1)); // milk D-2
      await tester.pumpWidget(
        RecareApp(
          repositoryFactory: () async => repo,
          preferencesFactory: () async =>
              PreferencesStore('${temp.path}/prefs.json'),
          clock: () => now,
        ),
      );
      await settlePage(tester, const ValueKey('home-page'));
      expect(find.byKey(const ValueKey('expiry-check-in')), findsNothing);
      now = today.add(const Duration(days: 2)); // milk D-1
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await waitFor(tester, find.byKey(const ValueKey('expiry-check-in')));
      await tester.pumpAndSettle();
      expect(find.text('1 / 1 · 소비기한 1일 전'), findsOneWidget);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await settlePage(tester, const ValueKey('home-page'));
      expect(find.byKey(const ValueKey('expiry-check-in')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('check-in-skip-all')));
      await waitClosed(tester);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'deferred popup opens when returning from a subroute after resume',
    (tester) async {
      var now = today.add(const Duration(days: 1));
      await tester.pumpWidget(
        RecareApp(
          repositoryFactory: () async => repo,
          preferencesFactory: () async =>
              PreferencesStore('${temp.path}/prefs.json'),
          clock: () => now,
        ),
      );
      await settlePage(tester, const ValueKey('home-page'));
      await reveal(tester, find.text('폐기 내역'));
      await tester.tap(find.text('폐기 내역'));
      await settlePage(tester, const ValueKey('weekly-page'));
      now = today.add(const Duration(days: 2));
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('expiry-check-in')), findsNothing);
      await tester.tap(find.byType(BackButton));
      await waitFor(tester, find.byKey(const ValueKey('expiry-check-in')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('expiry-check-in')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('check-in-skip-all')));
      await waitClosed(tester);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'foreground midnight transition prompts the newly due milestone',
    (tester) async {
      var now = today.add(const Duration(days: 1, hours: 23, minutes: 59));
      await tester.pumpWidget(
        RecareApp(
          repositoryFactory: () async => repo,
          preferencesFactory: () async =>
              PreferencesStore('${temp.path}/prefs.json'),
          clock: () => now,
        ),
      );
      await settlePage(tester, const ValueKey('home-page'));
      now = today.add(const Duration(days: 2));
      await tester.pump(const Duration(minutes: 1));
      await waitFor(tester, find.byKey(const ValueKey('expiry-check-in')));
      await tester.pumpAndSettle();
      expect(find.text('1 / 1 · 소비기한 1일 전'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('check-in-skip-all')));
      await waitClosed(tester);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
