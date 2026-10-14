import 'package:flutter_test/flutter_test.dart';
import 'package:recare/domain/inventory.dart';

void main() {
  final today = DateTime(2026, 10, 14);
  Food milk([int? price = 3000]) => Food(
    id: 'milk',
    name: '우유',
    unit: FoodUnit.litre,
    total: 1000000,
    expiry: today,
    price: price,
    created: today,
  );
  test('250ml waste leaves 750ml and costs 750 won', () {
    final result = processFood(
      milk(),
      ActionKind.waste,
      FoodUnit.ml.parseQuantity('250'),
      FoodUnit.ml,
      today,
      'a',
      today: today,
    );
    expect(FoodUnit.ml.quantityText(result.food.remaining), '750');
    expect(result.record.cost, 750);
  });
  test('partial processing preserves rounding and total price', () {
    var food = Food(
      id: 'eggs',
      name: '달걀',
      unit: FoodUnit.piece,
      total: 3000,
      expiry: today,
      price: 100,
      created: today,
    );
    final costs = <int>[];
    for (var i = 0; i < 3; i++) {
      final result = processFood(
        food,
        ActionKind.waste,
        1000,
        FoodUnit.piece,
        today,
        '$i',
        today: today,
      );
      food = result.food;
      costs.add(result.record.cost!);
    }
    expect(costs, [33, 34, 33]);
    expect(food.remaining, 0);
  });
  test('eating and waste share cost but weekly total excludes eating', () {
    final eaten = processFood(
      milk(),
      ActionKind.eat,
      500000,
      FoodUnit.ml,
      today,
      'eat',
      today: today,
    );
    final waste = processFood(
      eaten.food,
      ActionKind.waste,
      500000,
      FoodUnit.ml,
      today,
      'waste',
      today: today,
    );
    expect(eaten.record.cost! + waste.record.cost!, 3000);
    expect(weeklyWaste([eaten.record, waste.record], today).knownTotal, 1500);
  });
  test('missing price remains null and differs from zero', () {
    expect(parsePrice(''), isNull);
    expect(parsePrice('0'), 0);
    final unknown = processFood(
      milk(null),
      ActionKind.waste,
      1000,
      FoodUnit.ml,
      today,
      'a',
      today: today,
    );
    final free = processFood(
      milk(0),
      ActionKind.waste,
      1000,
      FoodUnit.ml,
      today,
      'b',
      today: today,
    );
    expect(unknown.record.cost, isNull);
    expect(free.record.cost, 0);
    expect(weeklyWaste([unknown.record, free.record], today).unknownCount, 1);
  });
  test('week starts Monday and excludes previous Sunday and future dates', () {
    FoodRecord record(String id, DateTime date) => FoodRecord(
      id: id,
      foodId: 'food',
      foodName: '우유',
      kind: ActionKind.waste,
      amount: 1000,
      unit: FoodUnit.ml,
      date: date,
      cost: 100,
    );
    final week = weeklyWaste([
      record('sun', DateTime(2026, 10, 11)),
      record('mon', DateTime(2026, 10, 12)),
      record('now', today),
      record('future', DateTime(2026, 10, 15)),
    ], today);
    expect(dateText(week.start), '2026-10-12');
    expect(dateText(week.end), '2026-10-18');
    expect(week.records.map((r) => r.id).toSet(), {'mon', 'now'});
    expect(week.knownTotal, 200);
  });
  test('week boundaries cross years and include Sundays', () {
    expect(dateText(weeklyWaste([], DateTime(2026, 1, 1)).start), '2025-12-29');
    expect(
      dateText(weeklyWaste([], DateTime(2026, 10, 18)).start),
      '2026-10-12',
    );
  });
  test('decimal quantity and conversions remain exact', () {
    expect(
      FoodUnit.kilogram.parseQuantity('0.125'),
      FoodUnit.gram.parseQuantity('125'),
    );
    expect(FoodUnit.ml.parseQuantity('0.001'), 1);
    expect(FoodUnit.litre.quantityText(749500), '0.7495');
  });
  test('invalid quantity and prices are rejected', () {
    for (final text in [
      '0',
      '-1',
      'NaN',
      '1e3',
      '0.0001',
      '9999999999999999999999',
      '',
    ]) {
      expect(() => FoodUnit.ml.parseQuantity(text), throwsArgumentError);
    }
    for (final text in ['-1', '1.5', '1000000000001']) {
      expect(() => parsePrice(text), throwsArgumentError);
    }
  });
  test('overdraw, incompatible units and future processing are rejected', () {
    for (final amount in [0, -1, 1000001]) {
      expect(
        () => processFood(
          milk(),
          ActionKind.waste,
          amount,
          FoodUnit.ml,
          today,
          'a',
          today: today,
        ),
        throwsArgumentError,
      );
    }
    expect(
      () => processFood(
        milk(),
        ActionKind.waste,
        1000,
        FoodUnit.gram,
        today,
        'a',
        today: today,
      ),
      throwsArgumentError,
    );
    expect(
      () => processFood(
        milk(),
        ActionKind.waste,
        1000,
        FoodUnit.ml,
        today.add(const Duration(days: 1)),
        'a',
        today: today,
      ),
      throwsArgumentError,
    );
  });
  test('large multiplication does not overflow and SQL rows round trip', () {
    final large = Food(
      id: 'large',
      name: '큰 수',
      unit: FoodUnit.ml,
      total: maxQuantity,
      expiry: today,
      price: maxPrice,
      created: today,
    );
    final result = processFood(
      large,
      ActionKind.waste,
      maxQuantity ~/ 2,
      FoodUnit.ml,
      today,
      'a',
      today: today,
    );
    expect(result.record.cost, maxPrice ~/ 2);
    expect(Food.fromRow(result.food.toRow()).remaining, maxQuantity ~/ 2);
    expect(FoodRecord.fromRow(result.record.toRow()).kind, ActionKind.waste);
  });
}
