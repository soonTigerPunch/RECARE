import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../domain/inventory.dart';

class InventorySnapshot {
  InventorySnapshot(Iterable<Food> foods, Iterable<FoodRecord> records)
    : foods = List.unmodifiable(foods),
      records = List.unmodifiable(records);
  final List<Food> foods;
  final List<FoodRecord> records;
}

class InventoryRepository {
  InventoryRepository._(this._db);
  final Database _db;

  static Future<InventoryRepository> open({
    String name = 'recare.db',
    DatabaseFactory? factory,
    String? databasePath,
  }) async {
    final driver = factory ?? databaseFactory;
    final path = databasePath ?? p.join(await driver.getDatabasesPath(), name);
    final db = await driver.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 1,
        onConfigure: (db) async {
          await db.execute('PRAGMA foreign_keys = ON');
        },
        onCreate: (db, version) async {
          await db.execute(
            '''CREATE TABLE foods (
          id TEXT PRIMARY KEY, name TEXT NOT NULL, unit TEXT NOT NULL,
          total INTEGER NOT NULL CHECK(total > 0),
          remaining INTEGER NOT NULL CHECK(remaining >= 0 AND remaining <= total),
          expiry TEXT NOT NULL, price INTEGER CHECK(price >= 0), created TEXT NOT NULL)''',
          );
          await db.execute(
            '''CREATE TABLE records (
          id TEXT PRIMARY KEY, food_id TEXT NOT NULL REFERENCES foods(id),
          food_name TEXT NOT NULL, kind TEXT NOT NULL, amount INTEGER NOT NULL CHECK(amount > 0),
          unit TEXT NOT NULL, date TEXT NOT NULL, cost INTEGER CHECK(cost >= 0))''',
          );
          await db.execute('CREATE INDEX records_food ON records(food_id)');
          await db.execute('CREATE INDEX records_date ON records(date, kind)');
        },
        onUpgrade: (db, oldVersion, newVersion) =>
            throw StateError('지원하지 않는 저장 버전입니다. 데이터를 유지하고 업데이트를 확인해주세요.'),
        onDowngrade: (db, oldVersion, newVersion) =>
            throw StateError('저장 버전이 더 높아요. 최신 앱을 사용해주세요.'),
      ),
    );
    return InventoryRepository._(db);
  }

  Future<List<Food>> recentFoods({int limit = 200}) async {
    require(limit > 0 && limit <= 200, '이전 등록 조회 범위를 확인해주세요.');
    final rows = await _db.query(
      'foods',
      orderBy: 'created DESC, rowid DESC',
      limit: limit,
    );
    return List.unmodifiable(rows.map(Food.fromRow));
  }

  Future<InventorySnapshot> load() => _db.transaction((txn) async {
    final foods = await txn.query('foods', orderBy: 'expiry, name');
    final records = await txn.query(
      'records',
      orderBy: 'date DESC, rowid DESC',
    );
    return InventorySnapshot(
      foods.map(Food.fromRow),
      records.map(FoodRecord.fromRow),
    );
  });

  Future<void> save(Food food) => _db.transaction((txn) async {
    final rows = await txn.query(
      'foods',
      where: 'id = ?',
      whereArgs: [food.id],
    );
    if (rows.isEmpty) {
      require(food.remaining == food.total, '새 식재료의 수량을 확인해주세요.');
      await txn.insert('foods', food.toRow());
      return;
    }
    final existing = Food.fromRow(rows.single);
    final records = await txn.query(
      'records',
      columns: ['id'],
      where: 'food_id = ?',
      whereArgs: [food.id],
      limit: 1,
    );
    if (records.isNotEmpty) {
      require(existing.remaining == food.remaining, '재고가 변경됐어요. 다시 확인해주세요.');
      require(
        existing.total == food.total &&
            existing.unit == food.unit &&
            existing.price == food.price,
        '처리 기록이 있는 재료는 이름과 소비기한만 수정할 수 있어요.',
      );
    } else {
      require(food.remaining == food.total, '등록 수량을 확인해주세요.');
    }
    final row = food.toRow()..['created'] = dateText(existing.created);
    final updated = await txn.update(
      'foods',
      row,
      where: 'id = ?',
      whereArgs: [food.id],
    );
    if (updated != 1) throw StateError('식재료 저장에 실패했어요.');
  });

  Future<void> process({
    required String foodId,
    required ActionKind kind,
    required int amount,
    required FoodUnit unit,
    required DateTime date,
    required String requestId,
    required DateTime today,
  }) => _db.transaction((txn) async {
    final duplicate = await txn.query(
      'records',
      columns: ['id'],
      where: 'id = ?',
      whereArgs: [requestId],
      limit: 1,
    );
    if (duplicate.isNotEmpty) return;
    final rows = await txn.query('foods', where: 'id = ?', whereArgs: [foodId]);
    if (rows.isEmpty) throw StateError('식재료를 찾을 수 없어요.');
    final result = processFood(
      Food.fromRow(rows.single),
      kind,
      amount,
      unit,
      date,
      requestId,
      today: today,
    );
    await txn.insert('records', result.record.toRow());
    final updated = await txn.update(
      'foods',
      {'remaining': result.food.remaining},
      where: 'id = ?',
      whereArgs: [foodId],
    );
    if (updated != 1) throw StateError('재고 저장에 실패했어요.');
  });

  Future<void> deleteFood(String foodId) => _db.transaction((txn) async {
    final records = await txn.query(
      'records',
      columns: ['id'],
      where: 'food_id = ?',
      whereArgs: [foodId],
      limit: 1,
    );
    require(
      records.isEmpty,
      '처리 기록을 보존하기 위해 삭제할 수 없어요. 남은 재고는 먹음 또는 폐기로 처리해주세요.',
    );
    await txn.delete('foods', where: 'id = ?', whereArgs: [foodId]);
  });
  Future<void> close() => _db.close();
}
