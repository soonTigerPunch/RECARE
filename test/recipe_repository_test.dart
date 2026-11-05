import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:recare/data/inventory_repository.dart';
import 'package:recare/data/recipe_repository.dart';
import 'package:recare/domain/inventory.dart';
import 'package:recare/domain/recipes.dart';
import 'package:recare/domain/shopping.dart';

void main() {
  sqfliteFfiInit();
  final today = DateTime.utc(2026, 11, 5);
  late Directory temp;
  late String path;
  late InventoryRepository inventory;
  late RecipeRepository repo;
  Food food(String id, {String name = '두부', int days = 0}) => Food(
    id: id,
    name: name,
    unit: FoodUnit.gram,
    total: 300000,
    expiry: today.add(Duration(days: days)),
    price: 1000,
    created: today,
  );
  Recipe recipe([String id = 'r']) => Recipe(
    id: id,
    title: '두부 구이',
    servings: 1,
    minutes: 10,
    reason: '임박 재료',
    ingredients: [
      RecipeIngredient(
        name: '두부',
        kind: RecipeIngredientKind.inventory,
        sourceId: 'i0',
        amount: 150000,
        unit: FoodUnit.gram,
        displayQuantity: '150 g',
        foodIds: ['a', 'b'],
      ),
    ],
    steps: ['익혀요'],
    warnings: ['상태를 확인하세요'],
    generatedAt: today,
  );
  Future<void> reopen() async {
    await inventory.close();
    inventory = await InventoryRepository.open(
      factory: databaseFactoryFfi,
      databasePath: path,
    );
    repo = RecipeRepository(inventory);
  }

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('recare-recipes-');
    path = p.join(temp.path, 'recare.db');
    inventory = await InventoryRepository.open(
      factory: databaseFactoryFfi,
      databasePath: path,
    );
    repo = RecipeRepository(inventory);
  });
  tearDown(() async {
    await inventory.close();
    await temp.delete(recursive: true);
  });
  test(
    'settings and independent favorites survive history cleanup and reopen',
    () async {
      await repo.saveSettings(
        RecipeSettings(
          staples: ['소금'],
          servings: 2,
          maxMinutes: null,
          consentVersion: 1,
        ),
      );
      for (var i = 0; i < 7; i++) {
        await repo.saveRecent(
          RecipeResult(
            requestId: '$i',
            recipes: [recipe('$i')],
            generatedAt: today.add(Duration(seconds: i)),
          ),
        );
      }
      await repo.setFavorite(recipe('0'), true);
      await repo.setFavorite(recipe('0'), true);
      expect((await repo.loadRecent()).map((r) => r.requestId), [
        '6',
        '5',
        '4',
        '3',
        '2',
      ]);
      final saved = await repo.favoriteSavedAt('0');
      await repo.clearRecent();
      await reopen();
      expect((await repo.loadSettings()).staples, ['소금']);
      expect((await repo.loadSettings()).maxMinutes, isNull);
      expect((await repo.loadFavorites()).single.id, '0');
      await repo.setFavorite(recipe('0'), false);
      await repo.restoreFavorite(recipe('0'), saved!);
      expect(await repo.favoriteSavedAt('0'), saved);
    },
  );
  test('favorites enforce limit without evicting saved recipes', () async {
    for (var i = 0; i < 100; i++) {
      await repo.setFavorite(recipe('$i'), true);
    }
    await repo.setFavorite(recipe('0'), true);
    await expectLater(
      repo.setFavorite(recipe('overflow'), true),
      throwsArgumentError,
    );
    expect((await repo.loadFavorites()).length, 100);
    expect(await repo.isFavorite('overflow'), isFalse);
  });
  test('cooking draft is persistent before stock writes and completed retry survives reopen', () async {
    await inventory.save(food('a'));
    final op = await repo.beginCooking(recipe(), today);
    expect(op.state, 'draft');
    expect((await inventory.load()).records, isEmpty);
    expect((await repo.beginCooking(recipe(), today)).id, op.id);
    await reopen();
    final persisted = (await repo.latestCooking('r'))!;
    expect(persisted.id, op.id);
    expect(await repo.completeCooking(op.id, persisted.usages, today), 1);
    await reopen();
    expect(await repo.completeCooking(op.id, persisted.usages, today), 1);
    final snapshot = await inventory.load();
    expect(snapshot.foods.single.remaining, 150000);
    expect(snapshot.records.single.cost, 500);
    expect((await repo.beginCooking(recipe(), today)).state, 'completed');
    expect(
      (await repo.beginCooking(recipe(), today, newRound: true)).id,
      isNot(op.id),
    );
  });
  test('draft accepts explicit replacement and zero omission but requires nonzero save', () async {
    await inventory.save(food('a'));
    await inventory.save(food('other', name: '감자'));
    final op = await repo.beginCooking(recipe(), today);
    final usages = [
      RecipeUsage(food: food('a'), amount: 0),
      RecipeUsage(food: food('other', name: '감자'), amount: 100000),
    ];
    await repo.saveCookingDraft(op.id, usages, today);
    expect(await repo.completeCooking(op.id, usages, today), 1);
    expect(
      (await inventory.load()).foods.firstWhere((f) => f.id == 'a').remaining,
      300000,
    );
    final next = await repo.beginCooking(recipe(), today, newRound: true);
    await repo.saveCookingDraft(next.id, [
      RecipeUsage(food: food('a'), amount: 0),
    ], today);
    await expectLater(
      repo.completeCooking(next.id, [
        RecipeUsage(food: food('a'), amount: 0),
      ], today),
      throwsArgumentError,
    );
  });
  test('cooking does not substitute unlinked same-name stock', () async {
    await inventory.save(food('same-name'));
    final op = await repo.beginCooking(recipe(), today);
    expect(op.usages, isEmpty);
    await expectLater(
      repo.completeCooking(op.id, op.usages, today),
      throwsArgumentError,
    );
    expect((await inventory.load()).records, isEmpty);
  });
  test(
    'changed day, name, quantity, unit and expiry reject stale cooking',
    () async {
      await inventory.save(food('a'));
      final op = await repo.beginCooking(recipe(), today);
      await expectLater(
        repo.completeCooking(
          op.id,
          op.usages,
          today.add(const Duration(days: 1)),
        ),
        throwsArgumentError,
      );
      for (final changes in [
        {'name': '다른 두부'},
        {'expiry': '2026-11-06'},
        {'remaining': 200000},
        {'unit': 'KG'},
      ]) {
        await inventory.database.update(
          'foods',
          changes,
          where: 'id = ?',
          whereArgs: ['a'],
        );
        await expectLater(
          repo.completeCooking(op.id, op.usages, today),
          throwsArgumentError,
        );
        await inventory.database.update(
          'foods',
          food('a').toRow(),
          where: 'id = ?',
          whereArgs: ['a'],
        );
      }
      expect((await inventory.load()).records, isEmpty);
    },
  );
  test(
    'mid-batch cooking DB failure rolls back inventory records costs and state',
    () async {
      await inventory.save(food('a'));
      await inventory.save(food('b'));
      final op = await repo.beginCooking(recipe(), today);
      final usages = [
        RecipeUsage(food: food('a'), amount: 100000),
        RecipeUsage(food: food('b'), amount: 100000),
      ];
      await repo.saveCookingDraft(op.id, usages, today);
      await inventory.database.execute(
        "CREATE TRIGGER fail_second BEFORE UPDATE ON foods WHEN NEW.id = 'b' BEGIN SELECT RAISE(ABORT, 'injected'); END",
      );
      await expectLater(
        repo.completeCooking(op.id, usages, today),
        throwsA(isA<DatabaseException>()),
      );
      final snapshot = await inventory.load();
      expect(snapshot.foods.every((f) => f.remaining == 300000), isTrue);
      expect(snapshot.records, isEmpty);
      expect((await repo.latestCooking('r'))!.state, 'draft');
    },
  );
  test(
    'undo is all-or-nothing latest-only and preserves voided records',
    () async {
      await inventory.save(food('a'));
      await inventory.save(food('b'));
      final op = await repo.beginCooking(recipe(), today);
      final usages = [
        RecipeUsage(food: food('a'), amount: 100000),
        RecipeUsage(food: food('b'), amount: 100000),
      ];
      await repo.saveCookingDraft(op.id, usages, today);
      await repo.completeCooking(op.id, usages, today);
      await inventory.process(
        foodId: 'b',
        kind: ActionKind.eat,
        amount: 10000,
        unit: FoodUnit.gram,
        date: today,
        requestId: 'later',
        today: today,
      );
      expect(await repo.undoCooking(op.id), isFalse);
      expect(
        (await inventory.load()).foods.firstWhere((f) => f.id == 'a').remaining,
        200000,
      );
      await inventory.undoProcess('later');
      await inventory.database.execute(
        "CREATE TRIGGER fail_undo BEFORE UPDATE ON foods WHEN NEW.id = 'b' BEGIN SELECT RAISE(ABORT, 'injected'); END",
      );
      await expectLater(
        repo.undoCooking(op.id),
        throwsA(isA<DatabaseException>()),
      );
      expect(
        (await inventory.load()).foods.firstWhere((f) => f.id == 'a').remaining,
        200000,
      );
      await inventory.database.execute('DROP TRIGGER fail_undo');
      expect(await repo.undoCooking(op.id), isTrue);
      expect(await repo.undoCooking(op.id), isFalse);
      expect((await inventory.load()).records, isEmpty);
      expect(
        (await inventory.database.query('records', where: 'voided = 1')).length,
        3,
      );
      await expectLater(
        repo.completeCooking(op.id, usages, today),
        throwsArgumentError,
      );
    },
  );
  test(
    'shopping batch is atomic idempotent and distinguishes duplicates',
    () async {
      ShoppingItem item(String id, String name) => ShoppingItem(
        id: id,
        name: name,
        unit: FoodUnit.gram,
        amount: 1000,
        created: today,
      );
      await inventory.addShoppingItem(item('old', '소금'));
      final items = [item('a', '소금'), item('b', '설탕')];
      final first = await repo.addShoppingBatch('batch', items);
      expect([first.added, first.existing], [1, 1]);
      await reopen();
      final retry = await repo.addShoppingBatch('batch', items);
      expect([retry.added, retry.existing], [1, 1]);
      expect((await inventory.loadShoppingList()).length, 2);
      await expectLater(
        repo.addShoppingBatch('batch', [item('changed', '후추')]),
        throwsArgumentError,
      );
      await inventory.database.execute(
        "CREATE TRIGGER fail_shopping BEFORE INSERT ON shopping_items WHEN NEW.name = '후추' BEGIN SELECT RAISE(ABORT, 'injected'); END",
      );
      await expectLater(
        repo.addShoppingBatch('bad', [item('c', '간장'), item('d', '후추')]),
        throwsA(isA<DatabaseException>()),
      );
      expect((await inventory.loadShoppingList()).length, 2);
    },
  );
  test('generic session values delete and survive reopen', () async {
    await repo.saveValue('auth', 'token');
    await reopen();
    expect(await repo.loadValue('auth'), 'token');
    await repo.saveValue('auth', null);
    expect(await repo.loadValue('auth'), isNull);
  });
  test('only explicit draft reconfirmation can rebase a cooking day', () async {
    await inventory.save(food('a', days: 2));
    final op = await repo.beginCooking(recipe(), today);
    final tomorrow = today.add(const Duration(days: 1));
    await expectLater(
      repo.completeCooking(op.id, op.usages, tomorrow),
      throwsArgumentError,
    );
    await repo.saveCookingDraft(op.id, op.usages, tomorrow);
    expect((await repo.latestCooking('r'))!.day, tomorrow);
    expect(await repo.completeCooking(op.id, op.usages, tomorrow), 1);
  });
  test('individual undo cannot split a completed recipe operation', () async {
    await inventory.save(food('a'));
    final op = await repo.beginCooking(recipe(), today);
    await repo.completeCooking(op.id, op.usages, today);
    final recordId = (await inventory.load()).records.single.id;
    expect(await inventory.undoProcess(recordId), isFalse);
    expect((await inventory.load()).foods.single.remaining, 150000);
    expect(await repo.undoCooking(op.id), isTrue);
  });
  for (final version in [1, 2, 3]) {
    test(
      'v$version migration preserves inventory records and prior feature tables',
      () async {
        await inventory.close();
        await File('test/fixtures/kotlin_v1.db').copy(path);
        final db = await databaseFactoryFfi.openDatabase(path);
        if (version >= 2) {
          await db.execute('ALTER TABLE records ADD COLUMN waste_reason TEXT');
          await db.execute(
            'ALTER TABLE records ADD COLUMN voided INTEGER NOT NULL DEFAULT 0',
          );
          await db.execute(
            'CREATE TABLE shopping_items (id TEXT PRIMARY KEY,name TEXT NOT NULL,unit TEXT NOT NULL,amount INTEGER NOT NULL,created TEXT NOT NULL,normalized_key TEXT NOT NULL UNIQUE)',
          );
          await db.insert(
            'shopping_items',
            ShoppingItem(
              id: 'shop',
              name: '두부',
              unit: FoodUnit.gram,
              amount: 1000,
              created: today,
            ).toRow(),
          );
        }
        if (version >= 3) {
          await db.execute(
            'CREATE TABLE expiry_check_ins (food_id TEXT NOT NULL REFERENCES foods(id) ON DELETE CASCADE,expiry TEXT NOT NULL,day TEXT NOT NULL,outcome TEXT NOT NULL,record_id TEXT,request_id TEXT NOT NULL UNIQUE,PRIMARY KEY(food_id,expiry,day))',
          );
          await db.insert('expiry_check_ins', {
            'food_id': 'milk',
            'expiry': '2026-10-12',
            'day': '2026-10-12',
            'outcome': 'none',
            'request_id': 'answer',
          });
        }
        await db.setVersion(version);
        await db.close();
        inventory = await InventoryRepository.open(
          factory: databaseFactoryFfi,
          databasePath: path,
        );
        repo = RecipeRepository(inventory);
        expect(await inventory.database.getVersion(), 4);
        final snapshot = await inventory.load();
        expect(snapshot.foods.length, 3);
        expect(snapshot.records.single.cost, 750);
        if (version >= 2) {
          expect((await inventory.loadShoppingList()).single.id, 'shop');
        }
        if (version >= 3) {
          expect(
            (await inventory.database.query('expiry_check_ins'))
                .single['request_id'],
            'answer',
          );
        }
        await repo.setFavorite(recipe(), true);
        expect((await repo.loadFavorites()).single.id, 'r');
      },
    );
  }
}
