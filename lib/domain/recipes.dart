import 'inventory.dart';
import 'shopping.dart';

const recipeStaples = <String>['소금', '설탕', '식용유', '간장', '후추', '참기름'];

enum RecipeIngredientKind { inventory, staple, shopping }

String _normalized(String value) => normalizedShoppingName(value);

List<Food> eligibleRecipeFoods(Iterable<Food> foods, DateTime today) {
  final day = civilDate(today);
  return foods.where((f) => f.remaining > 0 && !f.expiry.isBefore(day)).toList()
    ..sort((a, b) {
      final expiry = a.expiry.compareTo(b.expiry);
      final name = a.name.compareTo(b.name);
      return expiry != 0 ? expiry : (name != 0 ? name : a.id.compareTo(b.id));
    });
}

List<RecipeStock> groupRecipeFoods(Iterable<Food> foods) {
  final groups = <String, List<Food>>{};
  for (final food in foods) {
    groups
        .putIfAbsent('${_normalized(food.name)}|${food.unit.family}', () => [])
        .add(food);
  }
  return List.unmodifiable(
    groups.values.indexed.map(
      (entry) => RecipeStock(id: 'i${entry.$1}', foods: entry.$2),
    ),
  );
}

Set<String> defaultRecipeFoodIds(Iterable<Food> foods, DateTime today) {
  final eligible = eligibleRecipeFoods(foods, today);
  final imminent = eligible
      .where((f) => f.expiry.difference(civilDate(today)).inDays <= 3)
      .toList();
  final groups = groupRecipeFoods(imminent.isNotEmpty ? imminent : eligible);
  return groups
      .take(imminent.isNotEmpty ? 10 : 3)
      .expand((g) => g.foodIds)
      .toSet();
}

class RecipeStock {
  RecipeStock({required this.id, required List<Food> foods})
    : foods = List.unmodifiable(foods) {
    require(id.trim().isNotEmpty && this.foods.isNotEmpty, '추천할 재료를 확인해주세요.');
    final ids = <String>{};
    for (final food in this.foods) {
      require(
        ids.add(food.id) &&
            _normalized(food.name) == _normalized(name) &&
            food.unit.family == unit.family &&
            food.remaining > 0,
        '재료 묶음을 확인해주세요.',
      );
    }
    require(amount <= maxQuantity, '추천 재료의 수량 범위를 확인해주세요.');
  }
  final String id;
  final List<Food> foods;
  String get name => foods.first.name;
  FoodUnit get unit => foods.first.unit;
  int get amount => foods.fold(0, (sum, f) => sum + f.remaining);
  List<String> get foodIds => List.unmodifiable(foods.map((f) => f.id));
  Map<String, dynamic> toRequestJson(DateTime today) {
    require(
      eligibleRecipeFoods(foods, today).length == foods.length,
      '소비기한 또는 재고가 변경됐어요. 재료를 다시 확인해주세요.',
    );
    final expiry = foods
        .map((f) => f.expiry)
        .reduce((a, b) => a.isBefore(b) ? a : b);
    return {
      'id': id,
      'name': name,
      'amount': amount,
      'unit': unit.code,
      'days_left': expiry.difference(civilDate(today)).inDays,
    };
  }
}

class RecipeRequest {
  RecipeRequest({
    required this.requestId,
    required List<RecipeStock> stocks,
    List<String> staples = const [],
    this.servings = 1,
    this.maxMinutes = 20,
    this.allowShopping = false,
    this.exclusions = '',
  }) : stocks = List.unmodifiable(stocks),
       staples = List.unmodifiable(staples);
  final String requestId, exclusions;
  final List<RecipeStock> stocks;
  final List<String> staples;
  final int servings;
  final int? maxMinutes;
  final bool allowShopping;
  /// Structural checks also apply when replaying a completed historical result.
  void validate() {
    require(
      requestId.trim().isNotEmpty && stocks.isNotEmpty && stocks.length <= 10,
      '추천 재료는 1~10종 선택해주세요.',
    );
    RecipeSettings(
      staples: staples,
      servings: servings,
      maxMinutes: maxMinutes,
    );
    require(exclusions.length <= 200, '제외 재료는 200자 이내로 입력해주세요.');
    final ids = <String>{}, foodIds = <String>{}, names = <String>{};
    for (final stock in stocks) {
      require(
        ids.add(stock.id) &&
            names.add('${_normalized(stock.name)}|${stock.unit.family}'),
        '중복된 추천 재료를 확인해주세요.',
      );
      for (final id in stock.foodIds) {
        require(foodIds.add(id), '중복된 보관분을 확인해주세요.');
      }
    }
  }

  Map<String, dynamic> toJson(DateTime today) {
    validate();
    return {
      'request_id': requestId,
      'ingredients': stocks.map((s) => s.toRequestJson(today)).toList(),
      'staples': staples,
      'servings': servings,
      'max_minutes': maxMinutes,
      'allow_shopping': allowShopping,
      'exclusions': exclusions,
    };
  }
}

