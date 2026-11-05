import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:recare/domain/inventory.dart';
import 'package:recare/domain/recipes.dart';

void main() {
  final today = DateTime.utc(2026, 11, 5);
  Food food(
    String id, {
    String name = '두부',
    FoodUnit unit = FoodUnit.gram,
    int amount = 300000,
    int days = 0,
  }) => Food(
    id: id,
    name: name,
    unit: unit,
    total: amount,
    expiry: today.add(Duration(days: days)),
    price: 3000,
    created: today,
  );
  RecipeRequest request({
    String exclusions = '',
    bool shopping = false,
    List<String> staples = const [],
  }) => RecipeRequest(
    requestId: 'request',
    stocks: groupRecipeFoods([food('local-private-id')]),
    exclusions: exclusions,
    allowShopping: shopping,
    staples: staples,
  );
  Map<String, dynamic> response() => {
    'status': 'ok',
    'message': '',
    'recipes': <dynamic>[
      {
        'title': '두부 구이',
        'servings': 1,
        'minutes': 15,
        'reason': '임박한 두부 활용',
        'ingredients': <dynamic>[
          {
            'source_id': 'i0',
            'name': '두부',
            'amount': 150000,
            'unit': 'G',
            'display_quantity': '150 g',
            'kind': 'inventory',
          },
        ],
        'steps': ['두부를 충분히 익혀요'],
        'warnings': ['재료 상태를 확인하세요'],
      },
    ],
  };
  test('selection excludes expired and empty lots and uses earliest eligible groups', () {
    final foods = [
      food('late', name: '감자', days: 10),
      food('expired', days: -1),
      food('soon', days: 2),
      food('empty').withRemaining(0),
    ];
    expect(eligibleRecipeFoods(foods, today).map((f) => f.id), [
      'soon',
      'late',
    ]);
    expect(defaultRecipeFoodIds(foods, today), {'soon'});
    expect(
      defaultRecipeFoodIds([
        food('a', days: 5),
        food('b', name: '감자', days: 4),
      ], today),
      {'a', 'b'},
    );
  });
  test(
    'stock groups exact names and compatible families without fuzzy merging',
    () {
      final stocks = groupRecipeFoods([
        food('a'),
        food('b', unit: FoodUnit.kilogram),
        food('c', name: '순두부'),
        food('d', unit: FoodUnit.piece),
      ]);
      expect(stocks.length, 3);
      expect(stocks.first.foodIds, ['a', 'b']);
      expect(stocks.first.amount, 600000);
    },
  );
  test('default selection caps imminent stock groups at ten', () {
    final foods = List.generate(12, (i) => food('$i', name: '재료$i'));
    expect(defaultRecipeFoodIds(foods, today).length, 10);
  });
  test('wire request contains base integer quantities and no private inventory fields', () {
    final json = request().toJson(today);
    final text = jsonEncode(json);
    expect((json['ingredients'] as List).single, {
      'id': 'i0',
      'name': '두부',
      'amount': 300000,
      'unit': 'G',
      'days_left': 0,
    });
    for (final secret in [
      'local-private-id',
      'food_ids',
      'price',
      'expiry',
      'created',
    ]) {
      expect(text, isNot(contains(secret)));
    }
  });
  test('requests reject stale expiry, duplicate lots and invalid options', () {
    expect(
      () => request().toJson(today.add(const Duration(days: 1))),
      throwsArgumentError,
    );
    expect(
      () => RecipeRequest(
        requestId: 'x',
        stocks: [
          RecipeStock(id: 'i0', foods: [food('a'), food('a')]),
        ],
      ).toJson(today),
      throwsArgumentError,
    );
    expect(
      () =>
          RecipeRequest(requestId: 'x', stocks: [], servings: 5).toJson(today),
      throwsArgumentError,
    );
    expect(() => RecipeSettings(staples: ['미확인 양념']), throwsArgumentError);
  });
  test('response attaches local IDs and result round trips independently', () {
    final result = RecipeResult.fromResponse(response(), request(), today);
    expect(result.recipes.single.id, 'request:0');
    expect(result.recipes.single.stockFoodIds, {'local-private-id'});
    expect(RecipeResult.fromJson(result.toJson()).toJson(), result.toJson());
    expect(jsonEncode(result.toJson()), isNot(contains('exclusions')));
  });
  test('response rejects fractional, excessive, wrong unit and foreign source quantities', () {
    for (final replacement in [
      {'amount': 1.5},
      {'amount': 400000},
      {'unit': 'ML'},
      {'source_id': 'foreign'},
      {'name': '감자'},
    ]) {
      final json = response();
      ((json['recipes'] as List).single['ingredients'] as List).single.addAll(
        replacement,
      );
      expect(
        () => RecipeResult.fromResponse(json, request(), today),
        throwsArgumentError,
      );
    }
  });
  test(
    'response rejects cumulative inventory overdraw and duplicate dishes',
    () {
      final json = response();
      final dish = (json['recipes'] as List).single;
      final ingredient = Map<String, dynamic>.from(
        (dish['ingredients'] as List).single,
      )..['amount'] = 200000;
      (dish['ingredients'] as List)
        ..clear()
        ..add(ingredient)
        ..add(Map.of(ingredient));
      expect(
        () => RecipeResult.fromResponse(json, request(), today),
        throwsArgumentError,
      );
      final duplicates = response();
      (duplicates['recipes'] as List).add(
        Map.of((duplicates['recipes'] as List).single),
      );
      expect(
        () => RecipeResult.fromResponse(duplicates, request(), today),
        throwsArgumentError,
      );
    },
  );
  test(
    'response enforces confirmed staples, shopping permission and exclusions',
    () {
      final json = response();
      final ingredients =
          ((json['recipes'] as List).single['ingredients'] as List);
      ingredients.add({
        'source_id': null,
        'name': '간장',
        'amount': null,
        'unit': null,
        'display_quantity': '조금',
        'kind': 'staple',
      });
      expect(
        () => RecipeResult.fromResponse(json, request(), today),
        throwsArgumentError,
      );
      expect(
        RecipeResult.fromResponse(
          json,
          request(staples: ['간장']),
          today,
        ).recipes.length,
        1,
      );
      ingredients.last['kind'] = 'shopping';
      expect(
        () => RecipeResult.fromResponse(json, request(), today),
        throwsArgumentError,
      );
      expect(
        () => RecipeResult.fromResponse(
          json,
          request(shopping: true, exclusions: '간장'),
          today,
        ),
        throwsArgumentError,
      );
    },
  );
  test('no match must have no recipes', () {
    expect(
      RecipeResult.fromResponse(
        {'status': 'no_match', 'message': '조건에 맞는 요리가 없어요', 'recipes': []},
        request(),
        today,
      ).recipes,
      isEmpty,
    );
    final json = response()..['status'] = 'no_match';
    expect(
      () => RecipeResult.fromResponse(json, request(), today),
      throwsArgumentError,
    );
  });
  test('exclusion text is limited to 200 characters', () {
    expect(
      request(exclusions: '가' * 200).toJson(today)['exclusions'],
      '가' * 200,
    );
    expect(
      () => request(exclusions: '가' * 201).toJson(today),
      throwsArgumentError,
    );
  });
  test('known compound ingredients respect explicit allergen exclusions', () {
    for (final pair in [('간장', '밀'), ('참기름', '참깨'), ('두부', '대두')]) {
      final json = response();
      if (pair.$1 != '두부') {
        ((json['recipes'] as List).single['ingredients'] as List).add({
          'source_id': null,
          'name': pair.$1,
          'amount': null,
          'unit': null,
          'display_quantity': '조금',
          'kind': 'staple',
        });
      }
      expect(
        () => RecipeResult.fromResponse(
          json,
          request(staples: [if (pair.$1 != '두부') pair.$1], exclusions: pair.$2),
          today,
        ),
        throwsArgumentError,
      );
    }
  });
  test(
    'numeric model and persisted quantities display their validated amount',
    () {
      final json = response();
      ((json['recipes'] as List).single['ingredients'] as List)
              .single['display_quantity'] =
          '300 g';
      final ingredient = RecipeResult.fromResponse(
        json,
        request(),
        today,
      ).recipes.single.ingredients.single;
      expect(ingredient.amount, 150000);
      expect(ingredient.displayQuantity, '150 g');
      final persisted = ingredient.toJson()..['display_quantity'] = '300 g';
      expect(RecipeIngredient.fromJson(persisted).displayQuantity, '150 g');
      final textual = RecipeIngredient(
        name: '간장',
        kind: RecipeIngredientKind.staple,
        displayQuantity: '약간',
      );
      expect(RecipeIngredient.fromJson(textual.toJson()).displayQuantity, '약간');
    },
  );
  test('old response replays without fresh-stock eligibility while new requests reject', () {
    final originalRequest = request();
    final tomorrow = today.add(const Duration(days: 1));
    final result = RecipeResult.fromResponse(response(), originalRequest, tomorrow);
    expect(result.recipes.single.stockFoodIds, {'local-private-id'});
    expect(result.generatedAt, tomorrow);
    expect(() => originalRequest.toJson(tomorrow), throwsArgumentError);
  });
  test('server generation timestamp is stable across response replays', () {
    final generatedAt = today.add(const Duration(hours: 8, minutes: 30));
    final json = response()..['generated_at'] = generatedAt.toIso8601String();
    final result = RecipeResult.fromResponse(json, request(), today.add(const Duration(hours: 12)));
    expect(result.generatedAt, generatedAt);
    expect(result.recipes.single.generatedAt, generatedAt);
  });
}
