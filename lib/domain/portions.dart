import 'inventory.dart';

/// A portion of the current remaining stock, rounded to its smallest unit.
int portionAmount(int remaining, int denominator) {
  require(remaining > 0 && remaining <= maxQuantity, '남은 수량을 확인해주세요.');
  require(const [1, 2, 3, 4].contains(denominator), '처리 비율을 확인해주세요.');
  final value = BigInt.from(remaining);
  final divisor = BigInt.from(denominator);
  final amount = ((value * BigInt.two + divisor) ~/ (divisor * BigInt.two))
      .toInt();
  require(amount > 0, '남은 수량이 너무 적어요. 직접 입력해주세요.');
  return amount;
}