class RecipeIngredient {
  RecipeIngredient({
    required String name,
    required this.kind,
    this.sourceId,
    this.amount,
    this.unit,
    String displayQuantity = '',
    List<String> foodIds = const [],
  }) : name = name.trim(),
       displayQuantity = amount != null && unit != null
           ? '${unit.quantityText(amount)} ${unit.label}'
           : displayQuantity,
       foodIds = List.unmodifiable(foodIds) {
    require(
      this.name.isNotEmpty &&
          this.name.length <= 60 &&
          displayQuantity.length <= 100,
      '레시피 재료를 확인해주세요.',
    );
    require(
      amount == null || (amount! > 0 && amount! <= maxQuantity),
      '레시피 수량을 확인해주세요.',
    );
    require((amount == null) == (unit == null), '레시피 수량과 단위를 확인해주세요.');
    require(
      kind != RecipeIngredientKind.inventory ||
          (sourceId != null &&
              sourceId!.isNotEmpty &&
              amount != null &&
              unit != null),
      '재고 연결 재료를 확인해주세요.',
    );
    require(
      kind == RecipeIngredientKind.inventory ||
          (sourceId == null && foodIds.isEmpty),
      '재고 외 재료의 연결을 확인해주세요.',
    );
    require(foodIds.toSet().length == foodIds.length, '중복된 재고 연결을 확인해주세요.');
  }
  final String name, displayQuantity;
  final RecipeIngredientKind kind;
  final String? sourceId;
  final int? amount;
  final FoodUnit? unit;
  final List<String> foodIds;
  Map<String, dynamic> toJson() => {
    'name': name,
    'kind': kind.name,
    'source_id': sourceId,
    'amount': amount,
    'unit': unit?.code,
    'display_quantity': displayQuantity,
    'food_ids': foodIds,
  };
  factory RecipeIngredient.fromJson(Map<String, dynamic> json) =>
      RecipeIngredient(
        name: _string(json['name']),
        kind: _kind(json['kind']),
        sourceId: _nullableString(json['source_id']),
        amount: _nullableInt(json['amount']),
        unit: _unit(json['unit']),
        displayQuantity: _string(json['display_quantity']),
        foodIds: _strings(json['food_ids'] ?? []),
      );
}

class Recipe {
  Recipe({
    required this.id,
    required String title,
    required this.servings,
    required this.minutes,
    required this.reason,
    required List<RecipeIngredient> ingredients,
    required List<String> steps,
    required List<String> warnings,
    required this.generatedAt,
    this.schemaVersion = 1,
  }) : title = title.trim(),
       ingredients = List.unmodifiable(ingredients),
       steps = List.unmodifiable(steps),
       warnings = List.unmodifiable(warnings) {
    require(
      id.isNotEmpty &&
          this.title.isNotEmpty &&
          this.title.length <= 100 &&
          servings >= 1 &&
          servings <= 4 &&
          minutes > 0 &&
          minutes <= 240 &&
          reason.length <= 500 &&
          schemaVersion == 1,
      '레시피 형식을 확인해주세요.',
    );
    require(
      ingredients.isNotEmpty &&
          ingredients.length <= 30 &&
          ingredients.any((i) => i.kind == RecipeIngredientKind.inventory),
      '재고를 사용하는 레시피인지 확인해주세요.',
    );
    require(
      steps.isNotEmpty &&
          steps.length <= 20 &&
          warnings.isNotEmpty &&
          warnings.length <= 10 &&
          [
            ...steps,
            ...warnings,
          ].every((s) => s.trim().isNotEmpty && s.length <= 1000),
      '조리 순서와 주의사항을 확인해주세요.',
    );
  }
  final String id, title, reason;
  final int servings, minutes, schemaVersion;
  final List<RecipeIngredient> ingredients;
  final List<String> steps, warnings;
  final DateTime generatedAt;
  List<RecipeIngredient> get shoppingIngredients => List.unmodifiable(
    ingredients.where((i) => i.kind == RecipeIngredientKind.shopping),
  );
  Set<String> get stockFoodIds => ingredients
      .where((i) => i.kind == RecipeIngredientKind.inventory)
      .expand((i) => i.foodIds)
      .toSet();
  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'servings': servings,
    'minutes': minutes,
    'reason': reason,
    'ingredients': ingredients.map((i) => i.toJson()).toList(),
    'steps': steps,
    'warnings': warnings,
    'generated_at': generatedAt.toIso8601String(),
    'schema_version': schemaVersion,
  };
  factory Recipe.fromJson(Map<String, dynamic> json) => Recipe(
    id: _string(json['id']),
    title: _string(json['title']),
    servings: _integer(json['servings']),
    minutes: _integer(json['minutes']),
    reason: _string(json['reason']),
    ingredients: _maps(json['ingredients'])
        .map(RecipeIngredient.fromJson)
        .toList(),
    steps: _strings(json['steps']),
    warnings: _strings(json['warnings']),
    generatedAt: DateTime.parse(_string(json['generated_at'])),
    schemaVersion: _integer(json['schema_version'] ?? 1),
  );
}

