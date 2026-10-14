import 'package:flutter_test/flutter_test.dart';
import 'package:recare/domain/inventory.dart';
import 'package:recare/domain/portions.dart';

void main() {
  final today = DateTime(2026, 10, 14);

  test('presets use remaining stock instead of original registration', () {
    final food = Food(
      id: 'milk',
      name: '우유',
      unit: FoodUnit.litre,
      total: 1000000,
      remaining: 750000,
      expiry: today,
      price: 3000,
      created: today,
    );
    expect(portionAmount(food.remaining, 1), 750000);
    expect(portionAmount(food.remaining, 2), 375000);
    expect(portionAmount(food.remaining, 3), 250000);
    expect(portionAmount(food.remaining, 4), 187500);
  });

  test(
    'one third of a litre or kilogram stays exactly editable in base units',
    () {
      final amount = portionAmount(1000000, 3);
      expect(amount, 333333);
      for (final unit in [FoodUnit.ml, FoodUnit.gram]) {
        expect(unit.quantityText(amount), '333.333');
        expect(unit.parseQuantity(unit.quantityText(amount)), amount);
      }
    },
  );

  test('half-up rounding keeps small portions within remaining stock', () {
    expect(portionAmount(1, 1), 1);
    expect(portionAmount(1, 2), 1);
    expect(portionAmount(2, 4), 1);
    expect(portionAmount(4, 3), 1);
    expect(portionAmount(5, 3), 2);
    expect(portionAmount(3, 2), 2);
  });

  test('too-small fractions explain why direct input is needed', () {
    for (final denominator in [3, 4]) {
      expect(
        () => portionAmount(1, denominator),
        throwsA(
          isA<ArgumentError>().having(
            (error) => error.message,
            'message',
            '남은 수량이 너무 적어요. 직접 입력해주세요.',
          ),
        ),
      );
    }
  });

  test('maximum supported quantities remain exact', () {
    expect(portionAmount(maxQuantity, 1), maxQuantity);
    expect(portionAmount(maxQuantity, 2), 500000000000);
    expect(portionAmount(maxQuantity, 3), 333333333333);
    expect(portionAmount(maxQuantity, 4), 250000000000);
  });

  test('empty negative and out-of-range remaining stock are rejected', () {
    for (final remaining in [0, -1, maxQuantity + 1]) {
      expect(() => portionAmount(remaining, 1), throwsArgumentError);
    }
  });

  test('only all half one-third and one-quarter are supported', () {
    for (final denominator in [-1, 0, 5, 1000000]) {
      expect(() => portionAmount(1000000, denominator), throwsArgumentError);
    }
  });

  test('three successive thirds leave stock and final all conserves price', () {
    var food = Food(
      id: 'milk',
      name: '우유',
      unit: FoodUnit.litre,
      total: 1000000,
      expiry: today,
      price: 3000,
      created: today,
    );
    final records = <FoodRecord>[];
    for (var i = 0; i < 3; i++) {
      final amount = portionAmount(food.remaining, 3);
      final result = processFood(
        food,
        ActionKind.waste,
        FoodUnit.ml.parseQuantity(FoodUnit.ml.quantityText(amount)),
        FoodUnit.ml,
        today,
        'third-$i',
        today: today,
      );
      food = result.food;
      records.add(result.record);
    }
    expect(records.map((record) => record.amount), [333333, 222222, 148148]);
    expect(records.map((record) => record.cost), [1000, 667, 444]);
    expect(food.remaining, 296297);
    final finalProcessing = processFood(
      food,
      ActionKind.waste,
      portionAmount(food.remaining, 1),
      FoodUnit.ml,
      today,
      'all',
      today: today,
    );
    records.add(finalProcessing.record);
    expect(finalProcessing.food.remaining, 0);
    expect(finalProcessing.record.cost, 889);
    expect(records.fold(0, (sum, record) => sum + record.amount), 1000000);
    expect(weeklyWaste(records, today).knownTotal, 3000);
  });

  test('uneven purchase price is conserved across mixed preset actions', () {
    var food = Food(
      id: 'rice',
      name: '쌀',
      unit: FoodUnit.kilogram,
      total: 1000000,
      expiry: today,
      price: 100,
      created: today,
    );
    final records = <FoodRecord>[];
    for (final denominator in [3, 3, 3, 1]) {
      final amount = portionAmount(food.remaining, denominator);
      final result = processFood(
        food,
        records.isEmpty ? ActionKind.eat : ActionKind.waste,
        FoodUnit.gram.parseQuantity(FoodUnit.gram.quantityText(amount)),
        FoodUnit.gram,
        today,
        'record-${records.length}',
        today: today,
      );
      food = result.food;
      records.add(result.record);
    }
    expect(food.remaining, 0);
    expect(records.map((record) => record.cost), [33, 23, 14, 30]);
    expect(records.fold(0, (sum, record) => sum + record.cost!), 100);
    expect(weeklyWaste(records, today).knownTotal, 67);
  });

  test('missing purchase price stays unentered after preset processing', () {
    final food = Food(
      id: 'apple',
      name: '사과',
      unit: FoodUnit.piece,
      total: 1000,
      expiry: today,
      price: null,
      created: today,
    );
    final result = processFood(
      food,
      ActionKind.waste,
      portionAmount(food.remaining, 2),
      FoodUnit.piece,
      today,
      'half',
      today: today,
    );
    expect(result.food.remaining, 500);
    expect(result.record.cost, isNull);
    expect(weeklyWaste([result.record], today).unknownCount, 1);
  });
}
