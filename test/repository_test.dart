import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:recare/data/inventory_repository.dart';
import 'package:recare/domain/inventory.dart';

void main() {
  sqfliteFfiInit();
  late Directory temp;
  late InventoryRepository repo;
  late String databasePath;
  final today = DateTime(2026, 10, 12);
  Food milk([int? price = 3000]) => Food(
    id: 'milk',
    name: '우유',
    unit: FoodUnit.litre,
    total: 1000000,
    expiry: today,
    price: price,
    created: today,
  );
  setUp(() async {
    temp = await Directory.systemTemp.createTemp('recare-flutter-test-');
    databasePath = p.join(temp.path, 'recare.db');
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
  Future<void> waste({int amount = 250000, String request = 'waste'}) =>
      repo.process(
        foodId: 'milk',
        kind: ActionKind.waste,
        amount: amount,
        unit: FoodUnit.ml,
        date: today,
        requestId: request,
        today: today,
      );
  test('reopening preserves inventory and history', () async {
    await repo.save(milk());
    await waste();
    await repo.close();
    repo = await InventoryRepository.open(
      factory: databaseFactoryFfi,
      databasePath: databasePath,
    );
    final snapshot = await repo.load();
    expect(snapshot.foods.single.remaining, 750000);
    expect(snapshot.records.single.cost, 750);
    expect(weeklyWaste(snapshot.records, today).knownTotal, 750);
  });
  test('duplicate request never decrements twice', () async {
    await repo.save(milk());
    await waste();
    await waste();
    final snapshot = await repo.load();
    expect(snapshot.foods.single.remaining, 750000);
    expect(snapshot.records.length, 1);
  });
  test('overdraw keeps inventory and records unchanged', () async {
    await repo.save(milk());
    await expectLater(waste(amount: 2000000), throwsArgumentError);
    final snapshot = await repo.load();
    expect(snapshot.foods.single.remaining, 1000000);
    expect(snapshot.records, isEmpty);
  });
  test(
    'database failure rolls back record insertion and inventory update',
    () async {
      await repo.save(milk());
      final db = await databaseFactoryFfi.openDatabase(databasePath);
      await db.execute(
        "CREATE TRIGGER reject_inventory BEFORE UPDATE ON foods BEGIN SELECT RAISE(ABORT, 'injected failure'); END",
      );
      await expectLater(waste(), throwsA(isA<DatabaseException>()));
      final snapshot = await repo.load();
      expect(snapshot.foods.single.remaining, 1000000);
      expect(snapshot.records, isEmpty);
    },
  );
  test('editing respects historical quantity price and name', () async {
    await repo.save(milk());
    await repo.save(
      Food(
        id: 'milk',
        name: '우유',
        unit: FoodUnit.litre,
        total: 2000000,
        expiry: today,
        price: 6000,
        created: today,
      ),
    );
    await waste();
    await repo.save(
      Food(
        id: 'milk',
        name: '저지방 우유',
        unit: FoodUnit.litre,
        total: 2000000,
        remaining: 1750000,
        expiry: today,
        price: 6000,
        created: today,
      ),
    );
    final snapshot = await repo.load();
    expect(snapshot.foods.single.name, '저지방 우유');
    expect(snapshot.records.single.foodName, '우유');
    expect(snapshot.records.single.cost, 750);
    await expectLater(
      repo.save(
        Food(
          id: 'milk',
          name: '우유',
          unit: FoodUnit.litre,
          total: 2000000,
          remaining: 1750000,
          expiry: today,
          price: 9000,
          created: today,
        ),
      ),
      throwsArgumentError,
    );
  });
  test(
    'unprocessed deletion persists and preserves other food history',
    () async {
      await repo.save(milk());
      await repo.save(
        Food(
          id: 'other',
          name: '요거트',
          unit: FoodUnit.piece,
          total: 2000,
          expiry: today,
          price: 2000,
          created: today,
        ),
      );
      await repo.process(
        foodId: 'other',
        kind: ActionKind.waste,
        amount: 1000,
        unit: FoodUnit.piece,
        date: today,
        requestId: 'other-waste',
        today: today,
      );
      await repo.deleteFood('milk');
      await repo.close();
      repo = await InventoryRepository.open(
        factory: databaseFactoryFfi,
        databasePath: databasePath,
      );
      final snapshot = await repo.load();
      expect(snapshot.foods.single.id, 'other');
      expect(snapshot.foods.single.remaining, 1000);
      expect(snapshot.records.single.foodId, 'other');
      expect(weeklyWaste(snapshot.records, today).knownTotal, 1000);
    },
  );
  test('deleting missing or already deleted food is idempotent', () async {
    await repo.deleteFood('missing');
    await repo.save(milk());
    await repo.deleteFood('milk');
    await repo.deleteFood('milk');
    final snapshot = await repo.load();
    expect(snapshot.foods, isEmpty);
    expect(snapshot.records, isEmpty);
  });
  for (final kind in ActionKind.values) {
    test(
      '${kind.code} history blocks deletion without changing totals',
      () async {
        await repo.save(milk());
        await repo.process(
          foodId: 'milk',
          kind: kind,
          amount: 250000,
          unit: FoodUnit.ml,
          date: today,
          requestId: 'record',
          today: today,
        );
        final before = await repo.load();
        await expectLater(
          repo.deleteFood('milk'),
          throwsA(
            isA<ArgumentError>().having(
              (error) => error.message,
              'message',
              contains('처리 기록을 보존'),
            ),
          ),
        );
        final after = await repo.load();
        expect(after.foods.single.toRow(), before.foods.single.toRow());
        expect(after.records.single.toRow(), before.records.single.toRow());
        expect(
          weeklyWaste(after.records, today).knownTotal,
          weeklyWaste(before.records, today).knownTotal,
        );
      },
    );
  }
  test('unentered price survives reopening', () async {
    await repo.save(milk(null));
    await repo.close();
    repo = await InventoryRepository.open(
      factory: databaseFactoryFfi,
      databasePath: databasePath,
    );
    expect((await repo.load()).foods.single.price, isNull);
  });
  test(
    'existing Kotlin version 1 fixture opens without resetting records',
    () async {
      await repo.close();
      await File('test/fixtures/kotlin_v1.db').copy(databasePath);
      repo = await InventoryRepository.open(
        factory: databaseFactoryFfi,
        databasePath: databasePath,
      );
      final snapshot = await repo.load();
      expect(snapshot.foods.length, 3);
      expect(
        snapshot.foods.firstWhere((f) => f.id == 'milk').remaining,
        750000,
      );
      expect(snapshot.foods.firstWhere((f) => f.id == 'unknown').price, isNull);
      expect(snapshot.foods.firstWhere((f) => f.id == 'free').price, 0);
      expect(snapshot.records.single.cost, 750);
      await waste(amount: 250000, request: 'flutter-waste');
      final migrated = await repo.load();
      expect(
        migrated.foods.firstWhere((f) => f.id == 'milk').remaining,
        500000,
      );
      expect(migrated.records.length, 2);
    },
  );
}