class RecipeResult {
  RecipeResult({
    required this.requestId,
    required List<Recipe> recipes,
    this.message = '',
    required this.generatedAt,
  }) : recipes = List.unmodifiable(recipes) {
    require(
      requestId.isNotEmpty && recipes.length <= 3 && message.length <= 500,
      '추천 결과를 확인해주세요.',
    );
  }
  final String requestId, message;
  final List<Recipe> recipes;
  final DateTime generatedAt;
  Map<String, dynamic> toJson() => {
    'request_id': requestId,
    'recipes': recipes.map((r) => r.toJson()).toList(),
    'message': message,
    'generated_at': generatedAt.toIso8601String(),
  };
  factory RecipeResult.fromJson(Map<String, dynamic> json) => RecipeResult(
    requestId: _string(json['request_id']),
    recipes: _maps(json['recipes']).map(Recipe.fromJson).toList(),
    message: _string(json['message']),
    generatedAt: DateTime.parse(_string(json['generated_at'])),
  );
  static RecipeResult fromResponse(
    Map<String, dynamic> json,
    RecipeRequest request,
    DateTime now,
  ) {
    request.validate();
    final generatedAt = json['generated_at'] == null
        ? now
        : DateTime.parse(_string(json['generated_at']));
    final status = _string(json['status']);
    final items = _maps(json['recipes']);
    require(
      (status == 'ok' && items.isNotEmpty && items.length <= 3) ||
          (status == 'no_match' && items.isEmpty),
      '추천 응답 형식을 확인해주세요.',
    );
    final stocks = {for (final stock in request.stocks) stock.id: stock};
    final titles = <String>{}, signatures = <String>{};
    final excluded = request.exclusions
        .split(RegExp(r'[,;\n]+'))
        .map(_normalized)
        .where((s) => s.isNotEmpty)
        .toList();
    final recipes = <Recipe>[];
    for (final (index, item) in items.indexed) {
      final used = <String, int>{}, shopping = <String>{};
      final ingredients = <RecipeIngredient>[];
      for (final raw in _maps(item['ingredients'])) {
        // Server-provided local IDs are never accepted or persisted.
        final ingredient = RecipeIngredient.fromJson({
          ...raw,
          'food_ids': <String>[],
        });
        require(
          !excluded.any((e) => _excludesIngredient(ingredient.name, e)),
          '제외 재료가 포함된 응답이에요.',
        );
        if (ingredient.kind == RecipeIngredientKind.inventory) {
          final stock = stocks[ingredient.sourceId];
          require(
            stock != null &&
                _normalized(stock.name) == _normalized(ingredient.name) &&
                stock.unit.family == ingredient.unit!.family,
            '선택한 재고와 다른 응답이에요.',
          );
          used.update(
            stock!.id,
            (n) => n + ingredient.amount!,
            ifAbsent: () => ingredient.amount!,
          );
          require(used[stock.id]! <= stock.amount, '추천 사용량이 재고를 초과해요.');
          ingredients.add(
            RecipeIngredient(
              name: stock.name,
              kind: ingredient.kind,
              sourceId: stock.id,
              amount: ingredient.amount,
              unit: ingredient.unit,
              displayQuantity: ingredient.displayQuantity,
              foodIds: stock.foodIds,
            ),
          );
        } else {
          if (ingredient.kind == RecipeIngredientKind.staple) {
            require(
              request.staples.contains(ingredient.name),
              '보유를 확인하지 않은 양념이에요.',
            );
          } else {
            require(request.allowShopping, '추가 구매를 허용하지 않은 요청이에요.');
            shopping.add(_normalized(ingredient.name));
            require(shopping.length <= 3, '추가 구매 재료는 최대 3종이에요.');
          }
          ingredients.add(ingredient);
        }
      }
      final recipe = Recipe(
        id: '${request.requestId}:$index',
        title: _string(item['title']),
        servings: _integer(item['servings']),
        minutes: _integer(item['minutes']),
        reason: _string(item['reason']),
        ingredients: ingredients,
        steps: _strings(item['steps']),
        warnings: _strings(item['warnings']),
        generatedAt: generatedAt,
      );
      require(
        recipe.servings == request.servings &&
            (request.maxMinutes == null ||
                recipe.minutes <= request.maxMinutes!),
        '요청한 인분 또는 조리 시간과 다른 응답이에요.',
      );
      final signature =
          ingredients
              .map((i) => '${_normalized(i.name)}:${i.kind.name}')
              .toList()
            ..sort();
      final steps = recipe.steps.map(_normalized).join('|');
      require(
        titles.add(_normalized(recipe.title)) &&
            signatures.add('${signature.join('|')}::$steps'),
        '중복된 요리가 포함된 응답이에요.',
      );
      recipes.add(recipe);
    }
    return RecipeResult(
      requestId: request.requestId,
      recipes: recipes,
      message: _string(json['message']),
      generatedAt: generatedAt,
    );
  }
}

