import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../domain/inventory.dart';
import '../domain/shopping.dart';
import '../domain/expiry_check_in.dart';

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
        version: 3,
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
          unit TEXT NOT NULL, date TEXT NOT NULL, cost INTEGER CHECK(cost >= 0),
          waste_reason TEXT, voided INTEGER NOT NULL DEFAULT 0 CHECK(voided IN (0, 1)))''',
          );
          await db.execute('CREATE INDEX records_food ON records(food_id)');
          await db.execute('CREATE INDEX records_date ON records(date, kind)');
          await _createShopping(db);
          await _createExpiryCheckIns(db);
        },
        onUpgrade: (db, oldVersion, newVersion) async {
          if (oldVersion < 1 || newVersion > 3) {
            throw StateError('지원하지 않는 저장 버전입니다. 데이터를 유지하고 업데이트를 확인해주세요.');
          }
          if (oldVersion < 2) {
            await db.execute(
              'ALTER TABLE records ADD COLUMN waste_reason TEXT',
            );
            await db.execute(
              'ALTER TABLE records ADD COLUMN voided INTEGER NOT NULL DEFAULT 0 CHECK(voided IN (0, 1))',
            );
            await _createShopping(db);
          }
          if (oldVersion < 3) await _createExpiryCheckIns(db);
        },
        onDowngrade: (db, oldVersion, newVersion) =>
            throw StateError('저장 버전이 더 높아요. 최신 앱을 사용해주세요.'),
      ),
    );
    return InventoryRepository._(db);
  }

  static Future<void> _createShopping(DatabaseExecutor db) => db.execute('''
    CREATE TABLE shopping_items (
      id TEXT PRIMARY KEY, name TEXT NOT NULL, unit TEXT NOT NULL,
      amount INTEGER NOT NULL CHECK(amount > 0), created TEXT NOT NULL,
      normalized_key TEXT NOT NULL UNIQUE)''');

  static Future<void> _createExpiryCheckIns(DatabaseExecutor db) =>
      db.execute('''
    CREATE TABLE expiry_check_ins (
      food_id TEXT NOT NULL REFERENCES foods(id) ON DELETE CASCADE,
      expiry TEXT NOT NULL, day TEXT NOT NULL, outcome TEXT NOT NULL,
      record_id TEXT, request_id TEXT NOT NULL UNIQUE,
      PRIMARY KEY(food_id, expiry, day))''');

  Future<List<Food>> pendingExpiryCheckIns(DateTime today) async {
    final day = dateText(civilDate(today));
    final rows = await _db.rawQuery(
      '''
      SELECT f.* FROM foods f
      WHERE f.remaining > 0 AND NOT EXISTS (
        SELECT 1 FROM expiry_check_ins c
        WHERE c.food_id = f.id AND c.expiry = f.expiry AND c.day = ?)
      ORDER BY f.expiry, f.name''',
      [day],
    );
    return List.unmodifiable(
      rows.map(Food.fromRow).where((food) => isCheckInDay(food, today)),
    );
  }

  Future<bool> answerExpiryCheckIn({
    required Food food,
    required DateTime today,
    required CheckInAnswer answer,
    required String requestId,
  }) => _db.transaction((txn) async {
    require(requestId.trim().isNotEmpty, '답변 요청을 확인해주세요.');
    final day = dateText(civilDate(today));
    final expiry = dateText(food.expiry);
    final existingRequest = await txn.query(
      'expiry_check_ins',
      where: 'request_id = ?',
      whereArgs: [requestId],
      limit: 1,
    );
    if (existingRequest.isNotEmpty) {
      final row = existingRequest.single;
      require(
        row['food_id'] == food.id &&
            row['expiry'] == expiry &&
            row['day'] == day,
        '다른 답변에 사용한 요청이에요. 새로고침 후 다시 답해주세요.',
      );
      return false;
    }
    final existingRecord = await txn.query(
      'records',
      columns: ['id'],
      where: 'id = ?',
      whereArgs: [requestId],
      limit: 1,
    );
    require(existingRecord.isEmpty, '이미 사용한 요청이에요. 새로고침 후 다시 답해주세요.');
    final answered = await txn.query(
      'expiry_check_ins',
      columns: ['food_id'],
      where: 'food_id = ? AND expiry = ? AND day = ?',
      whereArgs: [food.id, expiry, day],
      limit: 1,
    );
    if (answered.isNotEmpty) return false;
    final rows = await txn.query(
      'foods',
      where: 'id = ?',
      whereArgs: [food.id],
    );
    require(rows.isNotEmpty, '재고가 변경됐어요. 새로고침 후 다시 답해주세요.');
    final current = Food.fromRow(rows.single);
    require(
      current.expiry == food.expiry && current.remaining == food.remaining,
      '재고가 변경됐어요. 새로고침 후 다시 답해주세요.',
    );
    require(
      isCheckInDay(current, today),
      '소비기한 확인 날짜가 아니에요. 새로고침 후 다시 확인해주세요.',
    );
    final amount = answer.amount(current.remaining);
    if (amount != null) {
      final result = processFood(
        current,
        ActionKind.eat,
        amount,
        current.unit,
        today,
        requestId,
        today: today,
      );
      await txn.insert('records', result.record.toRow());
      final updated = await txn.update(
        'foods',
        {'remaining': result.food.remaining},
        where: 'id = ?',
        whereArgs: [food.id],
      );
      if (updated != 1) throw StateError('재고 저장에 실패했어요.');
    }
    await txn.insert('expiry_check_ins', {
      'food_id': food.id,
      'expiry': expiry,
      'day': day,
      'outcome': answer.name,
      'record_id': amount == null ? null : requestId,
      'request_id': requestId,
    });
    return true;
  });

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
      where: 'voided = 0',
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
    WasteReason? wasteReason,
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
      wasteReason: wasteReason,
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

  Future<bool> hasProcessingHistory(String foodId) async => (await _db.query(
    'records',
    columns: ['id'],
    where: 'food_id = ?',
    whereArgs: [foodId],
    limit: 1,
  )).isNotEmpty;

  Future<bool> undoProcess(String recordId) => _db.transaction((txn) async {
    final rows = await txn.query(
      'records',
      where: 'id = ? AND voided = 0',
      whereArgs: [recordId],
    );
    if (rows.isEmpty) return false;
    final record = FoodRecord.fromRow(rows.single);
    final latest = await txn.query(
      'records',
      columns: ['id'],
      where: 'food_id = ? AND voided = 0',
      whereArgs: [record.foodId],
      orderBy: 'rowid DESC',
      limit: 1,
    );
    if (latest.single['id'] != recordId) return false;
    final foods = await txn.query(
      'foods',
      where: 'id = ?',
      whereArgs: [record.foodId],
    );
    if (foods.isEmpty) throw StateError('식재료를 찾을 수 없어요.');
    final food = Food.fromRow(foods.single);
    require(
      food.remaining + record.amount <= food.total,
      '재고가 변경됐어요. 다시 확인해주세요.',
    );
    final changed = await txn.update(
      'foods',
      {'remaining': food.remaining + record.amount},
      where: 'id = ?',
      whereArgs: [food.id],
    );
    if (changed != 1) throw StateError('재고 저장에 실패했어요.');
    await txn.update(
      'records',
      {'voided': 1},
      where: 'id = ? AND voided = 0',
      whereArgs: [recordId],
    );
    return true;
  });

  Future<List<ShoppingItem>> loadShoppingList() async => List.unmodifiable(
    (await _db.query(
      'shopping_items',
      orderBy: 'created, rowid',
    )).map(ShoppingItem.fromRow),
  );

  Future<void> addShoppingItem(ShoppingItem item) =>
      _db.transaction((txn) async {
        final sameId = await txn.query(
          'shopping_items',
          where: 'id = ?',
          whereArgs: [item.id],
        );
        if (sameId.isNotEmpty) {
          require(
            sameId.single['normalized_key'] == item.normalizedKey,
            '이미 사용한 장보기 항목이에요.',
          );
          return;
        }
        final duplicate = await txn.query(
          'shopping_items',
          columns: ['id'],
          where: 'normalized_key = ?',
          whereArgs: [item.normalizedKey],
          limit: 1,
        );
        if (duplicate.isNotEmpty) return;
        await txn.insert('shopping_items', item.toRow());
      });

  Future<void> removeShoppingItem(String id) async {
    await _db.delete('shopping_items', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> saveBatch(
    List<Food> foods, {
    Map<String, String> shoppingItemsByFoodId = const {},
  }) => _db.transaction((txn) async {
    require(foods.isNotEmpty, '등록할 식재료를 선택해주세요.');
    final ids = <String>{};
    for (final food in foods) {
      require(
        food.id.trim().isNotEmpty && ids.add(food.id),
        '중복된 식재료 항목을 확인해주세요.',
      );
      // Revalidate before any writes, including subclasses supplied by callers.
      Food.fromRow(food.toRow());
      require(food.remaining == food.total, '새 식재료의 수량을 확인해주세요.');
      final existing = await txn.query(
        'foods',
        columns: ['id'],
        where: 'id = ?',
        whereArgs: [food.id],
        limit: 1,
      );
      require(existing.isEmpty, '이미 등록한 식재료예요.');
    }
    final shoppingIds = <String>{};
    for (final entry in shoppingItemsByFoodId.entries) {
      require(
        ids.contains(entry.key) &&
            entry.value.trim().isNotEmpty &&
            shoppingIds.add(entry.value),
        '장보기 연결 항목을 확인해주세요.',
      );
      final rows = await txn.query(
        'shopping_items',
        columns: ['id'],
        where: 'id = ?',
        whereArgs: [entry.value],
        limit: 1,
      );
      require(rows.isNotEmpty, '장보기 목록이 변경됐어요. 다시 확인해주세요.');
    }
    for (final food in foods) {
      await txn.insert('foods', food.toRow());
    }
    for (final id in shoppingIds) {
      await txn.delete('shopping_items', where: 'id = ?', whereArgs: [id]);
    }
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
