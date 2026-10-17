import 'package:flutter_test/flutter_test.dart';
import 'package:recare/domain/food_catalog.dart';
import 'package:recare/domain/inventory.dart';

void main() {
  final today = DateTime(2026, 10, 17);
  Food food(
    String id,
    String name, {
    FoodUnit unit = FoodUnit.litre,
    int amount = 1000000,
  }) => Food(
    id: id,
    name: name,
    unit: unit,
    total: amount,
    remaining: 0,
    expiry: today,
    price: 3000,
    created: today,
  );

  test('partial Korean and whitespace normalized queries preserve product variants', () {
    final index = FoodSuggestionIndex();
    final results = index.search(' 서울 우 ');
    expect(results.map((r) => r.id), [
      'seoul-lowfat-1l',
      'seoul-lowfat-500ml',
      'seoul-lowfat-200ml',
    ]);
    expect(results.first.amount, 1000000);
    expect(results.first.unit, FoodUnit.litre);
    expect(results.first.visual, FoodVisual.milk);
  });
  test('aliases and exact names rank above substring matches', () {
    final index = FoodSuggestionIndex();
    expect(index.search('계란').single.name, '달걀');
    expect(index.search('MILK').single.name, '우유');
    expect(index.search('우유').first.name, '우유');
  });
  test('finished history supplies original quantity and deduplicates equivalent units', () {
    final newest = food('new', '우유', unit: FoodUnit.ml);
    final index = FoodSuggestionIndex(history: [newest, food('old', '우 유')]);
    final exact = index
        .search('우유')
        .where((r) => normalizeFoodName(r.name) == '우유')
        .toList();
    expect(exact, hasLength(1));
    expect(exact.single.id, 'history-new');
    expect(exact.single.amount, 1000000);
    expect(exact.single.unit, FoodUnit.ml);
    expect(newest.remaining, 0);
    expect(newest.price, 3000);
  });
  test('search is bounded and blank or unmatched queries do not manufacture products', () {
    final index = FoodSuggestionIndex(
      history: List.generate(210, (i) => food('$i', '우유 $i')),
    );
    expect(index.search('우유'), hasLength(5));
    expect(index.search('우유', limit: 0), isEmpty);
    expect(index.search('  '), isEmpty);
    expect(index.search('처음보는식재료'), isEmpty);
    expect(index.search('우유 209'), isEmpty);
  });
  test('all catalogue quantities are valid and identities are unique', () {
    expect(foodCatalog.map((p) => p.id).toSet().length, foodCatalog.length);
    for (final item in foodCatalog) {
      expect(
        item.unit.parseQuantity(item.unit.quantityText(item.amount)),
        item.amount,
      );
      expect(item.name.length, lessThanOrEqualTo(60));
    }
  });
  test(
    'custom names receive generic artwork without claiming a specific product',
    () {
      expect(foodVisualForName('우리집 우유'), FoodVisual.milk);
      expect(foodVisualForName('알 수 없는 식재료'), FoodVisual.grocery);
      expect(foodVisualForName(''), FoodVisual.grocery);
    },
  );

  test('history keeps catalogue aliases after deduplication', () {
    final index = FoodSuggestionIndex(
      history: [food('egg', '달걀', unit: FoodUnit.piece, amount: 10000)],
    );
    final result = index.search('계란');
    expect(result, hasLength(1));
    expect(result.single.id, 'history-egg');
  });
  test(
    'history input unit preserves quantities beyond three decimal places',
    () {
      final index = FoodSuggestionIndex(
        history: [food('precise', '특별 우유', amount: 1000333)],
      );
      final result = index.search('특별').single;
      expect(result.inputUnit, FoodUnit.ml);
      expect(
        result.inputUnit.parseQuantity(
          result.inputUnit.quantityText(result.amount),
        ),
        1000333,
      );
    },
  );
}