class RecipeSettings {
  RecipeSettings({
    List<String> staples = const [],
    this.servings = 1,
    this.maxMinutes = 20,
    this.consentVersion = 0,
  }) : staples = List.unmodifiable(staples) {
    require(
      staples.every(recipeStaples.contains) &&
          staples.toSet().length == staples.length &&
          servings >= 1 &&
          servings <= 4 &&
          [10, 20, 30, null].contains(maxMinutes) &&
          consentVersion >= 0,
      '추천 조건을 확인해주세요.',
    );
  }
  final List<String> staples;
  final int servings, consentVersion;
  final int? maxMinutes;
  Map<String, dynamic> toJson() => {
    'staples': staples,
    'servings': servings,
    'max_minutes': maxMinutes,
    'consent_version': consentVersion,
  };
  factory RecipeSettings.fromJson(Map<String, dynamic> json) => RecipeSettings(
    staples: _strings(json['staples']),
    servings: _integer(json['servings']),
    maxMinutes: _nullableInt(json['max_minutes']),
    consentVersion: _integer(json['consent_version']),
  );
}

class RecipeUsage {
  RecipeUsage({required this.food, required this.amount}) {
    require(amount >= 0 && amount <= maxQuantity, '사용량을 확인해주세요.');
  }
  final Food food;
  final int amount;
}

class CookingOperation {
  CookingOperation({
    required this.id,
    required this.recipeId,
    required this.state,
    required DateTime day,
    required List<RecipeUsage> usages,
  }) : day = civilDate(day),
       usages = List.unmodifiable(usages) {
    require(['draft', 'completed', 'undone'].contains(state), '조리 상태를 확인해주세요.');
  }
  final String id, recipeId, state;
  final DateTime day;
  final List<RecipeUsage> usages;
  int get recordCount => usages.where((u) => u.amount > 0).length;
}

class RecipeShoppingResult {
  const RecipeShoppingResult({required this.added, required this.existing});
  final int added, existing;
}

String _string(Object? value) {
  require(value is String, '응답의 문자열 형식을 확인해주세요.');
  return value as String;
}

String? _nullableString(Object? value) => value == null ? null : _string(value);
int _integer(Object? value) {
  require(value is int, '응답의 정수 수량을 확인해주세요.');
  return value as int;
}

int? _nullableInt(Object? value) => value == null ? null : _integer(value);
List<String> _strings(Object? value) {
  require(value is List, '응답 목록을 확인해주세요.');
  return (value as List).map(_string).toList();
}

List<Map<String, dynamic>> _maps(Object? value) {
  require(value is List, '응답 목록을 확인해주세요.');
  return (value as List).map((item) {
    require(item is Map<String, dynamic>, '응답 항목을 확인해주세요.');
    return item as Map<String, dynamic>;
  }).toList();
}

RecipeIngredientKind _kind(Object? value) {
  require(
    RecipeIngredientKind.values.any((k) => k.name == value),
    '재료 종류를 확인해주세요.',
  );
  return RecipeIngredientKind.values.firstWhere((k) => k.name == value);
}

FoodUnit? _unit(Object? value) {
  if (value == null) return null;
  require(FoodUnit.values.any((u) => u.code == value), '레시피 단위를 확인해주세요.');
  return FoodUnit.fromCode(value as String);
}

// Conservative known compound checks supplement literal matching, never a safety guarantee.
bool _excludesIngredient(String name, String exclusion) {
  final normalized = _normalized(name);
  if (normalized.contains(exclusion)) return true;
  const compounds = <String, List<String>>{
    '간장': ['대두', '콩', '밀', '소이', 'soy', 'wheat'],
    '두부': ['대두', '콩', '소이', 'soy'],
    '된장': ['대두', '콩', '소이', 'soy'],
    '고추장': ['대두', '콩', '밀', 'soy', 'wheat'],
    '참기름': ['참깨', '깨', 'sesame'],
    '마요네즈': ['달걀', '계란', '난류', 'egg'],
    '버터': ['우유', '유제품', 'milk', 'dairy'],
    '치즈': ['우유', '유제품', 'milk', 'dairy'],
  };
  return compounds.entries.any(
    (entry) =>
        normalized.contains(entry.key) &&
        entry.value.any((allergen) => allergen == exclusion),
  );
}
