import 'dart:convert';

import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../domain/inventory.dart';
import '../domain/recipes.dart';
import '../domain/shopping.dart';
import 'inventory_repository.dart';

class RecipeRepository {
  RecipeRepository(this.inventory);
  final InventoryRepository inventory;
  Database get _db => inventory.database;

  Future<String?> loadValue(String key) async {
    final rows = await _db.query(
      'recipe_values',
      where: 'key = ?',
      whereArgs: [key],
    );
    return rows.isEmpty ? null : rows.single['value'] as String;
  }

  Future<void> saveValue(String key, String? value) async {
    require(key.isNotEmpty, '저장 항목을 확인해주세요.');
    if (value == null) {
      await _db.delete('recipe_values', where: 'key = ?', whereArgs: [key]);
    } else {
      await _db.insert('recipe_values', {
        'key': key,
        'value': value,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }
  }

  Future<RecipeSettings> loadSettings() async {
    final value = await loadValue('recipe_settings');
    return value == null
        ? RecipeSettings()
        : RecipeSettings.fromJson(_decode(value));
  }

  Future<void> saveSettings(RecipeSettings settings) =>
      saveValue('recipe_settings', jsonEncode(settings.toJson()));

  Future<void> saveRecent(RecipeResult result) => _db.transaction((txn) async {
    final json = jsonEncode(RecipeResult.fromJson(result.toJson()).toJson());
    await txn.insert('recipe_recent', {
      'request_id': result.requestId,
      'result_json': json,
      'generated_at': result.generatedAt.toUtc().toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
    await txn.rawDelete(
      'DELETE FROM recipe_recent WHERE request_id NOT IN (SELECT request_id FROM recipe_recent ORDER BY generated_at DESC, rowid DESC LIMIT 5)',
    );
  });
  Future<List<RecipeResult>> loadRecent() async => List.unmodifiable(
    (await _db.query(
      'recipe_recent',
      orderBy: 'generated_at DESC, rowid DESC',
    )).map((r) => RecipeResult.fromJson(_decode(r['result_json'] as String))),
  );
  Future<void> clearRecent() async {
    await _db.delete('recipe_recent');
  }

  Future<List<Recipe>> loadFavorites() async => List.unmodifiable(
    (await _db.query(
      'recipe_favorites',
      orderBy: 'saved_at DESC, rowid DESC',
    )).map((r) => Recipe.fromJson(_decode(r['recipe_json'] as String))),
  );
  Future<bool> isFavorite(String recipeId) async =>
      await favoriteSavedAt(recipeId) != null;
  Future<DateTime?> favoriteSavedAt(String recipeId) async {
    final rows = await _db.query(
      'recipe_favorites',
      columns: ['saved_at'],
      where: 'recipe_id = ?',
      whereArgs: [recipeId],
    );
    return rows.isEmpty
        ? null
        : DateTime.parse(rows.single['saved_at'] as String);
  }

  Future<void> setFavorite(Recipe recipe, bool value) async {
    if (!value) {
      await _db.delete(
        'recipe_favorites',
        where: 'recipe_id = ?',
        whereArgs: [recipe.id],
      );
      return;
    }
    await restoreFavorite(recipe, DateTime.now().toUtc());
  }

  Future<void> restoreFavorite(Recipe recipe, DateTime savedAt) =>
      _db.transaction((txn) async {
        final existing = await txn.query(
          'recipe_favorites',
          columns: ['recipe_id'],
          where: 'recipe_id = ?',
          whereArgs: [recipe.id],
        );
        if (existing.isNotEmpty) return;
        final count = Sqflite.firstIntValue(
          await txn.rawQuery('SELECT COUNT(*) FROM recipe_favorites'),
        )!;
        require(count < 100, '즐겨찾기는 최대 100개 저장할 수 있어요.');
        await txn.insert('recipe_favorites', {
          'recipe_id': recipe.id,
          'recipe_json': jsonEncode(Recipe.fromJson(recipe.toJson()).toJson()),
          'saved_at': savedAt.toUtc().toIso8601String(),
        });
      });

  Future<CookingOperation?> latestCooking(String recipeId) async {
    final rows = await _db.query(
      'recipe_cooking',
      where: 'recipe_id = ?',
      whereArgs: [recipeId],
      orderBy: 'rowid DESC',
      limit: 1,
    );
    return rows.isEmpty ? null : _operation(rows.single);
  }

  Future<CookingOperation> beginCooking(
    Recipe recipe,
    DateTime today, {
    bool newRound = false,
  }) => _db.transaction((txn) async {
    final prior = await txn.query(
      'recipe_cooking',
      where: 'recipe_id = ?',
      whereArgs: [recipe.id],
      orderBy: 'rowid DESC',
      limit: 1,
    );
    if (!newRound && prior.isNotEmpty) return _operation(prior.single);
    Recipe.fromJson(recipe.toJson());
    final available = (await txn.query('foods')).map(Food.fromRow).toList();
    final byId = {
      for (final food in eligibleRecipeFoods(available, today)) food.id: food,
    };
    final allocations = <String, int>{};
    for (final ingredient in recipe.ingredients.where(
      (i) => i.kind == RecipeIngredientKind.inventory,
    )) {
      var remaining = ingredient.amount!;
      final lots =
          ingredient.foodIds
              .map((id) => byId[id])
              .whereType<Food>()
              .where(
                (food) =>
                    normalizedShoppingName(food.name) ==
                        normalizedShoppingName(ingredient.name) &&
                    food.unit.family == ingredient.unit!.family,
              )
              .toList()
            ..sort((a, b) => a.expiry.compareTo(b.expiry));
      for (final food in lots) {
        if (remaining == 0) break;
        final availableAmount = food.remaining - (allocations[food.id] ?? 0);
        final amount = remaining < availableAmount
            ? remaining
            : availableAmount;
        if (amount <= 0) continue;
        allocations.update(food.id, (n) => n + amount, ifAbsent: () => amount);
        remaining -= amount;
      }
    }
    final usages = allocations.entries
        .map((e) => RecipeUsage(food: byId[e.key]!, amount: e.value))
        .toList();
    final operation = CookingOperation(
      id: const Uuid().v4(),
      recipeId: recipe.id,
      state: 'draft',
      day: today,
      usages: usages,
    );
    await txn.insert('recipe_cooking', {
      'id': operation.id,
      'recipe_id': recipe.id,
      'recipe_json': jsonEncode(recipe.toJson()),
      'state': operation.state,
      'day': dateText(operation.day),
      'usages_json': _encodeUsages(usages),
      'record_count': 0,
    });
    return operation;
  });

  Future<void> saveCookingDraft(
    String operationId,
    List<RecipeUsage> usages,
    DateTime today,
  ) => _db.transaction((txn) async {
    final row = await _cookingRow(txn, operationId);
    require(row['state'] == 'draft', '조리 상태가 변경됐어요. 새 조리로 다시 확인해주세요.');
    await inventory.validateRecipeFoods(
      txn,
      usages.map((u) => (food: u.food, amount: u.amount)).toList(),
      today,
    );
    await txn.update(
      'recipe_cooking',
      {'usages_json': _encodeUsages(usages), 'day': dateText(civilDate(today))},
      where: 'id = ?',
      whereArgs: [operationId],
    );
  });

  Future<int> completeCooking(
    String operationId,
    List<RecipeUsage> usages,
    DateTime today,
  ) => _db.transaction((txn) async {
    final row = await _cookingRow(txn, operationId);
    if (row['state'] == 'completed') return row['record_count'] as int;
    require(
      row['state'] == 'draft' && row['day'] == dateText(civilDate(today)),
      '조리 날짜 또는 상태가 변경됐어요. 새 조리로 다시 확인해주세요.',
    );
    require(
      row['usages_json'] == _encodeUsages(usages),
      '사용량이 변경됐어요. 사용량을 다시 확인하고 저장해주세요.',
    );
    final records = await inventory.processRecipeFoods(
      txn,
      usages.indexed
          .map(
            (e) => (
              food: e.$2.food,
              amount: e.$2.amount,
              requestId: '$operationId:${e.$1}',
            ),
          )
          .toList(),
      today,
    );
    for (final record in records) {
      await txn.insert('recipe_cooking_records', {
        'operation_id': operationId,
        'record_id': record.id,
      });
    }
    final changed = await txn.update(
      'recipe_cooking',
      {'state': 'completed', 'record_count': records.length},
      where: 'id = ? AND state = ?',
      whereArgs: [operationId, 'draft'],
    );
    if (changed != 1) throw StateError('조리 상태 저장에 실패했어요.');
    return records.length;
  });

  Future<bool> undoCooking(String operationId) => _db.transaction((txn) async {
    final row = await _cookingRow(txn, operationId);
    if (row['state'] != 'completed') return false;
    final links = await txn.query(
      'recipe_cooking_records',
      where: 'operation_id = ?',
      whereArgs: [operationId],
      orderBy: 'rowid',
    );
    final restored = await inventory.undoRecipeRecords(
      txn,
      links.map((r) => r['record_id'] as String).toList(),
    );
    if (!restored) return false;
    await txn.update(
      'recipe_cooking',
      {'state': 'undone'},
      where: 'id = ?',
      whereArgs: [operationId],
    );
    return true;
  });

  Future<RecipeShoppingResult> addShoppingBatch(
    String requestId,
    List<ShoppingItem> items,
  ) => _db.transaction((txn) async {
    require(
      requestId.trim().isNotEmpty && items.isNotEmpty && items.length <= 30,
      '장보기 항목을 확인해주세요.',
    );
    final ids = <String>{};
    for (final item in items) {
      ShoppingItem.fromRow(item.toRow());
      require(ids.add(item.id), '중복된 장보기 항목을 확인해주세요.');
    }
    final payload = jsonEncode(items.map((i) => i.toRow()).toList());
    final prior = await txn.query(
      'recipe_shopping_batches',
      where: 'request_id = ?',
      whereArgs: [requestId],
    );
    if (prior.isNotEmpty) {
      require(prior.single['payload_json'] == payload, '다른 항목에 사용한 장보기 요청이에요.');
      return RecipeShoppingResult(
        added: prior.single['added'] as int,
        existing: prior.single['existing_count'] as int,
      );
    }
    var added = 0, existing = 0;
    for (final item in items) {
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
      }
      final duplicate = await txn.query(
        'shopping_items',
        columns: ['id'],
        where: 'normalized_key = ?',
        whereArgs: [item.normalizedKey],
        limit: 1,
      );
      if (duplicate.isNotEmpty) {
        existing++;
        continue;
      }
      await txn.insert('shopping_items', item.toRow());
      added++;
    }
    await txn.insert('recipe_shopping_batches', {
      'request_id': requestId,
      'payload_json': payload,
      'added': added,
      'existing_count': existing,
    });
    return RecipeShoppingResult(added: added, existing: existing);
  });
}

Map<String, dynamic> _decode(String value) =>
    jsonDecode(value) as Map<String, dynamic>;
String _encodeUsages(List<RecipeUsage> usages) => jsonEncode(
  usages.map((u) => {'food': u.food.toRow(), 'amount': u.amount}).toList(),
);
CookingOperation _operation(Map<String, Object?> row) => CookingOperation(
  id: row['id'] as String,
  recipeId: row['recipe_id'] as String,
  state: row['state'] as String,
  day: DateTime.parse(row['day'] as String),
  usages: (jsonDecode(row['usages_json'] as String) as List)
      .map(
        (u) => RecipeUsage(
          food: Food.fromRow(Map<String, Object?>.from(u['food'] as Map)),
          amount: u['amount'] as int,
        ),
      )
      .toList(),
);
Future<Map<String, Object?>> _cookingRow(
  DatabaseExecutor txn,
  String id,
) async {
  final rows = await txn.query(
    'recipe_cooking',
    where: 'id = ?',
    whereArgs: [id],
  );
  require(rows.isNotEmpty, '조리 작업을 찾을 수 없어요.');
  return rows.single;
}
