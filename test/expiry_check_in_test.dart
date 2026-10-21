import 'package:flutter_test/flutter_test.dart';
import 'package:recare/domain/expiry_check_in.dart';
import 'package:recare/domain/inventory.dart';

void main() {
  final today = DateTime(2026, 10, 21);
  Food food(int days, {int remaining = 3000}) => Food(
    id: 'a',
    name: '우유',
    unit: FoodUnit.ml,
    total: 3000,
    remaining: remaining,
    expiry: today.add(Duration(days: days)),
    price: 100,
    created: today,
  );
  test('check-ins occur exactly three one and zero days before expiry', () {
    for (final days in [-1, 0, 1, 2, 3, 4]) {
      expect(isCheckInDay(food(days), today), [0, 1, 3].contains(days));
    }
    expect(isCheckInDay(food(1, remaining: 0), today), isFalse);
  });
  test(
    'fractions use integer half-up rounding including very large amounts',
    () {
      expect(CheckInAnswer.half.amount(5), 3);
      expect(CheckInAnswer.third.amount(5), 2);
      expect(CheckInAnswer.twoThirds.amount(5), 3);
      expect(CheckInAnswer.twoThirds.amount(4), 3);
      expect(CheckInAnswer.all.amount(maxQuantity), maxQuantity);
      expect(CheckInAnswer.twoThirds.amount(maxQuantity), 666666666667);
      expect(CheckInAnswer.none.amount(3), isNull);
      expect(CheckInAnswer.skip.amount(3), isNull);
      expect(CheckInAnswer.none.amount(0), isNull);
      expect(CheckInAnswer.half.amount(0), 0);
      expect(CheckInAnswer.third.amount(1), 0);
      for (final answer in CheckInAnswer.values) {
        expect(answer.label, isNotEmpty);
      }
    },
  );
}
