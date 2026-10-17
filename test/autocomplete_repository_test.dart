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
  late String path;
  final today = DateTime(2026, 10, 17);
  Food item(String id, DateTime created) => Food(
    id: id,
    name: '우유 $id',
    unit: FoodUnit.litre,
    total: 1000000,
    expiry: today,
    price: 3000,
    created: created,
  );
  setUp(() async {
    temp = await Directory.systemTemp.createTemp('recare-history-');
    path = p.join(temp.path, 'recare.db');
    repo = await InventoryRepository.open(
      factory: databaseFactoryFfi,
      databasePath: path,
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
  test(
    'recent registrations are bounded newest first with stable same-day order',
    () async {
      await repo.save(item('older', today.subtract(const Duration(days: 1))));
      await repo.save(item('first', today));
      await repo.save(item('second', today));
      expect((await repo.recentFoods(limit: 2)).map((f) => f.id), [
        'second',
        'first',
      ]);
      await expectLater(repo.recentFoods(limit: 0), throwsArgumentError);
      await expectLater(repo.recentFoods(limit: 201), throwsArgumentError);
    },
  );
  test('finished original quantities survive restart without changing waste history', () async {
    await repo.save(item('done', today));
    await repo.process(
      foodId: 'done',
      kind: ActionKind.waste,
      amount: 1000000,
      unit: FoodUnit.ml,
      date: today,
      requestId: 'waste',
      today: today,
    );
    await repo.close();
    repo = await InventoryRepository.open(
      factory: databaseFactoryFfi,
      databasePath: path,
    );
    final history = await repo.recentFoods();
    expect(history.single.total, 1000000);
    expect(history.single.remaining, 0);
    expect((await repo.load()).records.single.cost, 3000);
  });
  test(
    'deleted unprocessed registrations do not remain as stale suggestions',
    () async {
      await repo.save(item('removed', today));
      await repo.deleteFood('removed');
      expect(await repo.recentFoods(), isEmpty);
    },
  );
}
