import 'inventory.dart';

enum CheckInAnswer {
  half('절반 먹었어요', 1, 2),
  third('1/3 먹었어요', 1, 3),
  twoThirds('2/3 먹었어요', 2, 3),
  all('모두 먹었어요', 1, 1),
  none('아직 안 먹었어요', 0, 1),
  skip('나중에 답할게요', 0, 1);

  const CheckInAnswer(this.label, this._numerator, this._denominator);
  final String label;
  final int _numerator, _denominator;

  /// Uses the stored base quantity, with exact HALF_UP rounding.
  /// A very small fraction may round to zero and cannot be processed.
  int? amount(int remaining) {
    if (this == none || this == skip) return null;
    require(remaining >= 0 && remaining <= maxQuantity, '남은 수량을 확인해주세요.');
    final product = BigInt.from(remaining) * BigInt.from(_numerator);
    final denominator = BigInt.from(_denominator);
    return ((product * BigInt.two + denominator) ~/ (denominator * BigInt.two))
        .toInt();
  }
}

bool isCheckInDay(Food food, DateTime today) {
  if (food.remaining <= 0) return false;
  final days = civilDate(food.expiry).difference(civilDate(today)).inDays;
  return days == 3 || days == 1 || days == 0;
}
