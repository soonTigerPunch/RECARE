import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:recare/data/inventory_repository.dart';
import 'package:recare/domain/inventory.dart';
import 'package:recare/domain/shopping.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  final today = DateTime(2026, 10, 21);
  late Directory temp;
  late InventoryRepository repo;
  Food food(String id, {int? remaining}) => Food(
    id: id,
    name: '우유',
    unit: FoodUnit.ml,
    total: 3000,
    remaining: remaining,
    expiry: today,
    price: 100,
    created: today,
  );
  ShoppingItem item(String id, {FoodUnit unit = FoodUnit.ml}) => ShoppingItem(
    id: id,
    name: '우유',
    unit: unit,
    amount: 1000000,
    created: today,
  );
  Future<void> process(String id, {DateTime? date}) => repo.process(
    foodId: 'milk',
    kind: ActionKind.waste,
    amount: 1000,
    unit: FoodUnit.ml,
    date: date ?? today,
    requestId: id,
    today: today,
    wasteReason: WasteReason.forgot,
  );
  setUp(() async {
    temp = await Directory.systemTemp.createTemp('recare-usability-');
    repo = await InventoryRepository.open(
      factory: databaseFactoryFfi,
      databasePath: '${temp.path}/recare.db',
    );
  });
  tearDown(() async {
    await repo.close();
    await temp.delete(recursive: true);
  });
  test(
    'undo is latest-insertion only, idempotent, and preserves exact costs',
    () async {
      await repo.save(food('milk'));
      await process('a');
      await process('b', date: today.subtract(const Duration(days: 1)));
      expect(await repo.undoProcess('a'), isFalse);
      expect(await repo.undoProcess('b'), isTrue);
      expect(await repo.undoProcess('b'), isFalse);
      await process('b');
      expect((await repo.load()).foods.single.remaining, 2000);
      await process('c');
      await process('d');
      final snapshot = await repo.load();
      expect(snapshot.records.map((r) => r.cost), [33, 34, 33]);
      expect(
        snapshot.records.every((r) => r.wasteReason == WasteReason.forgot),
        isTrue,
      );
      expect(weeklyWaste(snapshot.records, today).knownTotal, 100);
    },
  );
  test('undone records retain restrictions across reopening', () async {
    await repo.save(food('milk'));
    await process('a');
    expect(await repo.undoProcess('a'), isTrue);
    await repo.close();
    repo = await InventoryRepository.open(
      factory: databaseFactoryFfi,
      databasePath: '${temp.path}/recare.db',
    );
    expect((await repo.load()).records, isEmpty);
    expect(await repo.hasProcessingHistory('milk'), isTrue);
    await expectLater(repo.deleteFood('milk'), throwsArgumentError);
    expect(await repo.undoProcess('missing'), isFalse);
  });
  test('shopping equivalent entries preserve first item and persist', () async {
    await repo.addShoppingItem(item('a'));
    await repo.addShoppingItem(item('b', unit: FoodUnit.litre));
    expect((await repo.loadShoppingList()).single.id, 'a');
    await repo.close();
    repo = await InventoryRepository.open(
      factory: databaseFactoryFfi,
      databasePath: '${temp.path}/recare.db',
    );
    expect((await repo.loadShoppingList()).single.id, 'a');
    await repo.removeShoppingItem('a');
    expect(await repo.loadShoppingList(), isEmpty);
  });
  test(
    'checkout is atomic for stale malformed and duplicate mappings',
    () async {
      await repo.addShoppingItem(item('s'));
      for (final mapping in <Map<String, String>>[
        {'a': 'missing'},
        {'a': ''},
        {'unknown': 's'},
        {'a': 's', 'b': 's'},
      ]) {
        await expectLater(
          repo.saveBatch([
            food('a'),
            food('b'),
          ], shoppingItemsByFoodId: mapping),
          throwsArgumentError,
        );
        expect((await repo.load()).foods, isEmpty);
        expect((await repo.loadShoppingList()).single.id, 's');
      }
      await expectLater(
        repo.saveBatch([food('a'), food('b', remaining: 1000)]),
        throwsArgumentError,
      );
      await repo.saveBatch(
        [food('a'), food('b')],
        shoppingItemsByFoodId: {'a': 's'},
      );
      expect((await repo.load()).foods.length, 2);
      expect(await repo.loadShoppingList(), isEmpty);
      await expectLater(
        repo.saveBatch([food('a'), food('c')]),
        throwsArgumentError,
      );
      expect((await repo.load()).foods.length, 2);
    },
  );
  test('v1 fixture migrates without losing prices records or stock', () async {
    await repo.close();
    await File('test/fixtures/kotlin_v1.db').copy('${temp.path}/recare.db');
    repo = await InventoryRepository.open(
      factory: databaseFactoryFfi,
      databasePath: '${temp.path}/recare.db',
    );
    final snapshot = await repo.load();
    expect(snapshot.foods.length, 3);
    expect(snapshot.records.single.cost, 750);
    expect(snapshot.records.single.wasteReason, isNull);
    expect(await repo.loadShoppingList(), isEmpty);
    await repo.addShoppingItem(item('s'));
  });
  test('database failures roll back checkout and undo together', () async {
    await repo.addShoppingItem(item('s'));
    final db = await databaseFactoryFfi.openDatabase('${temp.path}/recare.db');
    await db.execute(
      "CREATE TRIGGER reject_second BEFORE INSERT ON foods WHEN NEW.id = 'b' BEGIN SELECT RAISE(ABORT, 'failure'); END",
    );
    await expectLater(
      repo.saveBatch([food('a'), food('b')], shoppingItemsByFoodId: {'a': 's'}),
      throwsA(isA<DatabaseException>()),
    );
    expect((await repo.load()).foods, isEmpty);
    expect((await repo.loadShoppingList()).single.id, 's');
    await repo.save(food('milk'));
    await process('a');
    await db.execute(
      "CREATE TRIGGER reject_stock BEFORE UPDATE ON foods BEGIN SELECT RAISE(ABORT, 'failure'); END",
    );
    await expectLater(repo.undoProcess('a'), throwsA(isA<DatabaseException>()));
    final snapshot = await repo.load();
    expect(snapshot.foods.single.remaining, 2000);
    expect(snapshot.records.single.id, 'a');
  });
  test(
    'shopping names normalize case and repeated whitespace without overwriting',
    () async {
      ShoppingItem named(String id, String name, {int amount = 1000000}) =>
          ShoppingItem(
            id: id,
            name: name,
            unit: FoodUnit.ml,
            amount: amount,
            created: today,
          );
      await repo.addShoppingItem(named('a', '  Low   Milk '));
      await repo.addShoppingItem(named('b', 'low milk'));
      expect((await repo.loadShoppingList()).single.name, 'Low   Milk');
      await expectLater(
        repo.addShoppingItem(named('a', '다른 재료')),
        throwsArgumentError,
      );
      await repo.addShoppingItem(named('c', 'low milk', amount: 500000));
      expect((await repo.loadShoppingList()).length, 2);
    },
  );
  test('shopping input rejects malformed identity name and quantity', () {
    expect(() => item(''), throwsArgumentError);
    expect(
      () => ShoppingItem(
        id: 'a',
        name: ' ',
        unit: FoodUnit.ml,
        amount: 1,
        created: today,
      ),
      throwsArgumentError,
    );
    for (final amount in [0, -1, maxQuantity + 1]) {
      expect(
        () => ShoppingItem(
          id: 'a',
          name: '우유',
          unit: FoodUnit.ml,
          amount: amount,
          created: today,
        ),
        throwsArgumentError,
      );
    }
  });
}
