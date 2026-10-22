import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:recare/data/inventory_repository.dart';
import 'package:recare/domain/expiry_check_in.dart';
import 'package:recare/domain/inventory.dart';
import 'package:recare/domain/shopping.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  final today = DateTime(2026, 10, 21);
  late Directory temp;
  late String path;
  late InventoryRepository repo;
  Food food(String id, {int days = 3, int total = 3000}) => Food(
    id: id,
    name: id,
    unit: FoodUnit.ml,
    total: total,
    expiry: today.add(Duration(days: days)),
    price: 100,
    created: today,
  );
  Future<bool> answer(
    Food value,
    CheckInAnswer choice,
    String request, {
    DateTime? day,
  }) => repo.answerExpiryCheckIn(
    food: value,
    today: day ?? today,
    answer: choice,
    requestId: request,
  );
  Future<void> reopen() async {
    await repo.close();
    repo = await InventoryRepository.open(
      factory: databaseFactoryFfi,
      databasePath: path,
    );
  }

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('recare-check-in-');
    path = '${temp.path}/recare.db';
    repo = await InventoryRepository.open(
      factory: databaseFactoryFfi,
      databasePath: path,
    );
  });
  tearDown(() async {
    await repo.close();
    await temp.delete(recursive: true);
  });
  test(
    'pending only lists milestones with stock in expiry name order',
    () async {
      for (final days in [-1, 0, 1, 2, 3, 4]) {
        await repo.save(food('day$days', days: days));
      }
      expect((await repo.pendingExpiryCheckIns(today)).map((f) => f.id), [
        'day0',
        'day1',
        'day3',
      ]);
      await expectLater(
        answer(food('day2', days: 2), CheckInAnswer.skip, 'bad'),
        throwsArgumentError,
      );
      expect((await repo.pendingExpiryCheckIns(today)).length, 3);
    },
  );
  test('skip survives restart suppresses only same day and does not restrict deletion', () async {
    final value = food('a');
    await repo.save(value);
    expect(await answer(value, CheckInAnswer.skip, 'skip'), isTrue);
    expect(await answer(value, CheckInAnswer.skip, 'skip'), isFalse);
    await reopen();
    expect(await repo.pendingExpiryCheckIns(today), isEmpty);
    expect((await repo.load()).foods.single.remaining, 3000);
    expect(await repo.hasProcessingHistory('a'), isFalse);
    expect(
      (await repo.pendingExpiryCheckIns(today.add(const Duration(days: 2))))
          .single
          .id,
      'a',
    );
    await repo.deleteFood('a');
    final db = await databaseFactoryFfi.openDatabase(path);
    expect(await db.query('expiry_check_ins'), isEmpty);
  });
  test(
    'fraction records eaten amount and rounding and undo retains suppression',
    () async {
      final value = food('a', total: 4000);
      await repo.save(value);
      expect(await answer(value, CheckInAnswer.twoThirds, 'eat'), isTrue);
      final snapshot = await repo.load();
      expect(snapshot.foods.single.remaining, 1333);
      expect(snapshot.records.single.amount, 2667);
      expect(snapshot.records.single.kind, ActionKind.eat);
      expect(snapshot.records.single.cost, 67);
      expect(await answer(value, CheckInAnswer.all, 'retry'), isFalse);
      expect(await repo.undoProcess('eat'), isTrue);
      expect(await repo.pendingExpiryCheckIns(today), isEmpty);
    },
  );
  test(
    'stale remaining expiry and deleted items reject without marking',
    () async {
      final value = food('a');
      await repo.save(value);
      await repo.process(
        foodId: 'a',
        kind: ActionKind.eat,
        amount: 1000,
        unit: FoodUnit.ml,
        date: today,
        requestId: 'old',
        today: today,
      );
      await expectLater(
        answer(value, CheckInAnswer.half, 'stale'),
        throwsArgumentError,
      );
      expect((await repo.pendingExpiryCheckIns(today)).length, 1);
      final fresh = (await repo.load()).foods.single;
      await repo.save(
        Food(
          id: fresh.id,
          name: fresh.name,
          unit: fresh.unit,
          total: fresh.total,
          remaining: fresh.remaining,
          expiry: today,
          price: fresh.price,
          created: fresh.created,
        ),
      );
      await expectLater(
        answer(fresh, CheckInAnswer.none, 'expiry'),
        throwsArgumentError,
      );
      await expectLater(
        answer(food('missing'), CheckInAnswer.skip, 'deleted'),
        throwsArgumentError,
      );
    },
  );
  test('reused request IDs never mark or modify another food or day', () async {
    final a = food('a');
    final b = food('b');
    await repo.saveBatch([a, b]);
    await answer(a, CheckInAnswer.none, 'shared');
    await expectLater(
      answer(b, CheckInAnswer.half, 'shared'),
      throwsArgumentError,
    );
    await expectLater(
      answer(
        a,
        CheckInAnswer.skip,
        'shared',
        day: today.add(const Duration(days: 2)),
      ),
      throwsArgumentError,
    );
    await repo.process(
      foodId: 'b',
      kind: ActionKind.eat,
      amount: 1000,
      unit: FoodUnit.ml,
      date: today,
      requestId: 'existing',
      today: today,
    );
    final fresh = (await repo.load()).foods.firstWhere((f) => f.id == 'b');
    await expectLater(
      answer(fresh, CheckInAnswer.half, 'existing'),
      throwsArgumentError,
    );
    expect((await repo.pendingExpiryCheckIns(today)).single.id, 'b');
  });
  test(
    'late check-in insertion failure rolls back eaten record and quantity',
    () async {
      final value = food('a');
      await repo.save(value);
      final db = await databaseFactoryFfi.openDatabase(path);
      await db.execute(
        "CREATE TRIGGER reject_check_in BEFORE INSERT ON expiry_check_ins BEGIN SELECT RAISE(ABORT, 'failure'); END",
      );
      await expectLater(
        answer(value, CheckInAnswer.all, 'fail'),
        throwsA(isA<DatabaseException>()),
      );
      final snapshot = await repo.load();
      expect(snapshot.foods.single.remaining, 3000);
      expect(snapshot.records, isEmpty);
      expect((await repo.pendingExpiryCheckIns(today)).single.id, 'a');
    },
  );
  test('v2 upgrade preserves shopping active records and tombstones', () async {
    final value = food('a');
    await repo.save(value);
    await repo.addShoppingItem(
      ShoppingItem(
        id: 's',
        name: '당근',
        unit: FoodUnit.gram,
        amount: 1000,
        created: today,
      ),
    );
    await repo.process(
      foodId: 'a',
      kind: ActionKind.waste,
      amount: 1000,
      unit: FoodUnit.ml,
      date: today,
      requestId: 'record',
      today: today,
      wasteReason: WasteReason.forgot,
    );
    await repo.undoProcess('record');
    await repo.close();
    final db = await databaseFactoryFfi.openDatabase(path);
    await db.execute('DROP TABLE IF EXISTS expiry_check_ins');
    await db.setVersion(2);
    await db.close();
    repo = await InventoryRepository.open(
      factory: databaseFactoryFfi,
      databasePath: path,
    );
    expect((await repo.load()).foods.single.remaining, 3000);
    expect(await repo.hasProcessingHistory('a'), isTrue);
    expect((await repo.loadShoppingList()).single.id, 's');
    expect(await answer(value, CheckInAnswer.none, 'none'), isTrue);
  });
  test('v1 fixture upgrades directly to v3 and retains old data', () async {
    await repo.close();
    await File('test/fixtures/kotlin_v1.db').copy(path);
    repo = await InventoryRepository.open(
      factory: databaseFactoryFfi,
      databasePath: path,
    );
    expect((await repo.load()).foods.length, 3);
    expect((await repo.load()).records.single.cost, 750);
    final db = await databaseFactoryFfi.openDatabase(path);
    expect(await db.getVersion(), 3);
    expect(await db.query('expiry_check_ins'), isEmpty);
  });
  test(
    'bulk check-in rolls back earlier consumption when a later item is stale',
    () async {
      final first = food('first');
      final second = food('second');
      await repo.save(first);
      await repo.save(second);
      await repo.process(
        foodId: second.id,
        kind: ActionKind.eat,
        amount: 1000,
        unit: second.unit,
        date: today,
        requestId: 'other',
        today: today,
      );
      await expectLater(
        repo.answerExpiryCheckIns(
          today: today,
          answers: [
            (food: first, answer: CheckInAnswer.half, requestId: 'bulk-first'),
            (
              food: second,
              answer: CheckInAnswer.half,
              requestId: 'bulk-second',
            ),
          ],
        ),
        throwsArgumentError,
      );
      final snapshot = await repo.load();
      expect(
        snapshot.foods.firstWhere((f) => f.id == first.id).remaining,
        first.total,
      );
      expect(snapshot.records.map((r) => r.id), ['other']);
      expect((await repo.pendingExpiryCheckIns(today)).length, 2);
      final latest = snapshot.foods.firstWhere((f) => f.id == second.id);
      await repo.answerExpiryCheckIns(
        today: today,
        answers: [
          (food: first, answer: CheckInAnswer.half, requestId: 'bulk-first'),
          (food: latest, answer: CheckInAnswer.skip, requestId: 'bulk-second'),
        ],
      );
      expect(await repo.pendingExpiryCheckIns(today), isEmpty);
      expect(
        (await repo.load()).foods.firstWhere((f) => f.id == first.id).remaining,
        1500,
      );
    },
  );
}
